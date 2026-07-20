import Foundation
import HermesBridgeXPC
import HermesRuntimeFoundation

public enum HermesBridgeCompositionRootError: Error, Equatable, Sendable {
  case missingExecutableCandidate
  case invalidExecutableCandidate
  case processConfigurationFailed(String)
  case stateStoreFailed(String)
  case bindingRegistryFailed(String)
  case authorizedRootRegistryFailed(String)
  case eventPolicyStoreFailed(String)
}

public final class HermesBridgeCompositionRoot: @unchecked Sendable {
  public let configuration: HermesBridgeServiceConfiguration
  public let paths: HermesBridgeServicePaths
  public let discovery: HermesDiscovery
  public let supervisor: HermesProcessSupervisor
  public let protocolFactory: HermesProtocolClientFactory
  public let stateStore: FileBackedHermesRequestStateStore
  public let bindingRegistry: ConfigurationBackedHermesRequestBindingRegistry
  public let authorizedRootRegistry: FileBackedHermesAuthorizedRootRegistry
  public let fileIntegration: HermesBridgeFileIntegrationCoordinator
  public let systemEventIntegration: HermesBridgeSystemEventCoordinator
  public let eventPolicyStore: FileBackedHermesEventPolicyStore
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
    self.eventPolicyEngine = HermesEventPolicyEngine(
      store: eventPolicyStore,
      bindingDiscovery: bindingRegistry,
      submitter: HermesBridgeEventPolicyRequestSubmitter(orchestrator: orchestrator),
      serviceManager: HermesBridgeEventPolicyServiceAdapter(),
      auditStore: auditStore
    )
    self.requestHandler = HermesBridgeServiceRequestHandler(
      orchestrator: orchestrator,
      bindingRegistry: bindingRegistry,
      fileIntegration: fileIntegration,
      systemEventIntegration: systemEventIntegration,
      eventPolicyEngine: eventPolicyEngine
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

  public init(
    orchestrator: HermesRequestOrchestrator,
    bindingRegistry: ConfigurationBackedHermesRequestBindingRegistry,
    fileIntegration: HermesBridgeFileIntegrationCoordinator,
    systemEventIntegration: HermesBridgeSystemEventCoordinator,
    eventPolicyEngine: HermesEventPolicyEngine
  ) {
    self.orchestrator = orchestrator
    self.bindingRegistry = bindingRegistry
    self.fileIntegration = fileIntegration
    self.systemEventIntegration = systemEventIntegration
    self.eventPolicyEngine = eventPolicyEngine
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
