import Foundation

public struct HermesRequestExecutionPolicy: Equatable, Sendable {
  public let timeoutSeconds: TimeInterval?

  public init(timeoutSeconds: TimeInterval? = nil) {
    self.timeoutSeconds = timeoutSeconds
  }
}

public struct HermesBoundedPrompt: Equatable, Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  public let text: String
  public let maximumBytes: Int

  public init(_ text: String, maximumBytes: Int) throws {
    guard !text.isEmpty, text.utf8.count <= maximumBytes else {
      throw HermesRequestOrchestratorError.invalidBinding
    }
    self.text = text
    self.maximumBytes = maximumBytes
  }

  public var description: String {
    "<redacted HermesBoundedPrompt bytes=\(text.utf8.count)>"
  }

  public var debugDescription: String {
    description
  }
}

public struct HermesRequestSubmission: Equatable, Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  public let bindingID: HermesRequestBindingID
  public let prompt: HermesBoundedPrompt
  public let executionPolicy: HermesRequestExecutionPolicy?

  public init(
    bindingID: HermesRequestBindingID,
    prompt: HermesBoundedPrompt,
    executionPolicy: HermesRequestExecutionPolicy? = nil
  ) {
    self.bindingID = bindingID
    self.prompt = prompt
    self.executionPolicy = executionPolicy
  }

  public var description: String {
    "HermesRequestSubmission(bindingID: \(bindingID), prompt: <redacted>)"
  }

  public var debugDescription: String {
    description
  }
}

public struct HermesRequestBinding: Equatable, Sendable {
  public let id: HermesRequestBindingID
  public let enabled: Bool
  public let maximumPromptBytes: Int
  public let timeoutPolicy: HermesRequestExecutionPolicy?
  public let approvalPolicy: String?
  public let resultPolicy: String?

  public init(
    id: HermesRequestBindingID,
    enabled: Bool = true,
    maximumPromptBytes: Int = 64 * 1024,
    timeoutPolicy: HermesRequestExecutionPolicy? = nil,
    approvalPolicy: String? = nil,
    resultPolicy: String? = nil
  ) {
    self.id = id
    self.enabled = enabled
    self.maximumPromptBytes = max(1, maximumPromptBytes)
    self.timeoutPolicy = timeoutPolicy
    self.approvalPolicy = approvalPolicy
    self.resultPolicy = resultPolicy
  }
}

public protocol HermesRequestBindingRegistry: Sendable {
  func binding(for id: HermesRequestBindingID) async throws -> HermesRequestBinding?
}

public struct StaticHermesRequestBindingRegistry: HermesRequestBindingRegistry {
  private let bindings: [HermesRequestBindingID: HermesRequestBinding]

  public init(bindings: [HermesRequestBinding]) {
    self.bindings = Dictionary(uniqueKeysWithValues: bindings.map { ($0.id, $0) })
  }

  public func binding(for id: HermesRequestBindingID) async throws -> HermesRequestBinding? {
    bindings[id]
  }
}

public enum HermesRequestOrchestratorState: Equatable, Sendable {
  case idle
  case startingBackend
  case connecting
  case ready
  case stopping
  case failed(HermesRequestOrchestratorError)
}

public enum HermesRequestOrchestratorError: Error, Equatable, Sendable,
  CustomStringConvertible
{
  case invalidBinding
  case duplicateRequest
  case stateStoreFailure(String)
  case backendLaunchFailure(String)
  case backendConnectionFailure(String)
  case sessionCreationFailure(String)
  case promptSubmissionFailure(String)
  case requestNotFound
  case invalidCancellationState
  case reconciliationRequired
  case shutdownFailure(String)

  public var description: String {
    switch self {
    case .invalidBinding:
      return "invalid Hermes request binding"
    case .duplicateRequest:
      return "duplicate Hermes request execution"
    case .stateStoreFailure(let code):
      return "Hermes request state store failure: \(code)"
    case .backendLaunchFailure(let code):
      return "Hermes backend launch failure: \(code)"
    case .backendConnectionFailure(let code):
      return "Hermes backend connection failure: \(code)"
    case .sessionCreationFailure(let code):
      return "Hermes session creation failure: \(code)"
    case .promptSubmissionFailure(let code):
      return "Hermes prompt submission failure: \(code)"
    case .requestNotFound:
      return "Hermes request not found"
    case .invalidCancellationState:
      return "invalid Hermes request cancellation state"
    case .reconciliationRequired:
      return "Hermes request requires explicit reconciliation"
    case .shutdownFailure(let code):
      return "Hermes orchestrator shutdown failure: \(code)"
    }
  }
}

public enum HermesApprovalResponseDecision: Equatable, Sendable {
  case approve
  case reject

  var protocolDecision: HermesApprovalDecision {
    switch self {
    case .approve:
      return .approve
    case .reject:
      return .reject
    }
  }
}

public protocol HermesProcessSupervising: Sendable {
  var state: HermesProcessState { get }
  func start(configuration: HermesProcessConfiguration) throws -> HermesProcessLaunchResult
  func stop() throws -> HermesProcessStopResult
}

extension HermesProcessSupervisor: HermesProcessSupervising {}

public protocol HermesProtocolServicing: Sendable {
  var state: HermesProtocolClientState { get }
  var events: AsyncStream<HermesGatewayEvent> { get }

  func connectAndWaitUntilReady(timeout: TimeInterval) async throws
  func createSession() async throws -> HermesSessionCreationResult
  func submitPrompt(sessionID: String, text: String) async throws -> HermesPromptSubmissionResult
  func sessionStatus(sessionID: String) async throws -> HermesSessionStatusResult
  func interruptSession(sessionID: String) async throws -> HermesSessionInterruptResult
  func respondToApproval(
    sessionID: String,
    decision: HermesApprovalDecision,
    all: Bool?
  ) async throws -> HermesApprovalResponseResult
  func close() async
}

extension HermesProtocolClient: HermesProtocolServicing {}

public protocol HermesProtocolServiceFactory: Sendable {
  func makeProtocolService(launchContext: HermesBackendLaunchContext) -> HermesProtocolServicing
}

public struct HermesProtocolClientFactory: HermesProtocolServiceFactory {
  public init() {}

  public func makeProtocolService(
    launchContext: HermesBackendLaunchContext
  ) -> HermesProtocolServicing {
    HermesProtocolClient(endpoint: launchContext.endpoint, token: launchContext.sessionToken)
  }
}

public actor HermesRequestOrchestrator {
  public private(set) var state: HermesRequestOrchestratorState = .idle

  private let bindingRegistry: HermesRequestBindingRegistry
  private let stateStore: HermesRequestStateStore
  private let supervisor: HermesProcessSupervising
  private let processConfiguration: HermesProcessConfiguration
  private let protocolFactory: HermesProtocolServiceFactory
  private let gatewayReadyTimeout: TimeInterval

  private var launchContext: HermesBackendLaunchContext?
  private var protocolService: HermesProtocolServicing?
  private var eventTask: Task<Void, Never>?
  private var executingRequestIDs: Set<HermesRequestID> = []
  private var submittedRequestIDs: Set<HermesRequestID> = []
  private var sessionToRequestID: [HermesBackendSessionID: HermesRequestID] = [:]

  public init(
    bindingRegistry: HermesRequestBindingRegistry,
    stateStore: HermesRequestStateStore,
    supervisor: HermesProcessSupervising,
    processConfiguration: HermesProcessConfiguration,
    protocolFactory: HermesProtocolServiceFactory = HermesProtocolClientFactory(),
    gatewayReadyTimeout: TimeInterval = 5
  ) {
    self.bindingRegistry = bindingRegistry
    self.stateStore = stateStore
    self.supervisor = supervisor
    self.processConfiguration = processConfiguration
    self.protocolFactory = protocolFactory
    self.gatewayReadyTimeout = max(0.001, gatewayReadyTimeout)
  }

  @discardableResult
  public func submit(
    bindingID: HermesRequestBindingID,
    prompt: String
  ) async throws -> HermesRequestID {
    let binding = try await validatedBinding(bindingID: bindingID, prompt: prompt)
    let boundedPrompt = try HermesBoundedPrompt(prompt, maximumBytes: binding.maximumPromptBytes)
    let submission = HermesRequestSubmission(
      bindingID: bindingID,
      prompt: boundedPrompt,
      executionPolicy: binding.timeoutPolicy
    )
    let requestID = try HermesRequestID.generate()

    do {
      _ = try await stateStore.createAcceptedRequest(
        requestID: requestID,
        bindingID: submission.bindingID,
        createdAt: Date()
      )
      _ = try await stateStore.transitionState(
        requestID: requestID,
        to: .queued,
        expectedRevision: nil,
        updatedAt: Date()
      )
    } catch let error as HermesRequestStateStoreError {
      throw mapStateStoreError(error)
    } catch {
      throw HermesRequestOrchestratorError.stateStoreFailure(Self.safeCode(for: error))
    }

    try await executeSubmission(submission, requestID: requestID)
    return requestID
  }

  public func status(requestID: HermesRequestID) async throws -> HermesRequestRecord {
    do {
      return try await stateStore.read(requestID: requestID)
    } catch HermesRequestStateStoreError.unknownRequest {
      throw HermesRequestOrchestratorError.requestNotFound
    } catch {
      throw HermesRequestOrchestratorError.stateStoreFailure(Self.safeCode(for: error))
    }
  }

  public func cancel(requestID: HermesRequestID) async throws -> HermesRequestRecord {
    let record: HermesRequestRecord
    do {
      record = try await stateStore.read(requestID: requestID)
    } catch HermesRequestStateStoreError.unknownRequest {
      throw HermesRequestOrchestratorError.requestNotFound
    } catch {
      throw HermesRequestOrchestratorError.stateStoreFailure(Self.safeCode(for: error))
    }

    if record.lifecycleState.isTerminal {
      return record
    }

    switch record.lifecycleState {
    case .accepted, .queued:
      _ = try await requestCancellation(requestID)
      return try await markCancelled(requestID)
    case .starting:
      let cancelling = try await requestCancellation(requestID)
      if let sessionID = cancelling.backendSessionID {
        return try await interruptAndMarkCancelled(requestID: requestID, sessionID: sessionID)
      }
      return try await markCancelled(requestID)
    case .running, .waitingForApproval, .cancelling:
      let cancelling = try await requestCancellation(requestID)
      guard let sessionID = cancelling.backendSessionID else {
        return try await markInterrupted(requestID)
      }
      return try await interruptAndMarkCancelled(requestID: requestID, sessionID: sessionID)
    case .cancelled, .completed, .failed, .interrupted:
      return record
    }
  }

  public func respondToApproval(
    requestID: HermesRequestID,
    decision: HermesApprovalResponseDecision
  ) async throws -> HermesRequestRecord {
    let record = try await status(requestID: requestID)
    guard record.lifecycleState == .waitingForApproval,
      let sessionID = record.backendSessionID
    else {
      throw HermesRequestOrchestratorError.invalidCancellationState
    }
    guard let protocolService else {
      throw HermesRequestOrchestratorError.backendConnectionFailure("not_ready")
    }

    do {
      _ = try await protocolService.respondToApproval(
        sessionID: sessionID.rawValue,
        decision: decision.protocolDecision,
        all: nil
      )
      return try await stateStore.transitionState(
        requestID: requestID,
        to: .running,
        expectedRevision: nil,
        updatedAt: Date()
      )
    } catch let error as HermesRequestStateStoreError {
      throw mapStateStoreError(error)
    } catch {
      throw HermesRequestOrchestratorError.backendConnectionFailure(Self.safeCode(for: error))
    }
  }

  public func reconcileRecoverableRequests() async throws {
    let items: [HermesRequestRecoveryItem]
    do {
      items = try await stateStore.listRecoverableRequests()
    } catch {
      throw HermesRequestOrchestratorError.stateStoreFailure(Self.safeCode(for: error))
    }

    for item in items {
      switch item.decision {
      case .resumeEligible:
        _ = try await stateStore.markInterrupted(
          requestID: item.record.requestID,
          expectedRevision: nil,
          completedAt: Date()
        )
      case .reconcileWithSupervisor:
        try await reconcileWithSupervisor(item.record)
      case .reconcileWithProtocolClient:
        try await reconcileWithProtocolClient(item.record)
      case .markInterrupted:
        _ = try await stateStore.markInterrupted(
          requestID: item.record.requestID,
          expectedRevision: nil,
          completedAt: Date()
        )
      case .noActionTerminal:
        continue
      }
    }
  }

  public func shutdown() async throws {
    if state == .stopping {
      return
    }
    state = .stopping
    eventTask?.cancel()
    eventTask = nil
    if let protocolService {
      await protocolService.close()
    }
    protocolService = nil
    launchContext = nil
    do {
      _ = try supervisor.stop()
      state = .idle
    } catch {
      let failure = HermesRequestOrchestratorError.shutdownFailure(Self.safeCode(for: error))
      state = .failed(failure)
      throw failure
    }
  }

  private func executeSubmission(
    _ submission: HermesRequestSubmission,
    requestID: HermesRequestID
  ) async throws {
    guard !executingRequestIDs.contains(requestID), !submittedRequestIDs.contains(requestID) else {
      throw HermesRequestOrchestratorError.duplicateRequest
    }
    executingRequestIDs.insert(requestID)
    defer {
      executingRequestIDs.remove(requestID)
    }

    do {
      _ = try await ensureBackendReady()
      guard try await canContinueBackendWork(requestID: requestID) else {
        return
      }

      _ = try await stateStore.transitionState(
        requestID: requestID,
        to: .starting,
        expectedRevision: nil,
        updatedAt: Date()
      )

      let session = try await createBackendSession(requestID: requestID)
      let backendSessionID = try HermesBackendSessionID(rawValue: session.sessionID)
      sessionToRequestID[backendSessionID] = requestID
      _ = try await stateStore.attachBackendSessionIdentity(
        requestID: requestID,
        backendSessionID: backendSessionID,
        processLaunchID: launchContext?.identity.launchNonce,
        expectedRevision: nil,
        updatedAt: Date()
      )

      guard try await canContinueBackendWork(requestID: requestID) else {
        return
      }
      guard !submittedRequestIDs.contains(requestID) else {
        throw HermesRequestOrchestratorError.duplicateRequest
      }
      submittedRequestIDs.insert(requestID)
      try await submitPromptOnce(
        requestID: requestID,
        sessionID: backendSessionID,
        prompt: submission.prompt
      )
      _ = try await stateStore.transitionState(
        requestID: requestID,
        to: .running,
        expectedRevision: nil,
        updatedAt: Date()
      )
    } catch let error as HermesRequestOrchestratorError {
      try await failRequestIfPossible(requestID: requestID, error: error)
      state = .failed(error)
      throw error
    } catch let error as HermesRequestStateStoreError {
      let mapped = mapStateStoreError(error)
      state = .failed(mapped)
      throw mapped
    } catch {
      let mapped = HermesRequestOrchestratorError.promptSubmissionFailure(Self.safeCode(for: error))
      try await failRequestIfPossible(requestID: requestID, error: mapped)
      state = .failed(mapped)
      throw mapped
    }
  }

  private func validatedBinding(
    bindingID: HermesRequestBindingID,
    prompt: String
  ) async throws -> HermesRequestBinding {
    guard let binding = try await bindingRegistry.binding(for: bindingID), binding.enabled else {
      throw HermesRequestOrchestratorError.invalidBinding
    }
    guard !prompt.isEmpty, prompt.utf8.count <= binding.maximumPromptBytes else {
      throw HermesRequestOrchestratorError.invalidBinding
    }
    return binding
  }

  private func ensureBackendReady() async throws -> HermesBackendLaunchContext {
    if let launchContext, let protocolService, protocolService.state == .ready {
      state = .ready
      return launchContext
    }

    if let readyContext = readySupervisorContext() {
      launchContext = readyContext
    } else {
      state = .startingBackend
      do {
        let result = try supervisor.start(configuration: processConfiguration)
        launchContext = result.launchContext
      } catch {
        throw HermesRequestOrchestratorError.backendLaunchFailure(Self.safeCode(for: error))
      }
    }

    guard let launchContext else {
      throw HermesRequestOrchestratorError.backendLaunchFailure("missing_launch_context")
    }

    let service =
      protocolService ?? protocolFactory.makeProtocolService(launchContext: launchContext)
    protocolService = service
    state = .connecting
    do {
      try await service.connectAndWaitUntilReady(timeout: gatewayReadyTimeout)
      startEventPumpIfNeeded(service)
      state = .ready
      return launchContext
    } catch {
      throw HermesRequestOrchestratorError.backendConnectionFailure(Self.safeCode(for: error))
    }
  }

  private func readySupervisorContext() -> HermesBackendLaunchContext? {
    guard case .ready(let identity) = supervisor.state else {
      return nil
    }
    return HermesBackendLaunchContext(
      identity: identity,
      endpoint: processConfigurationEndpoint(),
      sessionToken: processConfiguration.sessionToken
    )
  }

  private func processConfigurationEndpoint() -> HermesBackendEndpoint {
    try! HermesBackendEndpoint(port: processConfiguration.port)
  }

  private func createBackendSession(
    requestID: HermesRequestID
  ) async throws -> HermesSessionCreationResult {
    guard let protocolService else {
      throw HermesRequestOrchestratorError.backendConnectionFailure("not_ready")
    }
    do {
      return try await protocolService.createSession()
    } catch {
      throw HermesRequestOrchestratorError.sessionCreationFailure(Self.safeCode(for: error))
    }
  }

  private func submitPromptOnce(
    requestID: HermesRequestID,
    sessionID: HermesBackendSessionID,
    prompt: HermesBoundedPrompt
  ) async throws {
    guard let protocolService else {
      throw HermesRequestOrchestratorError.backendConnectionFailure("not_ready")
    }
    do {
      _ = try await protocolService.submitPrompt(sessionID: sessionID.rawValue, text: prompt.text)
    } catch {
      throw HermesRequestOrchestratorError.promptSubmissionFailure(Self.safeCode(for: error))
    }
  }

  private func canContinueBackendWork(requestID: HermesRequestID) async throws -> Bool {
    let record = try await stateStore.read(requestID: requestID)
    if record.lifecycleState == .cancelled || record.lifecycleState == .interrupted {
      return false
    }
    if record.cancellationRequested || record.lifecycleState == .cancelling {
      _ = try await stateStore.markCancelled(
        requestID: requestID,
        expectedRevision: nil,
        completedAt: Date()
      )
      return false
    }
    return true
  }

  private func requestCancellation(_ requestID: HermesRequestID) async throws -> HermesRequestRecord
  {
    do {
      return try await stateStore.requestCancellation(
        requestID: requestID,
        expectedRevision: nil,
        updatedAt: Date()
      )
    } catch {
      throw HermesRequestOrchestratorError.stateStoreFailure(Self.safeCode(for: error))
    }
  }

  private func markCancelled(_ requestID: HermesRequestID) async throws -> HermesRequestRecord {
    do {
      return try await stateStore.markCancelled(
        requestID: requestID,
        expectedRevision: nil,
        completedAt: Date()
      )
    } catch {
      throw HermesRequestOrchestratorError.stateStoreFailure(Self.safeCode(for: error))
    }
  }

  private func markInterrupted(_ requestID: HermesRequestID) async throws -> HermesRequestRecord {
    do {
      return try await stateStore.markInterrupted(
        requestID: requestID,
        expectedRevision: nil,
        completedAt: Date()
      )
    } catch {
      throw HermesRequestOrchestratorError.stateStoreFailure(Self.safeCode(for: error))
    }
  }

  private func interruptAndMarkCancelled(
    requestID: HermesRequestID,
    sessionID: HermesBackendSessionID
  ) async throws -> HermesRequestRecord {
    guard let protocolService else {
      return try await markInterrupted(requestID)
    }
    do {
      let result = try await protocolService.interruptSession(sessionID: sessionID.rawValue)
      if result.status == "interrupted" || result.status == "cancelled" {
        return try await markCancelled(requestID)
      }
      return try await markInterrupted(requestID)
    } catch {
      return try await markInterrupted(requestID)
    }
  }

  private func reconcileWithSupervisor(_ record: HermesRequestRecord) async throws {
    guard case .ready(let identity) = supervisor.state,
      record.processLaunchID == nil || record.processLaunchID == identity.launchNonce
    else {
      _ = try await stateStore.markInterrupted(
        requestID: record.requestID,
        expectedRevision: nil,
        completedAt: Date()
      )
      return
    }
    if record.lifecycleState == .starting {
      throw HermesRequestOrchestratorError.reconciliationRequired
    }
  }

  private func reconcileWithProtocolClient(_ record: HermesRequestRecord) async throws {
    guard let sessionID = record.backendSessionID, let protocolService else {
      _ = try await stateStore.markInterrupted(
        requestID: record.requestID,
        expectedRevision: nil,
        completedAt: Date()
      )
      return
    }
    do {
      _ = try await protocolService.sessionStatus(sessionID: sessionID.rawValue)
    } catch {
      _ = try await stateStore.markInterrupted(
        requestID: record.requestID,
        expectedRevision: nil,
        completedAt: Date()
      )
    }
  }

  private func failRequestIfPossible(
    requestID: HermesRequestID,
    error: HermesRequestOrchestratorError
  ) async throws {
    let record = try? await stateStore.read(requestID: requestID)
    guard let record, !record.lifecycleState.isTerminal else {
      return
    }
    let failure = try HermesRequestFailure(
      category: failureCategory(for: error),
      code: failureCode(for: error),
      safeMessage: failureMessage(for: error),
      retryable: isRetryable(error)
    )
    _ = try await stateStore.markFailed(
      requestID: requestID,
      failure: failure,
      expectedRevision: nil,
      completedAt: Date()
    )
  }

  private func startEventPumpIfNeeded(_ service: HermesProtocolServicing) {
    guard eventTask == nil else {
      return
    }
    eventTask = Task {
      for await event in service.events {
        if Task.isCancelled {
          return
        }
        await self.handleGatewayEvent(event)
      }
      await self.handleGatewayDisconnect()
    }
  }

  private func handleGatewayEvent(_ event: HermesGatewayEvent) async {
    switch event {
    case .gatewayReady:
      state = .ready
    case .approvalRequest(let approval):
      await handleApprovalRequest(approval)
    case .backendEvent(let backendEvent):
      if backendEvent.type == "connection.failure" || backendEvent.type == "gateway.disconnect" {
        await handleGatewayDisconnect()
      }
    case .unknown:
      break
    }
  }

  private func handleApprovalRequest(_ approval: HermesApprovalRequest) async {
    guard let rawSessionID = approval.sessionID,
      let sessionID = try? HermesBackendSessionID(rawValue: rawSessionID),
      let requestID = sessionToRequestID[sessionID],
      let record = try? await stateStore.read(requestID: requestID),
      record.lifecycleState == .running
    else {
      return
    }
    _ = try? await stateStore.transitionState(
      requestID: requestID,
      to: .waitingForApproval,
      expectedRevision: nil,
      updatedAt: Date()
    )
  }

  private func handleGatewayDisconnect() async {
    let requestIDs = Array(sessionToRequestID.values)
    for requestID in requestIDs {
      guard let record = try? await stateStore.read(requestID: requestID),
        !record.lifecycleState.isTerminal
      else {
        continue
      }
      _ = try? await stateStore.markInterrupted(
        requestID: requestID,
        expectedRevision: nil,
        completedAt: Date()
      )
    }
  }

  private func mapStateStoreError(
    _ error: HermesRequestStateStoreError
  ) -> HermesRequestOrchestratorError {
    switch error {
    case .duplicateRequest:
      return .duplicateRequest
    case .unknownRequest:
      return .requestNotFound
    default:
      return .stateStoreFailure(Self.safeCode(for: error))
    }
  }

  private func failureCategory(
    for error: HermesRequestOrchestratorError
  ) -> HermesRequestFailureCategory {
    switch error {
    case .invalidBinding, .duplicateRequest:
      return .validation
    case .backendLaunchFailure:
      return .supervisorFailure
    case .backendConnectionFailure, .sessionCreationFailure, .promptSubmissionFailure:
      return .protocolFailure
    case .requestNotFound, .invalidCancellationState, .stateStoreFailure, .reconciliationRequired,
      .shutdownFailure:
      return .internalFailure
    }
  }

  private func failureCode(for error: HermesRequestOrchestratorError) -> String {
    switch error {
    case .invalidBinding:
      return "invalid_binding"
    case .duplicateRequest:
      return "duplicate_request"
    case .stateStoreFailure:
      return "state_store_failure"
    case .backendLaunchFailure:
      return "backend_launch_failure"
    case .backendConnectionFailure:
      return "backend_connection_failure"
    case .sessionCreationFailure:
      return "session_creation_failure"
    case .promptSubmissionFailure:
      return "prompt_submission_failure"
    case .requestNotFound:
      return "request_not_found"
    case .invalidCancellationState:
      return "invalid_cancellation_state"
    case .reconciliationRequired:
      return "reconciliation_required"
    case .shutdownFailure:
      return "shutdown_failure"
    }
  }

  private func failureMessage(for error: HermesRequestOrchestratorError) -> String {
    switch error {
    case .invalidBinding:
      return "Request binding is not allowed."
    case .duplicateRequest:
      return "Request execution was already started."
    case .stateStoreFailure:
      return "Request state could not be updated."
    case .backendLaunchFailure:
      return "Hermes backend could not be launched."
    case .backendConnectionFailure:
      return "Hermes backend connection could not be established."
    case .sessionCreationFailure:
      return "Hermes backend session could not be created."
    case .promptSubmissionFailure:
      return "Hermes prompt could not be submitted."
    case .requestNotFound:
      return "Request was not found."
    case .invalidCancellationState:
      return "Request cannot be cancelled in its current state."
    case .reconciliationRequired:
      return "Request requires explicit restart reconciliation."
    case .shutdownFailure:
      return "Hermes orchestrator shutdown failed."
    }
  }

  private func isRetryable(_ error: HermesRequestOrchestratorError) -> Bool {
    switch error {
    case .backendLaunchFailure, .backendConnectionFailure, .sessionCreationFailure,
      .promptSubmissionFailure, .reconciliationRequired:
      return true
    case .invalidBinding, .duplicateRequest, .stateStoreFailure, .requestNotFound,
      .invalidCancellationState, .shutdownFailure:
      return false
    }
  }

  private static func safeCode(for error: Error) -> String {
    let raw = String(describing: type(of: error))
    let filtered = raw.filter { character in
      character.isASCII
        && (character.isLetter || character.isNumber || character == "." || character == "_"
          || character == "-")
    }
    return String(filtered.prefix(64)).isEmpty ? "unknown_error" : String(filtered.prefix(64))
  }
}
