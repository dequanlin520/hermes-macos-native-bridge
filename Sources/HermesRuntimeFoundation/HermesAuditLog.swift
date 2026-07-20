import CryptoKit
import Darwin
import Foundation
import Security

public struct HermesAuditEventID: Codable, Equatable, Hashable, Sendable,
  CustomStringConvertible
{
  public static let prefix = "haud_"
  public static let encodedRandomLength = 43
  public static let maximumLength = prefix.count + encodedRandomLength

  public let rawValue: String

  public static func generate() throws -> HermesAuditEventID {
    var bytes = [UInt8](repeating: 0, count: 32)
    let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    guard result == errSecSuccess else {
      throw HermesAuditError.identifierGenerationFailed
    }
    return try HermesAuditEventID(
      rawValue: prefix + Data(bytes).hermesAuditBase64URLEncodedString())
  }

  public init(rawValue: String) throws {
    guard Self.isValid(rawValue) else {
      throw HermesAuditError.invalidEventID
    }
    self.rawValue = rawValue
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    try self.init(rawValue: container.decode(String.self))
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  public var description: String { rawValue }

  public static func isValid(_ value: String) -> Bool {
    guard value.count == maximumLength, value.hasPrefix(prefix) else {
      return false
    }
    return value.dropFirst(prefix.count).allSatisfy {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_")
    }
  }
}

public enum HermesAuditEventKind: String, Codable, CaseIterable, Equatable, Sendable {
  case serviceInstalled
  case serviceStarted
  case serviceStopped
  case serviceRestarted
  case serviceUpgraded
  case serviceRolledBack
  case requestAccepted
  case requestStarted
  case requestCancelled
  case requestCompleted
  case requestFailed
  case approvalRequested
  case approvalResponded
  case authorizedRootAdded
  case authorizedRootRefreshed
  case authorizedRootDeactivated
  case authorizedRootRemoved
  case fileSubscriptionCreated
  case fileSubscriptionCancelled
  case fileRescanRequired
  case doctorExecuted
  case emergencyStopRequested
  case emergencyStopCompleted
  case auditExported
}

public enum HermesAuditActor: String, Codable, CaseIterable, Equatable, Sendable {
  case service
  case controlCLI
  case menuBar
  case appIntent
  case xpcClient
  case testFixture
  case unknown
}

public enum HermesAuditOutcome: String, Codable, CaseIterable, Equatable, Sendable {
  case accepted
  case started
  case succeeded
  case failed
  case cancelled
  case denied
  case unavailable
}

public struct HermesAuditMetadata: Codable, Equatable, Sendable {
  public static let maximumPairs = 16
  public static let maximumKeyCharacters = 40
  public static let maximumValueCharacters = 160
  public static let forbiddenKeyFragments = [
    "prompt", "token", "secret", "credential", "bookmark", "stdout", "stderr", "environment",
    "exception", "certificate", "private", "content", "path",
  ]

  public let values: [String: String]

  public init(_ values: [String: String] = [:]) throws {
    guard values.count <= Self.maximumPairs else {
      throw HermesAuditError.metadataRejected("too_many_pairs")
    }
    var sanitized: [String: String] = [:]
    for (key, value) in values {
      let safeKey = try Self.safeKey(key)
      let safeValue = try Self.safeValue(value)
      sanitized[safeKey] = safeValue
    }
    self.values = sanitized
  }

  public static func safeKey(_ key: String) throws -> String {
    let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty, normalized.count <= maximumKeyCharacters else {
      throw HermesAuditError.metadataRejected("invalid_key")
    }
    guard normalized.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) else {
      throw HermesAuditError.metadataRejected("invalid_key")
    }
    let lower = normalized.lowercased()
    guard !forbiddenKeyFragments.contains(where: { lower.contains($0) }) else {
      throw HermesAuditError.metadataRejected("forbidden_key")
    }
    return normalized
  }

  public static func safeValue(_ value: String) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count <= maximumValueCharacters else {
      throw HermesAuditError.metadataRejected("value_too_large")
    }
    guard !looksSensitive(trimmed) else {
      throw HermesAuditError.metadataRejected("sensitive_value")
    }
    let filtered = trimmed.unicodeScalars.filter { scalar in
      scalar.value >= 0x20 && scalar.value != 0x7F
    }
    return String(String.UnicodeScalarView(filtered))
  }

  public static func looksSensitive(_ value: String) -> Bool {
    let lower = value.lowercased()
    if lower.contains("prompt") || lower.contains("token") || lower.contains("bookmark") {
      return true
    }
    if lower.contains("file content") || lower.contains("contents of") {
      return true
    }
    if value.hasPrefix("/") || value.hasPrefix("~") {
      return true
    }
    if value.range(of: #"/Users/[A-Za-z0-9._-]+/"#, options: .regularExpression) != nil {
      return true
    }
    return false
  }
}

public struct HermesAuditEvent: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public let eventID: HermesAuditEventID
  public let timestamp: Date
  public let kind: HermesAuditEventKind
  public let actor: HermesAuditActor
  public let correlationID: String?
  public let requestID: String?
  public let rootID: String?
  public let subscriptionID: String?
  public let outcome: HermesAuditOutcome
  public let reasonCode: String
  public let metadata: HermesAuditMetadata

  public init(
    schemaVersion: Int = currentSchemaVersion,
    eventID: HermesAuditEventID,
    timestamp: Date,
    kind: HermesAuditEventKind,
    actor: HermesAuditActor,
    correlationID: String? = nil,
    requestID: String? = nil,
    rootID: String? = nil,
    subscriptionID: String? = nil,
    outcome: HermesAuditOutcome,
    reasonCode: String,
    metadata: HermesAuditMetadata = try! HermesAuditMetadata()
  ) throws {
    guard schemaVersion == Self.currentSchemaVersion else {
      throw HermesAuditError.unsupportedSchemaVersion
    }
    self.schemaVersion = schemaVersion
    self.eventID = eventID
    self.timestamp = timestamp
    self.kind = kind
    self.actor = actor
    self.correlationID = try correlationID.map(Self.safeToken)
    self.requestID = try requestID.map(Self.safeToken)
    self.rootID = try rootID.map(Self.safeToken)
    self.subscriptionID = try subscriptionID.map(Self.safeToken)
    self.outcome = outcome
    self.reasonCode = try Self.safeReasonCode(reasonCode)
    self.metadata = metadata
  }

  public static func make(
    kind: HermesAuditEventKind,
    actor: HermesAuditActor,
    outcome: HermesAuditOutcome,
    reasonCode: String,
    correlationID: String? = nil,
    requestID: String? = nil,
    rootID: String? = nil,
    subscriptionID: String? = nil,
    metadata: HermesAuditMetadata = try! HermesAuditMetadata(),
    timestamp: Date = Date()
  ) throws -> HermesAuditEvent {
    try HermesAuditEvent(
      eventID: HermesAuditEventID.generate(),
      timestamp: timestamp,
      kind: kind,
      actor: actor,
      correlationID: correlationID,
      requestID: requestID,
      rootID: rootID,
      subscriptionID: subscriptionID,
      outcome: outcome,
      reasonCode: reasonCode,
      metadata: metadata
    )
  }

  public static func safeToken(_ value: String) throws -> String {
    guard !HermesAuditMetadata.looksSensitive(value), !value.isEmpty, value.count <= 128 else {
      throw HermesAuditError.metadataRejected("invalid_token")
    }
    guard
      value.allSatisfy({
        $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-")
      })
    else {
      throw HermesAuditError.metadataRejected("invalid_token")
    }
    return value
  }

  public static func safeReasonCode(_ value: String) throws -> String {
    let token = try safeToken(value)
    guard token.count <= 64 else {
      throw HermesAuditError.metadataRejected("reason_too_large")
    }
    return token
  }
}

public struct HermesAuditQuery: Equatable, Sendable {
  public let start: Date?
  public let end: Date?
  public let kinds: Set<HermesAuditEventKind>?
  public let correlationID: String?
  public let limit: Int

  public init(
    start: Date? = nil,
    end: Date? = nil,
    kinds: Set<HermesAuditEventKind>? = nil,
    correlationID: String? = nil,
    limit: Int = 100
  ) throws {
    self.start = start
    self.end = end
    self.kinds = kinds
    self.correlationID = try correlationID.map(HermesAuditEvent.safeToken)
    self.limit = min(max(1, limit), 500)
  }

  func includes(_ event: HermesAuditEvent) -> Bool {
    if let start, event.timestamp < start { return false }
    if let end, event.timestamp > end { return false }
    if let kinds, !kinds.contains(event.kind) { return false }
    if let correlationID, event.correlationID != correlationID { return false }
    return true
  }
}

public struct HermesAuditStoreConfiguration: Equatable, Sendable {
  public let root: URL
  public let maximumFileBytes: Int
  public let maximumRetainedFiles: Int
  public let maximumRetainedEvents: Int

  public init(
    root: URL,
    maximumFileBytes: Int = 256 * 1024,
    maximumRetainedFiles: Int = 4,
    maximumRetainedEvents: Int = 10_000
  ) {
    self.root = root.standardizedFileURL
    self.maximumFileBytes = max(4096, maximumFileBytes)
    self.maximumRetainedFiles = min(max(1, maximumRetainedFiles), 32)
    self.maximumRetainedEvents = min(max(1, maximumRetainedEvents), 100_000)
  }
}

public enum HermesAuditError: Error, Equatable, Sendable, CustomStringConvertible {
  case identifierGenerationFailed
  case invalidEventID
  case unsupportedSchemaVersion
  case metadataRejected(String)
  case invalidStoreRoot(String)
  case persistenceFailed(String)
  case exportFailed(String)

  public var description: String {
    switch self {
    case .identifierGenerationFailed:
      return "audit identifier generation failed"
    case .invalidEventID:
      return "invalid audit event identifier"
    case .unsupportedSchemaVersion:
      return "unsupported audit schema version"
    case .metadataRejected(let code):
      return "audit metadata rejected: \(code)"
    case .invalidStoreRoot(let code):
      return "invalid audit store root: \(code)"
    case .persistenceFailed(let code):
      return "audit persistence failed: \(code)"
    case .exportFailed(let code):
      return "audit export failed: \(code)"
    }
  }
}

public protocol HermesAuditStore: Sendable {
  func append(_ event: HermesAuditEvent) async throws
  func query(_ query: HermesAuditQuery) async throws -> [HermesAuditEvent]
}

public struct NoopHermesAuditStore: HermesAuditStore {
  public init() {}
  public func append(_: HermesAuditEvent) async throws {}
  public func query(_: HermesAuditQuery) async throws -> [HermesAuditEvent] { [] }
}

public actor FileBackedHermesAuditStore: HermesAuditStore {
  public static let activeLogName = "audit.current.jsonl"

  private let configuration: HermesAuditStoreConfiguration
  private let fileManager: FileManager
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(configuration: HermesAuditStoreConfiguration, fileManager: FileManager = .default)
    throws
  {
    self.configuration = configuration
    self.fileManager = fileManager
    self.encoder = JSONEncoder()
    self.encoder.outputFormatting = [.sortedKeys]
    self.encoder.dateEncodingStrategy = .iso8601
    self.decoder = JSONDecoder()
    self.decoder.dateDecodingStrategy = .iso8601
    try Self.prepareRoot(configuration.root, fileManager: fileManager)
  }

  public func append(_ event: HermesAuditEvent) async throws {
    try validate(event)
    try rotateIfNeeded(extraBytes: encodedLine(event).count)
    let line = try encodedLine(event)
    let active = activeLogURL
    if !fileManager.fileExists(atPath: active.path) {
      fileManager.createFile(atPath: active.path, contents: nil)
      try setPermissions(active, 0o600)
    }
    let handle = try FileHandle(forWritingTo: active)
    try handle.seekToEnd()
    try handle.write(contentsOf: line)
    try handle.close()
    try setPermissions(active, 0o600)
    try enforceRetention()
  }

  public func query(_ query: HermesAuditQuery) async throws -> [HermesAuditEvent] {
    let files = try logFilesOldestFirst()
    var output: [HermesAuditEvent] = []
    for file in files {
      for event in try readEvents(from: file) where query.includes(event) {
        output.append(event)
      }
    }
    output.sort { lhs, rhs in
      if lhs.timestamp == rhs.timestamp { return lhs.eventID.rawValue < rhs.eventID.rawValue }
      return lhs.timestamp < rhs.timestamp
    }
    return Array(output.prefix(query.limit))
  }

  private var activeLogURL: URL {
    configuration.root.appendingPathComponent(Self.activeLogName)
  }

  private static func prepareRoot(_ root: URL, fileManager: FileManager) throws {
    guard root.isFileURL, !root.path.isEmpty else {
      throw HermesAuditError.invalidStoreRoot("non_file_url")
    }
    var info = stat()
    if lstat(root.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFLNK {
      throw HermesAuditError.invalidStoreRoot("symlink_root")
    }
    try fileManager.createDirectory(
      at: root,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
    )
    if lstat(root.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFLNK {
      throw HermesAuditError.invalidStoreRoot("symlink_root")
    }
    chmod(root.path, 0o700)
  }

  private func validate(_ event: HermesAuditEvent) throws {
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
  }

  private func encodedLine(_ event: HermesAuditEvent) throws -> Data {
    var data = try encoder.encode(event)
    data.append(0x0A)
    return data
  }

  private func rotateIfNeeded(extraBytes: Int) throws {
    let active = activeLogURL
    guard let size = try? fileManager.attributesOfItem(atPath: active.path)[.size] as? NSNumber
    else { return }
    guard size.intValue + extraBytes > configuration.maximumFileBytes else {
      return
    }
    let rotated = configuration.root.appendingPathComponent(
      "audit.\(Self.timestampForFilename(Date())).jsonl")
    if fileManager.fileExists(atPath: active.path) {
      try fileManager.moveItem(at: active, to: rotated)
      try setPermissions(rotated, 0o600)
    }
  }

  private func enforceRetention() throws {
    var rotated = try logFilesOldestFirst().filter { $0.lastPathComponent != Self.activeLogName }
    while rotated.count > configuration.maximumRetainedFiles - 1 {
      let victim = rotated.removeFirst()
      try fileManager.removeItem(at: victim)
    }
    let events = try queryAllEvents()
    guard events.count > configuration.maximumRetainedEvents else {
      return
    }
    try rewrite(events: Array(events.suffix(configuration.maximumRetainedEvents)))
  }

  private func queryAllEvents() throws -> [HermesAuditEvent] {
    var events: [HermesAuditEvent] = []
    for file in try logFilesOldestFirst() {
      events.append(contentsOf: try readEvents(from: file))
    }
    return events.sorted { $0.timestamp < $1.timestamp }
  }

  private func rewrite(events: [HermesAuditEvent]) throws {
    for file in try logFilesOldestFirst() {
      try? fileManager.removeItem(at: file)
    }
    for event in events {
      let line = try encodedLine(event)
      if !fileManager.fileExists(atPath: activeLogURL.path) {
        fileManager.createFile(atPath: activeLogURL.path, contents: nil)
      }
      let handle = try FileHandle(forWritingTo: activeLogURL)
      try handle.seekToEnd()
      try handle.write(contentsOf: line)
      try handle.close()
    }
    try setPermissions(activeLogURL, 0o600)
  }

  private func readEvents(from file: URL) throws -> [HermesAuditEvent] {
    guard let data = try? Data(contentsOf: file), !data.isEmpty else {
      return []
    }
    var events: [HermesAuditEvent] = []
    for line in String(decoding: data, as: UTF8.self).split(
      separator: "\n", omittingEmptySubsequences: true)
    {
      guard line.trimmingCharacters(in: .whitespaces).hasSuffix("}") else {
        continue
      }
      guard let recordData = String(line).data(using: .utf8),
        let event = try? decoder.decode(HermesAuditEvent.self, from: recordData),
        event.schemaVersion == HermesAuditEvent.currentSchemaVersion
      else {
        continue
      }
      events.append(event)
    }
    return events
  }

  private func logFilesOldestFirst() throws -> [URL] {
    let files =
      (try? fileManager.contentsOfDirectory(
        at: configuration.root,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles]
      )) ?? []
    return
      files
      .filter { $0.lastPathComponent.hasPrefix("audit.") && $0.pathExtension == "jsonl" }
      .sorted {
        if $0.lastPathComponent == Self.activeLogName { return false }
        if $1.lastPathComponent == Self.activeLogName { return true }
        return $0.lastPathComponent < $1.lastPathComponent
      }
  }

  private func setPermissions(_ url: URL, _ mode: Int16) throws {
    try fileManager.setAttributes(
      [.posixPermissions: NSNumber(value: mode)], ofItemAtPath: url.path)
    chmod(url.path, mode_t(mode))
  }

  private static func timestampForFilename(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
      .replacingOccurrences(of: ":", with: "")
      .replacingOccurrences(of: ".", with: "")
  }
}

public struct HermesAuditExportRequest: Equatable, Sendable {
  public let query: HermesAuditQuery
  public let outputDirectory: URL
  public let format: HermesAuditExportFormat

  public init(
    query: HermesAuditQuery,
    outputDirectory: URL,
    format: HermesAuditExportFormat = .jsonl
  ) {
    self.query = query
    self.outputDirectory = outputDirectory.standardizedFileURL
    self.format = format
  }
}

public enum HermesAuditExportFormat: String, Codable, Equatable, Sendable {
  case json
  case jsonl
}

public struct HermesAuditExportManifest: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let exportedAt: Date
  public let format: HermesAuditExportFormat
  public let eventCount: Int
  public let sha256: String
  public let dataFileName: String

  public init(
    schemaVersion: Int,
    exportedAt: Date,
    format: HermesAuditExportFormat,
    eventCount: Int,
    sha256: String,
    dataFileName: String
  ) {
    self.schemaVersion = schemaVersion
    self.exportedAt = exportedAt
    self.format = format
    self.eventCount = max(0, eventCount)
    self.sha256 = String(sha256.prefix(64))
    self.dataFileName = String(dataFileName.prefix(80))
  }
}

public struct HermesAuditExporter {
  private let store: any HermesAuditStore
  private let fileManager: FileManager

  public init(store: any HermesAuditStore, fileManager: FileManager = .default) {
    self.store = store
    self.fileManager = fileManager
  }

  public func export(_ request: HermesAuditExportRequest) async throws -> HermesAuditExportManifest
  {
    guard request.outputDirectory.isFileURL else {
      throw HermesAuditError.exportFailed("non_file_output")
    }
    try fileManager.createDirectory(
      at: request.outputDirectory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
    )
    let events = try await store.query(request.query)
    let dataFileName = request.format == .json ? "audit-export.json" : "audit-export.jsonl"
    let dataURL = request.outputDirectory.appendingPathComponent(dataFileName)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data: Data
    switch request.format {
    case .json:
      data = try encoder.encode(events)
    case .jsonl:
      let lineEncoder = JSONEncoder()
      lineEncoder.outputFormatting = [.sortedKeys]
      lineEncoder.dateEncodingStrategy = .iso8601
      data = try events.reduce(into: Data()) { partial, event in
        partial.append(try lineEncoder.encode(event))
        partial.append(0x0A)
      }
    }
    try data.write(to: dataURL, options: [.atomic])
    chmod(dataURL.path, 0o600)
    let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    let manifest = HermesAuditExportManifest(
      schemaVersion: 1,
      exportedAt: Date(),
      format: request.format,
      eventCount: events.count,
      sha256: checksum,
      dataFileName: dataFileName
    )
    let manifestData = try encoder.encode(manifest)
    try manifestData.write(
      to: request.outputDirectory.appendingPathComponent("manifest.json"), options: [.atomic])
    chmod(request.outputDirectory.appendingPathComponent("manifest.json").path, 0o600)
    try await store.append(
      HermesAuditEvent.make(
        kind: .auditExported,
        actor: .controlCLI,
        outcome: .succeeded,
        reasonCode: "export_complete",
        metadata: try HermesAuditMetadata([
          "format": request.format.rawValue,
          "eventCount": "\(events.count)",
          "checksum": checksum,
        ])
      ))
    return manifest
  }
}

extension Data {
  fileprivate func hermesAuditBase64URLEncodedString() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
