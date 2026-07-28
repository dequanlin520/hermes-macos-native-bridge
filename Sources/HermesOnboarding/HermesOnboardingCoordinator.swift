import Foundation

public final class HermesOnboardingCoordinator: @unchecked Sendable {
  private let readinessProvider: any HermesOnboardingReadinessProviding
  private let completionStore: any HermesOnboardingCompletionPersisting
  private let now: @Sendable () -> Date

  private var snapshot: HermesOnboardingSnapshot

  public init(
    readinessProvider: any HermesOnboardingReadinessProviding,
    completionStore: any HermesOnboardingCompletionPersisting = HermesOnboardingUserDefaultsCompletionStore(),
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.readinessProvider = readinessProvider
    self.completionStore = completionStore
    self.now = now
    self.snapshot = HermesOnboardingSnapshot()
  }

  public var currentSnapshot: HermesOnboardingSnapshot {
    snapshot
  }

  public var isComplete: Bool {
    completionStore.loadCompletionRecord()?.isCompleteForCurrentSchema == true
  }

  public func shouldOpenOnFirstRun() -> Bool {
    !isComplete
  }

  public func beginManualReopen() -> HermesOnboardingSnapshot {
    snapshot = HermesOnboardingSnapshot()
    return snapshot
  }

  public func advance() async -> HermesOnboardingSnapshot {
    switch snapshot.state {
    case .welcome, .serviceUnavailable, .connectionFailed:
      return await checkService()
    case .checkingService:
      return snapshot
    case .checkingAgent, .agentUnavailable:
      return await checkAgent()
    case .checkingPermissions, .permissionsRequired:
      return await checkPermissions()
    case .testingConnection:
      return await testConnection()
    case .ready:
      return finish()
    }
  }

  public func retry() async -> HermesOnboardingSnapshot {
    switch snapshot.state {
    case .serviceUnavailable, .connectionFailed:
      return await checkService()
    case .agentUnavailable:
      return await checkAgent()
    case .permissionsRequired:
      return await checkPermissions()
    case .welcome, .checkingService, .checkingAgent, .checkingPermissions, .testingConnection,
      .ready:
      return await advance()
    }
  }

  public func finish() -> HermesOnboardingSnapshot {
    guard snapshot.state == .ready else {
      return snapshot
    }
    completionStore.saveCompletionRecord(
      HermesOnboardingCompletionRecord(completedAt: now())
    )
    return snapshot
  }

  private func checkService() async -> HermesOnboardingSnapshot {
    snapshot = HermesOnboardingSnapshot(
      state: .checkingService,
      step: .service,
      status: "Checking Bridge Service",
      explanation: "Hermes Bridge is verifying the service boundary.",
      availableActions: []
    )
    let service = await readinessProvider.checkService()
    if service.isReady {
      snapshot = HermesOnboardingSnapshot(
        state: .checkingAgent,
        step: .agent,
        status: "Bridge Service is available",
        explanation: service.safeMessage,
        availableActions: [.continue],
        service: service
      )
      return await checkAgent()
    }
    snapshot = HermesOnboardingSnapshot(
      state: .serviceUnavailable,
      step: .service,
      status: "Bridge Service unavailable",
      explanation: service.safeMessage.isEmpty
        ? "Start or reinstall Hermes Bridge Service, then retry."
        : service.safeMessage,
      availableActions: [.retry, .openDiagnostics],
      service: service
    )
    return snapshot
  }

  private func checkAgent() async -> HermesOnboardingSnapshot {
    snapshot = HermesOnboardingSnapshot(
      state: .checkingAgent,
      step: .agent,
      status: "Checking Hermes Agent",
      explanation: "Hermes Bridge is checking the service-reported agent status.",
      availableActions: [],
      service: snapshot.service
    )
    let agent = await readinessProvider.checkAgent()
    if agent.isReady {
      snapshot = HermesOnboardingSnapshot(
        state: .checkingPermissions,
        step: .permissions,
        status: "Hermes Agent is available",
        explanation: agent.safeMessage,
        availableActions: [.continue],
        service: snapshot.service,
        agent: agent
      )
      return await checkPermissions()
    }
    snapshot = HermesOnboardingSnapshot(
      state: .agentUnavailable,
      step: .agent,
      status: "Hermes Agent unavailable",
      explanation: agent.safeMessage.isEmpty
        ? "Install or repair Hermes Agent, then retry. Hermes Bridge will not download it automatically."
        : agent.safeMessage,
      availableActions: [.retry, .openDiagnostics],
      service: snapshot.service,
      agent: agent
    )
    return snapshot
  }

  private func checkPermissions() async -> HermesOnboardingSnapshot {
    snapshot = HermesOnboardingSnapshot(
      state: .checkingPermissions,
      step: .permissions,
      status: "Checking permissions",
      explanation: "Hermes Bridge is reading macOS-reported permission status.",
      availableActions: [],
      service: snapshot.service,
      agent: snapshot.agent
    )
    let permissions = await readinessProvider.checkPermissions()
    if permissions.isReady {
      snapshot = HermesOnboardingSnapshot(
        state: .testingConnection,
        step: .connection,
        status: "Permissions ready",
        explanation: "Required permission checks are not blocking onboarding.",
        availableActions: [.continue],
        service: snapshot.service,
        agent: snapshot.agent,
        permissions: permissions
      )
      return await testConnection()
    }
    let permissionActions = permissions.permissions.compactMap(\.remediation)
    snapshot = HermesOnboardingSnapshot(
      state: .permissionsRequired,
      step: .permissions,
      status: "Permissions required",
      explanation: "Grant the required macOS permissions in System Settings, then retry.",
      availableActions: Array(Set(permissionActions + [.retry, .openDiagnostics])),
      service: snapshot.service,
      agent: snapshot.agent,
      permissions: permissions
    )
    return snapshot
  }

  private func testConnection() async -> HermesOnboardingSnapshot {
    snapshot = HermesOnboardingSnapshot(
      state: .testingConnection,
      step: .connection,
      status: "Testing connection",
      explanation: "Hermes Bridge is running a non-destructive client/service probe.",
      availableActions: [],
      service: snapshot.service,
      agent: snapshot.agent,
      permissions: snapshot.permissions
    )
    let connection = await readinessProvider.testConnection()
    if connection.isReady {
      snapshot = HermesOnboardingSnapshot(
        state: .ready,
        step: .ready,
        status: "Hermes Bridge is ready",
        explanation: connection.safeMessage,
        availableActions: [.finish],
        service: snapshot.service,
        agent: snapshot.agent,
        permissions: snapshot.permissions,
        connection: connection
      )
      return snapshot
    }
    snapshot = HermesOnboardingSnapshot(
      state: .connectionFailed,
      step: .connection,
      status: "Connection test failed",
      explanation: connection.safeMessage,
      availableActions: [.retry, .openDiagnostics],
      service: snapshot.service,
      agent: snapshot.agent,
      permissions: snapshot.permissions,
      connection: connection
    )
    return snapshot
  }
}
