import Darwin
import Foundation
import Security

public struct HermesRequestID: Codable, Equatable, Hashable, Sendable, CustomStringConvertible {
  public static let prefix = "hrq_"
  public static let encodedRandomLength = 43
  public static let maximumLength = prefix.count + encodedRandomLength

  public let rawValue: String

  public static func generate() throws -> HermesRequestID {
    var bytes = [UInt8](repeating: 0, count: 32)
    let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    guard result == errSecSuccess else {
      throw HermesRequestStateStoreError.identifierGenerationFailed
    }
    return try HermesRequestID(rawValue: prefix + Data(bytes).base64URLEncodedString())
  }

  public init(rawValue: String) throws {
    guard Self.isValid(rawValue) else {
      throw HermesRequestStateStoreError.invalidRequestID
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

  public var description: String {
    rawValue
  }

  static func isValid(_ value: String) -> Bool {
    guard value.count == maximumLength, value.hasPrefix(prefix) else {
      return false
    }
    return value.dropFirst(prefix.count).allSatisfy { character in
      character.isASCII
        && (character.isLetter || character.isNumber || character == "-" || character == "_")
    }
  }
}

public struct HermesRequestBindingID: Codable, Equatable, Hashable, Sendable,
  CustomStringConvertible
{
  public static let maximumLength = 160
  public let rawValue: String

  public init(rawValue: String) throws {
    guard Self.isValid(rawValue) else {
      throw HermesRequestStateStoreError.invalidBindingID
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

  public var description: String {
    rawValue
  }

  static func isValid(_ value: String) -> Bool {
    guard !value.isEmpty, value.count <= maximumLength, value.hasPrefix("binding:v") else {
      return false
    }
    let components = value.split(separator: ":", omittingEmptySubsequences: false)
    guard components.count == 3, components[0] == "binding" else {
      return false
    }
    let version = components[1]
    guard version.hasPrefix("v"), version.dropFirst().allSatisfy(\.isNumber) else {
      return false
    }
    let name = components[2]
    guard !name.isEmpty, let first = name.first, first.isLetter || first.isNumber else {
      return false
    }
    return name.allSatisfy { character in
      character.isASCII
        && (character.isLetter || character.isNumber || character == "." || character == "_"
          || character == "-")
    }
  }
}

public struct HermesBackendSessionID: Codable, Equatable, Hashable, Sendable,
  CustomStringConvertible
{
  public static let maximumLength = 128
  public let rawValue: String

  public init(rawValue: String) throws {
    guard Self.isValid(rawValue) else {
      throw HermesRequestStateStoreError.invalidBackendSessionID
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

  public var description: String {
    rawValue
  }

  static func isValid(_ value: String) -> Bool {
    guard !value.isEmpty, value.count <= maximumLength else {
      return false
    }
    return value.allSatisfy { character in
      character.isASCII
        && (character.isLetter || character.isNumber || character == "." || character == "_"
          || character == "-")
    }
  }
}

public enum HermesRequestLifecycleState: String, Codable, CaseIterable, Equatable, Sendable {
  case accepted
  case queued
  case starting
  case running
  case waitingForApproval
  case cancelling
  case cancelled
  case completed
  case failed
  case interrupted

  public var isTerminal: Bool {
    switch self {
    case .cancelled, .completed, .failed, .interrupted:
      return true
    case .accepted, .queued, .starting, .running, .waitingForApproval, .cancelling:
      return false
    }
  }

  public func canTransition(to state: HermesRequestLifecycleState) -> Bool {
    if self == state {
      return true
    }
    switch (self, state) {
    case (.accepted, .queued), (.accepted, .failed), (.accepted, .cancelling),
      (.queued, .starting), (.queued, .cancelling), (.queued, .failed),
      (.starting, .running), (.starting, .cancelling), (.starting, .failed),
      (.running, .waitingForApproval), (.running, .cancelling), (.running, .completed),
      (.running, .failed), (.running, .interrupted),
      (.waitingForApproval, .running), (.waitingForApproval, .cancelling),
      (.waitingForApproval, .failed), (.waitingForApproval, .interrupted),
      (.cancelling, .cancelled), (.cancelling, .failed), (.cancelling, .interrupted):
      return true
    default:
      return false
    }
  }
}

public enum HermesRequestFailureCategory: String, Codable, Equatable, Sendable {
  case validation
  case backendUnavailable
  case protocolFailure
  case supervisorFailure
  case cancellation
  case interrupted
  case internalFailure
}

public struct HermesRequestFailure: Codable, Equatable, Sendable {
  public static let maximumCodeLength = 64
  public static let maximumSafeMessageLength = 512

  public let category: HermesRequestFailureCategory
  public let code: String
  public let safeMessage: String
  public let retryable: Bool

  public init(
    category: HermesRequestFailureCategory,
    code: String,
    safeMessage: String,
    retryable: Bool
  ) throws {
    guard Self.isValidCode(code) else {
      throw HermesRequestStateStoreError.invalidFailureMetadata
    }
    guard Self.isValidSafeMessage(safeMessage) else {
      throw HermesRequestStateStoreError.invalidFailureMetadata
    }
    self.category = category
    self.code = code
    self.safeMessage = safeMessage
    self.retryable = retryable
  }

  static func isValidCode(_ value: String) -> Bool {
    guard !value.isEmpty, value.count <= maximumCodeLength else {
      return false
    }
    return value.allSatisfy { character in
      character.isASCII
        && (character.isLetter || character.isNumber || character == "." || character == "_"
          || character == "-")
    }
  }

  static func isValidSafeMessage(_ value: String) -> Bool {
    guard !value.isEmpty, value.count <= maximumSafeMessageLength else {
      return false
    }
    return value.unicodeScalars.allSatisfy { scalar in
      scalar.value >= 0x20 && scalar.value != 0x7F
    }
  }
}

public enum HermesRequestResultAvailability: String, Codable, Equatable, Sendable {
  case unavailable
  case available
}

public enum HermesRequestResultContentClass: String, Codable, Equatable, Sendable {
  case text
  case image
  case file
  case mixed
  case redacted
}

public struct HermesRequestResultMetadata: Codable, Equatable, Sendable {
  public static let maximumSummaryLength = 512
  public static let maximumLocatorLength = 256

  public let availability: HermesRequestResultAvailability
  public let completedAt: Date
  public let contentClass: HermesRequestResultContentClass?
  public let redactedSummary: String?
  public let bridgeOwnedResultLocator: String?

  public init(
    availability: HermesRequestResultAvailability,
    completedAt: Date,
    contentClass: HermesRequestResultContentClass? = nil,
    redactedSummary: String? = nil,
    bridgeOwnedResultLocator: String? = nil
  ) throws {
    if let redactedSummary {
      guard Self.isValidBoundedText(redactedSummary, maximum: Self.maximumSummaryLength) else {
        throw HermesRequestStateStoreError.invalidResultMetadata
      }
    }
    if let bridgeOwnedResultLocator {
      guard Self.isValidLocator(bridgeOwnedResultLocator) else {
        throw HermesRequestStateStoreError.invalidResultMetadata
      }
    }
    self.availability = availability
    self.completedAt = completedAt
    self.contentClass = contentClass
    self.redactedSummary = redactedSummary
    self.bridgeOwnedResultLocator = bridgeOwnedResultLocator
  }

  static func isValidBoundedText(_ value: String, maximum: Int) -> Bool {
    guard value.count <= maximum else {
      return false
    }
    return value.unicodeScalars.allSatisfy { scalar in
      scalar.value >= 0x20 && scalar.value != 0x7F
    }
  }

  static func isValidLocator(_ value: String) -> Bool {
    guard !value.isEmpty, value.count <= maximumLocatorLength, value.hasPrefix("bridge-result:v")
    else {
      return false
    }
    return value.allSatisfy { character in
      character.isASCII
        && (character.isLetter || character.isNumber || character == ":" || character == "."
          || character == "_" || character == "-")
    }
  }
}

public struct HermesRequestRecord: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public let requestID: HermesRequestID
  public let bindingID: HermesRequestBindingID
  public let lifecycleState: HermesRequestLifecycleState
  public let createdAt: Date
  public let updatedAt: Date
  public let startedAt: Date?
  public let completedAt: Date?
  public let backendSessionID: HermesBackendSessionID?
  public let processLaunchID: UUID?
  public let cancellationRequested: Bool
  public let failure: HermesRequestFailure?
  public let result: HermesRequestResultMetadata?
  public let revision: Int

  public init(
    schemaVersion: Int = currentSchemaVersion,
    requestID: HermesRequestID,
    bindingID: HermesRequestBindingID,
    lifecycleState: HermesRequestLifecycleState,
    createdAt: Date,
    updatedAt: Date,
    startedAt: Date? = nil,
    completedAt: Date? = nil,
    backendSessionID: HermesBackendSessionID? = nil,
    processLaunchID: UUID? = nil,
    cancellationRequested: Bool = false,
    failure: HermesRequestFailure? = nil,
    result: HermesRequestResultMetadata? = nil,
    revision: Int = 0
  ) throws {
    guard schemaVersion == Self.currentSchemaVersion else {
      throw HermesRequestStateStoreError.unsupportedSchemaVersion(schemaVersion)
    }
    guard revision >= 0 else {
      throw HermesRequestStateStoreError.corruptRecord(requestID: requestID)
    }
    if lifecycleState == .completed, result == nil {
      throw HermesRequestStateStoreError.invalidResultMetadata
    }
    if lifecycleState == .failed, failure == nil {
      throw HermesRequestStateStoreError.invalidFailureMetadata
    }
    self.schemaVersion = schemaVersion
    self.requestID = requestID
    self.bindingID = bindingID
    self.lifecycleState = lifecycleState
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.startedAt = startedAt
    self.completedAt = completedAt
    self.backendSessionID = backendSessionID
    self.processLaunchID = processLaunchID
    self.cancellationRequested = cancellationRequested
    self.failure = failure
    self.result = result
    self.revision = revision
  }
}

public enum HermesRequestRecoveryDecision: String, Codable, Equatable, Sendable {
  case resumeEligible
  case reconcileWithSupervisor
  case reconcileWithProtocolClient
  case markInterrupted
  case noActionTerminal
}

public struct HermesRequestRecoveryItem: Equatable, Sendable {
  public let record: HermesRequestRecord
  public let decision: HermesRequestRecoveryDecision
}

public struct HermesRequestRetentionPolicy: Equatable, Sendable {
  public let terminalRecordAge: TimeInterval
  public let maximumRecordsToPrune: Int

  public init(terminalRecordAge: TimeInterval, maximumRecordsToPrune: Int = Int.max) {
    self.terminalRecordAge = max(0, terminalRecordAge)
    self.maximumRecordsToPrune = max(0, maximumRecordsToPrune)
  }
}

public enum HermesRequestStateStoreError: Error, Equatable, Sendable, CustomStringConvertible {
  case identifierGenerationFailed
  case invalidRequestID
  case invalidBindingID
  case invalidBackendSessionID
  case invalidFailureMetadata
  case invalidResultMetadata
  case duplicateRequest(HermesRequestID)
  case unknownRequest(HermesRequestID)
  case invalidTransition(from: HermesRequestLifecycleState, to: HermesRequestLifecycleState)
  case terminalRecordConflict(HermesRequestID)
  case revisionConflict(expected: Int, actual: Int)
  case unsupportedSchemaVersion(Int)
  case corruptRecord(requestID: HermesRequestID?)
  case storageRootInvalid(String)
  case storageBoundaryViolation
  case recordLimitExceeded(maximum: Int)
  case recordTooLarge(maximumBytes: Int)
  case persistenceFailed(String)

  public var description: String {
    switch self {
    case .identifierGenerationFailed:
      return "failed to generate Hermes request identifier"
    case .invalidRequestID:
      return "invalid Hermes request identifier"
    case .invalidBindingID:
      return "invalid Hermes request binding identifier"
    case .invalidBackendSessionID:
      return "invalid Hermes backend session identifier"
    case .invalidFailureMetadata:
      return "invalid redacted failure metadata"
    case .invalidResultMetadata:
      return "invalid result metadata"
    case .duplicateRequest(let requestID):
      return "duplicate Hermes request \(requestID)"
    case .unknownRequest(let requestID):
      return "unknown Hermes request \(requestID)"
    case .invalidTransition(let from, let to):
      return "invalid Hermes request transition \(from.rawValue) -> \(to.rawValue)"
    case .terminalRecordConflict(let requestID):
      return "terminal Hermes request conflict \(requestID)"
    case .revisionConflict(let expected, let actual):
      return "Hermes request revision conflict expected \(expected), actual \(actual)"
    case .unsupportedSchemaVersion(let version):
      return "unsupported Hermes request schema version \(version)"
    case .corruptRecord:
      return "corrupt Hermes request record"
    case .storageRootInvalid(let reason):
      return "invalid Hermes request storage root: \(reason)"
    case .storageBoundaryViolation:
      return "Hermes request storage boundary violation"
    case .recordLimitExceeded(let maximum):
      return "Hermes request record limit exceeded: \(maximum)"
    case .recordTooLarge(let maximumBytes):
      return "Hermes request record exceeds \(maximumBytes) bytes"
    case .persistenceFailed(let reason):
      return "Hermes request persistence failed: \(reason)"
    }
  }
}

public protocol HermesRequestStateStore: Sendable {
  @discardableResult
  func createAcceptedRequest(
    requestID: HermesRequestID,
    bindingID: HermesRequestBindingID,
    createdAt: Date
  ) async throws -> HermesRequestRecord

  func read(requestID: HermesRequestID) async throws -> HermesRequestRecord

  @discardableResult
  func transitionState(
    requestID: HermesRequestID,
    to state: HermesRequestLifecycleState,
    expectedRevision: Int?,
    updatedAt: Date
  ) async throws -> HermesRequestRecord

  @discardableResult
  func attachBackendSessionIdentity(
    requestID: HermesRequestID,
    backendSessionID: HermesBackendSessionID,
    processLaunchID: UUID?,
    expectedRevision: Int?,
    updatedAt: Date
  ) async throws -> HermesRequestRecord

  @discardableResult
  func requestCancellation(
    requestID: HermesRequestID,
    expectedRevision: Int?,
    updatedAt: Date
  ) async throws -> HermesRequestRecord

  @discardableResult
  func markCancelled(
    requestID: HermesRequestID,
    expectedRevision: Int?,
    completedAt: Date
  ) async throws -> HermesRequestRecord

  @discardableResult
  func markCompleted(
    requestID: HermesRequestID,
    result: HermesRequestResultMetadata,
    expectedRevision: Int?,
    completedAt: Date
  ) async throws -> HermesRequestRecord

  @discardableResult
  func markFailed(
    requestID: HermesRequestID,
    failure: HermesRequestFailure,
    expectedRevision: Int?,
    completedAt: Date
  ) async throws -> HermesRequestRecord

  func listRecoverableRequests() async throws -> [HermesRequestRecoveryItem]

  @discardableResult
  func pruneTerminalRecords(
    policy: HermesRequestRetentionPolicy,
    now: Date
  ) async throws -> Int
}

public actor InMemoryHermesRequestStateStore: HermesRequestStateStore {
  private var records: [HermesRequestID: HermesRequestRecord] = [:]
  private let maximumRecords: Int

  public init(maximumRecords: Int = 1_000) {
    self.maximumRecords = max(1, maximumRecords)
  }

  public func createAcceptedRequest(
    requestID: HermesRequestID,
    bindingID: HermesRequestBindingID,
    createdAt: Date = Date()
  ) async throws -> HermesRequestRecord {
    guard records[requestID] == nil else {
      throw HermesRequestStateStoreError.duplicateRequest(requestID)
    }
    guard records.count < maximumRecords else {
      throw HermesRequestStateStoreError.recordLimitExceeded(maximum: maximumRecords)
    }
    let record = try HermesRequestRecord(
      requestID: requestID,
      bindingID: bindingID,
      lifecycleState: .accepted,
      createdAt: createdAt,
      updatedAt: createdAt
    )
    records[requestID] = record
    return record
  }

  public func read(requestID: HermesRequestID) async throws -> HermesRequestRecord {
    guard let record = records[requestID] else {
      throw HermesRequestStateStoreError.unknownRequest(requestID)
    }
    return record
  }

  public func transitionState(
    requestID: HermesRequestID,
    to state: HermesRequestLifecycleState,
    expectedRevision: Int? = nil,
    updatedAt: Date = Date()
  ) async throws -> HermesRequestRecord {
    try mutate(requestID: requestID, expectedRevision: expectedRevision) { record in
      try Self.transition(record, to: state, updatedAt: updatedAt)
    }
  }

  public func attachBackendSessionIdentity(
    requestID: HermesRequestID,
    backendSessionID: HermesBackendSessionID,
    processLaunchID: UUID? = nil,
    expectedRevision: Int? = nil,
    updatedAt: Date = Date()
  ) async throws -> HermesRequestRecord {
    try mutate(requestID: requestID, expectedRevision: expectedRevision) { record in
      try Self.next(
        record,
        updatedAt: updatedAt,
        backendSessionID: backendSessionID,
        processLaunchID: processLaunchID ?? record.processLaunchID
      )
    }
  }

  public func requestCancellation(
    requestID: HermesRequestID,
    expectedRevision: Int? = nil,
    updatedAt: Date = Date()
  ) async throws -> HermesRequestRecord {
    try mutate(requestID: requestID, expectedRevision: expectedRevision) { record in
      try Self.requestCancellation(record, updatedAt: updatedAt)
    }
  }

  public func markCancelled(
    requestID: HermesRequestID,
    expectedRevision: Int? = nil,
    completedAt: Date = Date()
  ) async throws -> HermesRequestRecord {
    try mutate(requestID: requestID, expectedRevision: expectedRevision) { record in
      if record.lifecycleState == .cancelled {
        return record
      }
      guard record.lifecycleState.canTransition(to: .cancelled) else {
        throw HermesRequestStateStoreError.invalidTransition(
          from: record.lifecycleState, to: .cancelled)
      }
      return try Self.next(
        record,
        state: .cancelled,
        updatedAt: completedAt,
        completedAt: completedAt,
        cancellationRequested: true
      )
    }
  }

  public func markCompleted(
    requestID: HermesRequestID,
    result: HermesRequestResultMetadata,
    expectedRevision: Int? = nil,
    completedAt: Date = Date()
  ) async throws -> HermesRequestRecord {
    try mutate(requestID: requestID, expectedRevision: expectedRevision) { record in
      if record.lifecycleState == .completed {
        guard record.result == result else {
          throw HermesRequestStateStoreError.terminalRecordConflict(requestID)
        }
        return record
      }
      guard record.lifecycleState.canTransition(to: .completed) else {
        throw HermesRequestStateStoreError.invalidTransition(
          from: record.lifecycleState, to: .completed)
      }
      return try Self.next(
        record,
        state: .completed,
        updatedAt: completedAt,
        completedAt: completedAt,
        result: result
      )
    }
  }

  public func markFailed(
    requestID: HermesRequestID,
    failure: HermesRequestFailure,
    expectedRevision: Int? = nil,
    completedAt: Date = Date()
  ) async throws -> HermesRequestRecord {
    try mutate(requestID: requestID, expectedRevision: expectedRevision) { record in
      if record.lifecycleState == .failed {
        guard record.failure == failure else {
          throw HermesRequestStateStoreError.terminalRecordConflict(requestID)
        }
        return record
      }
      guard record.lifecycleState.canTransition(to: .failed) else {
        throw HermesRequestStateStoreError.invalidTransition(
          from: record.lifecycleState, to: .failed)
      }
      return try Self.next(
        record,
        state: .failed,
        updatedAt: completedAt,
        completedAt: completedAt,
        failure: failure
      )
    }
  }

  public func listRecoverableRequests() async throws -> [HermesRequestRecoveryItem] {
    records.values
      .sorted { $0.createdAt < $1.createdAt }
      .map { HermesRequestRecoveryItem(record: $0, decision: Self.recoveryDecision(for: $0)) }
  }

  public func pruneTerminalRecords(
    policy: HermesRequestRetentionPolicy,
    now: Date = Date()
  ) async throws -> Int {
    let candidates = records.values
      .filter {
        $0.lifecycleState.isTerminal
          && now.timeIntervalSince($0.completedAt ?? $0.updatedAt) >= policy.terminalRecordAge
      }
      .sorted { ($0.completedAt ?? $0.updatedAt) < ($1.completedAt ?? $1.updatedAt) }
      .prefix(policy.maximumRecordsToPrune)
    for record in candidates {
      records.removeValue(forKey: record.requestID)
    }
    return candidates.count
  }

  private func mutate(
    requestID: HermesRequestID,
    expectedRevision: Int?,
    _ body: (HermesRequestRecord) throws -> HermesRequestRecord
  ) throws -> HermesRequestRecord {
    guard let record = records[requestID] else {
      throw HermesRequestStateStoreError.unknownRequest(requestID)
    }
    if let expectedRevision, expectedRevision != record.revision {
      throw HermesRequestStateStoreError.revisionConflict(
        expected: expectedRevision, actual: record.revision)
    }
    let updated = try body(record)
    records[requestID] = updated
    return updated
  }

  fileprivate static func transition(
    _ record: HermesRequestRecord,
    to state: HermesRequestLifecycleState,
    updatedAt: Date
  ) throws -> HermesRequestRecord {
    guard record.lifecycleState.canTransition(to: state) else {
      throw HermesRequestStateStoreError.invalidTransition(from: record.lifecycleState, to: state)
    }
    let startedAt = record.startedAt ?? (state == .running ? updatedAt : nil)
    return try next(record, state: state, updatedAt: updatedAt, startedAt: startedAt)
  }

  fileprivate static func requestCancellation(
    _ record: HermesRequestRecord,
    updatedAt: Date
  ) throws -> HermesRequestRecord {
    if record.cancellationRequested || record.lifecycleState == .cancelled {
      return record
    }
    if record.lifecycleState.isTerminal {
      return record
    }
    guard record.lifecycleState.canTransition(to: .cancelling) else {
      throw HermesRequestStateStoreError.invalidTransition(
        from: record.lifecycleState, to: .cancelling)
    }
    return try next(
      record,
      state: .cancelling,
      updatedAt: updatedAt,
      cancellationRequested: true
    )
  }

  fileprivate static func recoveryDecision(
    for record: HermesRequestRecord
  ) -> HermesRequestRecoveryDecision {
    if record.lifecycleState.isTerminal {
      return .noActionTerminal
    }
    switch record.lifecycleState {
    case .accepted, .queued:
      return .resumeEligible
    case .starting:
      return .reconcileWithSupervisor
    case .running, .waitingForApproval, .cancelling:
      return record.backendSessionID == nil
        ? .reconcileWithSupervisor : .reconcileWithProtocolClient
    case .cancelled, .completed, .failed, .interrupted:
      return .noActionTerminal
    }
  }

  fileprivate static func next(
    _ record: HermesRequestRecord,
    state: HermesRequestLifecycleState? = nil,
    updatedAt: Date,
    startedAt: Date? = nil,
    completedAt: Date? = nil,
    backendSessionID: HermesBackendSessionID? = nil,
    processLaunchID: UUID? = nil,
    cancellationRequested: Bool? = nil,
    failure: HermesRequestFailure? = nil,
    result: HermesRequestResultMetadata? = nil
  ) throws -> HermesRequestRecord {
    try HermesRequestRecord(
      requestID: record.requestID,
      bindingID: record.bindingID,
      lifecycleState: state ?? record.lifecycleState,
      createdAt: record.createdAt,
      updatedAt: updatedAt,
      startedAt: startedAt ?? record.startedAt,
      completedAt: completedAt ?? record.completedAt,
      backendSessionID: backendSessionID ?? record.backendSessionID,
      processLaunchID: processLaunchID ?? record.processLaunchID,
      cancellationRequested: cancellationRequested ?? record.cancellationRequested,
      failure: failure ?? record.failure,
      result: result ?? record.result,
      revision: record.revision + 1
    )
  }
}

public actor FileBackedHermesRequestStateStore: HermesRequestStateStore {
  private let root: URL
  private let maximumRecords: Int
  private let maximumRecordBytes: Int
  private let fileManager: FileManager
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(
    storageRoot: URL,
    maximumRecords: Int = 1_000,
    maximumRecordBytes: Int = 64 * 1024,
    fileManager: FileManager = .default
  ) throws {
    self.root = storageRoot.standardizedFileURL
    self.maximumRecords = max(1, maximumRecords)
    self.maximumRecordBytes = max(1024, maximumRecordBytes)
    self.fileManager = fileManager
    self.encoder = JSONEncoder()
    self.decoder = JSONDecoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    decoder.dateDecodingStrategy = .iso8601
    try Self.secureStorageRoot(root, fileManager: fileManager)
  }

  public func createAcceptedRequest(
    requestID: HermesRequestID,
    bindingID: HermesRequestBindingID,
    createdAt: Date = Date()
  ) async throws -> HermesRequestRecord {
    try rejectEscapingRecordPaths()
    if try recordExists(requestID: requestID) {
      throw HermesRequestStateStoreError.duplicateRequest(requestID)
    }
    let count = try recordFileURLs().count
    guard count < maximumRecords else {
      throw HermesRequestStateStoreError.recordLimitExceeded(maximum: maximumRecords)
    }
    let record = try HermesRequestRecord(
      requestID: requestID,
      bindingID: bindingID,
      lifecycleState: .accepted,
      createdAt: createdAt,
      updatedAt: createdAt
    )
    try persist(record)
    return record
  }

  public func read(requestID: HermesRequestID) async throws -> HermesRequestRecord {
    try readExistingRecord(requestID: requestID)
  }

  public func transitionState(
    requestID: HermesRequestID,
    to state: HermesRequestLifecycleState,
    expectedRevision: Int? = nil,
    updatedAt: Date = Date()
  ) async throws -> HermesRequestRecord {
    try mutate(requestID: requestID, expectedRevision: expectedRevision) { record in
      try InMemoryHermesRequestStateStore.transition(record, to: state, updatedAt: updatedAt)
    }
  }

  public func attachBackendSessionIdentity(
    requestID: HermesRequestID,
    backendSessionID: HermesBackendSessionID,
    processLaunchID: UUID? = nil,
    expectedRevision: Int? = nil,
    updatedAt: Date = Date()
  ) async throws -> HermesRequestRecord {
    try mutate(requestID: requestID, expectedRevision: expectedRevision) { record in
      try InMemoryHermesRequestStateStore.next(
        record,
        updatedAt: updatedAt,
        backendSessionID: backendSessionID,
        processLaunchID: processLaunchID ?? record.processLaunchID
      )
    }
  }

  public func requestCancellation(
    requestID: HermesRequestID,
    expectedRevision: Int? = nil,
    updatedAt: Date = Date()
  ) async throws -> HermesRequestRecord {
    try mutate(requestID: requestID, expectedRevision: expectedRevision) { record in
      try InMemoryHermesRequestStateStore.requestCancellation(record, updatedAt: updatedAt)
    }
  }

  public func markCancelled(
    requestID: HermesRequestID,
    expectedRevision: Int? = nil,
    completedAt: Date = Date()
  ) async throws -> HermesRequestRecord {
    try mutate(requestID: requestID, expectedRevision: expectedRevision) { record in
      if record.lifecycleState == .cancelled {
        return record
      }
      guard record.lifecycleState.canTransition(to: .cancelled) else {
        throw HermesRequestStateStoreError.invalidTransition(
          from: record.lifecycleState, to: .cancelled)
      }
      return try InMemoryHermesRequestStateStore.next(
        record,
        state: .cancelled,
        updatedAt: completedAt,
        completedAt: completedAt,
        cancellationRequested: true
      )
    }
  }

  public func markCompleted(
    requestID: HermesRequestID,
    result: HermesRequestResultMetadata,
    expectedRevision: Int? = nil,
    completedAt: Date = Date()
  ) async throws -> HermesRequestRecord {
    try mutate(requestID: requestID, expectedRevision: expectedRevision) { record in
      if record.lifecycleState == .completed {
        guard record.result == result else {
          throw HermesRequestStateStoreError.terminalRecordConflict(requestID)
        }
        return record
      }
      guard record.lifecycleState.canTransition(to: .completed) else {
        throw HermesRequestStateStoreError.invalidTransition(
          from: record.lifecycleState, to: .completed)
      }
      return try InMemoryHermesRequestStateStore.next(
        record,
        state: .completed,
        updatedAt: completedAt,
        completedAt: completedAt,
        result: result
      )
    }
  }

  public func markFailed(
    requestID: HermesRequestID,
    failure: HermesRequestFailure,
    expectedRevision: Int? = nil,
    completedAt: Date = Date()
  ) async throws -> HermesRequestRecord {
    try mutate(requestID: requestID, expectedRevision: expectedRevision) { record in
      if record.lifecycleState == .failed {
        guard record.failure == failure else {
          throw HermesRequestStateStoreError.terminalRecordConflict(requestID)
        }
        return record
      }
      guard record.lifecycleState.canTransition(to: .failed) else {
        throw HermesRequestStateStoreError.invalidTransition(
          from: record.lifecycleState, to: .failed)
      }
      return try InMemoryHermesRequestStateStore.next(
        record,
        state: .failed,
        updatedAt: completedAt,
        completedAt: completedAt,
        failure: failure
      )
    }
  }

  public func listRecoverableRequests() async throws -> [HermesRequestRecoveryItem] {
    try recordFileURLs()
      .map { try readRecord(at: $0) }
      .sorted { $0.createdAt < $1.createdAt }
      .map {
        HermesRequestRecoveryItem(
          record: $0,
          decision: InMemoryHermesRequestStateStore.recoveryDecision(for: $0)
        )
      }
  }

  public func pruneTerminalRecords(
    policy: HermesRequestRetentionPolicy,
    now: Date = Date()
  ) async throws -> Int {
    let candidates = try recordFileURLs()
      .map { try readRecord(at: $0) }
      .filter {
        $0.lifecycleState.isTerminal
          && now.timeIntervalSince($0.completedAt ?? $0.updatedAt) >= policy.terminalRecordAge
      }
      .sorted { ($0.completedAt ?? $0.updatedAt) < ($1.completedAt ?? $1.updatedAt) }
      .prefix(policy.maximumRecordsToPrune)

    for record in candidates {
      try fileManager.removeItem(at: recordURL(for: record.requestID))
    }
    return candidates.count
  }

  private func mutate(
    requestID: HermesRequestID,
    expectedRevision: Int?,
    _ body: (HermesRequestRecord) throws -> HermesRequestRecord
  ) throws -> HermesRequestRecord {
    let record = try readExistingRecord(requestID: requestID)
    if let expectedRevision, expectedRevision != record.revision {
      throw HermesRequestStateStoreError.revisionConflict(
        expected: expectedRevision, actual: record.revision)
    }
    let updated = try body(record)
    if updated == record {
      return updated
    }
    try persist(updated)
    return updated
  }

  private static func secureStorageRoot(_ root: URL, fileManager: FileManager) throws {
    let path = root.path
    if isSymlink(path) {
      throw HermesRequestStateStoreError.storageRootInvalid("root is a symbolic link")
    }

    var isDirectory: ObjCBool = false
    if fileManager.fileExists(atPath: path, isDirectory: &isDirectory) {
      guard isDirectory.boolValue else {
        throw HermesRequestStateStoreError.storageRootInvalid("root is a file")
      }
    } else {
      do {
        try fileManager.createDirectory(
          at: root,
          withIntermediateDirectories: true,
          attributes: [.posixPermissions: 0o700]
        )
      } catch {
        throw HermesRequestStateStoreError.storageRootInvalid(String(describing: error))
      }
    }

    chmod(path, 0o700)
    if isSymlink(path) {
      throw HermesRequestStateStoreError.storageRootInvalid("root became a symbolic link")
    }
  }

  private func readExistingRecord(requestID: HermesRequestID) throws -> HermesRequestRecord {
    let url = recordURL(for: requestID)
    guard try recordExists(requestID: requestID) else {
      throw HermesRequestStateStoreError.unknownRequest(requestID)
    }
    return try readRecord(at: url)
  }

  private func readRecord(at url: URL) throws -> HermesRequestRecord {
    try rejectEscaping(url)
    guard !Self.isSymlink(url.path) else {
      throw HermesRequestStateStoreError.storageBoundaryViolation
    }
    let data = try boundedData(at: url)
    do {
      let envelope = try decoder.decode(HermesRequestRecord.self, from: data)
      guard envelope.schemaVersion == HermesRequestRecord.currentSchemaVersion else {
        throw HermesRequestStateStoreError.unsupportedSchemaVersion(envelope.schemaVersion)
      }
      return envelope
    } catch let error as HermesRequestStateStoreError {
      throw error
    } catch {
      throw HermesRequestStateStoreError.corruptRecord(requestID: nil)
    }
  }

  private func boundedData(at url: URL) throws -> Data {
    let attributes = try fileManager.attributesOfItem(atPath: url.path)
    if let size = attributes[.size] as? NSNumber, size.intValue > maximumRecordBytes {
      throw HermesRequestStateStoreError.recordTooLarge(maximumBytes: maximumRecordBytes)
    }
    let data = try Data(contentsOf: url)
    guard data.count <= maximumRecordBytes else {
      throw HermesRequestStateStoreError.recordTooLarge(maximumBytes: maximumRecordBytes)
    }
    return data
  }

  private func persist(_ record: HermesRequestRecord) throws {
    let data = try encoder.encode(record)
    guard data.count <= maximumRecordBytes else {
      throw HermesRequestStateStoreError.recordTooLarge(maximumBytes: maximumRecordBytes)
    }

    let destination = recordURL(for: record.requestID)
    try rejectEscaping(destination)
    guard !Self.isSymlink(destination.path) else {
      throw HermesRequestStateStoreError.storageBoundaryViolation
    }

    let temporary = root.appendingPathComponent(
      ".tmp-\(UUID().uuidString).json", isDirectory: false)
    try rejectEscaping(temporary)
    do {
      try data.write(to: temporary, options: [.withoutOverwriting])
      chmod(temporary.path, 0o600)
      try renameReplacingItem(at: temporary, with: destination)
      fsyncDirectory(root)
    } catch let error as HermesRequestStateStoreError {
      try? fileManager.removeItem(at: temporary)
      throw error
    } catch {
      try? fileManager.removeItem(at: temporary)
      throw HermesRequestStateStoreError.persistenceFailed(String(describing: error))
    }
  }

  private func renameReplacingItem(at source: URL, with destination: URL) throws {
    let result = source.path.withCString { sourcePath in
      destination.path.withCString { destinationPath in
        rename(sourcePath, destinationPath)
      }
    }
    guard result == 0 else {
      throw HermesRequestStateStoreError.persistenceFailed(String(cString: strerror(errno)))
    }
  }

  private func recordExists(requestID: HermesRequestID) throws -> Bool {
    let url = recordURL(for: requestID)
    try rejectEscaping(url)
    return fileManager.fileExists(atPath: url.path)
  }

  private func recordFileURLs() throws -> [URL] {
    try rejectEscapingRecordPaths()
    return try fileManager.contentsOfDirectory(
      at: root,
      includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
      options: []
    )
    .filter { $0.lastPathComponent.hasSuffix(".json") && !$0.lastPathComponent.hasPrefix(".tmp-") }
  }

  private func rejectEscapingRecordPaths() throws {
    let urls = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
    for url in urls {
      try rejectEscaping(url)
      if Self.isSymlink(url.path) {
        throw HermesRequestStateStoreError.storageBoundaryViolation
      }
    }
  }

  private func recordURL(for requestID: HermesRequestID) -> URL {
    root.appendingPathComponent(requestID.rawValue + ".json", isDirectory: false)
  }

  private func rejectEscaping(_ url: URL) throws {
    let standardizedRoot = root.standardizedFileURL.path
    let standardizedPath = url.standardizedFileURL.path
    guard standardizedPath == standardizedRoot || standardizedPath.hasPrefix(standardizedRoot + "/")
    else {
      throw HermesRequestStateStoreError.storageBoundaryViolation
    }
  }

  private static func isSymlink(_ path: String) -> Bool {
    var statBuffer = stat()
    return lstat(path, &statBuffer) == 0 && (statBuffer.st_mode & S_IFMT) == S_IFLNK
  }

  private func fsyncDirectory(_ url: URL) {
    let fd = open(url.path, O_RDONLY)
    if fd >= 0 {
      fsync(fd)
      close(fd)
    }
  }
}

extension Data {
  fileprivate func base64URLEncodedString() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
