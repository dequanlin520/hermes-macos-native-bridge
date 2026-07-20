import CryptoKit
import Darwin
import Foundation
import Security

public enum HermesAuditSigningAlgorithm {
  public static let p256SHA256ManifestDigestV1 = "p256_sha256_manifest_digest_v1"
}

public struct HermesAuditSignerID: Codable, Equatable, Hashable, Sendable,
  CustomStringConvertible
{
  public static let prefix = "hasg_"
  public let rawValue: String

  public init(rawValue: String) throws {
    guard rawValue.hasPrefix(Self.prefix), rawValue.count <= 80,
      rawValue.allSatisfy({
        $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-")
      })
    else { throw HermesAuditSigningError.invalidSignerID }
    self.rawValue = rawValue
  }

  public static func generate(uuid: UUID = UUID()) throws -> HermesAuditSignerID {
    try HermesAuditSignerID(rawValue: "\(prefix)\(uuid.uuidString.lowercased())")
  }

  public var description: String { rawValue }
}

public struct HermesAuditSigningKeyFingerprint: Codable, Equatable, Hashable, Sendable,
  CustomStringConvertible
{
  public let rawValue: String

  public init(rawValue: String) throws {
    guard rawValue.count == 64,
      rawValue.allSatisfy({ $0.isASCII && $0.isLowercaseHexDigit })
    else { throw HermesAuditSigningError.invalidFingerprint }
    self.rawValue = rawValue
  }

  public init(publicKeyDER: Data) {
    self.rawValue = SHA256.hash(data: publicKeyDER).map { String(format: "%02x", $0) }.joined()
  }

  public var prefix: String { String(rawValue.prefix(12)) }
  public var description: String { rawValue }
}

public enum HermesAuditSigningKeyState: String, Codable, CaseIterable, Equatable, Sendable {
  case active
  case retired
  case missing
  case duplicate
  case locked
  case inaccessible
}

public struct HermesAuditPublicTrustAnchor: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public let signerID: HermesAuditSignerID
  public let algorithm: String
  public let publicKeyDERBase64: String
  public let fingerprint: HermesAuditSigningKeyFingerprint
  public let createdAt: Date
  public let state: HermesAuditSigningKeyState
  public let keyGenerationID: String
  public let checksum: HermesAuditDigest

  public init(
    schemaVersion: Int = currentSchemaVersion,
    signerID: HermesAuditSignerID,
    algorithm: String = HermesAuditSigningAlgorithm.p256SHA256ManifestDigestV1,
    publicKeyDER: Data,
    fingerprint: HermesAuditSigningKeyFingerprint? = nil,
    createdAt: Date,
    state: HermesAuditSigningKeyState,
    keyGenerationID: String,
    checksum: HermesAuditDigest? = nil
  ) throws {
    guard schemaVersion == Self.currentSchemaVersion else {
      throw HermesAuditError.unsupportedSchemaVersion
    }
    let resolvedFingerprint =
      fingerprint ?? HermesAuditSigningKeyFingerprint(publicKeyDER: publicKeyDER)
    self.schemaVersion = schemaVersion
    self.signerID = signerID
    self.algorithm = String(algorithm.prefix(64))
    self.publicKeyDERBase64 = publicKeyDER.base64EncodedString()
    self.fingerprint = resolvedFingerprint
    self.createdAt = createdAt
    self.state = state
    self.keyGenerationID = Self.safeGenerationID(keyGenerationID)
    self.checksum =
      checksum
      ?? HermesAuditDigest(
        Data(
          Self.canonicalChecksumPayload(
            schemaVersion: schemaVersion,
            signerID: signerID,
            algorithm: String(algorithm.prefix(64)),
            publicKeyDERBase64: publicKeyDER.base64EncodedString(),
            fingerprint: resolvedFingerprint,
            createdAt: createdAt,
            state: state,
            keyGenerationID: Self.safeGenerationID(keyGenerationID)
          ).utf8))!
  }

  public var publicKeyDER: Data? { Data(base64Encoded: publicKeyDERBase64) }

  public func checksumIsValid() -> Bool {
    guard
      let expected = HermesAuditDigest(
        Data(
          Self.canonicalChecksumPayload(
            schemaVersion: schemaVersion,
            signerID: signerID,
            algorithm: algorithm,
            publicKeyDERBase64: publicKeyDERBase64,
            fingerprint: fingerprint,
            createdAt: createdAt,
            state: state,
            keyGenerationID: keyGenerationID
          ).utf8))
    else { return false }
    return expected == checksum
  }

  private static func canonicalChecksumPayload(
    schemaVersion: Int,
    signerID: HermesAuditSignerID,
    algorithm: String,
    publicKeyDERBase64: String,
    fingerprint: HermesAuditSigningKeyFingerprint,
    createdAt: Date,
    state: HermesAuditSigningKeyState,
    keyGenerationID: String
  ) -> String {
    HermesAuditCanonical.canonicalJSONObject([
      ("schemaVersion", schemaVersion),
      ("signerID", signerID.rawValue),
      ("algorithm", algorithm),
      ("publicKeyDERBase64", publicKeyDERBase64),
      ("fingerprint", fingerprint.rawValue),
      ("createdAt", HermesAuditCanonical.normalizedTimestamp(createdAt)),
      ("state", state.rawValue),
      ("keyGenerationID", keyGenerationID),
    ])
  }

  private static func safeGenerationID(_ value: String) -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-")
    }
    return String((filtered.isEmpty ? UUID().uuidString.lowercased() : filtered).prefix(80))
  }
}

public struct HermesAuditManifestSignature: Codable, Equatable, Sendable {
  public let signerID: HermesAuditSignerID
  public let algorithm: String
  public let publicKeyFingerprint: HermesAuditSigningKeyFingerprint
  public let encodedSignature: String
  public let signedAt: Date
  public let keyGenerationID: String

  public init(
    signerID: HermesAuditSignerID,
    algorithm: String = HermesAuditSigningAlgorithm.p256SHA256ManifestDigestV1,
    publicKeyFingerprint: HermesAuditSigningKeyFingerprint,
    encodedSignature: String,
    signedAt: Date,
    keyGenerationID: String
  ) {
    self.signerID = signerID
    self.algorithm = String(algorithm.prefix(64))
    self.publicKeyFingerprint = publicKeyFingerprint
    self.encodedSignature = String(encodedSignature.prefix(1024))
    self.signedAt = signedAt
    self.keyGenerationID = String(keyGenerationID.prefix(80))
  }
}

public struct HermesAuditKeyRotationRecord: Codable, Equatable, Sendable {
  public let oldSignerID: HermesAuditSignerID
  public let newSignerID: HermesAuditSignerID
  public let oldFingerprint: HermesAuditSigningKeyFingerprint
  public let newFingerprint: HermesAuditSigningKeyFingerprint
  public let rotatedAt: Date
  public let finalizedSegmentID: HermesAuditSegmentID?

  public init(
    oldSignerID: HermesAuditSignerID,
    newSignerID: HermesAuditSignerID,
    oldFingerprint: HermesAuditSigningKeyFingerprint,
    newFingerprint: HermesAuditSigningKeyFingerprint,
    rotatedAt: Date,
    finalizedSegmentID: HermesAuditSegmentID?
  ) {
    self.oldSignerID = oldSignerID
    self.newSignerID = newSignerID
    self.oldFingerprint = oldFingerprint
    self.newFingerprint = newFingerprint
    self.rotatedAt = rotatedAt
    self.finalizedSegmentID = finalizedSegmentID
  }
}

public enum HermesAuditManifestSignatureVerificationResult: Equatable, Sendable {
  case verifiedSigned
  case retiredSignerValid
  case signatureUnavailable
  case signatureInvalid
  case unknownSigner
  case keyUnavailable
}

public protocol HermesAuditManifestSigningProvider: Sendable {
  var signerID: HermesAuditSignerID? { get }
  var publicKeyFingerprint: HermesAuditSigningKeyFingerprint? { get }
  func sign(manifestDigest: HermesAuditDigest) throws -> HermesAuditManifestSignature?
  func verify(signature: HermesAuditManifestSignature, manifestDigest: HermesAuditDigest) throws
    -> Bool
}

public protocol HermesAuditManifestSigner: HermesAuditManifestSigningProvider {}

public struct HermesUnsignedAuditManifestSigningProvider: HermesAuditManifestSigningProvider {
  public let signerID: HermesAuditSignerID? = nil
  public let publicKeyFingerprint: HermesAuditSigningKeyFingerprint? = nil
  public init() {}
  public func sign(manifestDigest _: HermesAuditDigest) throws -> HermesAuditManifestSignature? {
    nil
  }
  public func verify(signature _: HermesAuditManifestSignature, manifestDigest _: HermesAuditDigest)
    throws -> Bool
  {
    false
  }
}

public final class HermesEphemeralTestAuditManifestSigningProvider:
  HermesAuditManifestSigner, @unchecked Sendable
{
  private let privateKey: P256.Signing.PrivateKey?
  private let publicKey: P256.Signing.PublicKey
  public let signerID: HermesAuditSignerID?
  public let publicKeyFingerprint: HermesAuditSigningKeyFingerprint?
  public let keyGenerationID: String
  private let lock = NSLock()

  public init(keyID: String = "hasg_ephemeral_test") {
    let key = P256.Signing.PrivateKey()
    self.privateKey = key
    self.publicKey = key.publicKey
    self.signerID = try? HermesAuditSignerID(rawValue: keyID)
    self.publicKeyFingerprint = HermesAuditSigningKeyFingerprint(
      publicKeyDER: key.publicKey.derRepresentation)
    self.keyGenerationID = "test_generation"
  }

  public init(publicKey: P256.Signing.PublicKey, keyID: String = "hasg_ephemeral_test_public") {
    self.privateKey = nil
    self.publicKey = publicKey
    self.signerID = try? HermesAuditSignerID(rawValue: keyID)
    self.publicKeyFingerprint = HermesAuditSigningKeyFingerprint(
      publicKeyDER: publicKey.derRepresentation)
    self.keyGenerationID = "test_generation"
  }

  public var exportedPublicKey: P256.Signing.PublicKey { publicKey }

  public var publicTrustAnchor: HermesAuditPublicTrustAnchor {
    try! HermesAuditPublicTrustAnchor(
      signerID: signerID!,
      publicKeyDER: publicKey.derRepresentation,
      createdAt: Date(timeIntervalSince1970: 1),
      state: .active,
      keyGenerationID: keyGenerationID
    )
  }

  public func sign(manifestDigest: HermesAuditDigest) throws -> HermesAuditManifestSignature? {
    try lock.withLock {
      guard let privateKey, let signerID, let publicKeyFingerprint else { return nil }
      let signature = try privateKey.signature(for: manifestDigest.digestBytes)
      return HermesAuditManifestSignature(
        signerID: signerID,
        publicKeyFingerprint: publicKeyFingerprint,
        encodedSignature: signature.derRepresentation.base64EncodedString(),
        signedAt: Date(),
        keyGenerationID: keyGenerationID
      )
    }
  }

  public func verify(signature: HermesAuditManifestSignature, manifestDigest: HermesAuditDigest)
    throws -> Bool
  {
    guard signature.algorithm == HermesAuditSigningAlgorithm.p256SHA256ManifestDigestV1,
      signature.signerID == signerID,
      signature.publicKeyFingerprint == publicKeyFingerprint,
      let data = Data(base64Encoded: signature.encodedSignature)
    else { return false }
    let p256Signature = try P256.Signing.ECDSASignature(derRepresentation: data)
    return publicKey.isValidSignature(p256Signature, for: manifestDigest.digestBytes)
  }
}

public struct HermesAuditManifestVerifier: Sendable {
  public let trustAnchors: [HermesAuditPublicTrustAnchor]

  public init(trustAnchors: [HermesAuditPublicTrustAnchor]) {
    self.trustAnchors = trustAnchors
  }

  public func verify(
    signature: HermesAuditManifestSignature?,
    manifestDigest: HermesAuditDigest
  ) -> HermesAuditManifestSignatureVerificationResult {
    guard let signature else { return .signatureUnavailable }
    guard signature.algorithm == HermesAuditSigningAlgorithm.p256SHA256ManifestDigestV1 else {
      return .signatureInvalid
    }
    guard
      let anchor = trustAnchors.first(where: {
        $0.signerID == signature.signerID
          && $0.fingerprint == signature.publicKeyFingerprint
          && $0.keyGenerationID == signature.keyGenerationID
      })
    else {
      return trustAnchors.contains(where: { $0.signerID == signature.signerID })
        ? .signatureInvalid : .unknownSigner
    }
    guard anchor.checksumIsValid(), anchor.algorithm == signature.algorithm,
      let publicKeyDER = anchor.publicKeyDER,
      HermesAuditSigningKeyFingerprint(publicKeyDER: publicKeyDER)
        == signature.publicKeyFingerprint,
      let signatureData = Data(base64Encoded: signature.encodedSignature),
      let publicKey = try? P256.Signing.PublicKey(derRepresentation: publicKeyDER),
      let p256Signature = try? P256.Signing.ECDSASignature(derRepresentation: signatureData),
      publicKey.isValidSignature(p256Signature, for: manifestDigest.digestBytes)
    else { return .signatureInvalid }
    return anchor.state == .retired ? .retiredSignerValid : .verifiedSigned
  }
}

public enum HermesAuditSigningError: Error, Equatable, Sendable, CustomStringConvertible {
  case invalidSignerID
  case invalidFingerprint
  case keyMissing
  case duplicateKey
  case keychainLocked
  case keychainInaccessible(OSStatus)
  case keyCreationFailed(OSStatus)
  case signingFailed(OSStatus)
  case publicKeyExportFailed(OSStatus)
  case unsupportedKey

  public var description: String {
    switch self {
    case .invalidSignerID: return "invalid audit signer identifier"
    case .invalidFingerprint: return "invalid audit signing fingerprint"
    case .keyMissing: return "audit signing key missing"
    case .duplicateKey: return "duplicate audit signing key"
    case .keychainLocked: return "audit signing keychain locked"
    case .keychainInaccessible: return "audit signing keychain inaccessible"
    case .keyCreationFailed: return "audit signing key creation failed"
    case .signingFailed: return "audit signing failed"
    case .publicKeyExportFailed: return "audit signing public key export failed"
    case .unsupportedKey: return "unsupported audit signing key"
    }
  }
}

public final class HermesKeychainAuditManifestSigner: HermesAuditManifestSigner,
  @unchecked Sendable
{
  public static let applicationTagPrefix = "com.hermes.bridge.audit.signing.p256"
  private let privateKey: SecKey
  public let signerID: HermesAuditSignerID?
  public let publicKeyFingerprint: HermesAuditSigningKeyFingerprint?
  public let keyGenerationID: String
  private let publicKeyDER: Data
  private let lock = NSLock()

  public init(privateKey: SecKey, signerID: HermesAuditSignerID, keyGenerationID: String) throws {
    self.privateKey = privateKey
    self.signerID = signerID
    self.keyGenerationID = String(keyGenerationID.prefix(80))
    self.publicKeyDER = try Self.exportPublicKeyDER(privateKey: privateKey)
    self.publicKeyFingerprint = HermesAuditSigningKeyFingerprint(publicKeyDER: publicKeyDER)
  }

  public func sign(manifestDigest: HermesAuditDigest) throws -> HermesAuditManifestSignature? {
    try lock.withLock {
      guard let signerID, let publicKeyFingerprint else { return nil }
      var error: Unmanaged<CFError>?
      guard
        let signature = SecKeyCreateSignature(
          privateKey,
          .ecdsaSignatureMessageX962SHA256,
          manifestDigest.digestBytes as CFData,
          &error
        ) as Data?
      else {
        throw HermesAuditSigningError.signingFailed(
          error?.takeRetainedValue().osStatus ?? errSecInternalError)
      }
      return HermesAuditManifestSignature(
        signerID: signerID,
        publicKeyFingerprint: publicKeyFingerprint,
        encodedSignature: signature.base64EncodedString(),
        signedAt: Date(),
        keyGenerationID: keyGenerationID
      )
    }
  }

  public func verify(signature: HermesAuditManifestSignature, manifestDigest: HermesAuditDigest)
    throws -> Bool
  {
    guard let publicKey = SecKeyCopyPublicKey(privateKey),
      signature.signerID == signerID,
      signature.publicKeyFingerprint == publicKeyFingerprint,
      let data = Data(base64Encoded: signature.encodedSignature)
    else { return false }
    var error: Unmanaged<CFError>?
    let valid = SecKeyVerifySignature(
      publicKey,
      .ecdsaSignatureMessageX962SHA256,
      manifestDigest.digestBytes as CFData,
      data as CFData,
      &error
    )
    return valid
  }

  public func publicTrustAnchor(state: HermesAuditSigningKeyState = .active) throws
    -> HermesAuditPublicTrustAnchor
  {
    try HermesAuditPublicTrustAnchor(
      signerID: signerID!,
      publicKeyDER: publicKeyDER,
      createdAt: Date(),
      state: state,
      keyGenerationID: keyGenerationID
    )
  }

  private static func exportPublicKeyDER(privateKey: SecKey) throws -> Data {
    guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
      throw HermesAuditSigningError.unsupportedKey
    }
    var error: Unmanaged<CFError>?
    guard let data = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
      throw HermesAuditSigningError.publicKeyExportFailed(
        error?.takeRetainedValue().osStatus ?? errSecInternalError)
    }
    return try P256.Signing.PublicKey(x963Representation: data).derRepresentation
  }
}

public struct HermesAuditSigningKeyManager: Sendable {
  private let accessGroup: String?

  public init(accessGroup: String? = nil) {
    self.accessGroup = accessGroup
  }

  public func lookup(signerID: HermesAuditSignerID, keyGenerationID: String) throws
    -> HermesKeychainAuditManifestSigner
  {
    let tag = applicationTag(signerID: signerID, keyGenerationID: keyGenerationID)
    var query = baseQuery(tag: tag)
    query[kSecReturnRef as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitAll
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { throw HermesAuditSigningError.keyMissing }
    try mapKeychainStatus(status)
    guard let keys = result as? [SecKey] else {
      throw HermesAuditSigningError.keychainInaccessible(status)
    }
    guard keys.count == 1, let key = keys.first else {
      throw HermesAuditSigningError.duplicateKey
    }
    return try HermesKeychainAuditManifestSigner(
      privateKey: key,
      signerID: signerID,
      keyGenerationID: keyGenerationID
    )
  }

  public func createKey(signerID: HermesAuditSignerID, keyGenerationID: String) throws
    -> HermesKeychainAuditManifestSigner
  {
    do {
      let existing = try lookup(signerID: signerID, keyGenerationID: keyGenerationID)
      return existing
    } catch HermesAuditSigningError.keyMissing {
      // Creation is explicit and only follows a typed missing-key result.
    } catch {
      throw error
    }
    let tag = applicationTag(signerID: signerID, keyGenerationID: keyGenerationID)
    var access: SecAccess?
    let accessStatus = SecAccessCreate(
      "Hermes Bridge Audit Manifest Signing Key" as CFString,
      [] as CFArray,
      &access
    )
    guard accessStatus == errSecSuccess, let access else {
      throw HermesAuditSigningError.keyCreationFailed(accessStatus)
    }
    let attributes: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrKeySizeInBits as String: 256,
      kSecAttrIsPermanent as String: true,
      kSecPrivateKeyAttrs as String: [
        kSecAttrApplicationTag as String: tag,
        kSecAttrLabel as String: "Hermes Bridge Audit Manifest Signing Key",
        kSecAttrIsExtractable as String: false,
        kSecAttrAccess as String: access,
      ],
    ]
    var error: Unmanaged<CFError>?
    guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
      throw HermesAuditSigningError.keyCreationFailed(
        error?.takeRetainedValue().osStatus ?? errSecInternalError)
    }
    return try HermesKeychainAuditManifestSigner(
      privateKey: key,
      signerID: signerID,
      keyGenerationID: keyGenerationID
    )
  }

  public func createKey() throws -> HermesKeychainAuditManifestSigner {
    try createKey(signerID: .generate(), keyGenerationID: UUID().uuidString.lowercased())
  }

  public func rotateKey() throws -> HermesKeychainAuditManifestSigner {
    try createKey()
  }

  public func state(signerID: HermesAuditSignerID, keyGenerationID: String)
    -> HermesAuditSigningKeyState
  {
    do {
      _ = try lookup(signerID: signerID, keyGenerationID: keyGenerationID)
      return .active
    } catch HermesAuditSigningError.keyMissing {
      return .missing
    } catch HermesAuditSigningError.duplicateKey {
      return .duplicate
    } catch HermesAuditSigningError.keychainLocked {
      return .locked
    } catch {
      return .inaccessible
    }
  }

  private func baseQuery(tag: Data) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrApplicationTag as String: tag,
    ]
    if let accessGroup {
      query[kSecAttrAccessGroup as String] = accessGroup
    }
    return query
  }

  private func applicationTag(signerID: HermesAuditSignerID, keyGenerationID: String) -> Data {
    Data(
      "\(HermesKeychainAuditManifestSigner.applicationTagPrefix).\(signerID.rawValue).\(keyGenerationID)"
        .utf8)
  }

  private func mapKeychainStatus(_ status: OSStatus) throws {
    guard status == errSecSuccess else {
      if status == errSecInteractionNotAllowed || status == errSecAuthFailed {
        throw HermesAuditSigningError.keychainLocked
      }
      throw HermesAuditSigningError.keychainInaccessible(status)
    }
  }
}

public struct HermesAuditSigningStatus: Codable, Equatable, Sendable {
  public let signingAvailable: Bool
  public let state: HermesAuditSigningKeyState
  public let activeSignerID: HermesAuditSignerID?
  public let activeFingerprintPrefix: String?
  public let trustAnchorCount: Int
  public let remediationCode: String

  public init(
    signingAvailable: Bool,
    state: HermesAuditSigningKeyState,
    activeSignerID: HermesAuditSignerID?,
    activeFingerprintPrefix: String?,
    trustAnchorCount: Int,
    remediationCode: String
  ) {
    self.signingAvailable = signingAvailable
    self.state = state
    self.activeSignerID = activeSignerID
    self.activeFingerprintPrefix = activeFingerprintPrefix
    self.trustAnchorCount = max(0, trustAnchorCount)
    self.remediationCode = String(remediationCode.prefix(64))
  }
}

public struct HermesAuditPublicTrustAnchorStore: @unchecked Sendable {
  public static let fileName = "audit-signing-trust-anchors.json"
  private let root: URL
  private let fileManager: FileManager
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(root: URL, fileManager: FileManager = .default) {
    self.root = root.standardizedFileURL
    self.fileManager = fileManager
    self.encoder = JSONEncoder()
    self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    self.encoder.dateEncodingStrategy = .iso8601
    self.decoder = JSONDecoder()
    self.decoder.dateDecodingStrategy = .iso8601
  }

  public func load() throws -> [HermesAuditPublicTrustAnchor] {
    let url = root.appendingPathComponent(Self.fileName)
    guard fileManager.fileExists(atPath: url.path) else { return [] }
    return try decoder.decode([HermesAuditPublicTrustAnchor].self, from: Data(contentsOf: url))
  }

  public func save(_ anchors: [HermesAuditPublicTrustAnchor]) throws {
    try fileManager.createDirectory(
      at: root,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
    )
    let data = try encoder.encode(anchors)
    let url = root.appendingPathComponent(Self.fileName)
    try data.write(to: url, options: [.atomic])
    chmod(url.path, 0o600)
  }

  public func activeAnchor() throws -> HermesAuditPublicTrustAnchor? {
    try load().last { $0.state == .active }
  }

  public func status(keyManager: HermesAuditSigningKeyManager = HermesAuditSigningKeyManager())
    -> HermesAuditSigningStatus
  {
    do {
      let anchors = try load()
      guard let active = anchors.last(where: { $0.state == .active }) else {
        return HermesAuditSigningStatus(
          signingAvailable: false,
          state: .missing,
          activeSignerID: nil,
          activeFingerprintPrefix: nil,
          trustAnchorCount: anchors.count,
          remediationCode: "AUDIT_SIGNING_KEY_CREATE")
      }
      let state = keyManager.state(
        signerID: active.signerID,
        keyGenerationID: active.keyGenerationID
      )
      return HermesAuditSigningStatus(
        signingAvailable: state == .active,
        state: state,
        activeSignerID: active.signerID,
        activeFingerprintPrefix: active.fingerprint.prefix,
        trustAnchorCount: anchors.count,
        remediationCode: state == .active ? "NONE" : "AUDIT_SIGNING_KEY_REPAIR")
    } catch {
      return HermesAuditSigningStatus(
        signingAvailable: false,
        state: .inaccessible,
        activeSignerID: nil,
        activeFingerprintPrefix: nil,
        trustAnchorCount: 0,
        remediationCode: "AUDIT_SIGNING_KEYCHAIN_CHECK")
    }
  }

  public func appendCreatedAnchor(_ anchor: HermesAuditPublicTrustAnchor) throws {
    var anchors = try load().filter {
      !($0.signerID == anchor.signerID && $0.keyGenerationID == anchor.keyGenerationID)
    }
    if anchor.state == .active {
      anchors = try anchors.map { existing in
        guard existing.state == .active else { return existing }
        return try HermesAuditPublicTrustAnchor(
          signerID: existing.signerID,
          publicKeyDER: existing.publicKeyDER ?? Data(),
          fingerprint: existing.fingerprint,
          createdAt: existing.createdAt,
          state: .retired,
          keyGenerationID: existing.keyGenerationID
        )
      }
    }
    anchors.append(anchor)
    try save(anchors)
  }
}

extension HermesAuditDigest {
  fileprivate var digestBytes: Data {
    var bytes = Data(capacity: Self.sha256ByteCount)
    var index = rawValue.startIndex
    while index < rawValue.endIndex {
      let next = rawValue.index(index, offsetBy: 2)
      bytes.append(UInt8(rawValue[index..<next], radix: 16)!)
      index = next
    }
    return bytes
  }
}

extension Character {
  fileprivate var isLowercaseHexDigit: Bool {
    ("0"..."9").contains(self) || ("a"..."f").contains(self)
  }
}

extension CFError {
  fileprivate var osStatus: OSStatus {
    let nsError = self as Error as NSError
    return OSStatus(nsError.code)
  }
}
