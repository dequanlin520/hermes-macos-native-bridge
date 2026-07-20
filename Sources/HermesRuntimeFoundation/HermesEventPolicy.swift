import Darwin
import Foundation
import Security

public struct HermesEventPolicyID: Codable, Equatable, Hashable, Sendable,
  CustomStringConvertible
{
  public static let prefix = "hepol_"
  public static let maximumLength = 80

  public let rawValue: String

  public init(rawValue: String) throws {
    guard Self.isValid(rawValue) else {
      throw HermesEventPolicyError.invalidPolicyID
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
    guard value.hasPrefix(prefix), value.count > prefix.count, value.count <= maximumLength else {
      return false
    }
    return value.dropFirst(prefix.count).allSatisfy {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-")
    }
  }
}

public enum HermesEventPolicySchemaVersion: Int, Codable, CaseIterable, Equatable, Sendable {
  case v1 = 1
}

public enum HermesEventPolicyExecutionMode: String, Codable, CaseIterable, Equatable, Sendable {
  case active
  case dryRun
}

public enum HermesEventPolicyApprovalRequirement: String, Codable, CaseIterable, Equatable,
  Sendable
{
  case noApproval
  case requireUserApproval
  case requireApprovalEveryTime
}

public enum HermesEventPolicyDecision: String, Codable, CaseIterable, Equatable, Sendable {
  case notMatched
  case matchedDryRun
  case blockedDisabled
  case blockedCooldown
  case blockedRateLimit
  case blockedApprovalRequired
  case blockedBindingUnavailable
  case blockedGlobalPause
  case executed
  case failedRedacted
}

public enum HermesEventPolicyActionKind: String, Codable, CaseIterable, Equatable, Sendable {
  case recordAuditEvent
  case refreshBridgeHealth
  case restartBridgeService
  case submitApprovedBinding
  case createUserNotification
  case markPolicyAttentionRequired
}

public enum HermesEventPolicyCondition: Codable, Equatable, Sendable {
  case eventKindEquals(HermesSystemEventKind)
  case applicationBundleIdentifierEquals(String)
  case networkAvailabilityEquals(HermesNetworkStatusClassification)
  case networkInterfaceTypeEquals(HermesNetworkInterfaceSummary)
  case serviceHealthStateEquals(HermesBridgeServiceHealthClassification)
  case constrainedNetworkEquals(Bool)
  case expensiveNetworkEquals(Bool)
  case boundedTimeWindow(startHour: Int, endHour: Int)
  case minimumIntervalSincePreviousMatch(seconds: TimeInterval)

  private enum CodingKeys: String, CodingKey {
    case type
    case eventKind
    case bundleIdentifier
    case networkStatus
    case networkInterface
    case serviceHealth
    case flag
    case startHour
    case endHour
    case seconds
  }

  private enum Kind: String, Codable {
    case eventKindEquals
    case applicationBundleIdentifierEquals
    case networkAvailabilityEquals
    case networkInterfaceTypeEquals
    case serviceHealthStateEquals
    case constrainedNetworkEquals
    case expensiveNetworkEquals
    case boundedTimeWindow
    case minimumIntervalSincePreviousMatch
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .type) {
    case .eventKindEquals:
      self = .eventKindEquals(try container.decode(HermesSystemEventKind.self, forKey: .eventKind))
    case .applicationBundleIdentifierEquals:
      self = .applicationBundleIdentifierEquals(
        try Self.safeBundleIdentifier(container.decode(String.self, forKey: .bundleIdentifier)))
    case .networkAvailabilityEquals:
      self = .networkAvailabilityEquals(
        try container.decode(HermesNetworkStatusClassification.self, forKey: .networkStatus))
    case .networkInterfaceTypeEquals:
      self = .networkInterfaceTypeEquals(
        try container.decode(HermesNetworkInterfaceSummary.self, forKey: .networkInterface))
    case .serviceHealthStateEquals:
      self = .serviceHealthStateEquals(
        try container.decode(HermesBridgeServiceHealthClassification.self, forKey: .serviceHealth))
    case .constrainedNetworkEquals:
      self = .constrainedNetworkEquals(try container.decode(Bool.self, forKey: .flag))
    case .expensiveNetworkEquals:
      self = .expensiveNetworkEquals(try container.decode(Bool.self, forKey: .flag))
    case .boundedTimeWindow:
      self = .boundedTimeWindow(
        startHour: try container.decode(Int.self, forKey: .startHour),
        endHour: try container.decode(Int.self, forKey: .endHour)
      )
    case .minimumIntervalSincePreviousMatch:
      self = .minimumIntervalSincePreviousMatch(
        seconds: try container.decode(TimeInterval.self, forKey: .seconds))
    }
    try validate()
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .eventKindEquals(let value):
      try container.encode(Kind.eventKindEquals, forKey: .type)
      try container.encode(value, forKey: .eventKind)
    case .applicationBundleIdentifierEquals(let value):
      try container.encode(Kind.applicationBundleIdentifierEquals, forKey: .type)
      try container.encode(value, forKey: .bundleIdentifier)
    case .networkAvailabilityEquals(let value):
      try container.encode(Kind.networkAvailabilityEquals, forKey: .type)
      try container.encode(value, forKey: .networkStatus)
    case .networkInterfaceTypeEquals(let value):
      try container.encode(Kind.networkInterfaceTypeEquals, forKey: .type)
      try container.encode(value, forKey: .networkInterface)
    case .serviceHealthStateEquals(let value):
      try container.encode(Kind.serviceHealthStateEquals, forKey: .type)
      try container.encode(value, forKey: .serviceHealth)
    case .constrainedNetworkEquals(let value):
      try container.encode(Kind.constrainedNetworkEquals, forKey: .type)
      try container.encode(value, forKey: .flag)
    case .expensiveNetworkEquals(let value):
      try container.encode(Kind.expensiveNetworkEquals, forKey: .type)
      try container.encode(value, forKey: .flag)
    case .boundedTimeWindow(let startHour, let endHour):
      try container.encode(Kind.boundedTimeWindow, forKey: .type)
      try container.encode(startHour, forKey: .startHour)
      try container.encode(endHour, forKey: .endHour)
    case .minimumIntervalSincePreviousMatch(let seconds):
      try container.encode(Kind.minimumIntervalSincePreviousMatch, forKey: .type)
      try container.encode(seconds, forKey: .seconds)
    }
  }

  func validate() throws {
    switch self {
    case .applicationBundleIdentifierEquals(let value):
      _ = try Self.safeBundleIdentifier(value)
    case .boundedTimeWindow(let startHour, let endHour):
      guard (0...23).contains(startHour), (0...23).contains(endHour) else {
        throw HermesEventPolicyError.invalidCondition
      }
    case .minimumIntervalSincePreviousMatch(let seconds):
      guard seconds.isFinite, seconds > 0, seconds <= 86_400 else {
        throw HermesEventPolicyError.invalidCondition
      }
    default:
      return
    }
  }

  static func safeBundleIdentifier(_ value: String) throws -> String {
    guard !value.isEmpty,
      value.count
        <= HermesSafeApplicationIdentity
        .maximumBundleIdentifierCharacters
    else {
      throw HermesEventPolicyError.invalidCondition
    }
    guard
      value.allSatisfy({
        $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_")
      })
    else {
      throw HermesEventPolicyError.invalidCondition
    }
    return value
  }
}

public enum HermesEventPolicyPromptPlaceholder: String, Codable, CaseIterable, Equatable,
  Sendable
{
  case eventKind
  case reasonCode
  case applicationBundleIdentifier
  case networkStatus
  case networkInterface
  case networkExpensive
  case networkConstrained
  case serviceHealth
}

public struct HermesEventPolicyPromptTemplate: Codable, Equatable, Sendable {
  public static let maximumTemplateBytes = 16 * 1024

  public let reviewedStaticTemplate: String

  public init(reviewedStaticTemplate: String) throws {
    guard !reviewedStaticTemplate.isEmpty,
      reviewedStaticTemplate.utf8.count <= Self.maximumTemplateBytes
    else {
      throw HermesEventPolicyError.invalidPromptTemplate
    }
    self.reviewedStaticTemplate = reviewedStaticTemplate
    _ = try Self.placeholders(in: reviewedStaticTemplate)
  }

  public func render(event: HermesSystemEvent, maximumPromptBytes: Int) throws -> String {
    let values: [HermesEventPolicyPromptPlaceholder: String] = [
      .eventKind: event.kind.rawValue,
      .reasonCode: event.reasonCode,
      .applicationBundleIdentifier: event.application?.bundleIdentifier ?? "unavailable",
      .networkStatus: event.networkStatus?.rawValue ?? "unknown",
      .networkInterface: event.networkInterface?.rawValue ?? "unknown",
      .networkExpensive: String(event.networkExpensive ?? false),
      .networkConstrained: String(event.networkConstrained ?? false),
      .serviceHealth: event.serviceHealth?.rawValue ?? "unknown",
    ]
    var rendered = reviewedStaticTemplate
    for placeholder in try Self.placeholders(in: reviewedStaticTemplate) {
      rendered = rendered.replacingOccurrences(
        of: "{{\(placeholder.rawValue)}}",
        with: values[placeholder] ?? "unknown"
      )
    }
    guard !rendered.isEmpty, rendered.utf8.count <= maximumPromptBytes else {
      throw HermesEventPolicyError.promptTooLarge
    }
    return rendered
  }

  static func placeholders(in value: String) throws -> Set<HermesEventPolicyPromptPlaceholder> {
    var output = Set<HermesEventPolicyPromptPlaceholder>()
    var remainder = value[...]
    while let start = remainder.range(of: "{{") {
      guard let end = remainder[start.upperBound...].range(of: "}}") else {
        throw HermesEventPolicyError.invalidPromptTemplate
      }
      let token = String(remainder[start.upperBound..<end.lowerBound])
      guard let placeholder = HermesEventPolicyPromptPlaceholder(rawValue: token) else {
        throw HermesEventPolicyError.unknownPromptPlaceholder
      }
      output.insert(placeholder)
      remainder = remainder[end.upperBound...]
    }
    return output
  }
}

public enum HermesEventPolicyAction: Codable, Equatable, Sendable {
  case recordAuditEvent(reasonCode: String)
  case refreshBridgeHealth
  case restartBridgeService
  case submitApprovedBinding(
    bindingID: HermesRequestBindingID, prompt: HermesEventPolicyPromptTemplate)
  case createUserNotification(title: String, body: String)
  case markPolicyAttentionRequired(reasonCode: String)

  public var kind: HermesEventPolicyActionKind {
    switch self {
    case .recordAuditEvent: .recordAuditEvent
    case .refreshBridgeHealth: .refreshBridgeHealth
    case .restartBridgeService: .restartBridgeService
    case .submitApprovedBinding: .submitApprovedBinding
    case .createUserNotification: .createUserNotification
    case .markPolicyAttentionRequired: .markPolicyAttentionRequired
    }
  }

  private enum CodingKeys: String, CodingKey {
    case type
    case reasonCode
    case bindingID
    case prompt
    case title
    case body
  }

  private enum Kind: String, Codable {
    case recordAuditEvent
    case refreshBridgeHealth
    case restartBridgeService
    case submitApprovedBinding
    case createUserNotification
    case markPolicyAttentionRequired
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .type) {
    case .recordAuditEvent:
      self = .recordAuditEvent(
        reasonCode: try Self.safeReasonCode(container.decode(String.self, forKey: .reasonCode)))
    case .refreshBridgeHealth:
      self = .refreshBridgeHealth
    case .restartBridgeService:
      self = .restartBridgeService
    case .submitApprovedBinding:
      self = .submitApprovedBinding(
        bindingID: try HermesRequestBindingID(
          rawValue: container.decode(String.self, forKey: .bindingID)),
        prompt: try container.decode(HermesEventPolicyPromptTemplate.self, forKey: .prompt)
      )
    case .createUserNotification:
      self = .createUserNotification(
        title: try Self.safeNotificationText(container.decode(String.self, forKey: .title)),
        body: try Self.safeNotificationText(container.decode(String.self, forKey: .body))
      )
    case .markPolicyAttentionRequired:
      self = .markPolicyAttentionRequired(
        reasonCode: try Self.safeReasonCode(container.decode(String.self, forKey: .reasonCode)))
    }
    try validate()
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .recordAuditEvent(let reasonCode):
      try container.encode(Kind.recordAuditEvent, forKey: .type)
      try container.encode(reasonCode, forKey: .reasonCode)
    case .refreshBridgeHealth:
      try container.encode(Kind.refreshBridgeHealth, forKey: .type)
    case .restartBridgeService:
      try container.encode(Kind.restartBridgeService, forKey: .type)
    case .submitApprovedBinding(let bindingID, let prompt):
      try container.encode(Kind.submitApprovedBinding, forKey: .type)
      try container.encode(bindingID.rawValue, forKey: .bindingID)
      try container.encode(prompt, forKey: .prompt)
    case .createUserNotification(let title, let body):
      try container.encode(Kind.createUserNotification, forKey: .type)
      try container.encode(title, forKey: .title)
      try container.encode(body, forKey: .body)
    case .markPolicyAttentionRequired(let reasonCode):
      try container.encode(Kind.markPolicyAttentionRequired, forKey: .type)
      try container.encode(reasonCode, forKey: .reasonCode)
    }
  }

  func validate() throws {
    switch self {
    case .recordAuditEvent(let reasonCode), .markPolicyAttentionRequired(let reasonCode):
      _ = try Self.safeReasonCode(reasonCode)
    case .createUserNotification(let title, let body):
      _ = try Self.safeNotificationText(title)
      _ = try Self.safeNotificationText(body)
    case .submitApprovedBinding:
      return
    case .refreshBridgeHealth, .restartBridgeService:
      return
    }
  }

  static func safeReasonCode(_ value: String) throws -> String {
    try HermesSystemEvent.safeReasonCode(value)
  }

  static func safeNotificationText(_ value: String) throws -> String {
    let filtered = value.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F }
    let output = String(String.UnicodeScalarView(filtered)).prefixString(120)
    guard !output.isEmpty, !HermesAuditMetadata.looksSensitive(output) else {
      throw HermesEventPolicyError.invalidAction
    }
    return output
  }
}

public struct HermesEventPolicy: Codable, Equatable, Sendable {
  public static let maximumConditions = 16
  public static let maximumActions = 8

  public let schemaVersion: HermesEventPolicySchemaVersion
  public let id: HermesEventPolicyID
  public var revision: Int
  public var enabled: Bool
  public var executionMode: HermesEventPolicyExecutionMode
  public var conditions: [HermesEventPolicyCondition]
  public var actions: [HermesEventPolicyAction]
  public var cooldownSeconds: TimeInterval
  public var maximumExecutionsPerMinute: Int
  public var suppressDuplicateEvents: Bool
  public var approvalRequirement: HermesEventPolicyApprovalRequirement
  public var createdAt: Date
  public var updatedAt: Date

  public init(
    schemaVersion: HermesEventPolicySchemaVersion = .v1,
    id: HermesEventPolicyID,
    revision: Int = 1,
    enabled: Bool = true,
    executionMode: HermesEventPolicyExecutionMode = .active,
    conditions: [HermesEventPolicyCondition],
    actions: [HermesEventPolicyAction],
    cooldownSeconds: TimeInterval = 0,
    maximumExecutionsPerMinute: Int = 6,
    suppressDuplicateEvents: Bool = true,
    approvalRequirement: HermesEventPolicyApprovalRequirement = .noApproval,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) throws {
    self.schemaVersion = schemaVersion
    self.id = id
    self.revision = revision
    self.enabled = enabled
    self.executionMode = executionMode
    self.conditions = conditions
    self.actions = actions
    self.cooldownSeconds = cooldownSeconds
    self.maximumExecutionsPerMinute = maximumExecutionsPerMinute
    self.suppressDuplicateEvents = suppressDuplicateEvents
    self.approvalRequirement = approvalRequirement
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    try validate()
  }

  public func validate() throws {
    guard schemaVersion == .v1 else {
      throw HermesEventPolicyError.unsupportedSchemaVersion
    }
    guard revision > 0 else {
      throw HermesEventPolicyError.invalidRevision
    }
    guard !conditions.isEmpty, conditions.count <= Self.maximumConditions else {
      throw HermesEventPolicyError.invalidCondition
    }
    guard !actions.isEmpty, actions.count <= Self.maximumActions else {
      throw HermesEventPolicyError.invalidAction
    }
    guard cooldownSeconds.isFinite, cooldownSeconds >= 0, cooldownSeconds <= 86_400 else {
      throw HermesEventPolicyError.invalidPolicy
    }
    guard (1...60).contains(maximumExecutionsPerMinute) else {
      throw HermesEventPolicyError.invalidPolicy
    }
    try conditions.forEach { try $0.validate() }
    try actions.forEach { try $0.validate() }
  }
}

public struct HermesEventPolicyEvaluation: Codable, Equatable, Sendable {
  public let policyID: HermesEventPolicyID
  public let policyRevision: Int
  public let eventID: HermesSystemEventID
  public let eventKind: HermesSystemEventKind
  public let actionKind: HermesEventPolicyActionKind?
  public let decision: HermesEventPolicyDecision
  public let reasonCode: String
  public let evaluatedAt: Date
  public let approvalID: HermesEventPolicyApprovalID?

  public init(
    policyID: HermesEventPolicyID,
    policyRevision: Int,
    eventID: HermesSystemEventID,
    eventKind: HermesSystemEventKind,
    actionKind: HermesEventPolicyActionKind?,
    decision: HermesEventPolicyDecision,
    reasonCode: String,
    evaluatedAt: Date = Date(),
    approvalID: HermesEventPolicyApprovalID? = nil
  ) throws {
    self.policyID = policyID
    self.policyRevision = policyRevision
    self.eventID = eventID
    self.eventKind = eventKind
    self.actionKind = actionKind
    self.decision = decision
    self.reasonCode = try HermesSystemEvent.safeReasonCode(reasonCode)
    self.evaluatedAt = evaluatedAt
    self.approvalID = approvalID
  }
}

public struct HermesEventPolicyExecutionRecord: Codable, Equatable, Sendable {
  public let policyID: HermesEventPolicyID
  public let eventID: HermesSystemEventID
  public let actionKind: HermesEventPolicyActionKind
  public let decision: HermesEventPolicyDecision
  public let reasonCode: String
  public let executedAt: Date

  public init(
    policyID: HermesEventPolicyID,
    eventID: HermesSystemEventID,
    actionKind: HermesEventPolicyActionKind,
    decision: HermesEventPolicyDecision,
    reasonCode: String,
    executedAt: Date = Date()
  ) throws {
    self.policyID = policyID
    self.eventID = eventID
    self.actionKind = actionKind
    self.decision = decision
    self.reasonCode = try HermesSystemEvent.safeReasonCode(reasonCode)
    self.executedAt = executedAt
  }
}

public struct HermesEventPolicyEngineStatus: Codable, Equatable, Sendable {
  public let enabledPolicyCount: Int
  public let paused: Bool
  public let emergencyStopped: Bool
  public let circuitBreakerOpen: Bool
  public let consecutiveFailures: Int
  public let recentDecisions: [HermesEventPolicyEvaluation]

  public init(
    enabledPolicyCount: Int,
    paused: Bool,
    emergencyStopped: Bool,
    circuitBreakerOpen: Bool,
    consecutiveFailures: Int,
    recentDecisions: [HermesEventPolicyEvaluation]
  ) {
    self.enabledPolicyCount = enabledPolicyCount
    self.paused = paused
    self.emergencyStopped = emergencyStopped
    self.circuitBreakerOpen = circuitBreakerOpen
    self.consecutiveFailures = consecutiveFailures
    self.recentDecisions = Array(recentDecisions.prefix(20))
  }
}

public enum HermesEventPolicyError: Error, Equatable, Sendable {
  case invalidPolicyID
  case unsupportedSchemaVersion
  case invalidRevision
  case revisionConflict
  case duplicatePolicyID
  case policyNotFound
  case policyLimitExceeded
  case invalidPolicy
  case invalidCondition
  case invalidAction
  case invalidPromptTemplate
  case unknownPromptPlaceholder
  case promptTooLarge
  case invalidStoreRoot(String)
  case corruptStore(String)
  case persistenceFailed(String)
}

public protocol HermesEventPolicyStore: Sendable {
  func listPolicies() async throws -> [HermesEventPolicy]
  func createPolicy(_ policy: HermesEventPolicy) async throws -> HermesEventPolicy
  func updatePolicy(_ policy: HermesEventPolicy, expectedRevision: Int) async throws
    -> HermesEventPolicy
  func enablePolicy(id: HermesEventPolicyID, expectedRevision: Int?) async throws
    -> HermesEventPolicy
  func disablePolicy(id: HermesEventPolicyID, expectedRevision: Int?) async throws
    -> HermesEventPolicy
  func removePolicy(id: HermesEventPolicyID, expectedRevision: Int?) async throws
}

public actor FileBackedHermesEventPolicyStore: HermesEventPolicyStore {
  public static let storeFileName = "event-policies.v1.json"
  public static let maximumPolicyCount = 64

  private struct StoreDocument: Codable {
    let schemaVersion: HermesEventPolicySchemaVersion
    var policies: [HermesEventPolicy]
  }

  private let root: URL
  private let fileManager: FileManager
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(root: URL, fileManager: FileManager = .default) throws {
    self.root = root.standardizedFileURL
    self.fileManager = fileManager
    self.encoder = JSONEncoder()
    self.encoder.outputFormatting = [.sortedKeys]
    self.encoder.dateEncodingStrategy = .iso8601
    self.decoder = JSONDecoder()
    self.decoder.dateDecodingStrategy = .iso8601
    try Self.prepareRoot(self.root, fileManager: fileManager)
  }

  public func listPolicies() async throws -> [HermesEventPolicy] {
    try load().policies.sorted { $0.id.rawValue < $1.id.rawValue }
  }

  public func createPolicy(_ policy: HermesEventPolicy) async throws -> HermesEventPolicy {
    var document = try load()
    guard document.policies.count < Self.maximumPolicyCount else {
      throw HermesEventPolicyError.policyLimitExceeded
    }
    guard !document.policies.contains(where: { $0.id == policy.id }) else {
      throw HermesEventPolicyError.duplicatePolicyID
    }
    var created = policy
    created.revision = 1
    created.createdAt = Date()
    created.updatedAt = created.createdAt
    try created.validate()
    document.policies.append(created)
    try save(document)
    return created
  }

  public func updatePolicy(_ policy: HermesEventPolicy, expectedRevision: Int) async throws
    -> HermesEventPolicy
  {
    var document = try load()
    guard let index = document.policies.firstIndex(where: { $0.id == policy.id }) else {
      throw HermesEventPolicyError.policyNotFound
    }
    guard document.policies[index].revision == expectedRevision else {
      throw HermesEventPolicyError.revisionConflict
    }
    var updated = policy
    updated.revision = expectedRevision + 1
    updated.createdAt = document.policies[index].createdAt
    updated.updatedAt = Date()
    try updated.validate()
    document.policies[index] = updated
    try save(document)
    return updated
  }

  public func enablePolicy(id: HermesEventPolicyID, expectedRevision: Int?) async throws
    -> HermesEventPolicy
  {
    try mutateEnabled(id: id, enabled: true, expectedRevision: expectedRevision)
  }

  public func disablePolicy(id: HermesEventPolicyID, expectedRevision: Int?) async throws
    -> HermesEventPolicy
  {
    try mutateEnabled(id: id, enabled: false, expectedRevision: expectedRevision)
  }

  public func removePolicy(id: HermesEventPolicyID, expectedRevision: Int?) async throws {
    var document = try load()
    guard let index = document.policies.firstIndex(where: { $0.id == id }) else {
      throw HermesEventPolicyError.policyNotFound
    }
    if let expectedRevision, document.policies[index].revision != expectedRevision {
      throw HermesEventPolicyError.revisionConflict
    }
    document.policies.remove(at: index)
    try save(document)
  }

  private func mutateEnabled(
    id: HermesEventPolicyID,
    enabled: Bool,
    expectedRevision: Int?
  ) throws -> HermesEventPolicy {
    var document = try load()
    guard let index = document.policies.firstIndex(where: { $0.id == id }) else {
      throw HermesEventPolicyError.policyNotFound
    }
    if let expectedRevision, document.policies[index].revision != expectedRevision {
      throw HermesEventPolicyError.revisionConflict
    }
    document.policies[index].enabled = enabled
    document.policies[index].revision += 1
    document.policies[index].updatedAt = Date()
    try document.policies[index].validate()
    let updated = document.policies[index]
    try save(document)
    return updated
  }

  private var storeURL: URL {
    root.appendingPathComponent(Self.storeFileName)
  }

  private static func prepareRoot(_ root: URL, fileManager: FileManager) throws {
    guard root.isFileURL, !root.path.isEmpty, !root.path.contains("\u{0}") else {
      throw HermesEventPolicyError.invalidStoreRoot("invalid_url")
    }
    var info = stat()
    if lstat(root.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFLNK {
      throw HermesEventPolicyError.invalidStoreRoot("symlink_root")
    }
    try fileManager.createDirectory(
      at: root,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
    )
    if lstat(root.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFLNK {
      throw HermesEventPolicyError.invalidStoreRoot("symlink_root")
    }
    chmod(root.path, 0o700)
  }

  private func load() throws -> StoreDocument {
    guard fileManager.fileExists(atPath: storeURL.path) else {
      return StoreDocument(schemaVersion: .v1, policies: [])
    }
    do {
      let data = try Data(contentsOf: storeURL)
      let document = try decoder.decode(StoreDocument.self, from: data)
      guard document.schemaVersion == .v1 else {
        throw HermesEventPolicyError.unsupportedSchemaVersion
      }
      guard document.policies.count <= Self.maximumPolicyCount else {
        throw HermesEventPolicyError.policyLimitExceeded
      }
      var seen = Set<HermesEventPolicyID>()
      for policy in document.policies {
        try policy.validate()
        guard seen.insert(policy.id).inserted else {
          throw HermesEventPolicyError.duplicatePolicyID
        }
      }
      return document
    } catch let error as HermesEventPolicyError {
      throw error
    } catch {
      throw HermesEventPolicyError.corruptStore("decode_failed")
    }
  }

  private func save(_ document: StoreDocument) throws {
    do {
      let data = try encoder.encode(document)
      try data.write(to: storeURL, options: [.atomic])
      chmod(storeURL.path, 0o600)
    } catch let error as HermesEventPolicyError {
      throw error
    } catch {
      throw HermesEventPolicyError.persistenceFailed("write_failed")
    }
  }
}

public struct HermesEventPolicyBindingSummary: Codable, Equatable, Sendable {
  public let bindingID: HermesRequestBindingID
  public let enabled: Bool
  public let maximumPromptBytes: Int
  public let approvalPolicy: String
  public let allowsEventTriggeredInvocation: Bool

  public init(
    bindingID: HermesRequestBindingID,
    enabled: Bool,
    maximumPromptBytes: Int,
    approvalPolicy: String,
    allowsEventTriggeredInvocation: Bool
  ) {
    self.bindingID = bindingID
    self.enabled = enabled
    self.maximumPromptBytes = max(1, min(maximumPromptBytes, 64 * 1024))
    self.approvalPolicy = approvalPolicy
    self.allowsEventTriggeredInvocation = allowsEventTriggeredInvocation
  }
}

public protocol HermesEventPolicyBindingDiscovering: Sendable {
  func listEnabledEventPolicyBindings() async throws -> [HermesEventPolicyBindingSummary]
}

public protocol HermesEventPolicyRequestSubmitting: Sendable {
  func submit(bindingID: HermesRequestBindingID, prompt: String) async throws -> HermesRequestID
}

public protocol HermesEventPolicyServiceManaging: Sendable {
  func refreshBridgeHealth() async throws
  func restartBridgeService() async throws
}

public protocol HermesEventPolicyNotificationSending: Sendable {
  func createUserNotification(title: String, body: String) async throws
}

public struct NoopHermesEventPolicyServiceManager: HermesEventPolicyServiceManaging {
  public init() {}
  public func refreshBridgeHealth() async throws {}
  public func restartBridgeService() async throws {}
}

public struct NoopHermesEventPolicyNotificationSender: HermesEventPolicyNotificationSending {
  public init() {}
  public func createUserNotification(title _: String, body _: String) async throws {}
}

public actor HermesEventPolicyEngine {
  public static let maximumGlobalActionsPerMinute = 60
  public static let maximumConsecutiveFailures = 3

  private let store: any HermesEventPolicyStore
  private let bindingDiscovery: any HermesEventPolicyBindingDiscovering
  private let submitter: any HermesEventPolicyRequestSubmitting
  private let serviceManager: any HermesEventPolicyServiceManaging
  private let notificationSender: any HermesEventPolicyNotificationSending
  private let auditStore: any HermesAuditStore
  private let approvalCoordinator: HermesEventPolicyApprovalCoordinator?
  private let now: @Sendable () -> Date
  private let calendar: Calendar

  private var paused = false
  private var emergencyStopped = false
  private var circuitBreakerOpen = false
  private var consecutiveFailures = 0
  private var lastMatchedAt: [HermesEventPolicyID: Date] = [:]
  private var seenEventIDs: [HermesEventPolicyID: Set<HermesSystemEventID>] = [:]
  private var perPolicyExecutions: [HermesEventPolicyID: [Date]] = [:]
  private var globalExecutions: [Date] = []
  private var recentDecisions: [HermesEventPolicyEvaluation] = []

  public init(
    store: any HermesEventPolicyStore,
    bindingDiscovery: any HermesEventPolicyBindingDiscovering,
    submitter: any HermesEventPolicyRequestSubmitting,
    serviceManager: any HermesEventPolicyServiceManaging = NoopHermesEventPolicyServiceManager(),
    notificationSender: any HermesEventPolicyNotificationSending =
      NoopHermesEventPolicyNotificationSender(),
    auditStore: any HermesAuditStore = NoopHermesAuditStore(),
    approvalCoordinator: HermesEventPolicyApprovalCoordinator? = nil,
    now: @escaping @Sendable () -> Date = Date.init,
    calendar: Calendar = Calendar(identifier: .gregorian)
  ) {
    self.store = store
    self.bindingDiscovery = bindingDiscovery
    self.submitter = submitter
    self.serviceManager = serviceManager
    self.notificationSender = notificationSender
    self.auditStore = auditStore
    self.approvalCoordinator = approvalCoordinator
    self.now = now
    self.calendar = calendar
  }

  public func listPolicies() async throws -> [HermesEventPolicy] {
    try await store.listPolicies()
  }

  public func createPolicy(_ policy: HermesEventPolicy) async throws -> HermesEventPolicy {
    let created = try await store.createPolicy(policy)
    try await audit(.eventPolicyCreated, policy: created, decision: nil, reasonCode: "created")
    return created
  }

  public func updatePolicy(_ policy: HermesEventPolicy, expectedRevision: Int) async throws
    -> HermesEventPolicy
  {
    let updated = try await store.updatePolicy(policy, expectedRevision: expectedRevision)
    try await audit(.eventPolicyUpdated, policy: updated, decision: nil, reasonCode: "updated")
    return updated
  }

  public func enablePolicy(id: HermesEventPolicyID, expectedRevision: Int?) async throws
    -> HermesEventPolicy
  {
    let updated = try await store.enablePolicy(id: id, expectedRevision: expectedRevision)
    try await audit(.eventPolicyEnabled, policy: updated, decision: nil, reasonCode: "enabled")
    return updated
  }

  public func disablePolicy(id: HermesEventPolicyID, expectedRevision: Int?) async throws
    -> HermesEventPolicy
  {
    let updated = try await store.disablePolicy(id: id, expectedRevision: expectedRevision)
    try await audit(.eventPolicyDisabled, policy: updated, decision: nil, reasonCode: "disabled")
    return updated
  }

  public func removePolicy(id: HermesEventPolicyID, expectedRevision: Int?) async throws {
    try await store.removePolicy(id: id, expectedRevision: expectedRevision)
  }

  public func pause() async throws -> HermesEventPolicyEngineStatus {
    paused = true
    try await auditPolicyState(.eventPolicyPaused, reasonCode: "manual_pause")
    return try await status()
  }

  public func resume() async throws -> HermesEventPolicyEngineStatus {
    paused = false
    circuitBreakerOpen = false
    consecutiveFailures = 0
    try await auditPolicyState(.eventPolicyResumed, reasonCode: "manual_resume")
    return try await status()
  }

  public func emergencyStop() {
    emergencyStopped = true
    Task {
      _ = try? await approvalCoordinator?.sweepExpired()
    }
  }

  public func status() async throws -> HermesEventPolicyEngineStatus {
    let enabledCount = try await store.listPolicies().filter(\.enabled).count
    return HermesEventPolicyEngineStatus(
      enabledPolicyCount: enabledCount,
      paused: paused,
      emergencyStopped: emergencyStopped,
      circuitBreakerOpen: circuitBreakerOpen,
      consecutiveFailures: consecutiveFailures,
      recentDecisions: recentDecisions.reversed()
    )
  }

  public func listApprovals() async throws -> [HermesEventPolicyApprovalRequest] {
    guard let approvalCoordinator else {
      return []
    }
    return try await approvalCoordinator.listApprovals()
  }

  public func approvalStatus(id: HermesEventPolicyApprovalID) async throws
    -> HermesEventPolicyApprovalRequest
  {
    guard let approvalCoordinator else {
      throw HermesEventPolicyApprovalError.approvalNotFound
    }
    return try await approvalCoordinator.status(id: id)
  }

  public func approveApproval(id: HermesEventPolicyApprovalID) async throws
    -> HermesEventPolicyApprovalRequest
  {
    guard let approvalCoordinator else {
      throw HermesEventPolicyApprovalError.approvalNotFound
    }
    return try await approvalCoordinator.approve(
      id: id,
      runtimeState: HermesEventPolicyApprovalRuntimeState(
        paused: paused,
        emergencyStopped: emergencyStopped
      )
    )
  }

  public func denyApproval(id: HermesEventPolicyApprovalID) async throws
    -> HermesEventPolicyApprovalRequest
  {
    guard let approvalCoordinator else {
      throw HermesEventPolicyApprovalError.approvalNotFound
    }
    return try await approvalCoordinator.deny(id: id)
  }

  public func cancelApproval(id: HermesEventPolicyApprovalID) async throws
    -> HermesEventPolicyApprovalRequest
  {
    guard let approvalCoordinator else {
      throw HermesEventPolicyApprovalError.approvalNotFound
    }
    return try await approvalCoordinator.cancel(id: id)
  }

  public func approvalQueueStatus() async throws -> HermesEventPolicyApprovalQueueStatus {
    guard let approvalCoordinator else {
      return HermesEventPolicyApprovalQueueStatus(requests: [])
    }
    return try await approvalCoordinator.queueStatus()
  }

  public func evaluate(_ event: HermesSystemEvent, dryRun: Bool = false) async
    -> [HermesEventPolicyEvaluation]
  {
    let policies: [HermesEventPolicy]
    do {
      policies = try await store.listPolicies()
    } catch {
      return []
    }
    var evaluations: [HermesEventPolicyEvaluation] = []
    for policy in policies.sorted(by: deterministicPolicyOrder) {
      guard policy.enabled else {
        continue
      }
      guard conditionsMatch(policy.conditions, event: event, policyID: policy.id) else {
        if let evaluation = makeEvaluation(
          policy: policy,
          event: event,
          actionKind: nil,
          decision: .notMatched,
          reasonCode: "conditions_not_matched"
        ) {
          remember(evaluation)
          evaluations.append(evaluation)
        }
        continue
      }
      let decision = await evaluateMatchedPolicy(policy, event: event, dryRun: dryRun)
      evaluations.append(contentsOf: decision)
    }
    return evaluations
  }

  private func evaluateMatchedPolicy(
    _ policy: HermesEventPolicy,
    event: HermesSystemEvent,
    dryRun: Bool
  ) async -> [HermesEventPolicyEvaluation] {
    if paused || emergencyStopped || circuitBreakerOpen {
      let evaluation = makeEvaluation(
        policy: policy,
        event: event,
        actionKind: policy.actions.first?.kind,
        decision: .blockedGlobalPause,
        reasonCode: emergencyStopped
          ? "emergency_stop" : (circuitBreakerOpen ? "circuit_breaker" : "paused")
      )
      return evaluation.map { [recordAndAudit($0, policy: policy)] } ?? []
    }
    if policy.suppressDuplicateEvents,
      seenEventIDs[policy.id, default: []].contains(event.eventID)
    {
      let evaluation = makeEvaluation(
        policy: policy,
        event: event,
        actionKind: policy.actions.first?.kind,
        decision: .blockedCooldown,
        reasonCode: "duplicate_event"
      )
      return evaluation.map { [recordAndAudit($0, policy: policy)] } ?? []
    }
    if policy.cooldownSeconds > 0,
      let last = lastMatchedAt[policy.id],
      now().timeIntervalSince(last) < policy.cooldownSeconds
    {
      let evaluation = makeEvaluation(
        policy: policy,
        event: event,
        actionKind: policy.actions.first?.kind,
        decision: .blockedCooldown,
        reasonCode: "cooldown"
      )
      return evaluation.map { [recordAndAudit($0, policy: policy)] } ?? []
    }
    guard rateLimitAllows(policy: policy) else {
      let evaluation = makeEvaluation(
        policy: policy,
        event: event,
        actionKind: policy.actions.first?.kind,
        decision: .blockedRateLimit,
        reasonCode: "rate_limit"
      )
      return evaluation.map { [recordAndAudit($0, policy: policy)] } ?? []
    }
    if dryRun || policy.executionMode == .dryRun {
      let evaluation = makeEvaluation(
        policy: policy,
        event: event,
        actionKind: policy.actions.first?.kind,
        decision: .matchedDryRun,
        reasonCode: "dry_run"
      )
      lastMatchedAt[policy.id] = now()
      seenEventIDs[policy.id, default: []].insert(event.eventID)
      return evaluation.map { [recordAndAudit($0, policy: policy)] } ?? []
    }
    if policy.approvalRequirement != .noApproval {
      let approvalID: HermesEventPolicyApprovalID?
      if let approvalCoordinator, let action = policy.actions.first {
        let correlationID = "evtpol_\(event.eventID.rawValue)"
        let request = try? await approvalCoordinator.createApproval(
          policy: policy,
          event: event,
          action: action,
          correlationID: correlationID
        )
        approvalID = request?.snapshot.approvalID
      } else {
        approvalID = nil
      }
      let evaluation = makeEvaluation(
        policy: policy,
        event: event,
        actionKind: policy.actions.first?.kind,
        decision: .blockedApprovalRequired,
        reasonCode: policy.approvalRequirement.rawValue,
        approvalID: approvalID
      )
      return evaluation.map { [recordAndAudit($0, policy: policy)] } ?? []
    }

    lastMatchedAt[policy.id] = now()
    seenEventIDs[policy.id, default: []].insert(event.eventID)
    appendExecution(now(), policyID: policy.id)
    var output: [HermesEventPolicyEvaluation] = []
    for action in policy.actions {
      let evaluation = await execute(action, policy: policy, event: event)
      output.append(recordAndAudit(evaluation, policy: policy))
    }
    return output
  }

  private func execute(
    _ action: HermesEventPolicyAction,
    policy: HermesEventPolicy,
    event: HermesSystemEvent
  ) async -> HermesEventPolicyEvaluation {
    do {
      switch action {
      case .recordAuditEvent:
        break
      case .refreshBridgeHealth:
        try await serviceManager.refreshBridgeHealth()
      case .restartBridgeService:
        try await serviceManager.restartBridgeService()
      case .createUserNotification(let title, let body):
        try await notificationSender.createUserNotification(title: title, body: body)
      case .markPolicyAttentionRequired:
        break
      case .submitApprovedBinding(let bindingID, let prompt):
        let bindings = try await bindingDiscovery.listEnabledEventPolicyBindings()
        guard let binding = bindings.first(where: { $0.bindingID == bindingID && $0.enabled }),
          binding.allowsEventTriggeredInvocation
        else {
          return makeEvaluation(
            policy: policy,
            event: event,
            actionKind: action.kind,
            decision: .blockedBindingUnavailable,
            reasonCode: "binding_unavailable"
          )!
        }
        let rendered = try prompt.render(
          event: event, maximumPromptBytes: binding.maximumPromptBytes)
        _ = try await submitter.submit(bindingID: bindingID, prompt: rendered)
      }
      consecutiveFailures = 0
      return makeEvaluation(
        policy: policy,
        event: event,
        actionKind: action.kind,
        decision: .executed,
        reasonCode: "executed"
      )!
    } catch let error as HermesEventPolicyError {
      if case .promptTooLarge = error {
        return failure(
          policy: policy, event: event, actionKind: action.kind, reasonCode: "prompt_too_large")
      }
      return failure(
        policy: policy, event: event, actionKind: action.kind, reasonCode: "action_failed")
    } catch {
      return failure(
        policy: policy, event: event, actionKind: action.kind, reasonCode: "action_failed")
    }
  }

  private func failure(
    policy: HermesEventPolicy,
    event: HermesSystemEvent,
    actionKind: HermesEventPolicyActionKind,
    reasonCode: String
  ) -> HermesEventPolicyEvaluation {
    consecutiveFailures += 1
    if consecutiveFailures >= Self.maximumConsecutiveFailures {
      circuitBreakerOpen = true
      paused = true
    }
    return makeEvaluation(
      policy: policy,
      event: event,
      actionKind: actionKind,
      decision: .failedRedacted,
      reasonCode: reasonCode
    )!
  }

  private func conditionsMatch(
    _ conditions: [HermesEventPolicyCondition],
    event: HermesSystemEvent,
    policyID: HermesEventPolicyID
  ) -> Bool {
    conditions.allSatisfy { condition in
      switch condition {
      case .eventKindEquals(let kind):
        return event.kind == kind
      case .applicationBundleIdentifierEquals(let bundleID):
        return event.application?.bundleIdentifier == bundleID
      case .networkAvailabilityEquals(let status):
        return event.networkStatus == status
      case .networkInterfaceTypeEquals(let interface):
        return event.networkInterface == interface
      case .serviceHealthStateEquals(let state):
        return event.serviceHealth == state
      case .constrainedNetworkEquals(let value):
        return event.networkConstrained == value
      case .expensiveNetworkEquals(let value):
        return event.networkExpensive == value
      case .boundedTimeWindow(let startHour, let endHour):
        let hour = calendar.component(.hour, from: event.timestamp)
        if startHour <= endHour {
          return hour >= startHour && hour <= endHour
        }
        return hour >= startHour || hour <= endHour
      case .minimumIntervalSincePreviousMatch(let seconds):
        guard let last = lastMatchedAt[policyID] else { return true }
        return now().timeIntervalSince(last) >= seconds
      }
    }
  }

  private func rateLimitAllows(policy: HermesEventPolicy) -> Bool {
    let cutoff = now().addingTimeInterval(-60)
    globalExecutions = globalExecutions.filter { $0 >= cutoff }
    perPolicyExecutions[policy.id, default: []] =
      perPolicyExecutions[policy.id, default: []].filter { $0 >= cutoff }
    return globalExecutions.count < Self.maximumGlobalActionsPerMinute
      && perPolicyExecutions[policy.id, default: []].count < policy.maximumExecutionsPerMinute
  }

  private func appendExecution(_ date: Date, policyID: HermesEventPolicyID) {
    globalExecutions.append(date)
    perPolicyExecutions[policyID, default: []].append(date)
  }

  private func deterministicPolicyOrder(_ lhs: HermesEventPolicy, _ rhs: HermesEventPolicy) -> Bool
  {
    if lhs.updatedAt == rhs.updatedAt {
      return lhs.id.rawValue < rhs.id.rawValue
    }
    return lhs.id.rawValue < rhs.id.rawValue
  }

  private func makeEvaluation(
    policy: HermesEventPolicy,
    event: HermesSystemEvent,
    actionKind: HermesEventPolicyActionKind?,
    decision: HermesEventPolicyDecision,
    reasonCode: String,
    approvalID: HermesEventPolicyApprovalID? = nil
  ) -> HermesEventPolicyEvaluation? {
    try? HermesEventPolicyEvaluation(
      policyID: policy.id,
      policyRevision: policy.revision,
      eventID: event.eventID,
      eventKind: event.kind,
      actionKind: actionKind,
      decision: decision,
      reasonCode: reasonCode,
      evaluatedAt: now(),
      approvalID: approvalID
    )
  }

  @discardableResult
  private func recordAndAudit(
    _ evaluation: HermesEventPolicyEvaluation,
    policy: HermesEventPolicy
  ) -> HermesEventPolicyEvaluation {
    remember(evaluation)
    Task {
      try? await audit(
        auditKind(for: evaluation.decision),
        policy: policy,
        decision: evaluation,
        reasonCode: evaluation.reasonCode
      )
    }
    return evaluation
  }

  private func remember(_ evaluation: HermesEventPolicyEvaluation) {
    recentDecisions.append(evaluation)
    recentDecisions = Array(recentDecisions.suffix(20))
  }

  private func auditKind(for decision: HermesEventPolicyDecision) -> HermesAuditEventKind {
    switch decision {
    case .executed:
      return .eventPolicyActionExecuted
    case .failedRedacted:
      return .eventPolicyActionFailed
    case .notMatched:
      return .eventPolicyMatched
    default:
      return .eventPolicyActionBlocked
    }
  }

  private func audit(
    _ kind: HermesAuditEventKind,
    policy: HermesEventPolicy,
    decision: HermesEventPolicyEvaluation?,
    reasonCode: String
  ) async throws {
    var metadata = [
      "policy_id": policy.id.rawValue,
      "revision": String(policy.revision),
    ]
    if let decision {
      metadata["event_kind"] = decision.eventKind.rawValue
      metadata["decision"] = decision.decision.rawValue
      metadata["action"] = decision.actionKind?.rawValue ?? "none"
      metadata["approval_id"] = decision.approvalID?.rawValue ?? "none"
    }
    try await auditStore.append(
      HermesAuditEvent.make(
        kind: kind,
        actor: .service,
        outcome: auditOutcome(for: decision?.decision),
        reasonCode: reasonCode,
        metadata: try HermesAuditMetadata(metadata)
      ))
  }

  private func auditPolicyState(_ kind: HermesAuditEventKind, reasonCode: String) async throws {
    try await auditStore.append(
      HermesAuditEvent.make(
        kind: kind,
        actor: .service,
        outcome: .succeeded,
        reasonCode: reasonCode
      ))
  }

  private func auditOutcome(for decision: HermesEventPolicyDecision?) -> HermesAuditOutcome {
    switch decision {
    case .executed:
      return .succeeded
    case .failedRedacted:
      return .failed
    case .blockedApprovalRequired, .blockedBindingUnavailable, .blockedCooldown,
      .blockedDisabled, .blockedGlobalPause, .blockedRateLimit:
      return .denied
    case .matchedDryRun, .notMatched, .none:
      return .started
    }
  }
}

extension String {
  fileprivate func prefixString(_ count: Int) -> String {
    String(prefix(count))
  }
}
