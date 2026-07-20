import Foundation
import HermesRuntimeFoundation

public enum HermesBridgeXPCClientError: Error, Equatable, Sendable {
  case timedOut
  case interrupted
  case invalidated
  case responseDecodingFailure
  case service(HermesBridgeXPCError)
  case protocolNegotiationFailed
}

public struct HermesBridgeMachServiceName: Equatable, Hashable, Sendable, CustomStringConvertible {
  public static let maximumLength = 255

  public let rawValue: String

  public init(_ rawValue: String) throws {
    guard !rawValue.isEmpty, rawValue.count <= Self.maximumLength else {
      throw HermesBridgeXPCClientError.protocolNegotiationFailed
    }
    guard
      rawValue.allSatisfy({ character in
        character.isASCII
          && (character.isLetter || character.isNumber || character == "." || character == "-"
            || character == "_")
      })
    else {
      throw HermesBridgeXPCClientError.protocolNegotiationFailed
    }
    self.rawValue = rawValue
  }

  public var description: String {
    rawValue
  }
}

public actor HermesBridgeXPCClient {
  private let transport: HermesBridgeXPCTransport
  private let timeout: TimeInterval
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()
  private var closed = false
  private var connected = false

  public init(machServiceName: HermesBridgeMachServiceName, timeout: TimeInterval = 5) {
    self.transport = HermesBridgeMachServiceTransport(machServiceName: machServiceName.rawValue)
    self.timeout = max(0.001, timeout)
  }

  init(transport: HermesBridgeXPCTransport, timeout: TimeInterval = 5) {
    self.transport = transport
    self.timeout = max(0.001, timeout)
  }

  @discardableResult
  public func connect() async throws -> HermesBridgeCapabilitiesPayload {
    let version = try await protocolVersion()
    guard version.version.major == HermesBridgeProtocolVersion.current.major else {
      throw HermesBridgeXPCClientError.protocolNegotiationFailed
    }
    let capabilities = try await capabilities()
    guard capabilities.protocolVersion.major == HermesBridgeProtocolVersion.current.major else {
      throw HermesBridgeXPCClientError.protocolNegotiationFailed
    }
    connected = true
    return capabilities
  }

  public func protocolVersion() async throws -> HermesBridgeProtocolVersionPayload {
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .protocolVersion
      ))
    guard case .success(.protocolVersion(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func capabilities() async throws -> HermesBridgeCapabilitiesPayload {
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .capabilities
      ))
    guard case .success(.capabilities(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func listEnabledBindings() async throws -> HermesBridgeBindingListPayload {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .listEnabledBindings
      ))
    guard case .success(.listEnabledBindings(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func listAuthorizedRoots() async throws -> HermesBridgeAuthorizedRootListPayload {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .listAuthorizedRoots
      ))
    guard case .success(.listAuthorizedRoots(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func registerAuthorizedRoot(
    displayName: String,
    bookmarkData: Data
  ) async throws -> HermesBridgeAuthorizedRootPayload {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .registerAuthorizedRoot,
        registerAuthorizedRoot: HermesBridgeRegisterAuthorizedRootPayload(
          displayName: displayName,
          bookmarkData: bookmarkData
        )
      ))
    guard case .success(.registerAuthorizedRoot(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func refreshAuthorizedRoot(
    rootID: HermesAuthorizedRootID,
    bookmarkData: Data,
    expectedRevision: Int? = nil
  ) async throws -> HermesBridgeAuthorizedRootPayload {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .refreshAuthorizedRoot,
        refreshAuthorizedRoot: HermesBridgeRefreshAuthorizedRootPayload(
          rootID: rootID.rawValue,
          bookmarkData: bookmarkData,
          expectedRevision: expectedRevision
        )
      ))
    guard case .success(.refreshAuthorizedRoot(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func deactivateAuthorizedRoot(
    rootID: HermesAuthorizedRootID,
    expectedRevision: Int? = nil
  ) async throws -> HermesBridgeAuthorizedRootPayload {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .deactivateAuthorizedRoot,
        deactivateAuthorizedRoot: HermesBridgeRootIDPayload(
          rootID: rootID.rawValue,
          expectedRevision: expectedRevision
        )
      ))
    guard case .success(.deactivateAuthorizedRoot(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func reactivateAuthorizedRoot(
    rootID: HermesAuthorizedRootID,
    bookmarkData: Data,
    expectedRevision: Int? = nil
  ) async throws -> HermesBridgeAuthorizedRootPayload {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .reactivateAuthorizedRoot,
        reactivateAuthorizedRoot: HermesBridgeReactivateAuthorizedRootPayload(
          rootID: rootID.rawValue,
          bookmarkData: bookmarkData,
          expectedRevision: expectedRevision
        )
      ))
    guard case .success(.reactivateAuthorizedRoot(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func removeAuthorizedRoot(
    rootID: HermesAuthorizedRootID,
    expectedRevision: Int? = nil
  ) async throws -> HermesBridgeAuthorizedRootPayload {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .removeAuthorizedRoot,
        removeAuthorizedRoot: HermesBridgeRootIDPayload(
          rootID: rootID.rawValue,
          expectedRevision: expectedRevision
        )
      ))
    guard case .success(.removeAuthorizedRoot(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func authorizedRootStatus(rootID: HermesAuthorizedRootID) async throws
    -> HermesBridgeAuthorizedRootStatusPayload
  {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .authorizedRootStatus,
        authorizedRootStatus: HermesBridgeRootIDPayload(rootID: rootID.rawValue)
      ))
    guard case .success(.authorizedRootStatus(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func resolveAuthorizedRoot(rootID: HermesAuthorizedRootID) async throws
    -> HermesBridgeAuthorizedRootResolutionPayload
  {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .resolveAuthorizedRoot,
        resolveAuthorizedRoot: HermesBridgeRootIDPayload(rootID: rootID.rawValue)
      ))
    guard case .success(.resolveAuthorizedRoot(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func createFileEventSubscription(rootIDs: [HermesAuthorizedRootID]) async throws
    -> HermesBridgeFileEventSubscriptionPayload
  {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .createFileEventSubscription,
        createFileEventSubscription: HermesBridgeCreateFileEventSubscriptionPayload(
          rootIDs: rootIDs.map(\.rawValue)
        )
      ))
    guard case .success(.createFileEventSubscription(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func pollFileEventSubscription(
    subscriptionID: HermesBridgeFileEventSubscriptionID,
    timeoutMilliseconds: Int = 0
  ) async throws -> HermesBridgeFileEventBatchPayload {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .pollFileEventSubscription,
        pollFileEventSubscription: HermesBridgePollFileEventSubscriptionPayload(
          subscriptionID: subscriptionID.rawValue,
          timeoutMilliseconds: timeoutMilliseconds
        )
      ))
    guard case .success(.pollFileEventSubscription(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func acknowledgeFileEventBatch(
    subscriptionID: HermesBridgeFileEventSubscriptionID,
    acknowledgedEventID: UInt64
  ) async throws -> HermesBridgeAcknowledgementPayload {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .acknowledgeFileEventBatch,
        acknowledgeFileEventBatch: HermesBridgeAcknowledgeFileEventBatchPayload(
          subscriptionID: subscriptionID.rawValue,
          acknowledgedEventID: acknowledgedEventID
        )
      ))
    guard case .success(.acknowledgeFileEventBatch(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func cancelFileEventSubscription(
    subscriptionID: HermesBridgeFileEventSubscriptionID
  ) async throws -> HermesBridgeFileEventSubscriptionPayload {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .cancelFileEventSubscription,
        cancelFileEventSubscription: HermesBridgeCancelFileEventSubscriptionPayload(
          subscriptionID: subscriptionID.rawValue
        )
      ))
    guard case .success(.cancelFileEventSubscription(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func fileEventMonitorStatus() async throws -> HermesBridgeFileEventMonitorStatusPayload {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .fileEventMonitorStatus
      ))
    guard case .success(.fileEventMonitorStatus(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func createSystemEventSubscription(kinds: [HermesSystemEventKind]) async throws
    -> HermesBridgeSystemEventSubscriptionPayload
  {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .createSystemEventSubscription,
        createSystemEventSubscription: HermesBridgeCreateSystemEventSubscriptionPayload(
          kinds: kinds
        )
      ))
    guard case .success(.createSystemEventSubscription(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func pollSystemEventSubscription(
    subscriptionID: HermesSystemEventSubscriptionID,
    timeoutMilliseconds: Int = 0
  ) async throws -> HermesBridgeSystemEventBatchPayload {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .pollSystemEventSubscription,
        pollSystemEventSubscription: HermesBridgePollSystemEventSubscriptionPayload(
          subscriptionID: subscriptionID.rawValue,
          timeoutMilliseconds: timeoutMilliseconds
        )
      ))
    guard case .success(.pollSystemEventSubscription(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func acknowledgeSystemEventBatch(
    subscriptionID: HermesSystemEventSubscriptionID,
    acknowledgedEventOrdinal: UInt64
  ) async throws -> HermesBridgeAcknowledgementPayload {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .acknowledgeSystemEventBatch,
        acknowledgeSystemEventBatch: HermesBridgeAcknowledgeSystemEventBatchPayload(
          subscriptionID: subscriptionID.rawValue,
          acknowledgedEventOrdinal: acknowledgedEventOrdinal
        )
      ))
    guard case .success(.acknowledgeSystemEventBatch(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func cancelSystemEventSubscription(
    subscriptionID: HermesSystemEventSubscriptionID
  ) async throws -> HermesBridgeSystemEventSubscriptionPayload {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .cancelSystemEventSubscription,
        cancelSystemEventSubscription: HermesBridgeCancelSystemEventSubscriptionPayload(
          subscriptionID: subscriptionID.rawValue
        )
      ))
    guard case .success(.cancelSystemEventSubscription(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func systemEventMonitorStatus() async throws -> HermesBridgeSystemEventMonitorStatusPayload
  {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .systemEventMonitorStatus
      ))
    guard case .success(.systemEventMonitorStatus(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func listEventPolicies() async throws -> HermesBridgeEventPolicyListPayload {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .listEventPolicies
      ))
    guard case .success(.listEventPolicies(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func createEventPolicy(_ policy: HermesEventPolicy) async throws
    -> HermesBridgeEventPolicyPayload
  {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .createEventPolicy,
        eventPolicy: HermesBridgeEventPolicyPayload(policy: policy)
      ))
    guard case .success(.createEventPolicy(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func updateEventPolicy(_ policy: HermesEventPolicy, expectedRevision: Int) async throws
    -> HermesBridgeEventPolicyPayload
  {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .updateEventPolicy,
        eventPolicy: HermesBridgeEventPolicyPayload(
          policy: policy,
          expectedRevision: expectedRevision
        )
      ))
    guard case .success(.updateEventPolicy(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func enableEventPolicy(
    id: HermesEventPolicyID,
    expectedRevision: Int? = nil
  ) async throws -> HermesBridgeEventPolicyPayload {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .enableEventPolicy,
        eventPolicyID: HermesBridgeEventPolicyIDPayload(
          policyID: id,
          expectedRevision: expectedRevision
        )
      ))
    guard case .success(.enableEventPolicy(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func disableEventPolicy(
    id: HermesEventPolicyID,
    expectedRevision: Int? = nil
  ) async throws -> HermesBridgeEventPolicyPayload {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .disableEventPolicy,
        eventPolicyID: HermesBridgeEventPolicyIDPayload(
          policyID: id,
          expectedRevision: expectedRevision
        )
      ))
    guard case .success(.disableEventPolicy(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func removeEventPolicy(
    id: HermesEventPolicyID,
    expectedRevision: Int? = nil
  ) async throws -> HermesBridgeEventPolicyIDPayload {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .removeEventPolicy,
        eventPolicyID: HermesBridgeEventPolicyIDPayload(
          policyID: id,
          expectedRevision: expectedRevision
        )
      ))
    guard case .success(.removeEventPolicy(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func evaluateEventPolicyDryRun(event: HermesSystemEvent) async throws
    -> HermesBridgeEventPolicyEvaluationResultPayload
  {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .evaluateEventPolicyDryRun,
        eventPolicyEvaluation: HermesBridgeEventPolicyEvaluationPayload(event: event)
      ))
    guard case .success(.evaluateEventPolicyDryRun(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func eventPolicyEngineStatus() async throws -> HermesBridgeEventPolicyEngineStatusPayload {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .eventPolicyEngineStatus
      ))
    guard case .success(.eventPolicyEngineStatus(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func pauseEventPolicies() async throws -> HermesBridgeEventPolicyEngineStatusPayload {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .pauseEventPolicies
      ))
    guard case .success(.pauseEventPolicies(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func resumeEventPolicies() async throws -> HermesBridgeEventPolicyEngineStatusPayload {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .resumeEventPolicies
      ))
    guard case .success(.resumeEventPolicies(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func submit(bindingID: HermesRequestBindingID, prompt: String) async throws
    -> HermesRequestID
  {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .submit,
        submit: HermesBridgeSubmitPayload(bindingID: bindingID.rawValue, prompt: prompt)
      ))
    guard case .success(.submit(let payload)) = response.result else {
      throw clientError(from: response)
    }
    do {
      return try HermesRequestID(rawValue: payload.requestID)
    } catch {
      throw HermesBridgeXPCClientError.responseDecodingFailure
    }
  }

  public func status(requestID: HermesRequestID) async throws -> HermesBridgeRequestStatusPayload {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .status,
        status: HermesBridgeRequestIDPayload(requestID: requestID.rawValue)
      ))
    guard case .success(.status(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func cancel(requestID: HermesRequestID) async throws -> HermesBridgeRequestStatusPayload {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .cancel,
        cancel: HermesBridgeRequestIDPayload(requestID: requestID.rawValue)
      ))
    guard case .success(.cancel(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func respondToApproval(
    requestID: HermesRequestID,
    decision: HermesBridgeApprovalDecision
  ) async throws -> HermesBridgeRequestStatusPayload {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .approvalResponse,
        approvalResponse: HermesBridgeApprovalResponsePayload(
          requestID: requestID.rawValue,
          decision: decision
        )
      ))
    guard case .success(.approvalResponse(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func close() {
    if closed {
      return
    }
    closed = true
    transport.close()
  }

  private func send(_ envelope: HermesBridgeRequestEnvelope) async throws
    -> HermesBridgeResponseEnvelope
  {
    try ensureOpen()
    let requestData = try encoder.encode(envelope)
    let responseData = try await withThrowingTaskGroup(of: Data.self) { group in
      group.addTask {
        try await self.transport.send(requestData)
      }
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(self.timeout * 1_000_000_000))
        throw HermesBridgeXPCClientError.timedOut
      }
      let data = try await group.next()!
      group.cancelAll()
      return data
    }
    do {
      let response = try decoder.decode(HermesBridgeResponseEnvelope.self, from: responseData)
      guard response.correlationID == envelope.correlationID else {
        throw HermesBridgeXPCClientError.responseDecodingFailure
      }
      return response
    } catch let error as HermesBridgeXPCClientError {
      throw error
    } catch {
      throw HermesBridgeXPCClientError.responseDecodingFailure
    }
  }

  private func ensureOpen() throws {
    if closed {
      throw HermesBridgeXPCClientError.invalidated
    }
  }

  private func clientError(from response: HermesBridgeResponseEnvelope)
    -> HermesBridgeXPCClientError
  {
    switch response.result {
    case .failure(let error):
      return .service(error.code)
    case .success:
      return .responseDecodingFailure
    }
  }

  private static func correlationID() -> HermesBridgeCorrelationID {
    try! HermesBridgeCorrelationID(rawValue: UUID().uuidString)
  }
}

public struct HermesBridgeAppIntentAdapter: Sendable {
  private let client: HermesBridgeXPCClient

  public init(client: HermesBridgeXPCClient) {
    self.client = client
  }

  public func submit(bindingID: HermesRequestBindingID, prompt: String) async throws
    -> HermesRequestID
  {
    try await client.submit(bindingID: bindingID, prompt: prompt)
  }

  public func status(requestID: HermesRequestID) async throws -> HermesBridgeRequestStatusPayload {
    try await client.status(requestID: requestID)
  }

  public func cancel(requestID: HermesRequestID) async throws -> HermesBridgeRequestStatusPayload {
    try await client.cancel(requestID: requestID)
  }

  public func listEnabledBindings() async throws -> HermesBridgeBindingListPayload {
    try await client.listEnabledBindings()
  }
}

public struct HermesBridgeFileIntegrationAppAdapter: Sendable {
  private let client: HermesBridgeXPCClient

  public init(client: HermesBridgeXPCClient) {
    self.client = client
  }

  public func listAuthorizedRoots() async throws -> HermesBridgeAuthorizedRootListPayload {
    try await client.listAuthorizedRoots()
  }

  public func registerAuthorizedRoot(
    displayName: String,
    bookmarkData: Data
  ) async throws -> HermesBridgeAuthorizedRootPayload {
    try await client.registerAuthorizedRoot(displayName: displayName, bookmarkData: bookmarkData)
  }

  public func fileEventMonitorStatus() async throws -> HermesBridgeFileEventMonitorStatusPayload {
    try await client.fileEventMonitorStatus()
  }
}

public struct HermesBridgeSystemEventAppAdapter: Sendable {
  private let client: HermesBridgeXPCClient

  public init(client: HermesBridgeXPCClient) {
    self.client = client
  }

  public func monitorStatus() async throws -> HermesBridgeSystemEventMonitorStatusPayload {
    try await client.systemEventMonitorStatus()
  }

  public func createSubscription(kinds: [HermesSystemEventKind]) async throws
    -> HermesBridgeSystemEventSubscriptionPayload
  {
    try await client.createSystemEventSubscription(kinds: kinds)
  }

  public func poll(
    subscriptionID: HermesSystemEventSubscriptionID,
    timeoutMilliseconds: Int
  ) async throws -> HermesBridgeSystemEventBatchPayload {
    try await client.pollSystemEventSubscription(
      subscriptionID: subscriptionID,
      timeoutMilliseconds: timeoutMilliseconds
    )
  }

  public func acknowledge(
    subscriptionID: HermesSystemEventSubscriptionID,
    acknowledgedEventOrdinal: UInt64
  ) async throws -> HermesBridgeAcknowledgementPayload {
    try await client.acknowledgeSystemEventBatch(
      subscriptionID: subscriptionID,
      acknowledgedEventOrdinal: acknowledgedEventOrdinal
    )
  }

  public func cancel(subscriptionID: HermesSystemEventSubscriptionID) async throws
    -> HermesBridgeSystemEventSubscriptionPayload
  {
    try await client.cancelSystemEventSubscription(subscriptionID: subscriptionID)
  }
}

public struct HermesBridgeEventPolicyAppAdapter: Sendable {
  private let client: HermesBridgeXPCClient

  public init(client: HermesBridgeXPCClient) {
    self.client = client
  }

  public func listPolicies() async throws -> HermesBridgeEventPolicyListPayload {
    try await client.listEventPolicies()
  }

  public func createPolicy(_ policy: HermesEventPolicy) async throws
    -> HermesBridgeEventPolicyPayload
  {
    try await client.createEventPolicy(policy)
  }

  public func updatePolicy(_ policy: HermesEventPolicy, expectedRevision: Int) async throws
    -> HermesBridgeEventPolicyPayload
  {
    try await client.updateEventPolicy(policy, expectedRevision: expectedRevision)
  }

  public func enablePolicy(id: HermesEventPolicyID, expectedRevision: Int?) async throws
    -> HermesBridgeEventPolicyPayload
  {
    try await client.enableEventPolicy(id: id, expectedRevision: expectedRevision)
  }

  public func disablePolicy(id: HermesEventPolicyID, expectedRevision: Int?) async throws
    -> HermesBridgeEventPolicyPayload
  {
    try await client.disableEventPolicy(id: id, expectedRevision: expectedRevision)
  }

  public func dryRun(event: HermesSystemEvent) async throws
    -> HermesBridgeEventPolicyEvaluationResultPayload
  {
    try await client.evaluateEventPolicyDryRun(event: event)
  }

  public func status() async throws -> HermesBridgeEventPolicyEngineStatusPayload {
    try await client.eventPolicyEngineStatus()
  }

  public func pause() async throws -> HermesBridgeEventPolicyEngineStatusPayload {
    try await client.pauseEventPolicies()
  }

  public func resume() async throws -> HermesBridgeEventPolicyEngineStatusPayload {
    try await client.resumeEventPolicies()
  }
}

protocol HermesBridgeXPCTransport: Sendable {
  func send(_ requestData: Data) async throws -> Data
  func close()
}

final class HermesBridgeMachServiceTransport: HermesBridgeXPCTransport, @unchecked Sendable {
  private let lock = NSLock()
  private let connection: NSXPCConnection
  private var closed = false
  private var unavailableError: HermesBridgeXPCClientError?

  init(machServiceName: String) {
    connection = NSXPCConnection(machServiceName: machServiceName, options: [])
    connection.remoteObjectInterface = NSXPCInterface(with: HermesBridgeXPCProtocol.self)
    connection.interruptionHandler = { [weak self] in
      self?.setUnavailable(.interrupted)
    }
    connection.invalidationHandler = { [weak self] in
      self?.setUnavailable(.invalidated)
    }
    connection.resume()
  }

  func send(_ requestData: Data) async throws -> Data {
    let proxy: HermesBridgeXPCProtocol = try lock.withLock {
      if let unavailableError {
        throw unavailableError
      }
      if closed {
        throw HermesBridgeXPCClientError.invalidated
      }
      guard
        let proxy = connection.remoteObjectProxyWithErrorHandler({ [weak self] _ in
          self?.setUnavailable(.interrupted)
        }) as? HermesBridgeXPCProtocol
      else {
        throw HermesBridgeXPCClientError.interrupted
      }
      return proxy
    }

    return try await withCheckedThrowingContinuation { continuation in
      let resumer = HermesBridgeXPCReplyResumer(continuation)
      proxy.handleRequest(requestData) { data in
        resumer.resume(returning: data)
      }
    }
  }

  func close() {
    lock.withLock {
      if closed {
        return
      }
      closed = true
      unavailableError = .invalidated
      connection.invalidate()
    }
  }

  private func setUnavailable(_ error: HermesBridgeXPCClientError) {
    lock.withLock {
      unavailableError = error
    }
  }
}

private final class HermesBridgeXPCReplyResumer: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Data, Error>?

  init(_ continuation: CheckedContinuation<Data, Error>) {
    self.continuation = continuation
  }

  func resume(returning data: Data) {
    let continuation = lock.withLock {
      let current = self.continuation
      self.continuation = nil
      return current
    }
    continuation?.resume(returning: data)
  }
}
