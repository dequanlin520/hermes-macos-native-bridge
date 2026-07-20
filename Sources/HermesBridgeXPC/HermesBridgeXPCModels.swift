import Foundation
import HermesRuntimeFoundation

public struct HermesBridgeProtocolVersion: Codable, Equatable, Sendable,
  CustomStringConvertible
{
  public static let current = HermesBridgeProtocolVersion(major: 1, minor: 5)
  public static let supportedMajor = 1

  public let major: Int
  public let minor: Int

  public init(major: Int, minor: Int) {
    self.major = major
    self.minor = minor
  }

  public var isSupported: Bool {
    major == Self.supportedMajor && minor >= 0
  }

  public func isCompatible(with serviceVersion: HermesBridgeProtocolVersion) -> Bool {
    major == serviceVersion.major && minor >= serviceVersion.minor
  }

  public var description: String {
    "\(major).\(minor)"
  }
}

public enum HermesBridgeCapability: String, Codable, CaseIterable, Equatable, Sendable {
  case submitRequest
  case requestStatus
  case cancelRequest
  case respondToApproval
  case protocolVersion
  case bindingDiscovery
  case authorizedRootManagement
  case fileEventObservation
  case systemEventObservation
  case systemEventPolicyManagement
}

public enum HermesBridgeOperation: String, Codable, CaseIterable, Equatable, Sendable {
  case submit
  case status
  case cancel
  case approvalResponse
  case capabilities
  case protocolVersion
  case listEnabledBindings
  case listAuthorizedRoots
  case registerAuthorizedRoot
  case refreshAuthorizedRoot
  case deactivateAuthorizedRoot
  case reactivateAuthorizedRoot
  case removeAuthorizedRoot
  case authorizedRootStatus
  case resolveAuthorizedRoot
  case createFileEventSubscription
  case pollFileEventSubscription
  case acknowledgeFileEventBatch
  case cancelFileEventSubscription
  case fileEventMonitorStatus
  case createSystemEventSubscription
  case pollSystemEventSubscription
  case acknowledgeSystemEventBatch
  case cancelSystemEventSubscription
  case systemEventMonitorStatus
  case listEventPolicies
  case createEventPolicy
  case updateEventPolicy
  case enableEventPolicy
  case disableEventPolicy
  case removeEventPolicy
  case evaluateEventPolicyDryRun
  case eventPolicyEngineStatus
  case pauseEventPolicies
  case resumeEventPolicies
}

public struct HermesBridgeCorrelationID: Codable, Equatable, Hashable, Sendable,
  CustomStringConvertible
{
  public static let maximumLength = 128
  public static let fallback = try! HermesBridgeCorrelationID(rawValue: "unavailable")

  public let rawValue: String

  public init(rawValue: String) throws {
    guard Self.isValid(rawValue) else {
      throw HermesBridgeXPCError.malformedPayload
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

public enum HermesBridgeXPCError: String, Codable, Error, Equatable, Sendable {
  case unsupportedProtocolVersion
  case malformedPayload
  case oversizedPayload
  case unsupportedOperation
  case unsupportedCapability
  case invalidBinding
  case requestNotFound
  case invalidState
  case serviceUnavailable
  case internalFailure
  case duplicateAuthorizedRoot
  case rootNotFound
  case rootInactive
  case invalidBookmark
  case bookmarkTooLarge
  case staleAuthorization
  case securityScopeUnavailable
  case subscriptionNotFound
  case subscriptionExpired
  case acknowledgementRejected
  case eventBufferOverflow
  case rescanRequired
}

public enum HermesBridgeSecurityScopeStatus: String, Codable, Equatable, Sendable {
  case available
  case unavailable
}

public enum HermesBridgeAuthorizedRootKind: String, Codable, Equatable, Sendable {
  case directory
}

public struct HermesBridgeAuthorizedRootSummary: Codable, Equatable, Sendable {
  public let rootID: String
  public let displayName: String
  public let active: Bool
  public let staleAuthorization: Bool
  public let securityScopeStatus: HermesBridgeSecurityScopeStatus
  public let lastObservedEventID: UInt64
  public let revision: Int
  public let rootKind: HermesBridgeAuthorizedRootKind

  public init(
    record: HermesAuthorizedRootRecord,
    securityScopeStatus: HermesBridgeSecurityScopeStatus = .unavailable
  ) {
    self.rootID = record.rootID.rawValue
    self.displayName = record.displayName
    self.active = record.state == .active
    self.staleAuthorization = record.bookmarkDataIsStale
    self.securityScopeStatus = securityScopeStatus
    self.lastObservedEventID = record.lastObservedFSEventID
    self.revision = record.revision
    self.rootKind = .directory
  }
}

public struct HermesBridgeAuthorizedRootListPayload: Codable, Equatable, Sendable {
  public static let maximumRootCount = 128
  public let roots: [HermesBridgeAuthorizedRootSummary]

  public init(roots: [HermesBridgeAuthorizedRootSummary]) {
    self.roots = Array(roots.prefix(Self.maximumRootCount))
  }
}

public struct HermesBridgeAuthorizedRootPayload: Codable, Equatable, Sendable {
  public let root: HermesBridgeAuthorizedRootSummary

  public init(root: HermesBridgeAuthorizedRootSummary) {
    self.root = root
  }
}

public struct HermesBridgeRegisterAuthorizedRootPayload: Codable, Equatable, Sendable {
  public static let maximumBookmarkBytes = 80 * 1024
  public let displayName: String
  public let bookmarkData: Data

  public init(displayName: String, bookmarkData: Data) {
    self.displayName = displayName
    self.bookmarkData = bookmarkData
  }
}

public struct HermesBridgeRootIDPayload: Codable, Equatable, Sendable {
  public let rootID: String
  public let expectedRevision: Int?

  public init(rootID: String, expectedRevision: Int? = nil) {
    self.rootID = rootID
    self.expectedRevision = expectedRevision
  }
}

public struct HermesBridgeRefreshAuthorizedRootPayload: Codable, Equatable, Sendable {
  public let rootID: String
  public let bookmarkData: Data
  public let expectedRevision: Int?

  public init(rootID: String, bookmarkData: Data, expectedRevision: Int? = nil) {
    self.rootID = rootID
    self.bookmarkData = bookmarkData
    self.expectedRevision = expectedRevision
  }
}

public typealias HermesBridgeReactivateAuthorizedRootPayload =
  HermesBridgeRefreshAuthorizedRootPayload

public struct HermesBridgeAuthorizedRootStatusPayload: Codable, Equatable, Sendable {
  public let root: HermesBridgeAuthorizedRootSummary

  public init(root: HermesBridgeAuthorizedRootSummary) {
    self.root = root
  }
}

public enum HermesBridgeAuthorizedRootResolutionStatus: String, Codable, Equatable, Sendable {
  case resolved
  case resolvedStale
  case securityScopeStarted
  case securityScopeUnavailable
  case rejected
}

public struct HermesBridgeAuthorizedRootResolutionPayload: Codable, Equatable, Sendable {
  public let rootID: String
  public let status: HermesBridgeAuthorizedRootResolutionStatus
  public let staleAuthorization: Bool
  public let securityScopeStarted: Bool
  public let resolvedSameAuthorizedRoot: Bool

  public init(
    rootID: HermesAuthorizedRootID,
    resolution: HermesBookmarkAuthorizationResolution,
    expectedResolvedRootURL: URL
  ) {
    self.rootID = rootID.rawValue
    switch resolution.status {
    case .resolved:
      self.status = .resolved
    case .resolvedStale:
      self.status = .resolvedStale
    case .securityScopeStarted:
      self.status = .securityScopeStarted
    case .securityScopeUnavailable:
      self.status = .securityScopeUnavailable
    case .rejected:
      self.status = .rejected
    }
    self.staleAuthorization = resolution.bookmarkDataIsStale
    self.securityScopeStarted = resolution.securityScopedAccessStarted
    self.resolvedSameAuthorizedRoot =
      resolution.resolvedURL?.standardizedFileURL.resolvingSymlinksInPath().path
      == expectedResolvedRootURL.standardizedFileURL.resolvingSymlinksInPath().path
  }
}

public struct HermesBridgeFileEventSubscriptionID: Codable, Equatable, Hashable, Sendable,
  CustomStringConvertible
{
  public static let prefix = "fsub_"
  public let rawValue: String

  public init(rawValue: String) throws {
    guard rawValue.hasPrefix(Self.prefix), rawValue.count <= 80,
      rawValue.dropFirst(Self.prefix.count).allSatisfy({
        $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_")
      })
    else {
      throw HermesBridgeXPCError.malformedPayload
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
}

public struct HermesBridgeCreateFileEventSubscriptionPayload: Codable, Equatable, Sendable {
  public let rootIDs: [String]

  public init(rootIDs: [String]) {
    self.rootIDs = rootIDs
  }
}

public struct HermesBridgeFileEventSubscriptionPayload: Codable, Equatable, Sendable {
  public let subscriptionID: String
  public let rootIDs: [String]
  public let expiresAt: Date
  public let rescanRequired: Bool

  public init(
    subscriptionID: HermesBridgeFileEventSubscriptionID,
    rootIDs: [HermesAuthorizedRootID],
    expiresAt: Date,
    rescanRequired: Bool = false
  ) {
    self.subscriptionID = subscriptionID.rawValue
    self.rootIDs = rootIDs.map(\.rawValue)
    self.expiresAt = expiresAt
    self.rescanRequired = rescanRequired
  }
}

public struct HermesBridgePollFileEventSubscriptionPayload: Codable, Equatable, Sendable {
  public let subscriptionID: String
  public let timeoutMilliseconds: Int

  public init(subscriptionID: String, timeoutMilliseconds: Int = 0) {
    self.subscriptionID = subscriptionID
    self.timeoutMilliseconds = timeoutMilliseconds
  }
}

public struct HermesBridgeAcknowledgeFileEventBatchPayload: Codable, Equatable, Sendable {
  public let subscriptionID: String
  public let acknowledgedEventID: UInt64

  public init(subscriptionID: String, acknowledgedEventID: UInt64) {
    self.subscriptionID = subscriptionID
    self.acknowledgedEventID = acknowledgedEventID
  }
}

public struct HermesBridgeAcknowledgementPayload: Codable, Equatable, Sendable {
  public let subscriptionID: String
  public let acknowledgedEventID: UInt64

  public init(subscriptionID: HermesBridgeFileEventSubscriptionID, acknowledgedEventID: UInt64) {
    self.subscriptionID = subscriptionID.rawValue
    self.acknowledgedEventID = acknowledgedEventID
  }

  public init(subscriptionID: String, acknowledgedEventID: UInt64) {
    self.subscriptionID = subscriptionID
    self.acknowledgedEventID = acknowledgedEventID
  }
}

public struct HermesBridgeCancelFileEventSubscriptionPayload: Codable, Equatable, Sendable {
  public let subscriptionID: String

  public init(subscriptionID: String) {
    self.subscriptionID = subscriptionID
  }
}

public struct HermesBridgeFileEventSummary: Codable, Equatable, Sendable {
  public static let maximumPathBytes = HermesRootRelativePath.maximumUTF8Bytes
  public let rootID: String
  public let relativePath: String
  public let kind: String
  public let eventID: UInt64
  public let isDirectory: Bool?
  public let flags: [String]
  public let replayed: Bool

  public init(event: HermesFileEvent, replayed: Bool) {
    self.rootID = event.rootID.rawValue
    self.relativePath = event.relativePath.rawValue
    self.kind = event.kind.rawValue
    self.eventID = event.fseventID
    self.isDirectory = event.isDirectory
    self.flags = event.flags.map(\.rawValue).sorted()
    self.replayed = replayed
  }
}

public struct HermesBridgeFileEventBatchPayload: Codable, Equatable, Sendable {
  public static let maximumEventCount = 128
  public static let maximumEncodedBytes = 64 * 1024
  public let subscriptionID: String
  public let rootID: String
  public let events: [HermesBridgeFileEventSummary]
  public let newestEventID: UInt64
  public let replayed: Bool
  public let historyDone: Bool
  public let rescanRequired: Bool
  public let droppedEventReason: String?

  public init(
    subscriptionID: HermesBridgeFileEventSubscriptionID,
    rootID: HermesAuthorizedRootID,
    events: [HermesBridgeFileEventSummary],
    newestEventID: UInt64,
    replayed: Bool,
    historyDone: Bool = false,
    rescanRequired: Bool,
    droppedEventReason: HermesFileEventDroppedReason? = nil
  ) throws {
    self.subscriptionID = subscriptionID.rawValue
    self.rootID = rootID.rawValue
    self.events = Array(events.prefix(Self.maximumEventCount))
    self.newestEventID = newestEventID
    self.replayed = replayed
    self.historyDone = historyDone
    self.rescanRequired = rescanRequired
    self.droppedEventReason = droppedEventReason?.rawValue
    guard (try? JSONEncoder().encode(self).count) ?? Int.max <= Self.maximumEncodedBytes else {
      throw HermesBridgeXPCError.oversizedPayload
    }
  }
}

public struct HermesBridgeFileEventMonitorStatusPayload: Codable, Equatable, Sendable {
  public let activeSubscriptionCount: Int
  public let observedCursor: UInt64
  public let deliveredCursor: UInt64
  public let acknowledgedCursor: UInt64
  public let rescanRequired: Bool

  public init(
    activeSubscriptionCount: Int,
    observedCursor: UInt64,
    deliveredCursor: UInt64,
    acknowledgedCursor: UInt64,
    rescanRequired: Bool
  ) {
    self.activeSubscriptionCount = activeSubscriptionCount
    self.observedCursor = observedCursor
    self.deliveredCursor = deliveredCursor
    self.acknowledgedCursor = acknowledgedCursor
    self.rescanRequired = rescanRequired
  }
}

public struct HermesBridgeCreateSystemEventSubscriptionPayload: Codable, Equatable, Sendable {
  public let kinds: [HermesSystemEventKind]

  public init(kinds: [HermesSystemEventKind]) {
    self.kinds = kinds
  }
}

public struct HermesBridgeSystemEventSubscriptionPayload: Codable, Equatable, Sendable {
  public let subscriptionID: String
  public let kinds: [HermesSystemEventKind]
  public let expiresAt: Date
  public let resyncRequired: Bool

  public init(
    subscriptionID: HermesSystemEventSubscriptionID,
    kinds: [HermesSystemEventKind],
    expiresAt: Date,
    resyncRequired: Bool = false
  ) {
    self.subscriptionID = subscriptionID.rawValue
    self.kinds = Array(
      kinds.prefix(HermesBridgeSystemEventCoordinator.maximumEventKindsPerSubscription))
    self.expiresAt = expiresAt
    self.resyncRequired = resyncRequired
  }
}

public struct HermesBridgePollSystemEventSubscriptionPayload: Codable, Equatable, Sendable {
  public let subscriptionID: String
  public let timeoutMilliseconds: Int

  public init(subscriptionID: String, timeoutMilliseconds: Int = 0) {
    self.subscriptionID = subscriptionID
    self.timeoutMilliseconds = timeoutMilliseconds
  }
}

public struct HermesBridgeAcknowledgeSystemEventBatchPayload: Codable, Equatable, Sendable {
  public let subscriptionID: String
  public let acknowledgedEventOrdinal: UInt64

  public init(subscriptionID: String, acknowledgedEventOrdinal: UInt64) {
    self.subscriptionID = subscriptionID
    self.acknowledgedEventOrdinal = acknowledgedEventOrdinal
  }
}

public struct HermesBridgeCancelSystemEventSubscriptionPayload: Codable, Equatable, Sendable {
  public let subscriptionID: String

  public init(subscriptionID: String) {
    self.subscriptionID = subscriptionID
  }
}

public struct HermesBridgeSystemEventSummary: Codable, Equatable, Sendable {
  public let eventID: String
  public let kind: HermesSystemEventKind
  public let source: HermesSystemEventSource
  public let timestamp: Date
  public let applicationBundleIdentifier: String?
  public let applicationLocalizedName: String?
  public let networkStatus: HermesNetworkStatusClassification?
  public let networkInterface: HermesNetworkInterfaceSummary?
  public let networkExpensive: Bool?
  public let networkConstrained: Bool?
  public let serviceHealth: HermesBridgeServiceHealthClassification?
  public let replayed: Bool
  public let coalesced: Bool
  public let reasonCode: String

  public init(event: HermesSystemEvent) {
    self.eventID = event.eventID.rawValue
    self.kind = event.kind
    self.source = event.source
    self.timestamp = event.timestamp
    self.applicationBundleIdentifier = event.application?.bundleIdentifier
    self.applicationLocalizedName = event.application?.localizedName
    self.networkStatus = event.networkStatus
    self.networkInterface = event.networkInterface
    self.networkExpensive = event.networkExpensive
    self.networkConstrained = event.networkConstrained
    self.serviceHealth = event.serviceHealth
    self.replayed = event.replayed
    self.coalesced = event.coalesced
    self.reasonCode = event.reasonCode
  }
}

public struct HermesBridgeSystemEventBatchPayload: Codable, Equatable, Sendable {
  public static let maximumEventCount = HermesSystemEventBatch.maximumEventCount
  public static let maximumEncodedBytes = HermesSystemEventBatch.maximumEncodedBytes

  public let subscriptionID: String
  public let events: [HermesBridgeSystemEventSummary]
  public let newestEventOrdinal: UInt64
  public let replayed: Bool
  public let resyncRequired: Bool
  public let droppedEventReason: String?

  public init(
    subscriptionID: HermesSystemEventSubscriptionID,
    events: [HermesSystemEvent],
    newestEventOrdinal: UInt64,
    replayed: Bool,
    resyncRequired: Bool,
    droppedEventReason: String? = nil
  ) throws {
    self.subscriptionID = subscriptionID.rawValue
    self.events = Array(
      events.map(HermesBridgeSystemEventSummary.init).prefix(Self.maximumEventCount))
    self.newestEventOrdinal = newestEventOrdinal
    self.replayed = replayed
    self.resyncRequired = resyncRequired
    self.droppedEventReason = try droppedEventReason.map(HermesSystemEvent.safeReasonCode)
    guard (try? JSONEncoder().encode(self).count) ?? Int.max <= Self.maximumEncodedBytes else {
      throw HermesBridgeXPCError.oversizedPayload
    }
  }
}

public struct HermesBridgeSystemEventMonitorStatusPayload: Codable, Equatable, Sendable {
  public let status: HermesSystemEventMonitorStatus

  public init(status: HermesSystemEventMonitorStatus) {
    self.status = status
  }
}

public struct HermesBridgeEventPolicyListPayload: Codable, Equatable, Sendable {
  public let policies: [HermesEventPolicy]

  public init(policies: [HermesEventPolicy]) {
    self.policies = Array(policies.prefix(FileBackedHermesEventPolicyStore.maximumPolicyCount))
  }
}

public struct HermesBridgeEventPolicyPayload: Codable, Equatable, Sendable {
  public let policy: HermesEventPolicy
  public let expectedRevision: Int?

  public init(policy: HermesEventPolicy, expectedRevision: Int? = nil) {
    self.policy = policy
    self.expectedRevision = expectedRevision
  }
}

public struct HermesBridgeEventPolicyIDPayload: Codable, Equatable, Sendable {
  public let policyID: HermesEventPolicyID
  public let expectedRevision: Int?

  public init(policyID: HermesEventPolicyID, expectedRevision: Int? = nil) {
    self.policyID = policyID
    self.expectedRevision = expectedRevision
  }
}

public struct HermesBridgeEventPolicyEvaluationPayload: Codable, Equatable, Sendable {
  public let event: HermesSystemEvent

  public init(event: HermesSystemEvent) {
    self.event = event
  }
}

public struct HermesBridgeEventPolicyEvaluationResultPayload: Codable, Equatable, Sendable {
  public let evaluations: [HermesEventPolicyEvaluation]

  public init(evaluations: [HermesEventPolicyEvaluation]) {
    self.evaluations = Array(
      evaluations.prefix(FileBackedHermesEventPolicyStore.maximumPolicyCount))
  }
}

public struct HermesBridgeEventPolicyEngineStatusPayload: Codable, Equatable, Sendable {
  public let status: HermesEventPolicyEngineStatus

  public init(status: HermesEventPolicyEngineStatus) {
    self.status = status
  }
}

public struct HermesBridgeSubmitPayload: Codable, Equatable, Sendable {
  public let bindingID: String
  public let prompt: String

  public init(bindingID: String, prompt: String) {
    self.bindingID = bindingID
    self.prompt = prompt
  }
}

public struct HermesBridgeRequestIDPayload: Codable, Equatable, Sendable {
  public let requestID: String

  public init(requestID: String) {
    self.requestID = requestID
  }
}

public enum HermesBridgeApprovalDecision: String, Codable, Equatable, Sendable {
  case approve
  case reject

  var orchestratorDecision: HermesApprovalResponseDecision {
    switch self {
    case .approve:
      return .approve
    case .reject:
      return .reject
    }
  }
}

public struct HermesBridgeApprovalResponsePayload: Codable, Equatable, Sendable {
  public let requestID: String
  public let decision: HermesBridgeApprovalDecision

  public init(requestID: String, decision: HermesBridgeApprovalDecision) {
    self.requestID = requestID
    self.decision = decision
  }
}

public struct HermesBridgeBindingSummary: Codable, Equatable, Sendable {
  public static let maximumCount = 128
  public static let maximumPayloadBytes = 64 * 1024
  public static let maximumDisplayNameCharacters = 80
  public static let maximumDescriptionCharacters = 240

  public let bindingID: String
  public let localizedDisplayName: String
  public let safeLocalizedDescription: String
  public let maximumPromptBytes: Int
  public let approvalPolicy: String
  public let enabled: Bool
  public let allowsEventTriggeredInvocation: Bool

  public init(
    bindingID: HermesRequestBindingID,
    localizedDisplayName: String,
    safeLocalizedDescription: String,
    maximumPromptBytes: Int,
    approvalPolicy: String,
    enabled: Bool,
    allowsEventTriggeredInvocation: Bool = false
  ) {
    self.bindingID = bindingID.rawValue
    self.localizedDisplayName = Self.safeText(
      localizedDisplayName,
      maximumCharacters: Self.maximumDisplayNameCharacters
    )
    self.safeLocalizedDescription = Self.safeText(
      safeLocalizedDescription,
      maximumCharacters: Self.maximumDescriptionCharacters
    )
    self.maximumPromptBytes = max(
      0, min(maximumPromptBytes, HermesBridgeRequestEnvelope.maximumPromptBytes))
    self.approvalPolicy = Self.safeToken(approvalPolicy)
    self.enabled = enabled
    self.allowsEventTriggeredInvocation = allowsEventTriggeredInvocation
  }

  private static func safeText(_ value: String, maximumCharacters: Int) -> String {
    let filtered = value.unicodeScalars.filter { scalar in
      scalar.value >= 0x20 && scalar.value != 0x7F
    }
    return String(String.UnicodeScalarView(filtered)).prefixString(maximumCharacters)
  }

  private static func safeToken(_ value: String) -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-")
    }
    return String(filtered.prefix(40))
  }
}

public struct HermesBridgeBindingListPayload: Codable, Equatable, Sendable {
  public let protocolVersion: HermesBridgeProtocolVersion
  public let bindings: [HermesBridgeBindingSummary]

  public init(
    protocolVersion: HermesBridgeProtocolVersion = .current,
    bindings: [HermesBridgeBindingSummary]
  ) throws {
    let sorted =
      bindings
      .filter(\.enabled)
      .sorted { $0.bindingID.localizedStandardCompare($1.bindingID) == .orderedAscending }
    self.protocolVersion = protocolVersion
    self.bindings = Array(sorted.prefix(HermesBridgeBindingSummary.maximumCount))
    let encoded = (try? JSONEncoder().encode(self)) ?? Data()
    guard encoded.count <= HermesBridgeBindingSummary.maximumPayloadBytes else {
      throw HermesBridgeXPCError.oversizedPayload
    }
  }
}

public struct HermesBridgeRequestEnvelope: Codable, Equatable, Sendable {
  public static let maximumEnvelopeBytes = 128 * 1024
  public static let maximumPromptBytes = 64 * 1024

  public let protocolVersion: HermesBridgeProtocolVersion
  public let correlationID: HermesBridgeCorrelationID
  public let operation: HermesBridgeOperation
  public let submit: HermesBridgeSubmitPayload?
  public let status: HermesBridgeRequestIDPayload?
  public let cancel: HermesBridgeRequestIDPayload?
  public let approvalResponse: HermesBridgeApprovalResponsePayload?
  public let registerAuthorizedRoot: HermesBridgeRegisterAuthorizedRootPayload?
  public let refreshAuthorizedRoot: HermesBridgeRefreshAuthorizedRootPayload?
  public let deactivateAuthorizedRoot: HermesBridgeRootIDPayload?
  public let reactivateAuthorizedRoot: HermesBridgeReactivateAuthorizedRootPayload?
  public let removeAuthorizedRoot: HermesBridgeRootIDPayload?
  public let authorizedRootStatus: HermesBridgeRootIDPayload?
  public let resolveAuthorizedRoot: HermesBridgeRootIDPayload?
  public let createFileEventSubscription: HermesBridgeCreateFileEventSubscriptionPayload?
  public let pollFileEventSubscription: HermesBridgePollFileEventSubscriptionPayload?
  public let acknowledgeFileEventBatch: HermesBridgeAcknowledgeFileEventBatchPayload?
  public let cancelFileEventSubscription: HermesBridgeCancelFileEventSubscriptionPayload?
  public let createSystemEventSubscription: HermesBridgeCreateSystemEventSubscriptionPayload?
  public let pollSystemEventSubscription: HermesBridgePollSystemEventSubscriptionPayload?
  public let acknowledgeSystemEventBatch: HermesBridgeAcknowledgeSystemEventBatchPayload?
  public let cancelSystemEventSubscription: HermesBridgeCancelSystemEventSubscriptionPayload?
  public let eventPolicy: HermesBridgeEventPolicyPayload?
  public let eventPolicyID: HermesBridgeEventPolicyIDPayload?
  public let eventPolicyEvaluation: HermesBridgeEventPolicyEvaluationPayload?

  public init(
    protocolVersion: HermesBridgeProtocolVersion = .current,
    correlationID: HermesBridgeCorrelationID,
    operation: HermesBridgeOperation,
    submit: HermesBridgeSubmitPayload? = nil,
    status: HermesBridgeRequestIDPayload? = nil,
    cancel: HermesBridgeRequestIDPayload? = nil,
    approvalResponse: HermesBridgeApprovalResponsePayload? = nil,
    registerAuthorizedRoot: HermesBridgeRegisterAuthorizedRootPayload? = nil,
    refreshAuthorizedRoot: HermesBridgeRefreshAuthorizedRootPayload? = nil,
    deactivateAuthorizedRoot: HermesBridgeRootIDPayload? = nil,
    reactivateAuthorizedRoot: HermesBridgeReactivateAuthorizedRootPayload? = nil,
    removeAuthorizedRoot: HermesBridgeRootIDPayload? = nil,
    authorizedRootStatus: HermesBridgeRootIDPayload? = nil,
    resolveAuthorizedRoot: HermesBridgeRootIDPayload? = nil,
    createFileEventSubscription: HermesBridgeCreateFileEventSubscriptionPayload? = nil,
    pollFileEventSubscription: HermesBridgePollFileEventSubscriptionPayload? = nil,
    acknowledgeFileEventBatch: HermesBridgeAcknowledgeFileEventBatchPayload? = nil,
    cancelFileEventSubscription: HermesBridgeCancelFileEventSubscriptionPayload? = nil,
    createSystemEventSubscription: HermesBridgeCreateSystemEventSubscriptionPayload? = nil,
    pollSystemEventSubscription: HermesBridgePollSystemEventSubscriptionPayload? = nil,
    acknowledgeSystemEventBatch: HermesBridgeAcknowledgeSystemEventBatchPayload? = nil,
    cancelSystemEventSubscription: HermesBridgeCancelSystemEventSubscriptionPayload? = nil,
    eventPolicy: HermesBridgeEventPolicyPayload? = nil,
    eventPolicyID: HermesBridgeEventPolicyIDPayload? = nil,
    eventPolicyEvaluation: HermesBridgeEventPolicyEvaluationPayload? = nil
  ) {
    self.protocolVersion = protocolVersion
    self.correlationID = correlationID
    self.operation = operation
    self.submit = submit
    self.status = status
    self.cancel = cancel
    self.approvalResponse = approvalResponse
    self.registerAuthorizedRoot = registerAuthorizedRoot
    self.refreshAuthorizedRoot = refreshAuthorizedRoot
    self.deactivateAuthorizedRoot = deactivateAuthorizedRoot
    self.reactivateAuthorizedRoot = reactivateAuthorizedRoot
    self.removeAuthorizedRoot = removeAuthorizedRoot
    self.authorizedRootStatus = authorizedRootStatus
    self.resolveAuthorizedRoot = resolveAuthorizedRoot
    self.createFileEventSubscription = createFileEventSubscription
    self.pollFileEventSubscription = pollFileEventSubscription
    self.acknowledgeFileEventBatch = acknowledgeFileEventBatch
    self.cancelFileEventSubscription = cancelFileEventSubscription
    self.createSystemEventSubscription = createSystemEventSubscription
    self.pollSystemEventSubscription = pollSystemEventSubscription
    self.acknowledgeSystemEventBatch = acknowledgeSystemEventBatch
    self.cancelSystemEventSubscription = cancelSystemEventSubscription
    self.eventPolicy = eventPolicy
    self.eventPolicyID = eventPolicyID
    self.eventPolicyEvaluation = eventPolicyEvaluation
  }
}

public struct HermesBridgeRequestStatusPayload: Codable, Equatable, Sendable {
  public let requestID: String
  public let bindingID: String
  public let lifecycleState: String
  public let cancellationRequested: Bool
  public let resultAvailable: Bool
  public let failureCode: String?
  public let failureRetryable: Bool?

  public init(record: HermesRequestRecord) {
    self.requestID = record.requestID.rawValue
    self.bindingID = record.bindingID.rawValue
    self.lifecycleState = record.lifecycleState.rawValue
    self.cancellationRequested = record.cancellationRequested
    self.resultAvailable = record.result?.availability == .available
    self.failureCode = record.failure?.code
    self.failureRetryable = record.failure?.retryable
  }
}

public struct HermesBridgeProtocolVersionPayload: Codable, Equatable, Sendable {
  public let version: HermesBridgeProtocolVersion

  public init(version: HermesBridgeProtocolVersion) {
    self.version = version
  }
}

public struct HermesBridgeCapabilitiesPayload: Codable, Equatable, Sendable {
  public let protocolVersion: HermesBridgeProtocolVersion
  public let capabilities: [HermesBridgeCapability]

  public init(
    protocolVersion: HermesBridgeProtocolVersion = .current,
    capabilities: [HermesBridgeCapability] = HermesBridgeCapability.allCases
  ) {
    self.protocolVersion = protocolVersion
    self.capabilities = capabilities
  }
}

public enum HermesBridgeSuccessPayload: Codable, Equatable, Sendable {
  case protocolVersion(HermesBridgeProtocolVersionPayload)
  case capabilities(HermesBridgeCapabilitiesPayload)
  case listEnabledBindings(HermesBridgeBindingListPayload)
  case listAuthorizedRoots(HermesBridgeAuthorizedRootListPayload)
  case registerAuthorizedRoot(HermesBridgeAuthorizedRootPayload)
  case refreshAuthorizedRoot(HermesBridgeAuthorizedRootPayload)
  case deactivateAuthorizedRoot(HermesBridgeAuthorizedRootPayload)
  case reactivateAuthorizedRoot(HermesBridgeAuthorizedRootPayload)
  case removeAuthorizedRoot(HermesBridgeAuthorizedRootPayload)
  case authorizedRootStatus(HermesBridgeAuthorizedRootStatusPayload)
  case resolveAuthorizedRoot(HermesBridgeAuthorizedRootResolutionPayload)
  case createFileEventSubscription(HermesBridgeFileEventSubscriptionPayload)
  case pollFileEventSubscription(HermesBridgeFileEventBatchPayload)
  case acknowledgeFileEventBatch(HermesBridgeAcknowledgementPayload)
  case cancelFileEventSubscription(HermesBridgeFileEventSubscriptionPayload)
  case fileEventMonitorStatus(HermesBridgeFileEventMonitorStatusPayload)
  case createSystemEventSubscription(HermesBridgeSystemEventSubscriptionPayload)
  case pollSystemEventSubscription(HermesBridgeSystemEventBatchPayload)
  case acknowledgeSystemEventBatch(HermesBridgeAcknowledgementPayload)
  case cancelSystemEventSubscription(HermesBridgeSystemEventSubscriptionPayload)
  case systemEventMonitorStatus(HermesBridgeSystemEventMonitorStatusPayload)
  case listEventPolicies(HermesBridgeEventPolicyListPayload)
  case createEventPolicy(HermesBridgeEventPolicyPayload)
  case updateEventPolicy(HermesBridgeEventPolicyPayload)
  case enableEventPolicy(HermesBridgeEventPolicyPayload)
  case disableEventPolicy(HermesBridgeEventPolicyPayload)
  case removeEventPolicy(HermesBridgeEventPolicyIDPayload)
  case evaluateEventPolicyDryRun(HermesBridgeEventPolicyEvaluationResultPayload)
  case eventPolicyEngineStatus(HermesBridgeEventPolicyEngineStatusPayload)
  case pauseEventPolicies(HermesBridgeEventPolicyEngineStatusPayload)
  case resumeEventPolicies(HermesBridgeEventPolicyEngineStatusPayload)
  case submit(HermesBridgeRequestIDPayload)
  case status(HermesBridgeRequestStatusPayload)
  case cancel(HermesBridgeRequestStatusPayload)
  case approvalResponse(HermesBridgeRequestStatusPayload)
}

public struct HermesBridgeErrorPayload: Codable, Equatable, Sendable {
  public let code: HermesBridgeXPCError
  public let safeMessage: String

  public init(code: HermesBridgeXPCError, safeMessage: String) {
    self.code = code
    self.safeMessage = safeMessage
  }
}

public enum HermesBridgeResponseResult: Codable, Equatable, Sendable {
  case success(HermesBridgeSuccessPayload)
  case failure(HermesBridgeErrorPayload)
}

public struct HermesBridgeResponseEnvelope: Codable, Equatable, Sendable {
  public let protocolVersion: HermesBridgeProtocolVersion
  public let correlationID: HermesBridgeCorrelationID
  public let result: HermesBridgeResponseResult

  public init(
    protocolVersion: HermesBridgeProtocolVersion = .current,
    correlationID: HermesBridgeCorrelationID,
    result: HermesBridgeResponseResult
  ) {
    self.protocolVersion = protocolVersion
    self.correlationID = correlationID
    self.result = result
  }
}

extension String {
  fileprivate func prefixString(_ count: Int) -> String {
    String(prefix(count))
  }
}
