import Foundation
import HermesBridgeXPC
import HermesRuntimeFoundation
import HermesTimeline

public enum HermesBridgeCompositionRootError: Error, Equatable, Sendable {
  case missingExecutableCandidate
  case invalidExecutableCandidate
  case processConfigurationFailed(String)
  case stateStoreFailed(String)
  case bindingRegistryFailed(String)
  case authorizedRootRegistryFailed(String)
  case eventPolicyStoreFailed(String)
  case eventPolicyApprovalStoreFailed(String)
}

public final class HermesBridgeCompositionRoot: @unchecked Sendable {
  public let configuration: HermesBridgeServiceConfiguration
  public let paths: HermesBridgeServicePaths
  public let discovery: HermesDiscovery
  public let supervisor: HermesProcessSupervisor
  public let protocolFactory: HermesProtocolClientFactory
  public let runtimeEventBus: HermesRuntimeEventBus
  public let timelineCollector: HermesTimelineCollector
  public let runtimeSessionManager: HermesRuntimeSessionManager
  public let runtimeCommandAPI: HermesRuntimeCommandAPI
  public let stateStore: FileBackedHermesRequestStateStore
  public let bindingRegistry: ConfigurationBackedHermesRequestBindingRegistry
  public let authorizedRootRegistry: FileBackedHermesAuthorizedRootRegistry
  public let fileIntegration: HermesBridgeFileIntegrationCoordinator
  public let systemEventIntegration: HermesBridgeSystemEventCoordinator
  public let eventPolicyStore: FileBackedHermesEventPolicyStore
  public let eventPolicyApprovalStore: FileBackedHermesEventPolicyApprovalStore
  public let eventPolicyApprovalCoordinator: HermesEventPolicyApprovalCoordinator
  public let eventPolicyEngine: HermesEventPolicyEngine
  public let orchestrator: HermesRequestOrchestrator
  public let auditStore: any HermesAuditStore
  public let requestHandler: HermesBridgeServiceRequestHandler
  public let dispatcher: HermesBridgeXPCRequestDispatcher
  public let xpcService: HermesBridgeXPCService
  public let logger: HermesBridgeServiceLogger

  private let lock = NSLock()
  private var stopped = false

  public init(
    configuration: HermesBridgeServiceConfiguration,
    paths: HermesBridgeServicePaths? = nil,
    logger: HermesBridgeServiceLogger? = nil
  ) throws {
    self.configuration = configuration
    let resolvedPaths = try paths ?? HermesBridgeServicePaths(configuration: configuration)
    self.paths = resolvedPaths
    self.logger = logger ?? HermesBridgeServiceLogger(logsRoot: resolvedPaths.logsRoot)
    self.discovery = HermesDiscovery(
      allowlistedExecutableCandidates: configuration.allowlistedHermesExecutableCandidates,
      timeoutSeconds: min(configuration.timeouts.startup, 10)
    )
    self.supervisor = HermesProcessSupervisor()
    self.protocolFactory = HermesProtocolClientFactory()
    self.runtimeEventBus = HermesRuntimeEventBus()
    self.timelineCollector = HermesTimelineCollector()

    do {
      self.stateStore = try FileBackedHermesRequestStateStore(
        storageRoot: resolvedPaths.requestStateRoot)
    } catch {
      throw HermesBridgeCompositionRootError.stateStoreFailed(Self.safeCode(for: error))
    }

    do {
      self.bindingRegistry = try ConfigurationBackedHermesRequestBindingRegistry(
        definitions: configuration.bindings)
    } catch {
      throw HermesBridgeCompositionRootError.bindingRegistryFailed(Self.safeCode(for: error))
    }

    do {
      self.authorizedRootRegistry = try FileBackedHermesAuthorizedRootRegistry(
        registryRoot: resolvedPaths.authorizedRootsRoot,
        policy: HermesAuthorizedRootPolicy(permittedRootParents: [])
      )
    } catch {
      throw HermesBridgeCompositionRootError.authorizedRootRegistryFailed(Self.safeCode(for: error))
    }
    self.fileIntegration = HermesBridgeFileIntegrationCoordinator(
      registry: authorizedRootRegistry
    )
    self.systemEventIntegration = HermesBridgeSystemEventCoordinator()
    do {
      self.eventPolicyStore = try FileBackedHermesEventPolicyStore(
        root: resolvedPaths.eventPoliciesRoot)
    } catch {
      throw HermesBridgeCompositionRootError.eventPolicyStoreFailed(Self.safeCode(for: error))
    }
    do {
      self.eventPolicyApprovalStore = try FileBackedHermesEventPolicyApprovalStore(
        root: resolvedPaths.eventPolicyApprovalsRoot)
    } catch {
      throw HermesBridgeCompositionRootError.eventPolicyApprovalStoreFailed(
        Self.safeCode(for: error))
    }
    let monitor = HermesFSEventsMonitor(registry: authorizedRootRegistry) {
      [fileIntegration] batch in
      await fileIntegration.ingest(batch: batch)
    }
    let networkMonitor = HermesSystemNetworkMonitor { [systemEventIntegration] state in
      await systemEventIntegration.ingestNetworkState(state)
    }
    let workspaceMonitor = HermesSystemWorkspaceMonitor { [systemEventIntegration] kind, app in
      await systemEventIntegration.ingestWorkspace(kind: kind, application: app)
    }

    let processConfiguration: HermesProcessConfiguration
    do {
      processConfiguration = try HermesProcessConfiguration(
        executable: Self.serviceExecutableCandidate(configuration),
        port: configuration.loopbackPortPolicy.fixedPort,
        runtimeRoot: resolvedPaths.runtimeRoot,
        startupTimeout: configuration.timeouts.startup,
        gracefulShutdownTimeout: configuration.timeouts.gracefulShutdown,
        forcedShutdownTimeout: configuration.timeouts.forcedShutdown
      )
    } catch {
      throw HermesBridgeCompositionRootError.processConfigurationFailed(Self.safeCode(for: error))
    }

    let backendConfiguration = HermesBackendAdapterConfiguration(
      executableURL: URL(fileURLWithPath: processConfiguration.executable.resolvedPath),
      port: processConfiguration.port,
      runtimeRoot: processConfiguration.runtimeRoot,
      startupTimeout: processConfiguration.startupTimeout,
      gracefulShutdownTimeout: processConfiguration.gracefulShutdownTimeout,
      forcedShutdownTimeout: processConfiguration.forcedShutdownTimeout
    )
    let runtimeSupervisor = supervisor
    self.runtimeSessionManager = HermesRuntimeSessionManager(
      backendFactory: {
        HermesBackendAdapter(
          allowlistedExecutableCandidates: configuration.allowlistedHermesExecutableCandidates,
          configuration: backendConfiguration,
          supervisor: runtimeSupervisor
        )
      },
      eventBus: runtimeEventBus
    )
    self.runtimeCommandAPI = HermesRuntimeCommandAPI(sessionManager: runtimeSessionManager)
    timelineCollector.start(eventBus: runtimeEventBus)

    self.orchestrator = HermesRequestOrchestrator(
      bindingRegistry: bindingRegistry,
      stateStore: stateStore,
      supervisor: supervisor,
      processConfiguration: processConfiguration,
      protocolFactory: protocolFactory,
      gatewayReadyTimeout: configuration.timeouts.gatewayReady
    )
    self.auditStore =
      (try? FileBackedHermesAuditStore(
        configuration: HermesAuditStoreConfiguration(
          root: resolvedPaths.logsRoot.appendingPathComponent("Audit", isDirectory: true)
        ))) ?? NoopHermesAuditStore()
    self.eventPolicyApprovalCoordinator = HermesEventPolicyApprovalCoordinator(
      store: eventPolicyApprovalStore,
      policyStore: eventPolicyStore,
      bindingDiscovery: bindingRegistry,
      submitter: HermesBridgeEventPolicyRequestSubmitter(orchestrator: orchestrator),
      serviceManager: HermesBridgeEventPolicyServiceAdapter(),
      auditStore: auditStore
    )
    self.eventPolicyEngine = HermesEventPolicyEngine(
      store: eventPolicyStore,
      bindingDiscovery: bindingRegistry,
      submitter: HermesBridgeEventPolicyRequestSubmitter(orchestrator: orchestrator),
      serviceManager: HermesBridgeEventPolicyServiceAdapter(),
      auditStore: auditStore,
      approvalCoordinator: eventPolicyApprovalCoordinator
    )
    self.requestHandler = HermesBridgeServiceRequestHandler(
      orchestrator: orchestrator,
      bindingRegistry: bindingRegistry,
      fileIntegration: fileIntegration,
      systemEventIntegration: systemEventIntegration,
      eventPolicyEngine: eventPolicyEngine,
      runtimeCommandAPI: runtimeCommandAPI,
      agentDiscovery: discovery,
      agentExecutableURL: backendConfiguration.executableURL
    )
    self.dispatcher = HermesBridgeXPCRequestDispatcher(
      handler: requestHandler,
      auditStore: auditStore,
      maximumConcurrentRequests: configuration.maximumConcurrentXPCRequests
    )
    self.xpcService = HermesBridgeXPCService(dispatcher: dispatcher)
    Task {
      await fileIntegration.setMonitor(monitor)
      await systemEventIntegration.setNetworkMonitor(networkMonitor)
      await systemEventIntegration.setWorkspaceMonitor(workspaceMonitor)
      await systemEventIntegration.setEventHandler { [eventPolicyEngine] event in
        _ = await eventPolicyEngine.evaluate(event)
      }
    }
  }

  public func shutdown() async throws {
    let shouldStop = lock.withLock {
      if stopped {
        return false
      }
      stopped = true
      return true
    }
    guard shouldStop else {
      return
    }
    logger.log(.stopping)
    timelineCollector.stop()
    xpcService.invalidate()
    await fileIntegration.shutdown()
    await systemEventIntegration.shutdown()
    do {
      try await orchestrator.shutdown()
      logger.log(.stopped)
    } catch {
      logger.log(.stopped, error: error)
      throw error
    }
  }

  private static func serviceExecutableCandidate(
    _ configuration: HermesBridgeServiceConfiguration
  ) throws -> HermesExecutableCandidate {
    guard let url = configuration.allowlistedHermesExecutableCandidates.first else {
      throw HermesBridgeCompositionRootError.missingExecutableCandidate
    }
    let standardized = url.standardizedFileURL
    guard standardized.isFileURL, !standardized.path.isEmpty else {
      throw HermesBridgeCompositionRootError.invalidExecutableCandidate
    }
    return HermesExecutableCandidate(
      allowlistedCandidatePath: standardized.path,
      originalPath: standardized.path,
      resolvedPath: standardized.resolvingSymlinksInPath().path,
      symlinkStatus: symlinkStatus(for: standardized)
    )
  }

  private static func symlinkStatus(for url: URL) -> HermesExecutableCandidate.SymlinkStatus {
    do {
      _ = try FileManager.default.destinationOfSymbolicLink(atPath: url.path)
      return .symlink(
        resolved: FileManager.default.fileExists(
          atPath: url.resolvingSymlinksInPath().path))
    } catch {
      return .notSymlink
    }
  }

  private static func safeCode(for error: Error) -> String {
    String(describing: type(of: error))
      .filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
  }
}

public struct HermesBridgeServiceRequestHandler: HermesBridgeRequestHandling {
  private let orchestrator: HermesRequestOrchestrator
  private let bindingRegistry: ConfigurationBackedHermesRequestBindingRegistry
  private let fileIntegration: HermesBridgeFileIntegrationCoordinator
  private let systemEventIntegration: HermesBridgeSystemEventCoordinator
  private let eventPolicyEngine: HermesEventPolicyEngine
  private let runtimeCommandAPI: HermesRuntimeCommandAPI
  private let agentDiscovery: any HermesBackendDiscovering
  private let agentExecutableURL: URL
  private let runtimeEvents: HermesBridgeRuntimeEventSubscriptionCoordinator

  public init(
    orchestrator: HermesRequestOrchestrator,
    bindingRegistry: ConfigurationBackedHermesRequestBindingRegistry,
    fileIntegration: HermesBridgeFileIntegrationCoordinator,
    systemEventIntegration: HermesBridgeSystemEventCoordinator,
    eventPolicyEngine: HermesEventPolicyEngine,
    runtimeCommandAPI: HermesRuntimeCommandAPI,
    agentDiscovery: any HermesBackendDiscovering,
    agentExecutableURL: URL
  ) {
    self.orchestrator = orchestrator
    self.bindingRegistry = bindingRegistry
    self.fileIntegration = fileIntegration
    self.systemEventIntegration = systemEventIntegration
    self.eventPolicyEngine = eventPolicyEngine
    self.runtimeCommandAPI = runtimeCommandAPI
    self.agentDiscovery = agentDiscovery
    self.agentExecutableURL = agentExecutableURL.standardizedFileURL
    self.runtimeEvents = HermesBridgeRuntimeEventSubscriptionCoordinator(commandAPI: runtimeCommandAPI)
  }

  public func listEnabledBindings() async throws -> [HermesBridgeBindingSummary] {
    try await bindingRegistry.listEnabledBindings()
  }

  public func listAuthorizedRoots() async throws -> HermesBridgeAuthorizedRootListPayload {
    try await fileIntegration.listAuthorizedRoots()
  }

  public func registerAuthorizedRoot(
    displayName: String,
    bookmarkData: Data
  ) async throws -> HermesBridgeAuthorizedRootPayload {
    try await fileIntegration.registerAuthorizedRoot(
      displayName: displayName,
      bookmarkData: bookmarkData
    )
  }

  public func refreshAuthorizedRoot(
    rootID: HermesAuthorizedRootID,
    bookmarkData: Data,
    expectedRevision: Int?
  ) async throws -> HermesBridgeAuthorizedRootPayload {
    try await fileIntegration.refreshAuthorizedRoot(
      rootID: rootID,
      bookmarkData: bookmarkData,
      expectedRevision: expectedRevision
    )
  }

  public func deactivateAuthorizedRoot(
    rootID: HermesAuthorizedRootID,
    expectedRevision: Int?
  ) async throws -> HermesBridgeAuthorizedRootPayload {
    try await fileIntegration.deactivateAuthorizedRoot(
      rootID: rootID,
      expectedRevision: expectedRevision
    )
  }

  public func reactivateAuthorizedRoot(
    rootID: HermesAuthorizedRootID,
    bookmarkData: Data,
    expectedRevision: Int?
  ) async throws -> HermesBridgeAuthorizedRootPayload {
    try await fileIntegration.reactivateAuthorizedRoot(
      rootID: rootID,
      bookmarkData: bookmarkData,
      expectedRevision: expectedRevision
    )
  }

  public func removeAuthorizedRoot(
    rootID: HermesAuthorizedRootID,
    expectedRevision: Int?
  ) async throws -> HermesBridgeAuthorizedRootPayload {
    try await fileIntegration.removeAuthorizedRoot(
      rootID: rootID,
      expectedRevision: expectedRevision
    )
  }

  public func authorizedRootStatus(rootID: HermesAuthorizedRootID) async throws
    -> HermesBridgeAuthorizedRootStatusPayload
  {
    try await fileIntegration.authorizedRootStatus(rootID: rootID)
  }

  public func createFileEventSubscription(rootIDs: [HermesAuthorizedRootID]) async throws
    -> HermesBridgeFileEventSubscriptionPayload
  {
    try await fileIntegration.createFileEventSubscription(rootIDs: rootIDs)
  }

  public func pollFileEventSubscription(
    subscriptionID: HermesBridgeFileEventSubscriptionID,
    timeoutMilliseconds: Int
  ) async throws -> HermesBridgeFileEventBatchPayload {
    try await fileIntegration.pollFileEventSubscription(
      subscriptionID: subscriptionID,
      timeoutMilliseconds: timeoutMilliseconds
    )
  }

  public func acknowledgeFileEventBatch(
    subscriptionID: HermesBridgeFileEventSubscriptionID,
    acknowledgedEventID: UInt64
  ) async throws -> HermesBridgeAcknowledgementPayload {
    try await fileIntegration.acknowledgeFileEventBatch(
      subscriptionID: subscriptionID,
      acknowledgedEventID: acknowledgedEventID
    )
  }

  public func cancelFileEventSubscription(
    subscriptionID: HermesBridgeFileEventSubscriptionID
  ) async throws -> HermesBridgeFileEventSubscriptionPayload {
    try await fileIntegration.cancelFileEventSubscription(subscriptionID: subscriptionID)
  }

  public func fileEventMonitorStatus() async throws -> HermesBridgeFileEventMonitorStatusPayload {
    try await fileIntegration.fileEventMonitorStatus()
  }

  public func createSystemEventSubscription(kinds: [HermesSystemEventKind]) async throws
    -> HermesBridgeSystemEventSubscriptionPayload
  {
    try await systemEventIntegration.createSubscription(kinds: kinds)
  }

  public func pollSystemEventSubscription(
    subscriptionID: HermesSystemEventSubscriptionID,
    timeoutMilliseconds: Int
  ) async throws -> HermesBridgeSystemEventBatchPayload {
    try await systemEventIntegration.pollSubscription(
      subscriptionID: subscriptionID,
      timeoutMilliseconds: timeoutMilliseconds
    )
  }

  public func acknowledgeSystemEventBatch(
    subscriptionID: HermesSystemEventSubscriptionID,
    acknowledgedEventOrdinal: UInt64
  ) async throws -> HermesBridgeAcknowledgementPayload {
    try await systemEventIntegration.acknowledgeBatch(
      subscriptionID: subscriptionID,
      acknowledgedEventOrdinal: acknowledgedEventOrdinal
    )
  }

  public func cancelSystemEventSubscription(
    subscriptionID: HermesSystemEventSubscriptionID
  ) async throws -> HermesBridgeSystemEventSubscriptionPayload {
    try await systemEventIntegration.cancelSubscription(subscriptionID: subscriptionID)
  }

  public func systemEventMonitorStatus() async throws -> HermesBridgeSystemEventMonitorStatusPayload
  {
    try await systemEventIntegration.monitorStatus()
  }

  public func listEventPolicies() async throws -> HermesBridgeEventPolicyListPayload {
    HermesBridgeEventPolicyListPayload(policies: try await eventPolicyEngine.listPolicies())
  }

  public func createEventPolicy(_ policy: HermesEventPolicy) async throws
    -> HermesBridgeEventPolicyPayload
  {
    HermesBridgeEventPolicyPayload(policy: try await eventPolicyEngine.createPolicy(policy))
  }

  public func updateEventPolicy(_ policy: HermesEventPolicy, expectedRevision: Int) async throws
    -> HermesBridgeEventPolicyPayload
  {
    HermesBridgeEventPolicyPayload(
      policy: try await eventPolicyEngine.updatePolicy(
        policy,
        expectedRevision: expectedRevision
      ),
      expectedRevision: nil
    )
  }

  public func enableEventPolicy(
    id: HermesEventPolicyID,
    expectedRevision: Int?
  ) async throws -> HermesBridgeEventPolicyPayload {
    HermesBridgeEventPolicyPayload(
      policy: try await eventPolicyEngine.enablePolicy(
        id: id,
        expectedRevision: expectedRevision
      ))
  }

  public func disableEventPolicy(
    id: HermesEventPolicyID,
    expectedRevision: Int?
  ) async throws -> HermesBridgeEventPolicyPayload {
    HermesBridgeEventPolicyPayload(
      policy: try await eventPolicyEngine.disablePolicy(
        id: id,
        expectedRevision: expectedRevision
      ))
  }

  public func removeEventPolicy(
    id: HermesEventPolicyID,
    expectedRevision: Int?
  ) async throws -> HermesBridgeEventPolicyIDPayload {
    try await eventPolicyEngine.removePolicy(id: id, expectedRevision: expectedRevision)
    return HermesBridgeEventPolicyIDPayload(policyID: id, expectedRevision: nil)
  }

  public func evaluateEventPolicyDryRun(event: HermesSystemEvent) async throws
    -> HermesBridgeEventPolicyEvaluationResultPayload
  {
    HermesBridgeEventPolicyEvaluationResultPayload(
      evaluations: await eventPolicyEngine.evaluate(event, dryRun: true))
  }

  public func eventPolicyEngineStatus() async throws -> HermesBridgeEventPolicyEngineStatusPayload {
    HermesBridgeEventPolicyEngineStatusPayload(status: try await eventPolicyEngine.status())
  }

  public func pauseEventPolicies() async throws -> HermesBridgeEventPolicyEngineStatusPayload {
    HermesBridgeEventPolicyEngineStatusPayload(status: try await eventPolicyEngine.pause())
  }

  public func resumeEventPolicies() async throws -> HermesBridgeEventPolicyEngineStatusPayload {
    HermesBridgeEventPolicyEngineStatusPayload(status: try await eventPolicyEngine.resume())
  }

  public func listEventPolicyApprovals() async throws -> HermesBridgeEventPolicyApprovalListPayload
  {
    try HermesBridgeEventPolicyApprovalListPayload(
      approvals: try await eventPolicyEngine.listApprovals())
  }

  public func eventPolicyApprovalStatus(id: HermesEventPolicyApprovalID) async throws
    -> HermesBridgeEventPolicyApprovalPayload
  {
    HermesBridgeEventPolicyApprovalPayload(
      approval: try await eventPolicyEngine.approvalStatus(id: id))
  }

  public func approveEventPolicyExecution(id: HermesEventPolicyApprovalID) async throws
    -> HermesBridgeEventPolicyApprovalPayload
  {
    HermesBridgeEventPolicyApprovalPayload(
      approval: try await eventPolicyEngine.approveApproval(id: id))
  }

  public func denyEventPolicyExecution(id: HermesEventPolicyApprovalID) async throws
    -> HermesBridgeEventPolicyApprovalPayload
  {
    HermesBridgeEventPolicyApprovalPayload(
      approval: try await eventPolicyEngine.denyApproval(id: id))
  }

  public func cancelEventPolicyApproval(id: HermesEventPolicyApprovalID) async throws
    -> HermesBridgeEventPolicyApprovalPayload
  {
    HermesBridgeEventPolicyApprovalPayload(
      approval: try await eventPolicyEngine.cancelApproval(id: id))
  }

  public func eventPolicyApprovalQueueStatus() async throws
    -> HermesBridgeEventPolicyApprovalQueueStatusPayload
  {
    HermesBridgeEventPolicyApprovalQueueStatusPayload(
      status: try await eventPolicyEngine.approvalQueueStatus())
  }

  public func executeRuntimeCommand(_ command: HermesRuntimeCommand) async throws
    -> HermesRuntimeCommandResult
  {
    try await runtimeCommandAPI.execute(command)
  }

  public func discoverAgent() async throws -> HermesBridgeAgentDiscoveryPayload {
    do {
      let result = try agentDiscovery.discover(at: agentExecutableURL)
      let compatibility = Self.agentCompatibility(for: result.versionInfo.semanticVersion)
      return HermesBridgeAgentDiscoveryPayload(
        status: compatibility == .compatible ? .available : .incompatible,
        semanticVersion: result.versionInfo.semanticVersion,
        compatibility: compatibility
      )
    } catch let error as HermesDiscoveryError {
      switch error {
      case .executableNotFound:
        return HermesBridgeAgentDiscoveryPayload(status: .unavailable)
      case .malformedVersionOutput, .versionCommandFailed:
        return HermesBridgeAgentDiscoveryPayload(status: .incompatible, compatibility: .incompatible)
      case .pathNotAllowlisted, .executableNotRunnable, .timeout:
        return HermesBridgeAgentDiscoveryPayload(status: .unknown)
      }
    } catch {
      return HermesBridgeAgentDiscoveryPayload(status: .unknown)
    }
  }

  public func createRuntimeEventSubscription() async throws -> HermesBridgeRuntimeEventSubscriptionPayload {
    try await runtimeEvents.createSubscription()
  }

  public func pollRuntimeEventSubscription(
    subscriptionID: UUID,
    timeoutMilliseconds: Int
  ) async throws -> HermesBridgeRuntimeEventBatchPayload {
    try await runtimeEvents.pollSubscription(
      subscriptionID: subscriptionID,
      timeoutMilliseconds: timeoutMilliseconds
    )
  }

  public func cancelRuntimeEventSubscription(subscriptionID: UUID) async throws
    -> HermesBridgeRuntimeEventSubscriptionPayload
  {
    try await runtimeEvents.cancelSubscription(subscriptionID: subscriptionID)
  }

  public func submit(bindingID: HermesRequestBindingID, prompt: String) async throws
    -> HermesRequestID
  {
    try await orchestrator.submit(bindingID: bindingID, prompt: prompt)
  }

  public func status(requestID: HermesRequestID) async throws -> HermesRequestRecord {
    try await orchestrator.status(requestID: requestID)
  }

  public func cancel(requestID: HermesRequestID) async throws -> HermesRequestRecord {
    try await orchestrator.cancel(requestID: requestID)
  }

  public func respondToApproval(
    requestID: HermesRequestID,
    decision: HermesApprovalResponseDecision
  ) async throws -> HermesRequestRecord {
    try await orchestrator.respondToApproval(requestID: requestID, decision: decision)
  }

  private static func agentCompatibility(
    for semanticVersion: String
  ) -> HermesBridgeAgentCompatibilityState {
    guard let majorText = semanticVersion.split(separator: ".").first,
      let major = Int(majorText)
    else {
      return .unknown
    }
    return major == 0 ? .compatible : .incompatible
  }
}

private actor HermesBridgeRuntimeEventSubscriptionCoordinator {
  private struct Subscription {
    let task: Task<Void, Never>
    var buffer: [HermesRuntimeCommandEvent]
  }

  private let commandAPI: HermesRuntimeCommandAPI
  private var subscriptions: [UUID: Subscription] = [:]

  init(commandAPI: HermesRuntimeCommandAPI) {
    self.commandAPI = commandAPI
  }

  func createSubscription() async throws -> HermesBridgeRuntimeEventSubscriptionPayload {
    let result = try await commandAPI.execute(.subscribeEvents)
    guard case .eventSubscription(let source) = result else {
      throw HermesBridgeXPCError.internalFailure
    }
    let id = source.id
    let task = Task { [weak self] in
      for await event in source.events {
        await self?.append(event, to: id)
      }
    }
    subscriptions[id] = Subscription(task: task, buffer: [])
    return HermesBridgeRuntimeEventSubscriptionPayload(subscriptionID: id)
  }

  func pollSubscription(
    subscriptionID: UUID,
    timeoutMilliseconds: Int
  ) async throws -> HermesBridgeRuntimeEventBatchPayload {
    guard subscriptions[subscriptionID] != nil else {
      throw HermesBridgeXPCError.subscriptionNotFound
    }
    if subscriptions[subscriptionID]?.buffer.isEmpty == true, timeoutMilliseconds > 0 {
      try? await Task.sleep(nanoseconds: UInt64(min(timeoutMilliseconds, 5_000)) * 1_000_000)
    }
    guard var subscription = subscriptions[subscriptionID] else {
      throw HermesBridgeXPCError.subscriptionNotFound
    }
    let events = Array(subscription.buffer.prefix(128))
    subscription.buffer.removeFirst(min(events.count, subscription.buffer.count))
    subscriptions[subscriptionID] = subscription
    return HermesBridgeRuntimeEventBatchPayload(subscriptionID: subscriptionID, events: events)
  }

  func cancelSubscription(subscriptionID: UUID) async throws -> HermesBridgeRuntimeEventSubscriptionPayload {
    guard let subscription = subscriptions.removeValue(forKey: subscriptionID) else {
      throw HermesBridgeXPCError.subscriptionNotFound
    }
    subscription.task.cancel()
    return HermesBridgeRuntimeEventSubscriptionPayload(subscriptionID: subscriptionID)
  }

  private func append(_ event: HermesRuntimeCommandEvent, to subscriptionID: UUID) {
    guard var subscription = subscriptions[subscriptionID] else { return }
    subscription.buffer.append(event)
    if subscription.buffer.count > 512 {
      subscription.buffer.removeFirst(subscription.buffer.count - 512)
    }
    subscriptions[subscriptionID] = subscription
  }
}

public struct HermesBridgeEventPolicyRequestSubmitter: HermesEventPolicyRequestSubmitting {
  private let orchestrator: HermesRequestOrchestrator

  public init(orchestrator: HermesRequestOrchestrator) {
    self.orchestrator = orchestrator
  }

  public func submit(bindingID: HermesRequestBindingID, prompt: String) async throws
    -> HermesRequestID
  {
    try await orchestrator.submit(bindingID: bindingID, prompt: prompt)
  }
}

public struct HermesBridgeEventPolicyServiceAdapter: HermesEventPolicyServiceManaging {
  public init() {}

  public func refreshBridgeHealth() async throws {}

  public func restartBridgeService() async throws {}
}
