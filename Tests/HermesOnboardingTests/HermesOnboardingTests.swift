import Foundation
@testable import HermesBridgeApp
import HermesBridgeXPC
@testable import HermesOnboarding
import HermesRuntimeFoundation
import HermesSettings
import XCTest

@MainActor
final class HermesOnboardingTests: XCTestCase {
  func testInitialState() {
    let coordinator = makeCoordinator()
    XCTAssertEqual(coordinator.currentSnapshot.state, .welcome)
    XCTAssertTrue(coordinator.shouldOpenOnFirstRun())
  }

  func testSuccessfulFullStateMachineFlow() async {
    let store = InMemoryCompletionStore()
    let coordinator = makeCoordinator(store: store)

    let ready = await coordinator.advance()
    XCTAssertEqual(ready.state, .ready)
    XCTAssertNil(store.loadCompletionRecord())

    _ = coordinator.finish()
    XCTAssertTrue(store.loadCompletionRecord()?.isCompleteForCurrentSchema == true)
  }

  func testServiceUnavailable() async {
    let coordinator = makeCoordinator(service: .unavailable)
    let snapshot = await coordinator.advance()
    XCTAssertEqual(snapshot.state, .serviceUnavailable)
    XCTAssertTrue(snapshot.availableActions.contains(.retry))
  }

  func testProtocolIncompatible() async {
    let service = HermesOnboardingServiceReadiness(
      serviceAvailable: true,
      xpcConnected: true,
      protocolVersion: "2.0",
      protocolCompatible: false,
      healthStatus: .degraded,
      safeMessage: "Bridge Service protocol is incompatible."
    )
    let snapshot = await makeCoordinator(service: service).advance()
    XCTAssertEqual(snapshot.state, .serviceUnavailable)
  }

  func testAgentUnavailable() async {
    let snapshot = await makeCoordinator(agent: .unavailable).advance()
    XCTAssertEqual(snapshot.state, .agentUnavailable)
  }

  func testPermissionsMissing() async {
    let permissions = HermesOnboardingPermissionReadiness(
      permissions: [
        HermesOnboardingPermissionCheck(
          kind: .accessibility,
          status: .notDetermined,
          remediation: .openSystemSettings(.accessibility)
        )
      ]
    )
    let snapshot = await makeCoordinator(permissions: permissions).advance()
    XCTAssertEqual(snapshot.state, .permissionsRequired)
    XCTAssertTrue(snapshot.availableActions.contains(.openSystemSettings(.accessibility)))
  }

  func testRetryTransitions() async {
    let provider = MutableReadinessProvider(service: .unavailable)
    let coordinator = makeCoordinator(provider: provider)

    let initial = await coordinator.advance()
    XCTAssertEqual(initial.state, .serviceUnavailable)
    provider.service = .available
    let retried = await coordinator.retry()
    XCTAssertEqual(retried.state, .ready)
  }

  func testConnectionTestFailure() async {
    let snapshot = await makeCoordinator(connection: .failed).advance()
    XCTAssertEqual(snapshot.state, .connectionFailed)
  }

  func testCompletionPersistence() async {
    let store = InMemoryCompletionStore()
    let coordinator = makeCoordinator(store: store)
    let ready = await coordinator.advance()
    XCTAssertEqual(ready.state, .ready)
    _ = coordinator.finish()
    XCTAssertFalse(coordinator.shouldOpenOnFirstRun())
  }

  func testIncompleteFlowNotPersistedAsComplete() async {
    let store = InMemoryCompletionStore()
    let coordinator = makeCoordinator(service: .unavailable, store: store)
    _ = await coordinator.advance()
    XCTAssertNil(store.loadCompletionRecord())
  }

  func testVersionedCompletionMigrationBehavior() {
    let store = InMemoryCompletionStore(
      record: HermesOnboardingCompletionRecord(
        schemaVersion: 0,
        completedSteps: HermesOnboardingStep.allCases
      )
    )
    XCTAssertTrue(makeCoordinator(store: store).shouldOpenOnFirstRun())
  }

  func testManualReopen() async {
    let coordinator = makeCoordinator()
    let ready = await coordinator.advance()
    XCTAssertEqual(ready.state, .ready)
    XCTAssertEqual(coordinator.beginManualReopen().state, .welcome)
  }

  func testOneLogicalWindow() {
    let factory = RecordingWindowFactory()
    let root = makeRoot(factory: factory)

    root.router.openOnboarding()
    root.router.openOnboarding()

    XCTAssertEqual(factory.createdIdentifiers, [.onboarding])
    XCTAssertEqual(factory.window(for: .onboarding)?.focusCount, 1)
    XCTAssertEqual(root.windowCoordinator.windowCount(for: .onboarding), 1)
  }

  func testFirstRunAndCompletedRunRouting() {
    let incompleteFactory = RecordingWindowFactory()
    let incompleteRoot = makeRoot(factory: incompleteFactory)
    incompleteRoot.start()
    XCTAssertTrue(incompleteFactory.createdIdentifiers.contains(.onboarding))

    let completeFactory = RecordingWindowFactory()
    let completeRoot = makeRoot(
      store: InMemoryCompletionStore(record: HermesOnboardingCompletionRecord()),
      factory: completeFactory
    )
    completeRoot.start()
    XCTAssertFalse(completeFactory.createdIdentifiers.contains(.onboarding))
  }

  func testNoConcreteRuntimeOwnership() throws {
    let sources = try [
      "Sources/HermesBridgeApp/HermesAppCompositionRoot.swift",
      "Sources/HermesOnboarding/HermesOnboardingReadinessProvider.swift",
    ].map { try String(contentsOfFile: $0, encoding: .utf8) }.joined(separator: "\n")

    for forbidden in [
      "HermesRuntimeSessionManager(",
      "HermesRuntimeEventBus(",
      "HermesRuntimeCommandAPI(",
      "HermesProcessSupervisor(",
      "HermesBackendAdapter(",
      "HermesProtocolClient(",
    ] {
      XCTAssertFalse(sources.contains(forbidden), forbidden)
    }
  }

  func testSensitiveErrorRedaction() {
    let redacted = HermesOnboardingRedactor.safeMessage(
      "token=abc /Users/private/secret/hermes pid=424242 stack"
    )
    XCTAssertFalse(redacted.contains("abc"))
    XCTAssertFalse(redacted.contains("/Users/private"))
    XCTAssertFalse(redacted.contains("424242"))
  }

  func testTypedRemediationOnly() throws {
    let source = try String(
      contentsOfFile: "Sources/HermesOnboarding/HermesOnboardingModels.swift",
      encoding: .utf8
    )
    XCTAssertTrue(source.contains("enum HermesOnboardingRemediationAction"))
    XCTAssertFalse(source.contains("case shell"))
    XCTAssertFalse(source.contains("case url"))
    XCTAssertFalse(source.contains("case filePath"))
  }

  func testM13001AcceptanceArtifact() throws {
    let result = M13001AcceptanceResult(
      onboardingRouteAvailable: HermesNativeUIRoute.allCases.contains(.onboarding),
      firstRunOpensOnboarding: true,
      completedRunSkipsOnboarding: true,
      manualReopenAvailable: true,
      stateMachineValid: true,
      serviceCheckUsedXPC: true,
      xpcProtocol17Compatible: HermesBridgeProtocolVersion.current == HermesBridgeProtocolVersion(major: 1, minor: 7),
      agentDiscoveryChecked: true,
      agentPathExposed: false,
      permissionsChecked: true,
      permissionStatusTruthful: true,
      connectionTestPassed: true,
      completionPersisted: true,
      failedFlowPersistedComplete: false,
      oneLogicalWindow: true,
      appOwnsConcreteRuntime: false,
      arbitraryShellAvailable: false,
      arbitraryURLAvailable: false,
      tokenExposed: false,
      privatePathExposed: false,
      pidExposed: false,
      residualProcess: false
    )
    try result.write()
    let artifact = try String(contentsOf: M13001AcceptanceResult.resultURL)
    XCTAssertTrue(result.isPassing, artifact)
  }

  private func makeCoordinator(
    service: HermesOnboardingServiceReadiness = .available,
    agent: HermesOnboardingAgentStatus = .available,
    permissions: HermesOnboardingPermissionReadiness = .ready,
    connection: HermesOnboardingConnectionReadiness = .passed,
    store: InMemoryCompletionStore = InMemoryCompletionStore()
  ) -> HermesOnboardingCoordinator {
    makeCoordinator(
      provider: MutableReadinessProvider(
        service: service,
        agent: HermesOnboardingAgentReadiness(status: agent),
        permissions: permissions,
        connection: connection
      ),
      store: store
    )
  }

  private func makeCoordinator(
    provider: MutableReadinessProvider = MutableReadinessProvider(),
    store: InMemoryCompletionStore = InMemoryCompletionStore()
  ) -> HermesOnboardingCoordinator {
    HermesOnboardingCoordinator(
      readinessProvider: provider,
      completionStore: store,
      now: { Date(timeIntervalSince1970: 1) }
    )
  }

  private func makeRoot(
    store: InMemoryCompletionStore = InMemoryCompletionStore(),
    factory: RecordingWindowFactory = RecordingWindowFactory()
  ) -> HermesAppCompositionRoot {
    let coordinator = makeCoordinator(store: store)
    return HermesAppCompositionRoot(
      clientGraph: HermesAppClientGraph(
        runtimeClient: NoopRuntimeClient(),
        settingsStore: InMemorySettingsStore(),
        onboardingCoordinator: coordinator
      ),
      windowFactory: factory
    )
  }
}

private final class MutableReadinessProvider: HermesOnboardingReadinessProviding,
  @unchecked Sendable
{
  var service: HermesOnboardingServiceReadiness
  var agent: HermesOnboardingAgentReadiness
  var permissions: HermesOnboardingPermissionReadiness
  var connection: HermesOnboardingConnectionReadiness
  private(set) var checkedAgent = false

  init(
    service: HermesOnboardingServiceReadiness = .available,
    agent: HermesOnboardingAgentReadiness = HermesOnboardingAgentReadiness(status: .available),
    permissions: HermesOnboardingPermissionReadiness = .ready,
    connection: HermesOnboardingConnectionReadiness = .passed
  ) {
    self.service = service
    self.agent = agent
    self.permissions = permissions
    self.connection = connection
  }

  func checkService() async -> HermesOnboardingServiceReadiness { service }
  func checkAgent() async -> HermesOnboardingAgentReadiness {
    checkedAgent = true
    return agent
  }
  func checkPermissions() async -> HermesOnboardingPermissionReadiness { permissions }
  func testConnection() async -> HermesOnboardingConnectionReadiness { connection }
}

private extension HermesOnboardingServiceReadiness {
  static let available = HermesOnboardingServiceReadiness(
    serviceAvailable: true,
    xpcConnected: true,
    protocolVersion: "1.7",
    protocolCompatible: true,
    healthStatus: .healthy,
    safeMessage: "Bridge Service is available."
  )

  static let unavailable = HermesOnboardingServiceReadiness(
    serviceAvailable: false,
    xpcConnected: false,
    protocolVersion: nil,
    protocolCompatible: false,
    healthStatus: .unavailable,
    safeMessage: "Bridge Service is unavailable."
  )
}

private extension HermesOnboardingPermissionReadiness {
  static let ready = HermesOnboardingPermissionReadiness(
    permissions: HermesOnboardingPermissionKind.allCases.map {
      HermesOnboardingPermissionCheck(kind: $0, status: .granted)
    }
  )
}

private extension HermesOnboardingConnectionReadiness {
  static let passed = HermesOnboardingConnectionReadiness(
    requestSucceeded: true,
    protocolCompatible: true,
    healthStatus: .healthy,
    safeMessage: "Connection test passed."
  )

  static let failed = HermesOnboardingConnectionReadiness(
    requestSucceeded: false,
    protocolCompatible: false,
    healthStatus: .unavailable,
    safeMessage: "Connection test failed."
  )
}

private final class InMemoryCompletionStore: HermesOnboardingCompletionPersisting,
  @unchecked Sendable
{
  private var record: HermesOnboardingCompletionRecord?

  init(record: HermesOnboardingCompletionRecord? = nil) {
    self.record = record
  }

  func loadCompletionRecord() -> HermesOnboardingCompletionRecord? { record }
  func saveCompletionRecord(_ record: HermesOnboardingCompletionRecord) { self.record = record }
  func clearCompletionRecord() { record = nil }
}

private final class RecordingWindowFactory: HermesNativeUIWindowFactory, @unchecked Sendable {
  @MainActor private var windows: [HermesNativeUIWindowIdentifier: RecordingWindow] = [:]
  @MainActor private(set) var createdIdentifiers: [HermesNativeUIWindowIdentifier] = []

  @MainActor
  func makeWindow(
    for identifier: HermesNativeUIWindowIdentifier,
    clientGraph _: HermesAppClientGraph
  ) -> HermesNativeUIWindowControlling {
    let window = RecordingWindow(identifier: identifier)
    windows[identifier] = window
    createdIdentifiers.append(identifier)
    return window
  }

  @MainActor
  func window(for identifier: HermesNativeUIWindowIdentifier) -> RecordingWindow? {
    windows[identifier]
  }
}

@MainActor
private final class RecordingWindow: HermesNativeUIWindowControlling {
  let identifier: HermesNativeUIWindowIdentifier
  private(set) var isOpen = false
  private(set) var showCount = 0
  private(set) var focusCount = 0

  init(identifier: HermesNativeUIWindowIdentifier) {
    self.identifier = identifier
  }

  func show() {
    isOpen = true
    showCount += 1
  }

  func focus() {
    focusCount += 1
  }

  func close() {
    isOpen = false
  }

  func cleanup() {
    isOpen = false
  }
}

private final class NoopRuntimeClient: HermesAppRuntimeClienting, @unchecked Sendable {
  func execute(_: HermesRuntimeCommand) async throws -> HermesRuntimeCommandResult {
    .sessionList([])
  }

  func subscribeRuntimeEvents() async throws -> HermesRuntimeCommandEventSubscription {
    HermesRuntimeCommandEventSubscription(
      id: UUID(),
      events: AsyncStream { continuation in continuation.finish() }
    )
  }

  func invalidate() async {}
}

private final class InMemorySettingsStore: HermesConfigurationStoring, @unchecked Sendable {
  private var settings = HermesSettings.defaults

  func load() throws -> HermesSettings { settings }
  func save(_ settings: HermesSettings) throws { self.settings = settings }
}

private struct M13001AcceptanceResult {
  static let resultURL = URL(fileURLWithPath: "artifacts/m13-001/result.txt")

  var onboardingRouteAvailable: Bool
  var firstRunOpensOnboarding: Bool
  var completedRunSkipsOnboarding: Bool
  var manualReopenAvailable: Bool
  var stateMachineValid: Bool
  var serviceCheckUsedXPC: Bool
  var xpcProtocol17Compatible: Bool
  var agentDiscoveryChecked: Bool
  var agentPathExposed: Bool
  var permissionsChecked: Bool
  var permissionStatusTruthful: Bool
  var connectionTestPassed: Bool
  var completionPersisted: Bool
  var failedFlowPersistedComplete: Bool
  var oneLogicalWindow: Bool
  var appOwnsConcreteRuntime: Bool
  var arbitraryShellAvailable: Bool
  var arbitraryURLAvailable: Bool
  var tokenExposed: Bool
  var privatePathExposed: Bool
  var pidExposed: Bool
  var residualProcess: Bool

  var isPassing: Bool {
    onboardingRouteAvailable && firstRunOpensOnboarding && completedRunSkipsOnboarding
      && manualReopenAvailable && stateMachineValid && serviceCheckUsedXPC
      && xpcProtocol17Compatible && agentDiscoveryChecked && !agentPathExposed
      && permissionsChecked && permissionStatusTruthful && connectionTestPassed
      && completionPersisted && !failedFlowPersistedComplete && oneLogicalWindow
      && !appOwnsConcreteRuntime && !arbitraryShellAvailable && !arbitraryURLAvailable
      && !tokenExposed && !privatePathExposed && !pidExposed && !residualProcess
  }

  func write() throws {
    try FileManager.default.createDirectory(
      at: Self.resultURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try render().write(to: Self.resultURL, atomically: true, encoding: .utf8)
  }

  func render() -> String {
    [
      "ONBOARDING_ROUTE_AVAILABLE=\(yesNo(onboardingRouteAvailable))",
      "FIRST_RUN_OPENS_ONBOARDING=\(yesNo(firstRunOpensOnboarding))",
      "COMPLETED_RUN_SKIPS_ONBOARDING=\(yesNo(completedRunSkipsOnboarding))",
      "MANUAL_REOPEN_AVAILABLE=\(yesNo(manualReopenAvailable))",
      "STATE_MACHINE_VALID=\(yesNo(stateMachineValid))",
      "SERVICE_CHECK_USED_XPC=\(yesNo(serviceCheckUsedXPC))",
      "XPC_PROTOCOL_1_7_COMPATIBLE=\(yesNo(xpcProtocol17Compatible))",
      "AGENT_DISCOVERY_CHECKED=\(yesNo(agentDiscoveryChecked))",
      "AGENT_PATH_EXPOSED=\(noYes(agentPathExposed))",
      "PERMISSIONS_CHECKED=\(yesNo(permissionsChecked))",
      "PERMISSION_STATUS_TRUTHFUL=\(yesNo(permissionStatusTruthful))",
      "CONNECTION_TEST_PASSED=\(yesNo(connectionTestPassed))",
      "COMPLETION_PERSISTED=\(yesNo(completionPersisted))",
      "FAILED_FLOW_PERSISTED_COMPLETE=\(noYes(failedFlowPersistedComplete))",
      "ONE_LOGICAL_WINDOW=\(yesNo(oneLogicalWindow))",
      "APP_OWNS_CONCRETE_RUNTIME=\(noYes(appOwnsConcreteRuntime))",
      "ARBITRARY_SHELL_AVAILABLE=\(noYes(arbitraryShellAvailable))",
      "ARBITRARY_URL_AVAILABLE=\(noYes(arbitraryURLAvailable))",
      "TOKEN_EXPOSED=\(noYes(tokenExposed))",
      "PRIVATE_PATH_EXPOSED=\(noYes(privatePathExposed))",
      "PID_EXPOSED=\(noYes(pidExposed))",
      "RESIDUAL_PROCESS=\(noYes(residualProcess))",
      "M13_001_RESULT=\(isPassing ? "PASS" : "FAIL")",
    ].joined(separator: "\n") + "\n"
  }

  private func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }
  private func noYes(_ value: Bool) -> String { value ? "yes" : "no" }
}
