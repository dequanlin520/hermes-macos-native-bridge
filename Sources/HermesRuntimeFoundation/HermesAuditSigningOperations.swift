import CryptoKit
import Darwin
import Foundation
import Security

public enum HermesAuditKeyAccessStatus: String, Codable, CaseIterable, Equatable, Sendable {
  case setupRequired
  case configuredForCurrentApp
  case configuredForCurrentService
  case configuredForAppAndService
  case locked
  case identityMismatch
  case inaccessible
  case unsupported
}

public enum HermesAuditKeyAccessRemediation: String, Codable, CaseIterable, Equatable, Sendable {
  case configureAuditSigningAccess
  case unlockKeychain
  case rebuildSignedApp
  case reinstallService
  case resetAuditSigningConfiguration
  case none
}

public enum HermesAuditSigningRequirementPolicy: String, Codable, CaseIterable, Equatable,
  Sendable
{
  case signingRequired
  case signingPreferred
  case unsignedAllowedForLegacyOnly
}

public enum HermesAuditSigningOperationalError: Error, Equatable, Sendable,
  CustomStringConvertible
{
  case signingRequired(HermesAuditKeyAccessStatus)
  case identityMismatch
  case locked
  case inaccessible
  case unsupported
  case confirmationRequired
  case recoveryRequired(HermesAuditSigningRecoveryOperation)

  public var description: String {
    switch self {
    case .signingRequired(let status):
      return "audit signing required but unavailable: \(status.rawValue)"
    case .identityMismatch:
      return "audit signing code identity mismatch"
    case .locked:
      return "audit signing keychain locked"
    case .inaccessible:
      return "audit signing keychain inaccessible"
    case .unsupported:
      return "audit signing access policy unsupported"
    case .confirmationRequired:
      return "explicit confirmation required"
    case .recoveryRequired(let operation):
      return "audit signing recovery required: \(operation.rawValue)"
    }
  }
}

public enum HermesAuditSigningRecoveryOperation: String, Codable, CaseIterable, Equatable,
  Sendable
{
  case recreateMissingSigningKey
  case importPublicTrustAnchors
  case retireUnknownSigner
  case resumeInterruptedRotation
  case abandonIncompleteRotation
  case resetAuditSigningConfiguration
}

public enum HermesAuditKeyRotationTransactionStage: String, Codable, CaseIterable, Equatable,
  Sendable
{
  case prepared
  case oldSegmentFinalized
  case newKeyCreated
  case oldAnchorRetired
  case newAnchorActivated
  case rotationEventWritten
  case completed
}

public struct HermesAuditAuthorizedCodeIdentity: Codable, Equatable, Sendable {
  public let role: String
  public let bundleIdentifier: String?
  public let designatedRequirement: String?
  public let teamIdentifier: String?
  public let signingKind: String
  public let hardenedRuntime: Bool
  public let appSandbox: Bool
  public let fingerprint: String

  public init(
    role: String,
    bundleIdentifier: String?,
    designatedRequirement: String?,
    teamIdentifier: String?,
    signingKind: String,
    hardenedRuntime: Bool,
    appSandbox: Bool,
    fingerprint: String
  ) {
    self.role = Self.safeToken(role)
    self.bundleIdentifier = bundleIdentifier.map(Self.safeIdentifier)
    self.designatedRequirement = designatedRequirement.map { String($0.prefix(1024)) }
    self.teamIdentifier = teamIdentifier.map(Self.safeToken)
    self.signingKind = Self.safeToken(signingKind)
    self.hardenedRuntime = hardenedRuntime
    self.appSandbox = appSandbox
    self.fingerprint = Self.safeFingerprint(fingerprint)
  }

  public static func current(role: String = "currentApp") -> HermesAuditAuthorizedCodeIdentity {
    executable(role: role, url: Bundle.main.executableURL)
  }

  public static func executable(
    role: String,
    url: URL?
  ) -> HermesAuditAuthorizedCodeIdentity {
    guard let url else {
      return HermesAuditAuthorizedCodeIdentity(
        role: role,
        bundleIdentifier: nil,
        designatedRequirement: nil,
        teamIdentifier: nil,
        signingKind: "unavailable",
        hardenedRuntime: false,
        appSandbox: false,
        fingerprint: "unavailable"
      )
    }
    var staticCode: SecStaticCode?
    let createResult = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
    guard createResult == errSecSuccess, let staticCode else {
      return HermesAuditAuthorizedCodeIdentity(
        role: role,
        bundleIdentifier: nil,
        designatedRequirement: nil,
        teamIdentifier: nil,
        signingKind: "unsigned",
        hardenedRuntime: false,
        appSandbox: false,
        fingerprint: Self.fingerprint(url: url)
      )
    }

    var information: CFDictionary?
    let flags = SecCSFlags(rawValue: kSecCSSigningInformation | kSecCSRequirementInformation)
    let infoResult = SecCodeCopySigningInformation(staticCode, flags, &information)
    let dictionary = (information as? [String: Any]) ?? [:]
    var requirementText: String?
    if let requirement = dictionary[kSecCodeInfoDesignatedRequirement as String] {
      requirementText = String(describing: requirement)
    }
    let entitlements = dictionary[kSecCodeInfoEntitlementsDict as String] as? [String: Any] ?? [:]
    let flagsValue = dictionary[kSecCodeInfoStatus as String] as? UInt32 ?? 0
    let team = dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    let signingKind: String
    if infoResult != errSecSuccess {
      signingKind = "unknown"
    } else if team?.isEmpty == false {
      signingKind = "developerIDOrTeamSigned"
    } else {
      signingKind = "adhoc"
    }
    return HermesAuditAuthorizedCodeIdentity(
      role: role,
      bundleIdentifier: dictionary[kSecCodeInfoIdentifier as String] as? String,
      designatedRequirement: requirementText,
      teamIdentifier: team,
      signingKind: signingKind,
      hardenedRuntime: flagsValue & SecCodeSignatureFlags.runtime.rawValue != 0,
      appSandbox: entitlements["com.apple.security.app-sandbox"] as? Bool == true,
      fingerprint: Self.fingerprint(url: url)
    )
  }

  public func isCompatible(with other: HermesAuditAuthorizedCodeIdentity) -> Bool {
    if let designatedRequirement, let otherRequirement = other.designatedRequirement {
      return designatedRequirement == otherRequirement
    }
    return fingerprint == other.fingerprint && signingKind == other.signingKind
  }

  private static func fingerprint(url: URL) -> String {
    guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
      return "unavailable"
    }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func safeIdentifier(_ value: String) -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-")
    }
    return String(filtered.prefix(160))
  }

  private static func safeToken(_ value: String) -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-")
    }
    return String((filtered.isEmpty ? "unknown" : filtered).prefix(80))
  }

  private static func safeFingerprint(_ value: String) -> String {
    let filtered = value.filter {
      $0.isASCII && (($0 >= "0" && $0 <= "9") || ($0 >= "a" && $0 <= "f"))
    }
    return String((filtered.isEmpty ? "unavailable" : filtered).prefix(64))
  }
}

public struct HermesAuditKeyAccessPolicy: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public let appIdentity: HermesAuditAuthorizedCodeIdentity?
  public let serviceIdentity: HermesAuditAuthorizedCodeIdentity?
  public let signingPolicy: HermesAuditSigningRequirementPolicy
  public let configuredAt: Date?
  public let nonInteractiveSigningProven: Bool
  public let lastSuccessfulSignatureAt: Date?
  public let status: HermesAuditKeyAccessStatus
  public let remediation: HermesAuditKeyAccessRemediation

  public init(
    schemaVersion: Int = currentSchemaVersion,
    appIdentity: HermesAuditAuthorizedCodeIdentity?,
    serviceIdentity: HermesAuditAuthorizedCodeIdentity?,
    signingPolicy: HermesAuditSigningRequirementPolicy,
    configuredAt: Date?,
    nonInteractiveSigningProven: Bool,
    lastSuccessfulSignatureAt: Date?,
    status: HermesAuditKeyAccessStatus,
    remediation: HermesAuditKeyAccessRemediation
  ) {
    self.schemaVersion = schemaVersion
    self.appIdentity = appIdentity
    self.serviceIdentity = serviceIdentity
    self.signingPolicy = signingPolicy
    self.configuredAt = configuredAt
    self.nonInteractiveSigningProven = nonInteractiveSigningProven
    self.lastSuccessfulSignatureAt = lastSuccessfulSignatureAt
    self.status = status
    self.remediation = remediation
  }
}

public struct HermesAuditSigningReleaseIdentityValidation: Codable, Equatable, Sendable {
  public let appIdentity: HermesAuditAuthorizedCodeIdentity
  public let serviceIdentity: HermesAuditAuthorizedCodeIdentity?
  public let developerIDAvailable: Bool
  public let validationPassed: Bool
  public let blocked: Bool
  public let issueCodes: [String]

  public init(
    appIdentity: HermesAuditAuthorizedCodeIdentity,
    serviceIdentity: HermesAuditAuthorizedCodeIdentity?,
    developerIDAvailable: Bool,
    validationPassed: Bool,
    blocked: Bool,
    issueCodes: [String]
  ) {
    self.appIdentity = appIdentity
    self.serviceIdentity = serviceIdentity
    self.developerIDAvailable = developerIDAvailable
    self.validationPassed = validationPassed
    self.blocked = blocked
    self.issueCodes = issueCodes.map { String($0.prefix(80)) }.sorted()
  }
}

public struct HermesAuditSigningOperationalStatus: Codable, Equatable, Sendable {
  public let activeSignerID: HermesAuditSignerID?
  public let activeFingerprintPrefix: String?
  public let accessPolicyState: HermesAuditKeyAccessStatus
  public let signingRequiredPolicy: HermesAuditSigningRequirementPolicy
  public let nonInteractiveSigningProven: Bool
  public let lastSuccessfulSignatureAt: Date?
  public let rotationTransactionState: HermesAuditKeyRotationTransactionStage?
  public let recoveryRequired: HermesAuditSigningRecoveryOperation?
  public let releaseIdentityValidation: HermesAuditSigningReleaseIdentityValidation
  public let trustAnchorCount: Int

  public init(
    activeSignerID: HermesAuditSignerID?,
    activeFingerprintPrefix: String?,
    accessPolicyState: HermesAuditKeyAccessStatus,
    signingRequiredPolicy: HermesAuditSigningRequirementPolicy,
    nonInteractiveSigningProven: Bool,
    lastSuccessfulSignatureAt: Date?,
    rotationTransactionState: HermesAuditKeyRotationTransactionStage?,
    recoveryRequired: HermesAuditSigningRecoveryOperation?,
    releaseIdentityValidation: HermesAuditSigningReleaseIdentityValidation,
    trustAnchorCount: Int
  ) {
    self.activeSignerID = activeSignerID
    self.activeFingerprintPrefix = activeFingerprintPrefix
    self.accessPolicyState = accessPolicyState
    self.signingRequiredPolicy = signingRequiredPolicy
    self.nonInteractiveSigningProven = nonInteractiveSigningProven
    self.lastSuccessfulSignatureAt = lastSuccessfulSignatureAt
    self.rotationTransactionState = rotationTransactionState
    self.recoveryRequired = recoveryRequired
    self.releaseIdentityValidation = releaseIdentityValidation
    self.trustAnchorCount = max(0, trustAnchorCount)
  }
}

public struct HermesAuditKeyRotationTransaction: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1
  public let schemaVersion: Int
  public let transactionID: String
  public let stage: HermesAuditKeyRotationTransactionStage
  public let oldSignerID: HermesAuditSignerID?
  public let newSignerID: HermesAuditSignerID?
  public let oldFingerprint: HermesAuditSigningKeyFingerprint?
  public let newFingerprint: HermesAuditSigningKeyFingerprint?
  public let startedAt: Date
  public let updatedAt: Date

  public init(
    schemaVersion: Int = currentSchemaVersion,
    transactionID: String = UUID().uuidString.lowercased(),
    stage: HermesAuditKeyRotationTransactionStage,
    oldSignerID: HermesAuditSignerID?,
    newSignerID: HermesAuditSignerID?,
    oldFingerprint: HermesAuditSigningKeyFingerprint?,
    newFingerprint: HermesAuditSigningKeyFingerprint?,
    startedAt: Date,
    updatedAt: Date
  ) {
    self.schemaVersion = schemaVersion
    self.transactionID = Self.safeToken(transactionID)
    self.stage = stage
    self.oldSignerID = oldSignerID
    self.newSignerID = newSignerID
    self.oldFingerprint = oldFingerprint
    self.newFingerprint = newFingerprint
    self.startedAt = startedAt
    self.updatedAt = updatedAt
  }

  private static func safeToken(_ value: String) -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-")
    }
    return String((filtered.isEmpty ? UUID().uuidString.lowercased() : filtered).prefix(80))
  }
}

public struct HermesAuditKeychainSetupCoordinator: @unchecked Sendable {
  public static let accessPolicyFileName = "audit-signing-access-policy.json"
  public static let rotationTransactionFileName = "audit-signing-rotation-transaction.json"

  private let auditRoot: URL
  private let keyManager: HermesAuditSigningKeyManager
  private let fileManager: FileManager
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(
    auditRoot: URL,
    keyManager: HermesAuditSigningKeyManager = HermesAuditSigningKeyManager(),
    fileManager: FileManager = .default
  ) {
    self.auditRoot = auditRoot.standardizedFileURL
    self.keyManager = keyManager
    self.fileManager = fileManager
    self.encoder = JSONEncoder()
    self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    self.encoder.dateEncodingStrategy = .iso8601
    self.decoder = JSONDecoder()
    self.decoder.dateDecodingStrategy = .iso8601
  }

  public func status(
    serviceExecutableURL: URL? = nil,
    signingPolicy: HermesAuditSigningRequirementPolicy = .signingPreferred
  ) -> HermesAuditSigningOperationalStatus {
    let trustStore = HermesAuditPublicTrustAnchorStore(root: auditRoot)
    let anchors = (try? trustStore.load()) ?? []
    let active = anchors.last { $0.state == .active }
    let access = accessStatus(active: active)
    let metadata = loadPolicy()
    let release = releaseIdentityValidation(serviceExecutableURL: serviceExecutableURL)
    return HermesAuditSigningOperationalStatus(
      activeSignerID: active?.signerID,
      activeFingerprintPrefix: active?.fingerprint.prefix,
      accessPolicyState: access,
      signingRequiredPolicy: metadata?.signingPolicy ?? signingPolicy,
      nonInteractiveSigningProven: metadata?.nonInteractiveSigningProven == true
        && [.configuredForCurrentApp, .configuredForCurrentService, .configuredForAppAndService]
          .contains(access),
      lastSuccessfulSignatureAt: metadata?.lastSuccessfulSignatureAt,
      rotationTransactionState: loadRotationTransaction()?.stage,
      recoveryRequired: recoveryRequired(active: active, anchors: anchors, access: access),
      releaseIdentityValidation: release,
      trustAnchorCount: anchors.count
    )
  }

  public func configureAuditSigningAccess(
    appExecutableURL: URL? = Bundle.main.executableURL,
    serviceExecutableURL: URL? = nil,
    signingPolicy: HermesAuditSigningRequirementPolicy = .signingRequired,
    auditActor: HermesAuditActor = .controlCLI
  ) async throws -> HermesAuditSigningOperationalStatus {
    let appIdentity = HermesAuditAuthorizedCodeIdentity.executable(
      role: "currentApp",
      url: appExecutableURL
    )
    let serviceIdentity = serviceExecutableURL.map {
      HermesAuditAuthorizedCodeIdentity.executable(role: "currentService", url: $0)
    }
    guard appIdentity.signingKind != "unsigned" else {
      throw HermesAuditSigningOperationalError.identityMismatch
    }
    try fileManager.createDirectory(
      at: auditRoot,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
    )

    let trustStore = HermesAuditPublicTrustAnchorStore(root: auditRoot)
    let trustedPaths = [appExecutableURL, serviceExecutableURL].compactMap { $0?.path }
    let signer: HermesKeychainAuditManifestSigner
    if let active = try trustStore.activeAnchor() {
      signer = try keyManager.lookup(
        signerID: active.signerID, keyGenerationID: active.keyGenerationID)
      try keyManager.configureAccess(
        signerID: active.signerID,
        keyGenerationID: active.keyGenerationID,
        trustedApplicationPaths: trustedPaths
      )
    } else {
      signer = try keyManager.createKey(trustedApplicationPaths: trustedPaths)
      try trustStore.appendCreatedAnchor(try signer.publicTrustAnchor(state: .active))
    }

    let digest = HermesAuditDigest(Data("m6-004-setup-test".utf8))!
    guard let signature = try signer.sign(manifestDigest: digest),
      try signer.verify(signature: signature, manifestDigest: digest)
    else {
      throw HermesAuditSigningOperationalError.inaccessible
    }
    let now = Date()
    let policy = HermesAuditKeyAccessPolicy(
      appIdentity: appIdentity,
      serviceIdentity: serviceIdentity,
      signingPolicy: signingPolicy,
      configuredAt: now,
      nonInteractiveSigningProven: true,
      lastSuccessfulSignatureAt: now,
      status: serviceIdentity == nil ? .configuredForCurrentApp : .configuredForAppAndService,
      remediation: .none
    )
    try savePolicy(policy)
    try? await auditSetupEvent(actor: auditActor, status: policy.status)
    return status(serviceExecutableURL: serviceExecutableURL, signingPolicy: signingPolicy)
  }

  public func signingProvider(policy: HermesAuditSigningRequirementPolicy)
    throws -> any HermesAuditManifestSigningProvider
  {
    let trustStore = HermesAuditPublicTrustAnchorStore(root: auditRoot)
    guard let active = try trustStore.activeAnchor() else {
      if policy == .signingRequired {
        throw HermesAuditSigningOperationalError.signingRequired(.setupRequired)
      }
      return HermesUnsignedAuditManifestSigningProvider()
    }
    do {
      return try keyManager.lookup(
        signerID: active.signerID, keyGenerationID: active.keyGenerationID)
    } catch HermesAuditSigningError.keychainLocked {
      if policy == .signingRequired { throw HermesAuditSigningOperationalError.locked }
      return HermesUnsignedAuditManifestSigningProvider()
    } catch HermesAuditSigningError.keyMissing {
      if policy == .signingRequired {
        throw HermesAuditSigningOperationalError.signingRequired(.setupRequired)
      }
      return HermesUnsignedAuditManifestSigningProvider()
    } catch {
      if policy == .signingRequired { throw HermesAuditSigningOperationalError.inaccessible }
      return HermesUnsignedAuditManifestSigningProvider()
    }
  }

  public func verifyAuditSigning() throws -> Bool {
    guard let active = try HermesAuditPublicTrustAnchorStore(root: auditRoot).activeAnchor() else {
      return false
    }
    let signer = try keyManager.lookup(
      signerID: active.signerID,
      keyGenerationID: active.keyGenerationID
    )
    let digest = HermesAuditDigest(Data("m6-004-verify-test".utf8))!
    guard let signature = try signer.sign(manifestDigest: digest) else { return false }
    let verified = try signer.verify(signature: signature, manifestDigest: digest)
    if verified {
      var policy = loadPolicy()
      policy = HermesAuditKeyAccessPolicy(
        appIdentity: policy?.appIdentity,
        serviceIdentity: policy?.serviceIdentity,
        signingPolicy: policy?.signingPolicy ?? .signingPreferred,
        configuredAt: policy?.configuredAt,
        nonInteractiveSigningProven: true,
        lastSuccessfulSignatureAt: Date(),
        status: policy?.status ?? .configuredForCurrentApp,
        remediation: .none
      )
      if let policy { try savePolicy(policy) }
    }
    return verified
  }

  public func exportPublicTrustAnchors(to outputDirectory: URL) throws -> Int {
    let anchors = try HermesAuditPublicTrustAnchorStore(root: auditRoot).load()
    try fileManager.createDirectory(
      at: outputDirectory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
    )
    try encoder.encode(anchors).write(
      to: outputDirectory.appendingPathComponent("audit-trust-anchors.json"),
      options: [.atomic]
    )
    return anchors.count
  }

  public func importPublicTrustAnchors(from fileURL: URL) throws -> Int {
    let imported = try decoder.decode(
      [HermesAuditPublicTrustAnchor].self,
      from: Data(contentsOf: fileURL)
    )
    guard imported.allSatisfy({ $0.checksumIsValid() && $0.publicKeyDER != nil }) else {
      throw HermesAuditSigningOperationalError.inaccessible
    }
    var existing = (try? HermesAuditPublicTrustAnchorStore(root: auditRoot).load()) ?? []
    for anchor in imported
    where !existing.contains(where: {
      $0.signerID == anchor.signerID && $0.keyGenerationID == anchor.keyGenerationID
    }) {
      existing.append(anchor)
    }
    try HermesAuditPublicTrustAnchorStore(root: auditRoot).save(existing)
    return imported.count
  }

  public func resetAuditSigningConfiguration(confirm: Bool) throws {
    guard confirm else { throw HermesAuditSigningOperationalError.confirmationRequired }
    try? fileManager.removeItem(at: policyURL)
    try? fileManager.removeItem(at: rotationURL)
  }

  public func prepareRotationTransaction(
    interruptAt stage: HermesAuditKeyRotationTransactionStage
  )
    throws -> HermesAuditKeyRotationTransaction
  {
    let active = try HermesAuditPublicTrustAnchorStore(root: auditRoot).activeAnchor()
    let transaction = HermesAuditKeyRotationTransaction(
      stage: stage,
      oldSignerID: active?.signerID,
      newSignerID: nil,
      oldFingerprint: active?.fingerprint,
      newFingerprint: nil,
      startedAt: Date(),
      updatedAt: Date()
    )
    try saveRotationTransaction(transaction)
    return transaction
  }

  public func resumeInterruptedRotation(auditActor: HermesAuditActor = .controlCLI) async throws
    -> HermesAuditSigningOperationalStatus
  {
    guard let transaction = loadRotationTransaction(), transaction.stage != .completed else {
      return status()
    }
    let trustStore = HermesAuditPublicTrustAnchorStore(root: auditRoot)
    let oldAnchors = try trustStore.load()
    let oldActive = oldAnchors.last { $0.state == .active }
    let newKey = try keyManager.rotateKey()
    try saveRotationTransaction(
      HermesAuditKeyRotationTransaction(
        transactionID: transaction.transactionID,
        stage: .newKeyCreated,
        oldSignerID: oldActive?.signerID,
        newSignerID: newKey.signerID,
        oldFingerprint: oldActive?.fingerprint,
        newFingerprint: newKey.publicKeyFingerprint,
        startedAt: transaction.startedAt,
        updatedAt: Date()
      ))
    try trustStore.appendCreatedAnchor(try newKey.publicTrustAnchor(state: .active))
    try saveRotationTransaction(
      HermesAuditKeyRotationTransaction(
        transactionID: transaction.transactionID,
        stage: .newAnchorActivated,
        oldSignerID: oldActive?.signerID,
        newSignerID: newKey.signerID,
        oldFingerprint: oldActive?.fingerprint,
        newFingerprint: newKey.publicKeyFingerprint,
        startedAt: transaction.startedAt,
        updatedAt: Date()
      ))
    try? await auditRecoveryEvent(actor: auditActor, operation: .resumeInterruptedRotation)
    try saveRotationTransaction(
      HermesAuditKeyRotationTransaction(
        transactionID: transaction.transactionID,
        stage: .completed,
        oldSignerID: oldActive?.signerID,
        newSignerID: newKey.signerID,
        oldFingerprint: oldActive?.fingerprint,
        newFingerprint: newKey.publicKeyFingerprint,
        startedAt: transaction.startedAt,
        updatedAt: Date()
      ))
    try? fileManager.removeItem(at: rotationURL)
    return status()
  }

  public func abandonIncompleteRotation(confirm: Bool) throws {
    guard confirm else { throw HermesAuditSigningOperationalError.confirmationRequired }
    try? fileManager.removeItem(at: rotationURL)
  }

  private func accessStatus(active: HermesAuditPublicTrustAnchor?) -> HermesAuditKeyAccessStatus {
    guard let active else { return .setupRequired }
    switch keyManager.state(signerID: active.signerID, keyGenerationID: active.keyGenerationID) {
    case .active:
      guard let policy = loadPolicy() else { return .setupRequired }
      return policy.status
    case .locked:
      return .locked
    case .missing:
      return .setupRequired
    case .duplicate, .inaccessible:
      return .inaccessible
    case .retired:
      return .unsupported
    }
  }

  private func recoveryRequired(
    active: HermesAuditPublicTrustAnchor?,
    anchors: [HermesAuditPublicTrustAnchor],
    access: HermesAuditKeyAccessStatus
  ) -> HermesAuditSigningRecoveryOperation? {
    if loadRotationTransaction() != nil { return .resumeInterruptedRotation }
    if active == nil && anchors.isEmpty { return .recreateMissingSigningKey }
    if active == nil { return .importPublicTrustAnchors }
    if access == .setupRequired { return .recreateMissingSigningKey }
    if access == .identityMismatch { return .resetAuditSigningConfiguration }
    if access == .locked { return nil }
    return nil
  }

  private func releaseIdentityValidation(
    serviceExecutableURL: URL?
  ) -> HermesAuditSigningReleaseIdentityValidation {
    let app = HermesAuditAuthorizedCodeIdentity.current(role: "currentApp")
    let service = serviceExecutableURL.map {
      HermesAuditAuthorizedCodeIdentity.executable(role: "currentService", url: $0)
    }
    var issues: [String] = []
    if app.teamIdentifier == nil { issues.append("developer_id_unavailable") }
    if !app.hardenedRuntime { issues.append("hardened_runtime_unavailable") }
    if let service, app.teamIdentifier != nil, service.teamIdentifier != nil,
      app.teamIdentifier != service.teamIdentifier
    {
      issues.append("team_id_mismatch")
    }
    if let service, service.signingKind == "unsigned" { issues.append("service_unsigned") }
    let developerID = app.teamIdentifier != nil
    let passed = developerID && issues.isEmpty
    return HermesAuditSigningReleaseIdentityValidation(
      appIdentity: app,
      serviceIdentity: service,
      developerIDAvailable: developerID,
      validationPassed: passed,
      blocked: !passed,
      issueCodes: issues
    )
  }

  private func auditSetupEvent(
    actor: HermesAuditActor,
    status: HermesAuditKeyAccessStatus
  ) async throws {
    let store = try FileBackedHermesAuditStore(
      configuration: HermesAuditStoreConfiguration(root: auditRoot)
    )
    try await store.append(
      HermesAuditEvent.make(
        kind: .auditSigningAccessConfigured,
        actor: actor,
        outcome: .succeeded,
        reasonCode: "audit_signing_access_configured",
        metadata: try HermesAuditMetadata(["state": status.rawValue])
      ))
  }

  private func auditRecoveryEvent(
    actor: HermesAuditActor,
    operation: HermesAuditSigningRecoveryOperation
  ) async throws {
    let store = try FileBackedHermesAuditStore(
      configuration: HermesAuditStoreConfiguration(root: auditRoot)
    )
    try await store.append(
      HermesAuditEvent.make(
        kind: .auditSigningRecoveryPerformed,
        actor: actor,
        outcome: .succeeded,
        reasonCode: operation.rawValue
      ))
  }

  private var policyURL: URL { auditRoot.appendingPathComponent(Self.accessPolicyFileName) }
  private var rotationURL: URL {
    auditRoot.appendingPathComponent(Self.rotationTransactionFileName)
  }

  private func loadPolicy() -> HermesAuditKeyAccessPolicy? {
    guard fileManager.fileExists(atPath: policyURL.path) else { return nil }
    return try? decoder.decode(HermesAuditKeyAccessPolicy.self, from: Data(contentsOf: policyURL))
  }

  private func savePolicy(_ policy: HermesAuditKeyAccessPolicy) throws {
    try fileManager.createDirectory(
      at: auditRoot,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
    )
    try encoder.encode(policy).write(to: policyURL, options: [.atomic])
    chmod(policyURL.path, 0o600)
  }

  private func loadRotationTransaction() -> HermesAuditKeyRotationTransaction? {
    guard fileManager.fileExists(atPath: rotationURL.path) else { return nil }
    return try? decoder.decode(
      HermesAuditKeyRotationTransaction.self,
      from: Data(contentsOf: rotationURL)
    )
  }

  private func saveRotationTransaction(_ transaction: HermesAuditKeyRotationTransaction) throws {
    try fileManager.createDirectory(
      at: auditRoot,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
    )
    try encoder.encode(transaction).write(to: rotationURL, options: [.atomic])
    chmod(rotationURL.path, 0o600)
  }
}
