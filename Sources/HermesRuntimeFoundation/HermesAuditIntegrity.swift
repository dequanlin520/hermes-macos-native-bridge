import CryptoKit
import Foundation

public struct HermesAuditDigest: Codable, Equatable, Hashable, Sendable,
  CustomStringConvertible
{
  public static let sha256ByteCount = 32
  public static let genesis = HermesAuditDigest(rawValue: String(repeating: "0", count: 64))!

  public let rawValue: String

  public init?(_ data: Data) {
    self.init(rawValue: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
  }

  public init?(rawValue: String) {
    guard rawValue.count == 64,
      rawValue.allSatisfy({ $0.isASCII && $0.isHexDigit && $0.isLowercaseHexDigit })
    else { return nil }
    self.rawValue = rawValue
  }

  public var description: String { rawValue }
}

extension Character {
  fileprivate var isLowercaseHexDigit: Bool {
    ("0"..."9").contains(self) || ("a"..."f").contains(self)
  }
}

public struct HermesAuditSegmentID: Codable, Equatable, Hashable, Sendable,
  CustomStringConvertible
{
  public static let prefix = "hseg_"
  public let rawValue: String

  public init(rawValue: String) throws {
    guard rawValue.hasPrefix(Self.prefix), rawValue.count <= 80,
      rawValue.allSatisfy({
        $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-")
      })
    else { throw HermesAuditError.persistenceFailed("invalid_segment_id") }
    self.rawValue = rawValue
  }

  public static func generate(date: Date = Date(), uuid: UUID = UUID()) throws
    -> HermesAuditSegmentID
  {
    try HermesAuditSegmentID(
      rawValue: "\(prefix)\(HermesAuditCanonical.timestampForIdentifier(date))_\(uuid.uuidString)")
  }

  public var description: String { rawValue }
}

public struct HermesAuditChainLink: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1
  public let schemaVersion: Int
  public let segmentID: HermesAuditSegmentID
  public let sequenceNumber: Int
  public let previousDigest: HermesAuditDigest
  public let eventDigest: HermesAuditDigest

  public init(
    schemaVersion: Int = currentSchemaVersion,
    segmentID: HermesAuditSegmentID,
    sequenceNumber: Int,
    previousDigest: HermesAuditDigest,
    eventDigest: HermesAuditDigest
  ) throws {
    guard schemaVersion == Self.currentSchemaVersion else {
      throw HermesAuditError.unsupportedSchemaVersion
    }
    guard sequenceNumber > 0 else {
      throw HermesAuditError.persistenceFailed("invalid_sequence")
    }
    self.schemaVersion = schemaVersion
    self.segmentID = segmentID
    self.sequenceNumber = sequenceNumber
    self.previousDigest = previousDigest
    self.eventDigest = eventDigest
  }
}

public struct HermesAuditRecord: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1
  public let recordSchemaVersion: Int
  public let event: HermesAuditEvent
  public let chain: HermesAuditChainLink

  public init(
    recordSchemaVersion: Int = currentSchemaVersion,
    event: HermesAuditEvent,
    chain: HermesAuditChainLink
  ) throws {
    guard recordSchemaVersion == Self.currentSchemaVersion else {
      throw HermesAuditError.unsupportedSchemaVersion
    }
    self.recordSchemaVersion = recordSchemaVersion
    self.event = event
    self.chain = chain
  }
}

public struct HermesAuditSegmentManifest: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1
  public let schemaVersion: Int
  public let segmentID: HermesAuditSegmentID
  public let firstSequence: Int
  public let lastSequence: Int
  public let eventCount: Int
  public let firstDigest: HermesAuditDigest
  public let terminalDigest: HermesAuditDigest
  public let previousSegmentManifestDigest: HermesAuditDigest?
  public let segmentFileSHA256: HermesAuditDigest
  public let createdAt: Date
  public let closedAt: Date
  public let signature: HermesAuditManifestSignature?

  public init(
    schemaVersion: Int = currentSchemaVersion,
    segmentID: HermesAuditSegmentID,
    firstSequence: Int,
    lastSequence: Int,
    eventCount: Int,
    firstDigest: HermesAuditDigest,
    terminalDigest: HermesAuditDigest,
    previousSegmentManifestDigest: HermesAuditDigest?,
    segmentFileSHA256: HermesAuditDigest,
    createdAt: Date,
    closedAt: Date,
    signature: HermesAuditManifestSignature? = nil
  ) throws {
    guard schemaVersion == Self.currentSchemaVersion else {
      throw HermesAuditError.unsupportedSchemaVersion
    }
    guard firstSequence > 0, lastSequence >= firstSequence, eventCount > 0 else {
      throw HermesAuditError.persistenceFailed("invalid_manifest_bounds")
    }
    self.schemaVersion = schemaVersion
    self.segmentID = segmentID
    self.firstSequence = firstSequence
    self.lastSequence = lastSequence
    self.eventCount = eventCount
    self.firstDigest = firstDigest
    self.terminalDigest = terminalDigest
    self.previousSegmentManifestDigest = previousSegmentManifestDigest
    self.segmentFileSHA256 = segmentFileSHA256
    self.createdAt = createdAt
    self.closedAt = closedAt
    self.signature = signature
  }
}

public enum HermesAuditIntegrityState: String, Codable, CaseIterable, Equatable, Sendable {
  case verified
  case verifiedUnsigned
  case verifiedSigned
  case incompleteRecoverableTail
  case corrupted
  case unsupported
  case signatureUnavailable
  case signatureInvalid
  case unknownSigner
  case retiredSignerValid
  case keyUnavailable
}

public enum HermesAuditIntegrityIssue: String, Codable, CaseIterable, Equatable, Sendable {
  case canonicalEncodingRejected
  case eventDigestMismatch
  case previousEventMismatch
  case sequenceGap
  case segmentChecksumMismatch
  case manifestChecksumMismatch
  case previousSegmentMismatch
  case expectedEventCountMismatch
  case unexpectedTruncation
  case missingSegment
  case duplicateSegment
  case reorderedSegment
  case unsupportedSchema
  case signatureUnavailable
  case signatureInvalid
  case unknownSigner
  case retiredSignerValid
  case keyUnavailable
  case recoverableActiveTail
  case corruptActiveTail
  case retainedChainAnchor
}

public struct HermesAuditVerificationReport: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1
  public let schemaVersion: Int
  public let state: HermesAuditIntegrityState
  public let verifiedSegmentCount: Int
  public let verifiedEventCount: Int
  public let issueCodes: [HermesAuditIntegrityIssue]
  public let verifiedAt: Date

  public init(
    schemaVersion: Int = currentSchemaVersion,
    state: HermesAuditIntegrityState,
    verifiedSegmentCount: Int,
    verifiedEventCount: Int,
    issueCodes: [HermesAuditIntegrityIssue],
    verifiedAt: Date = Date()
  ) {
    self.schemaVersion = schemaVersion
    self.state = state
    self.verifiedSegmentCount = max(0, verifiedSegmentCount)
    self.verifiedEventCount = max(0, verifiedEventCount)
    self.issueCodes = Array(Set(issueCodes)).sorted { $0.rawValue < $1.rawValue }
    self.verifiedAt = verifiedAt
  }
}

public struct HermesAuditExportIntegrityEvidence: Codable, Equatable, Sendable {
  public let state: HermesAuditIntegrityState
  public let verifiedSegmentCount: Int
  public let verifiedEventCount: Int
  public let issueCodes: [HermesAuditIntegrityIssue]
  public let verifiedAt: Date

  public init(report: HermesAuditVerificationReport) {
    self.state = report.state
    self.verifiedSegmentCount = report.verifiedSegmentCount
    self.verifiedEventCount = report.verifiedEventCount
    self.issueCodes = report.issueCodes
    self.verifiedAt = report.verifiedAt
  }
}

public enum HermesAuditCanonical {
  public static let eventEncodingSchemaVersion = 1

  public static func canonicalEventBytes(_ event: HermesAuditEvent) throws -> Data {
    _ = try HermesAuditEvent(
      schemaVersion: event.schemaVersion,
      eventID: event.eventID,
      timestamp: event.timestamp,
      kind: event.kind,
      actor: event.actor,
      correlationID: event.correlationID,
      requestID: event.requestID,
      rootID: event.rootID,
      subscriptionID: event.subscriptionID,
      outcome: event.outcome,
      reasonCode: event.reasonCode,
      metadata: event.metadata
    )
    var fields: [(String, Any)] = [
      ("canonicalSchemaVersion", eventEncodingSchemaVersion),
      ("eventSchemaVersion", event.schemaVersion),
      ("eventID", event.eventID.rawValue),
      ("timestamp", normalizedTimestamp(event.timestamp)),
      ("kind", event.kind.rawValue),
      ("actor", event.actor.rawValue),
      ("outcome", event.outcome.rawValue),
      ("correlationID", event.correlationID ?? NSNull()),
      ("requestID", event.requestID ?? NSNull()),
      ("rootID", event.rootID ?? NSNull()),
      ("subscriptionID", event.subscriptionID ?? NSNull()),
      ("reasonCode", event.reasonCode),
    ]
    let metadata = event.metadata.values.keys.sorted().map { key in
      (key, event.metadata.values[key] ?? "")
    }
    fields.append(("metadata", metadata.map { ["key": $0.0, "value": $0.1] }))
    return Data(canonicalJSONObject(fields).utf8)
  }

  public static func eventDigest(
    event: HermesAuditEvent,
    segmentID: HermesAuditSegmentID,
    sequenceNumber: Int,
    previousDigest: HermesAuditDigest
  ) throws -> HermesAuditDigest {
    let eventBytes = try canonicalEventBytes(event)
    let object = canonicalJSONObject([
      ("chainSchemaVersion", HermesAuditChainLink.currentSchemaVersion),
      ("segmentID", segmentID.rawValue),
      ("sequenceNumber", sequenceNumber),
      ("previousDigest", previousDigest.rawValue),
      ("eventCanonicalSHA256", HermesAuditDigest(eventBytes)!.rawValue),
    ])
    return HermesAuditDigest(Data(object.utf8))!
  }

  public static func manifestDigest(_ manifest: HermesAuditSegmentManifest) throws
    -> HermesAuditDigest
  {
    let data = try manifestEncoder.encode(manifest)
    return HermesAuditDigest(data)!
  }

  public static func normalizedTimestamp(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
  }

  public static func timestampForIdentifier(_ date: Date) -> String {
    normalizedTimestamp(date)
      .replacingOccurrences(of: ":", with: "")
      .replacingOccurrences(of: ".", with: "")
      .replacingOccurrences(of: "-", with: "")
  }

  public static var manifestEncoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }

  static func canonicalJSONObject(_ fields: [(String, Any)]) -> String {
    let values = fields.map { "\"\($0.0)\":\(canonicalValue($0.1))" }
    return "{\(values.joined(separator: ","))}"
  }

  private static func canonicalValue(_ value: Any) -> String {
    switch value {
    case is NSNull:
      return "null"
    case let string as String:
      return quote(string)
    case let integer as Int:
      return "\(integer)"
    case let array as [[String: String]]:
      return "["
        + array.map { item in
          canonicalJSONObject([
            ("key", item["key"] ?? ""),
            ("value", item["value"] ?? ""),
          ])
        }.joined(separator: ",") + "]"
    case let optional as String?:
      return optional.map(quote) ?? "null"
    default:
      return "null"
    }
  }

  private static func quote(_ value: String) -> String {
    let data = try! JSONEncoder().encode(value)
    return String(decoding: data, as: UTF8.self)
  }
}

public struct HermesAuditIntegrityVerifier {
  private let root: URL
  private let fileManager: FileManager
  private let signingProvider: any HermesAuditManifestSigningProvider
  private let manifestVerifier: HermesAuditManifestVerifier?
  private let decoder: JSONDecoder
  private let verifiedAt: @Sendable () -> Date

  public init(
    root: URL,
    fileManager: FileManager = .default,
    signingProvider: any HermesAuditManifestSigningProvider =
      HermesUnsignedAuditManifestSigningProvider(),
    trustAnchors: [HermesAuditPublicTrustAnchor] = [],
    verifiedAt: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.root = root.standardizedFileURL
    self.fileManager = fileManager
    self.signingProvider = signingProvider
    self.manifestVerifier =
      trustAnchors.isEmpty
      ? nil : HermesAuditManifestVerifier(trustAnchors: trustAnchors)
    self.decoder = JSONDecoder()
    self.decoder.dateDecodingStrategy = .iso8601
    self.verifiedAt = verifiedAt
  }

  public func verify() throws -> HermesAuditVerificationReport {
    let files = try fileManager.contentsOfDirectory(
      at: root,
      includingPropertiesForKeys: [.contentModificationDateKey],
      options: [.skipsHiddenFiles]
    )
    let segmentFiles = files.filter {
      $0.lastPathComponent.hasPrefix("audit.") && $0.pathExtension == "jsonl"
    }.sorted { lhs, rhs in
      segmentSortKey(lhs) < segmentSortKey(rhs)
    }

    var issues: [HermesAuditIntegrityIssue] = []
    var verifiedSegments = 0
    var verifiedEvents = 0
    var previousEventDigest = HermesAuditDigest.genesis
    var previousManifestDigest: HermesAuditDigest?
    var lastClosedManifestDigest: HermesAuditDigest?
    var seenSegments: Set<HermesAuditSegmentID> = []
    var anySignature = false
    var anyRetiredSignerValid = false
    var closedCount = 0

    let segmentFileNames = Set(segmentFiles.map(\.lastPathComponent))
    for manifest in files where manifest.lastPathComponent.hasSuffix(".manifest.json") {
      let expectedLog = manifest.lastPathComponent.replacingOccurrences(
        of: ".manifest.json",
        with: ".jsonl"
      )
      if !segmentFileNames.contains(expectedLog) {
        issues.append(.missingSegment)
      }
    }

    for file in segmentFiles {
      let active = file.lastPathComponent == FileBackedHermesAuditStore.activeLogName
      let parsed = parseRecords(file: file, active: active)
      issues.append(contentsOf: parsed.issues)
      if active, parsed.records.isEmpty {
        continue
      }
      guard let first = parsed.records.first else {
        if !active { issues.append(.unexpectedTruncation) }
        continue
      }
      let segmentID = first.chain.segmentID
      if seenSegments.contains(segmentID) { issues.append(.duplicateSegment) }
      seenSegments.insert(segmentID)
      let sameSegment = parsed.records.allSatisfy { $0.chain.segmentID == segmentID }
      if !sameSegment { issues.append(.reorderedSegment) }
      if previousManifestDigest == nil, previousEventDigest == .genesis,
        first.chain.previousDigest != .genesis,
        retainedAnchorIsBackedByManifest(segmentID: segmentID, active: active)
      {
        issues.append(.retainedChainAnchor)
        previousEventDigest = first.chain.previousDigest
      }
      if first.chain.previousDigest != previousEventDigest {
        issues.append(previousEventDigest == .genesis ? .previousEventMismatch : .missingSegment)
      }
      var expectedSequence = first.chain.sequenceNumber
      var segmentEvents = 0
      var firstDigest: HermesAuditDigest?
      var terminalDigest: HermesAuditDigest?
      var segmentValid = sameSegment
      for record in parsed.records {
        if record.chain.sequenceNumber != expectedSequence {
          issues.append(.sequenceGap)
          segmentValid = false
        }
        let expectedDigest = try HermesAuditCanonical.eventDigest(
          event: record.event,
          segmentID: record.chain.segmentID,
          sequenceNumber: record.chain.sequenceNumber,
          previousDigest: record.chain.previousDigest
        )
        if expectedDigest != record.chain.eventDigest {
          issues.append(.eventDigestMismatch)
          segmentValid = false
        }
        if record.chain.previousDigest != previousEventDigest {
          issues.append(.previousEventMismatch)
          segmentValid = false
        }
        firstDigest = firstDigest ?? record.chain.eventDigest
        terminalDigest = record.chain.eventDigest
        previousEventDigest = record.chain.eventDigest
        expectedSequence += 1
        segmentEvents += 1
      }
      verifiedEvents += segmentEvents

      if !active {
        closedCount += 1
        let manifestURL = manifestURL(for: segmentID)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
          issues.append(.missingSegment)
          continue
        }
        let manifestData = try Data(contentsOf: manifestURL)
        guard
          let manifest = try? decoder.decode(HermesAuditSegmentManifest.self, from: manifestData)
        else {
          issues.append(.unsupportedSchema)
          continue
        }
        if manifest.schemaVersion != HermesAuditSegmentManifest.currentSchemaVersion {
          issues.append(.unsupportedSchema)
        }
        if manifest.segmentID != segmentID { issues.append(.reorderedSegment) }
        if manifest.eventCount != segmentEvents { issues.append(.expectedEventCountMismatch) }
        if manifest.firstSequence != first.chain.sequenceNumber
          || manifest.lastSequence != parsed.records.last?.chain.sequenceNumber
        {
          issues.append(.sequenceGap)
        }
        if manifest.firstDigest != firstDigest { issues.append(.eventDigestMismatch) }
        if manifest.terminalDigest != terminalDigest { issues.append(.eventDigestMismatch) }
        if HermesAuditDigest((try Data(contentsOf: file))) != manifest.segmentFileSHA256 {
          issues.append(.segmentChecksumMismatch)
        }
        let manifestDigest = HermesAuditDigest(manifestData)!
        if let checksumData = try? Data(contentsOf: manifestChecksumURL(for: segmentID)),
          let checksum = String(data: checksumData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
          HermesAuditDigest(rawValue: checksum) != manifestDigest
        {
          issues.append(.manifestChecksumMismatch)
        }
        if manifest.previousSegmentManifestDigest != previousManifestDigest {
          if previousManifestDigest == nil, closedCount == 1 {
            issues.append(.retainedChainAnchor)
          } else {
            issues.append(.previousSegmentMismatch)
          }
        }
        if let signature = manifest.signature {
          anySignature = true
          let signatureDigest = try HermesAuditCanonical.manifestDigest(
            HermesAuditSegmentManifest(
              segmentID: manifest.segmentID,
              firstSequence: manifest.firstSequence,
              lastSequence: manifest.lastSequence,
              eventCount: manifest.eventCount,
              firstDigest: manifest.firstDigest,
              terminalDigest: manifest.terminalDigest,
              previousSegmentManifestDigest: manifest.previousSegmentManifestDigest,
              segmentFileSHA256: manifest.segmentFileSHA256,
              createdAt: manifest.createdAt,
              closedAt: manifest.closedAt,
              signature: nil
            ))
          if let manifestVerifier {
            switch manifestVerifier.verify(signature: signature, manifestDigest: signatureDigest) {
            case .verifiedSigned:
              break
            case .retiredSignerValid:
              anyRetiredSignerValid = true
              issues.append(.retiredSignerValid)
            case .signatureUnavailable:
              issues.append(.signatureUnavailable)
            case .signatureInvalid:
              issues.append(.signatureInvalid)
            case .unknownSigner:
              issues.append(.unknownSigner)
            case .keyUnavailable:
              issues.append(.keyUnavailable)
            }
          } else if signingProvider.signerID == nil {
            issues.append(.signatureUnavailable)
          } else if signingProvider.signerID != signature.signerID
            || signingProvider.publicKeyFingerprint != signature.publicKeyFingerprint
          {
            issues.append(.unknownSigner)
          } else if (try? signingProvider.verify(
            signature: signature, manifestDigest: signatureDigest))
            != true
          {
            issues.append(.signatureInvalid)
          }
        }
        previousManifestDigest = manifestDigest
        lastClosedManifestDigest = manifestDigest
        if segmentValid { verifiedSegments += 1 }
      } else if segmentValid {
        verifiedSegments += 1
      }
    }

    if let activeState = try? readState(),
      activeState.previousSegmentManifestDigest != lastClosedManifestDigest
    {
      issues.append(.previousSegmentMismatch)
    }

    let state = state(
      for: issues,
      anySignature: anySignature,
      anyRetiredSignerValid: anyRetiredSignerValid
    )
    return HermesAuditVerificationReport(
      state: state,
      verifiedSegmentCount: verifiedSegments,
      verifiedEventCount: verifiedEvents,
      issueCodes: issues,
      verifiedAt: verifiedAt()
    )
  }

  private func parseRecords(file: URL, active: Bool)
    -> (records: [HermesAuditRecord], issues: [HermesAuditIntegrityIssue])
  {
    guard let data = try? Data(contentsOf: file), !data.isEmpty else {
      return ([], active ? [] : [.unexpectedTruncation])
    }
    let text = String(decoding: data, as: UTF8.self)
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    var records: [HermesAuditRecord] = []
    var issues: [HermesAuditIntegrityIssue] = []
    for (index, rawLine) in lines.enumerated() {
      if rawLine.isEmpty, index == lines.count - 1 { continue }
      guard rawLine.trimmingCharacters(in: .whitespaces).hasSuffix("}") else {
        issues.append(
          active && index == lines.count - 1 ? .recoverableActiveTail : .unexpectedTruncation)
        continue
      }
      let recordData = Data(String(rawLine).utf8)
      guard let record = try? decoder.decode(HermesAuditRecord.self, from: recordData) else {
        issues.append(active && index == lines.count - 1 ? .corruptActiveTail : .unsupportedSchema)
        continue
      }
      guard record.recordSchemaVersion == HermesAuditRecord.currentSchemaVersion,
        record.event.schemaVersion == HermesAuditEvent.currentSchemaVersion,
        record.chain.schemaVersion == HermesAuditChainLink.currentSchemaVersion
      else {
        issues.append(.unsupportedSchema)
        continue
      }
      records.append(record)
    }
    return (records, issues)
  }

  private func state(
    for issues: [HermesAuditIntegrityIssue],
    anySignature: Bool,
    anyRetiredSignerValid: Bool
  ) -> HermesAuditIntegrityState {
    if issues.contains(.unsupportedSchema) { return .unsupported }
    if issues.contains(.signatureInvalid) { return .signatureInvalid }
    if issues.contains(.unknownSigner) { return .unknownSigner }
    if issues.contains(.keyUnavailable) { return .keyUnavailable }
    if issues.contains(.signatureUnavailable) { return .signatureUnavailable }
    var nonCorrupt = Set<HermesAuditIntegrityIssue>([
      .recoverableActiveTail, .retainedChainAnchor, .retiredSignerValid,
    ])
    if issues.contains(.retainedChainAnchor) {
      nonCorrupt.formUnion([.missingSegment, .previousEventMismatch, .previousSegmentMismatch])
    }
    if issues.allSatisfy({ nonCorrupt.contains($0) }) && issues.contains(.recoverableActiveTail) {
      return .incompleteRecoverableTail
    }
    if issues.contains(where: { !nonCorrupt.contains($0) }) { return .corrupted }
    if anyRetiredSignerValid { return .retiredSignerValid }
    return anySignature ? .verifiedSigned : .verifiedUnsigned
  }

  private func manifestURL(for segmentID: HermesAuditSegmentID) -> URL {
    root.appendingPathComponent("audit.\(segmentID.rawValue).manifest.json")
  }

  private func retainedAnchorIsBackedByManifest(
    segmentID: HermesAuditSegmentID,
    active: Bool
  ) -> Bool {
    guard !active,
      let data = try? Data(contentsOf: manifestURL(for: segmentID)),
      let manifest = try? decoder.decode(HermesAuditSegmentManifest.self, from: data)
    else { return false }
    return manifest.previousSegmentManifestDigest != nil
  }

  private func segmentSortKey(_ file: URL) -> String {
    if file.lastPathComponent == FileBackedHermesAuditStore.activeLogName {
      return "999999999999:\(file.lastPathComponent)"
    }
    let manifestURL = root.appendingPathComponent(
      file.lastPathComponent.replacingOccurrences(of: ".jsonl", with: ".manifest.json"))
    if let data = try? Data(contentsOf: manifestURL),
      let manifest = try? decoder.decode(HermesAuditSegmentManifest.self, from: data)
    {
      return String(format: "%012d:%@", manifest.firstSequence, file.lastPathComponent)
    }
    return "000000000000:\(file.lastPathComponent)"
  }

  private func manifestChecksumURL(for segmentID: HermesAuditSegmentID) -> URL {
    root.appendingPathComponent("audit.\(segmentID.rawValue).manifest.sha256")
  }

  private func readState() throws -> HermesAuditStoreChainState? {
    let url = root.appendingPathComponent(FileBackedHermesAuditStore.chainStateName)
    guard fileManager.fileExists(atPath: url.path) else { return nil }
    let data = try Data(contentsOf: url)
    return try decoder.decode(HermesAuditStoreChainState.self, from: data)
  }
}

public struct HermesAuditStoreChainState: Codable, Equatable, Sendable {
  public let segmentID: HermesAuditSegmentID
  public let createdAt: Date
  public let nextSequence: Int
  public let previousEventDigest: HermesAuditDigest
  public let previousSegmentManifestDigest: HermesAuditDigest?
}
