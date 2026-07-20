import CryptoKit
import Darwin
import Foundation
import Security

public struct HermesEventPolicyApprovalID: Codable, Equatable, Hashable, Sendable,
  CustomStringConvertible
{
  public static let prefix = "heapr_"
  public static let encodedRandomLength = 43
  public static let maximumLength = prefix.count + encodedRandomLength

  public let rawValue: String

  public static func generate() throws -> HermesEventPolicyApprovalID {
    var bytes = [UInt8](repeating: 0, count: 32)
    let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    guard result == errSecSuccess else {
      throw HermesEventPolicyApprovalError.identifierGenerationFailed
    }
    return try HermesEventPolicyApprovalID(
      rawValue: prefix + Data(bytes).hermesApprovalBase64URLEncodedString())
  }

  public init(rawValue: String) throws {
    guard Self.isValid(rawValue) else {
      throw HermesEventPolicyApprovalError.invalidApprovalID
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

public enum HermesEventPolicyApprovalState: String, Codable, CaseIterable, Equatable, Sendable {
  case pending
  case approved
  case denied
  case expired
  case cancelled
  case executing
  case executed
  case failedRedacted
  case invalidatedByPolicyChange
  case blockedByEmergencyStop

  public var isTerminal: Bool {
    switch self {
    case .pending, .approved, .executing:
      return false
    case .denied, .expired, .cancelled, .executed, .failedRedacted,
      .invalidatedByPolicyChange, .blockedByEmergencyStop:
      return true
    }
  }
}

public enum HermesEventPolicyApprovalDecision: String, Codable, CaseIterable, Equatable, Sendable {
  case approve
  case deny
  case cancel
  case expire
}

public enum HermesEventPolicyApprovalExecutionResult: String, Codable, CaseIterable, Equatable,
  Sendable
{
  case notExecuted
  case executed
  case denied
  case cancelled
  case expired
  case invalidatedByPolicyChange
  case blockedByEmergencyStop
  case blockedByGlobalPause
  case bindingUnavailable
  case eventTriggerDisabled
  case failedRedacted
}

public struct HermesEventPolicyApprovalRuntimeState: Equatable, Sendable {
  public let paused: Bool
  public let emergencyStopped: Bool

  public init(paused: Bool, emergencyStopped: Bool) {
    self.paused = paused
    self.emergencyStopped = emergencyStopped
  }
}

public struct HermesEventPolicyApprovalNotification: Equatable, Sendable {
  public let approvalID: HermesEventPolicyApprovalID
  public let policyDisplayName: String
  public let eventKind: HermesSystemEventKind
  public let actionSummary: String
  public let expiresAt: Date

  public init(
    approvalID: HermesEventPolicyApprovalID,
    policyDisplayName: String,
    eventKind: HermesSystemEventKind,
    actionSummary: String,
    expiresAt: Date
  ) throws {
    self.approvalID = approvalID
    self.policyDisplayName = try HermesEventPolicyApprovalSnapshot.safeSummary(policyDisplayName)
    self.eventKind = eventKind
    self.actionSummary = try HermesEventPolicyApprovalSnapshot.safeSummary(actionSummary)
    self.expiresAt = expiresAt
  }
}

public protocol HermesEventPolicyApprovalNotificationSending: Sendable {
  func notifyApprovalRequired(_ notification: HermesEventPolicyApprovalNotification) async throws
}

public struct NoopHermesEventPolicyApprovalNotificationSender:
  HermesEventPolicyApprovalNotificationSending
{
  public init() {}

  public func notifyApprovalRequired(_: HermesEventPolicyApprovalNotification) async throws {}
}

public struct HermesEventPolicyApprovalSnapshot: Codable, Equatable, Sendable {
  public static let maximumSummaryCharacters = 240

  public let approvalID: HermesEventPolicyApprovalID
  public let policyID: HermesEventPolicyID
  public let policyRevision: Int
  public let eventID: HermesSystemEventID
  public let eventKind: HermesSystemEventKind
  public let actionKind: HermesEventPolicyActionKind
  public let bindingID: HermesRequestBindingID?
  public let reviewedStaticTemplate: String?
  public let reviewedStaticTemplateDigest: String
  public let safeRenderedSummary: String
  public let createdAt: Date
  public let expiresAt: Date
  public let approvalRequirement: HermesEventPolicyApprovalRequirement
  public let correlationID: String

  public init(
    approvalID: HermesEventPolicyApprovalID,
    policyID: HermesEventPolicyID,
    policyRevision: Int,
    eventID: HermesSystemEventID,
    eventKind: HermesSystemEventKind,
    action: HermesEventPolicyAction,
    safeRenderedSummary: String,
    createdAt: Date,
    expiresAt: Date,
    approvalRequirement: HermesEventPolicyApprovalRequirement,
    correlationID: String
  ) throws {
    self.approvalID = approvalID
    self.policyID = policyID
    self.policyRevision = policyRevision
    self.eventID = eventID
    self.eventKind = eventKind
    self.actionKind = action.kind
    if case .submitApprovedBinding(let bindingID, let prompt) = action {
      self.bindingID = bindingID
      self.reviewedStaticTemplate = prompt.reviewedStaticTemplate
      self.reviewedStaticTemplateDigest = Self.digest(prompt.reviewedStaticTemplate)
    } else {
      self.bindingID = nil
      self.reviewedStaticTemplate = nil
      self.reviewedStaticTemplateDigest = Self.digest(action.kind.rawValue)
    }
    self.safeRenderedSummary = try Self.safeSummary(safeRenderedSummary)
    self.createdAt = createdAt
    self.expiresAt = expiresAt
    self.approvalRequirement = approvalRequirement
    self.correlationID = try Self.safeToken(correlationID, maximumCharacters: 128)
    try validate()
  }

  public func validate() throws {
    guard policyRevision > 0, expiresAt > createdAt else {
      throw HermesEventPolicyApprovalError.invalidSnapshot
    }
    _ = try Self.safeSummary(safeRenderedSummary)
    _ = try Self.safeToken(correlationID, maximumCharacters: 128)
    if let reviewedStaticTemplate {
      guard reviewedStaticTemplateDigest == Self.digest(reviewedStaticTemplate) else {
        throw HermesEventPolicyApprovalError.templateDigestMismatch
      }
      _ = try HermesEventPolicyPromptTemplate(reviewedStaticTemplate: reviewedStaticTemplate)
      guard bindingID != nil, actionKind == .submitApprovedBinding else {
        throw HermesEventPolicyApprovalError.invalidSnapshot
      }
    } else if bindingID != nil {
      throw HermesEventPolicyApprovalError.invalidSnapshot
    }
  }

  public static func digest(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  public static func safeSummary(_ value: String) throws -> String {
    let filtered = value.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F }
    let output = String(String.UnicodeScalarView(filtered)).prefixString(maximumSummaryCharacters)
    guard !output.isEmpty, !HermesAuditMetadata.looksSensitive(output) else {
      throw HermesEventPolicyApprovalError.invalidSnapshot
    }
    return output
  }

  public static func safeToken(_ value: String, maximumCharacters: Int) throws -> String {
    let output = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-")
    }
    guard !output.isEmpty, output.count <= maximumCharacters else {
      throw HermesEventPolicyApprovalError.invalidSnapshot
    }
    return output
  }
}

public struct HermesEventPolicyApprovalRequest: Codable, Equatable, Sendable {
  public let snapshot: HermesEventPolicyApprovalSnapshot
  public var state: HermesEventPolicyApprovalState
  public var decidedAt: Date?
  public var completedAt: Date?
  public var result: HermesEventPolicyApprovalExecutionResult
  public var reasonCode: String

  public init(
    snapshot: HermesEventPolicyApprovalSnapshot,
    state: HermesEventPolicyApprovalState = .pending,
    decidedAt: Date? = nil,
    completedAt: Date? = nil,
    result: HermesEventPolicyApprovalExecutionResult = .notExecuted,
    reasonCode: String = "pending"
  ) throws {
    try snapshot.validate()
    self.snapshot = snapshot
    self.state = state
    self.decidedAt = decidedAt
    self.completedAt = completedAt
    self.result = result
    self.reasonCode = try HermesSystemEvent.safeReasonCode(reasonCode)
  }
}

public struct HermesEventPolicyApprovalQueueStatus: Codable, Equatable, Sendable {
  public let pendingCount: Int
  public let retainedCount: Int
  public let oldestPendingCreatedAt: Date?

  public init(requests: [HermesEventPolicyApprovalRequest]) {
    let pending = requests.filter { $0.state == .pending }.sorted {
      if $0.snapshot.createdAt == $1.snapshot.createdAt {
        return $0.snapshot.approvalID.rawValue < $1.snapshot.approvalID.rawValue
      }
      return $0.snapshot.createdAt < $1.snapshot.createdAt
    }
    self.pendingCount = pending.count
    self.retainedCount = requests.count
    self.oldestPendingCreatedAt = pending.first?.snapshot.createdAt
  }
}

public enum HermesEventPolicyApprovalError: Error, Equatable, Sendable {
  case invalidApprovalID
  case identifierGenerationFailed
  case invalidSnapshot
  case templateDigestMismatch
  case approvalNotFound
  case pendingLimitExceeded
  case invalidState
  case conflictingDecision
  case revisionConflict
  case corruptStore(String)
  case invalidStoreRoot(String)
  case persistenceFailed(String)
}

public protocol HermesEventPolicyApprovalStore: Sendable {
  func listApprovals() async throws -> [HermesEventPolicyApprovalRequest]
  func createPending(_ request: HermesEventPolicyApprovalRequest) async throws
    -> HermesEventPolicyApprovalRequest
  func status(id: HermesEventPolicyApprovalID) async throws -> HermesEventPolicyApprovalRequest
  func transition(
    id: HermesEventPolicyApprovalID,
    to state: HermesEventPolicyApprovalState,
    result: HermesEventPolicyApprovalExecutionResult,
    reasonCode: String,
    decidedAt: Date?,
    completedAt: Date?
  ) async throws -> HermesEventPolicyApprovalRequest
  func sweepExpired(now: Date) async throws -> [HermesEventPolicyApprovalRequest]
}

public actor FileBackedHermesEventPolicyApprovalStore: HermesEventPolicyApprovalStore {
  public static let storeFileName = "event-policy-approvals.v1.json"
  public static let maximumPendingCount = 64
  public static let maximumRetainedCount = 256
  public static let defaultRetentionSeconds: TimeInterval = 7 * 24 * 60 * 60

  private struct StoreDocument: Codable {
    let schemaVersion: HermesEventPolicySchemaVersion
    var approvals: [HermesEventPolicyApprovalRequest]
  }

  private let root: URL
  private let fileManager: FileManager
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder
  private let retentionSeconds: TimeInterval

  public init(
    root: URL,
    fileManager: FileManager = .default,
    retentionSeconds: TimeInterval = defaultRetentionSeconds
  ) throws {
    self.root = root.standardizedFileURL
    self.fileManager = fileManager
    self.retentionSeconds = max(60, retentionSeconds)
    self.encoder = JSONEncoder()
    self.encoder.outputFormatting = [.sortedKeys]
    self.encoder.dateEncodingStrategy = .iso8601
    self.decoder = JSONDecoder()
    self.decoder.dateDecodingStrategy = .iso8601
    try Self.prepareRoot(self.root, fileManager: fileManager)
  }

  public func listApprovals() async throws -> [HermesEventPolicyApprovalRequest] {
    try load().approvals.sorted(by: deterministicOrder)
  }

  public func createPending(_ request: HermesEventPolicyApprovalRequest) async throws
    -> HermesEventPolicyApprovalRequest
  {
    guard request.state == .pending else {
      throw HermesEventPolicyApprovalError.invalidState
    }
    var document = try prune(load(), now: Date())
    guard document.approvals.filter({ $0.state == .pending }).count < Self.maximumPendingCount
    else {
      throw HermesEventPolicyApprovalError.pendingLimitExceeded
    }
    guard
      !document.approvals.contains(where: {
        $0.snapshot.approvalID == request.snapshot.approvalID
      })
    else {
      throw HermesEventPolicyApprovalError.invalidApprovalID
    }
    document.approvals.append(request)
    try save(document)
    return request
  }

  public func status(id: HermesEventPolicyApprovalID) async throws
    -> HermesEventPolicyApprovalRequest
  {
    guard let request = try load().approvals.first(where: { $0.snapshot.approvalID == id }) else {
      throw HermesEventPolicyApprovalError.approvalNotFound
    }
    return request
  }

  public func transition(
    id: HermesEventPolicyApprovalID,
    to state: HermesEventPolicyApprovalState,
    result: HermesEventPolicyApprovalExecutionResult,
    reasonCode: String,
    decidedAt: Date? = nil,
    completedAt: Date? = nil
  ) async throws -> HermesEventPolicyApprovalRequest {
    var document = try load()
    guard let index = document.approvals.firstIndex(where: { $0.snapshot.approvalID == id }) else {
      throw HermesEventPolicyApprovalError.approvalNotFound
    }
    var request = document.approvals[index]
    request.state = state
    request.result = result
    request.reasonCode = try HermesSystemEvent.safeReasonCode(reasonCode)
    request.decidedAt = decidedAt ?? request.decidedAt
    request.completedAt = completedAt ?? request.completedAt
    document.approvals[index] = request
    try save(try prune(document, now: completedAt ?? decidedAt ?? Date()))
    return request
  }

  public func sweepExpired(now: Date) async throws -> [HermesEventPolicyApprovalRequest] {
    var document = try load()
    var expired: [HermesEventPolicyApprovalRequest] = []
    for index in document.approvals.indices
    where document.approvals[index].state == .pending
      && document.approvals[index].snapshot.expiresAt <= now
    {
      document.approvals[index].state = .expired
      document.approvals[index].result = .expired
      document.approvals[index].reasonCode = "expired"
      document.approvals[index].completedAt = now
      expired.append(document.approvals[index])
    }
    try save(try prune(document, now: now))
    return expired
  }

  private var storeURL: URL {
    root.appendingPathComponent(Self.storeFileName)
  }

  private static func prepareRoot(_ root: URL, fileManager: FileManager) throws {
    guard root.isFileURL, !root.path.isEmpty, !root.path.contains("\u{0}") else {
      throw HermesEventPolicyApprovalError.invalidStoreRoot("invalid_url")
    }
    var info = stat()
    if lstat(root.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFLNK {
      throw HermesEventPolicyApprovalError.invalidStoreRoot("symlink_root")
    }
    try fileManager.createDirectory(
      at: root,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
    )
    if lstat(root.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFLNK {
      throw HermesEventPolicyApprovalError.invalidStoreRoot("symlink_root")
    }
    chmod(root.path, 0o700)
  }

  private func load() throws -> StoreDocument {
    guard fileManager.fileExists(atPath: storeURL.path) else {
      return StoreDocument(schemaVersion: .v1, approvals: [])
    }
    do {
      let data = try Data(contentsOf: storeURL)
      let document = try decoder.decode(StoreDocument.self, from: data)
      guard document.schemaVersion == .v1 else {
        throw HermesEventPolicyApprovalError.corruptStore("unsupported_schema")
      }
      guard document.approvals.count <= Self.maximumRetainedCount else {
        throw HermesEventPolicyApprovalError.corruptStore("too_many_approvals")
      }
      var seen = Set<HermesEventPolicyApprovalID>()
      for request in document.approvals {
        try request.snapshot.validate()
        guard seen.insert(request.snapshot.approvalID).inserted else {
          throw HermesEventPolicyApprovalError.corruptStore("duplicate_id")
        }
      }
      return document
    } catch let error as HermesEventPolicyApprovalError {
      throw error
    } catch {
      throw HermesEventPolicyApprovalError.corruptStore("decode_failed")
    }
  }

  private func prune(_ document: StoreDocument, now: Date) throws -> StoreDocument {
    let cutoff = now.addingTimeInterval(-retentionSeconds)
    let kept = document.approvals.filter {
      $0.state == .pending || ($0.completedAt ?? $0.decidedAt ?? $0.snapshot.createdAt) >= cutoff
    }
    let sorted = kept.sorted(by: deterministicOrder)
    return StoreDocument(
      schemaVersion: document.schemaVersion,
      approvals: Array(sorted.suffix(Self.maximumRetainedCount))
    )
  }

  private func save(_ document: StoreDocument) throws {
    do {
      let data = try encoder.encode(document)
      try data.write(to: storeURL, options: [.atomic])
      chmod(storeURL.path, 0o600)
    } catch let error as HermesEventPolicyApprovalError {
      throw error
    } catch {
      throw HermesEventPolicyApprovalError.persistenceFailed("write_failed")
    }
  }

  private func deterministicOrder(
    _ lhs: HermesEventPolicyApprovalRequest,
    _ rhs: HermesEventPolicyApprovalRequest
  ) -> Bool {
    if lhs.snapshot.createdAt == rhs.snapshot.createdAt {
      return lhs.snapshot.approvalID.rawValue < rhs.snapshot.approvalID.rawValue
    }
    return lhs.snapshot.createdAt < rhs.snapshot.createdAt
  }
}

public actor HermesEventPolicyApprovalCoordinator {
  public static let defaultLifetimeSeconds: TimeInterval = 10 * 60

  private let store: any HermesEventPolicyApprovalStore
  private let policyStore: any HermesEventPolicyStore
  private let bindingDiscovery: any HermesEventPolicyBindingDiscovering
  private let submitter: any HermesEventPolicyRequestSubmitting
  private let serviceManager: any HermesEventPolicyServiceManaging
  private let notificationSender: any HermesEventPolicyApprovalNotificationSending
  private let auditStore: any HermesAuditStore
  private let now: @Sendable () -> Date
  private let lifetimeSeconds: TimeInterval
  private var respondingApprovalIDs: Set<HermesEventPolicyApprovalID> = []

  public init(
    store: any HermesEventPolicyApprovalStore,
    policyStore: any HermesEventPolicyStore,
    bindingDiscovery: any HermesEventPolicyBindingDiscovering,
    submitter: any HermesEventPolicyRequestSubmitting,
    serviceManager: any HermesEventPolicyServiceManaging,
    notificationSender: any HermesEventPolicyApprovalNotificationSending =
      NoopHermesEventPolicyApprovalNotificationSender(),
    auditStore: any HermesAuditStore = NoopHermesAuditStore(),
    now: @escaping @Sendable () -> Date = Date.init,
    lifetimeSeconds: TimeInterval = defaultLifetimeSeconds
  ) {
    self.store = store
    self.policyStore = policyStore
    self.bindingDiscovery = bindingDiscovery
    self.submitter = submitter
    self.serviceManager = serviceManager
    self.notificationSender = notificationSender
    self.auditStore = auditStore
    self.now = now
    self.lifetimeSeconds = max(30, min(lifetimeSeconds, 60 * 60))
  }

  public func createApproval(
    policy: HermesEventPolicy,
    event: HermesSystemEvent,
    action: HermesEventPolicyAction,
    correlationID: String
  ) async throws -> HermesEventPolicyApprovalRequest {
    try policy.validate()
    if case .submitApprovedBinding(let bindingID, let template) = action {
      let bindings = try await bindingDiscovery.listEnabledEventPolicyBindings()
      guard let binding = bindings.first(where: { $0.bindingID == bindingID && $0.enabled }),
        binding.allowsEventTriggeredInvocation
      else {
        throw HermesEventPolicyApprovalError.invalidSnapshot
      }
      _ = try template.render(event: event, maximumPromptBytes: binding.maximumPromptBytes)
    }
    let createdAt = now()
    let summary = Self.summary(policy: policy, event: event, action: action)
    let snapshot = try HermesEventPolicyApprovalSnapshot(
      approvalID: .generate(),
      policyID: policy.id,
      policyRevision: policy.revision,
      eventID: event.eventID,
      eventKind: event.kind,
      action: action,
      safeRenderedSummary: summary,
      createdAt: createdAt,
      expiresAt: createdAt.addingTimeInterval(lifetimeSeconds),
      approvalRequirement: policy.approvalRequirement,
      correlationID: correlationID
    )
    let request = try HermesEventPolicyApprovalRequest(snapshot: snapshot)
    let created = try await store.createPending(request)
    try await audit(
      .eventPolicyApprovalCreated,
      request: created,
      outcome: .accepted,
      reasonCode: "created"
    )
    try? await notificationSender.notifyApprovalRequired(
      HermesEventPolicyApprovalNotification(
        approvalID: created.snapshot.approvalID,
        policyDisplayName: policy.id.rawValue,
        eventKind: event.kind,
        actionSummary: summary,
        expiresAt: created.snapshot.expiresAt
      ))
    return created
  }

  public func listApprovals() async throws -> [HermesEventPolicyApprovalRequest] {
    _ = try await sweepExpired()
    return try await store.listApprovals()
  }

  public func status(id: HermesEventPolicyApprovalID) async throws
    -> HermesEventPolicyApprovalRequest
  {
    _ = try await sweepExpired()
    return try await store.status(id: id)
  }

  public func deny(id: HermesEventPolicyApprovalID) async throws
    -> HermesEventPolicyApprovalRequest
  {
    try await terminalResponse(
      id: id,
      desiredState: .denied,
      idempotentState: .denied,
      result: .denied,
      auditKind: .eventPolicyApprovalDenied,
      reasonCode: "denied"
    )
  }

  public func cancel(id: HermesEventPolicyApprovalID) async throws
    -> HermesEventPolicyApprovalRequest
  {
    try await terminalResponse(
      id: id,
      desiredState: .cancelled,
      idempotentState: .cancelled,
      result: .cancelled,
      auditKind: .eventPolicyApprovalCancelled,
      reasonCode: "cancelled"
    )
  }

  public func expire(id: HermesEventPolicyApprovalID) async throws
    -> HermesEventPolicyApprovalRequest
  {
    try await terminalResponse(
      id: id,
      desiredState: .expired,
      idempotentState: .expired,
      result: .expired,
      auditKind: .eventPolicyApprovalExpired,
      reasonCode: "expired"
    )
  }

  public func approve(
    id: HermesEventPolicyApprovalID,
    runtimeState: HermesEventPolicyApprovalRuntimeState
  ) async throws -> HermesEventPolicyApprovalRequest {
    guard !respondingApprovalIDs.contains(id) else {
      throw HermesEventPolicyApprovalError.conflictingDecision
    }
    respondingApprovalIDs.insert(id)
    defer {
      respondingApprovalIDs.remove(id)
    }
    let current = try await store.status(id: id)
    switch current.state {
    case .executed, .approved:
      return current
    case .pending:
      break
    case .denied, .cancelled, .expired, .failedRedacted, .invalidatedByPolicyChange,
      .blockedByEmergencyStop, .executing:
      throw HermesEventPolicyApprovalError.conflictingDecision
    }
    if current.snapshot.expiresAt <= now() {
      return try await expire(id: id)
    }
    let approved = try await store.transition(
      id: id,
      to: .approved,
      result: .notExecuted,
      reasonCode: "approved",
      decidedAt: now(),
      completedAt: nil
    )
    try await audit(
      .eventPolicyApprovalApproved,
      request: approved,
      outcome: .accepted,
      reasonCode: "approved"
    )
    return try await executeApproved(approved, runtimeState: runtimeState)
  }

  public func queueStatus() async throws -> HermesEventPolicyApprovalQueueStatus {
    try await HermesEventPolicyApprovalQueueStatus(requests: listApprovals())
  }

  public func sweepExpired() async throws -> [HermesEventPolicyApprovalRequest] {
    let expired = try await store.sweepExpired(now: now())
    for request in expired {
      try await audit(
        .eventPolicyApprovalExpired,
        request: request,
        outcome: .denied,
        reasonCode: "expired"
      )
    }
    return expired
  }

  private func terminalResponse(
    id: HermesEventPolicyApprovalID,
    desiredState: HermesEventPolicyApprovalState,
    idempotentState: HermesEventPolicyApprovalState,
    result: HermesEventPolicyApprovalExecutionResult,
    auditKind: HermesAuditEventKind,
    reasonCode: String
  ) async throws -> HermesEventPolicyApprovalRequest {
    let current = try await store.status(id: id)
    if current.state == idempotentState {
      return current
    }
    guard current.state == .pending else {
      throw HermesEventPolicyApprovalError.conflictingDecision
    }
    let updated = try await store.transition(
      id: id,
      to: desiredState,
      result: result,
      reasonCode: reasonCode,
      decidedAt: now(),
      completedAt: now()
    )
    try await audit(auditKind, request: updated, outcome: .denied, reasonCode: reasonCode)
    return updated
  }

  private func executeApproved(
    _ approved: HermesEventPolicyApprovalRequest,
    runtimeState: HermesEventPolicyApprovalRuntimeState
  ) async throws -> HermesEventPolicyApprovalRequest {
    if runtimeState.emergencyStopped {
      let blocked = try await store.transition(
        id: approved.snapshot.approvalID,
        to: .blockedByEmergencyStop,
        result: .blockedByEmergencyStop,
        reasonCode: "emergency_stop",
        decidedAt: approved.decidedAt,
        completedAt: now()
      )
      try await audit(
        .eventPolicyApprovalInvalidated,
        request: blocked,
        outcome: .denied,
        reasonCode: "emergency_stop"
      )
      return blocked
    }
    if runtimeState.paused {
      let failed = try await store.transition(
        id: approved.snapshot.approvalID,
        to: .failedRedacted,
        result: .blockedByGlobalPause,
        reasonCode: "paused",
        decidedAt: approved.decidedAt,
        completedAt: now()
      )
      try await audit(
        .eventPolicyApprovalFailed,
        request: failed,
        outcome: .denied,
        reasonCode: "paused"
      )
      return failed
    }
    guard
      let policy = try await policyStore.listPolicies().first(where: {
        $0.id == approved.snapshot.policyID
      }), policy.enabled, policy.revision == approved.snapshot.policyRevision
    else {
      let invalidated = try await store.transition(
        id: approved.snapshot.approvalID,
        to: .invalidatedByPolicyChange,
        result: .invalidatedByPolicyChange,
        reasonCode: "policy_revision_mismatch",
        decidedAt: approved.decidedAt,
        completedAt: now()
      )
      try await audit(
        .eventPolicyApprovalInvalidated,
        request: invalidated,
        outcome: .denied,
        reasonCode: "policy_revision_mismatch"
      )
      return invalidated
    }
    let executing = try await store.transition(
      id: approved.snapshot.approvalID,
      to: .executing,
      result: .notExecuted,
      reasonCode: "executing",
      decidedAt: approved.decidedAt,
      completedAt: nil
    )
    do {
      try await execute(snapshot: executing.snapshot)
      let executed = try await store.transition(
        id: executing.snapshot.approvalID,
        to: .executed,
        result: .executed,
        reasonCode: "executed",
        decidedAt: executing.decidedAt,
        completedAt: now()
      )
      try await audit(
        .eventPolicyApprovalExecuted,
        request: executed,
        outcome: .succeeded,
        reasonCode: "executed"
      )
      return executed
    } catch let error as HermesEventPolicyApprovalError {
      let reason: String
      let result: HermesEventPolicyApprovalExecutionResult
      switch error {
      case .templateDigestMismatch:
        reason = "template_digest_mismatch"
        result = .failedRedacted
      case .invalidSnapshot:
        reason = "invalid_snapshot"
        result = .failedRedacted
      default:
        reason = "execution_failed"
        result = .failedRedacted
      }
      let failed = try await store.transition(
        id: executing.snapshot.approvalID,
        to: .failedRedacted,
        result: result,
        reasonCode: reason,
        decidedAt: executing.decidedAt,
        completedAt: now()
      )
      try await audit(
        .eventPolicyApprovalFailed, request: failed, outcome: .failed, reasonCode: reason)
      return failed
    } catch {
      let failed = try await store.transition(
        id: executing.snapshot.approvalID,
        to: .failedRedacted,
        result: .failedRedacted,
        reasonCode: "execution_failed",
        decidedAt: executing.decidedAt,
        completedAt: now()
      )
      try await audit(
        .eventPolicyApprovalFailed,
        request: failed,
        outcome: .failed,
        reasonCode: "execution_failed"
      )
      return failed
    }
  }

  private func execute(snapshot: HermesEventPolicyApprovalSnapshot) async throws {
    try snapshot.validate()
    switch snapshot.actionKind {
    case .recordAuditEvent, .markPolicyAttentionRequired, .createUserNotification:
      return
    case .refreshBridgeHealth:
      try await serviceManager.refreshBridgeHealth()
    case .restartBridgeService:
      try await serviceManager.restartBridgeService()
    case .submitApprovedBinding:
      guard let bindingID = snapshot.bindingID,
        let template = snapshot.reviewedStaticTemplate,
        snapshot.reviewedStaticTemplateDigest == HermesEventPolicyApprovalSnapshot.digest(template)
      else {
        throw HermesEventPolicyApprovalError.templateDigestMismatch
      }
      let bindings = try await bindingDiscovery.listEnabledEventPolicyBindings()
      guard let binding = bindings.first(where: { $0.bindingID == bindingID && $0.enabled }) else {
        throw HermesEventPolicyApprovalError.invalidSnapshot
      }
      guard binding.allowsEventTriggeredInvocation else {
        throw HermesEventPolicyApprovalError.invalidSnapshot
      }
      let promptTemplate = try HermesEventPolicyPromptTemplate(reviewedStaticTemplate: template)
      let safeEvent = try HermesSystemEvent(
        eventID: snapshot.eventID,
        kind: snapshot.eventKind,
        source: .testFixture,
        timestamp: snapshot.createdAt,
        reasonCode: "approved_snapshot"
      )
      let rendered = try promptTemplate.render(
        event: safeEvent,
        maximumPromptBytes: binding.maximumPromptBytes
      )
      _ = try await submitter.submit(bindingID: bindingID, prompt: rendered)
    }
  }

  private static func summary(
    policy: HermesEventPolicy,
    event: HermesSystemEvent,
    action: HermesEventPolicyAction
  ) -> String {
    "Policy \(policy.id.rawValue) \(event.kind.rawValue) \(action.kind.rawValue)"
  }

  private func audit(
    _ kind: HermesAuditEventKind,
    request: HermesEventPolicyApprovalRequest,
    outcome: HermesAuditOutcome,
    reasonCode: String
  ) async throws {
    try await auditStore.append(
      HermesAuditEvent.make(
        kind: kind,
        actor: .service,
        outcome: outcome,
        reasonCode: reasonCode,
        correlationID: request.snapshot.correlationID,
        metadata: try HermesAuditMetadata([
          "approval_id": request.snapshot.approvalID.rawValue,
          "state": request.state.rawValue,
          "policy_id": request.snapshot.policyID.rawValue,
          "event_kind": request.snapshot.eventKind.rawValue,
          "action_kind": request.snapshot.actionKind.rawValue,
          "reason_code": reasonCode,
        ])
      ))
  }
}

extension Data {
  fileprivate func hermesApprovalBase64URLEncodedString() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}

extension String {
  fileprivate func prefixString(_ count: Int) -> String {
    String(prefix(count))
  }
}
