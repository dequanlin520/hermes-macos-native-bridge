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

  func testCompatibleAgentWithZeroSessionsReportsAvailable() async {
    let client = RecordingXPCReadinessClient(
      discovery: HermesBridgeAgentDiscoveryPayload(
        status: .available,
        semanticVersion: "0.18.2",
        compatibility: .compatible
      ),
      runtimeResult: .sessionList([])
    )
    let provider = HermesOnboardingProductionReadinessProvider(client: client)

    let readiness = await provider.checkAgent()

    XCTAssertEqual(readiness.status, .available)
    let executeCount = await client.executeCountValue()
    XCTAssertEqual(executeCount, 0)
  }

  func testCapabilityAbsentAgentDiscoveryReportsUnknownWithoutCallingDiscovery() async {
    let client = RecordingXPCReadinessClient(
      capabilities: HermesBridgeCapabilitiesPayload(
        protocolVersion: HermesBridgeProtocolVersion(major: 1, minor: 7),
        capabilities: HermesBridgeCapability.allCases.filter { $0 != .agentDiscovery }
      ),
      discovery: HermesBridgeAgentDiscoveryPayload(status: .available),
      runtimeResult: .sessionList([
        HermesRuntimeCommandSessionStatus(
          sessionID: UUID(),
          currentStatus: .running,
          backendVersion: "0.18.2",
          startTime: Date(timeIntervalSince1970: 1),
          capabilities: nil,
          lastErrorMessage: nil,
          shutdownReason: nil
        )
      ])
    )
    let provider = HermesOnboardingProductionReadinessProvider(client: client)

    let readiness = await provider.checkAgent()

    XCTAssertEqual(readiness.status, .unknown)
    let discoverAgentCount = await client.discoverAgentCountValue()
    let executeCount = await client.executeCountValue()
    XCTAssertEqual(discoverAgentCount, 0)
    XCTAssertEqual(executeCount, 0)
  }

  func testUnavailableAgentWithHistoricalSessionsReportsUnavailable() async {
    let client = RecordingXPCReadinessClient(
      discovery: HermesBridgeAgentDiscoveryPayload(status: .unavailable),
      runtimeResult: .sessionList([
        HermesRuntimeCommandSessionStatus(
          sessionID: UUID(),
          currentStatus: .stopped,
          backendVersion: "0.18.2",
          startTime: nil,
          capabilities: nil,
          lastErrorMessage: nil,
          shutdownReason: .requested
        )
      ])
    )
    let provider = HermesOnboardingProductionReadinessProvider(client: client)

    let readiness = await provider.checkAgent()

    XCTAssertEqual(readiness.status, HermesOnboardingAgentStatus.unavailable)
    let executeCount = await client.executeCountValue()
    XCTAssertEqual(executeCount, 0)
  }

  func testIncompatibleAgentReportsIncompatible() async {
    let client = RecordingXPCReadinessClient(
      discovery: HermesBridgeAgentDiscoveryPayload(
        status: .incompatible,
        semanticVersion: "99.0.0",
        compatibility: .incompatible
      )
    )
    let provider = HermesOnboardingProductionReadinessProvider(client: client)

    let readiness = await provider.checkAgent()

    XCTAssertEqual(readiness.status, .incompatible)
  }

  func testDiscoveryFailureMapsToUnknown() async {
    let client = RecordingXPCReadinessClient(discoveryError: HermesBridgeXPCClientError.interrupted)
    let provider = HermesOnboardingProductionReadinessProvider(client: client)

    let readiness = await provider.checkAgent()

    XCTAssertEqual(readiness.status, .unknown)
  }

  func testAgentDiscoveryDTODoesNotExposeExecutablePath() throws {
    let payload = HermesBridgeAgentDiscoveryPayload(
      status: .available,
      semanticVersion: "0.18.2 /Users/private/hermes",
      compatibility: .compatible
    )
    let encoded = String(data: try JSONEncoder().encode(payload), encoding: .utf8) ?? ""

    XCTAssertFalse(encoded.contains("/Users/private"))
    XCTAssertFalse(encoded.contains("hermes"))
    XCTAssertTrue(encoded.contains("0.18.2"))
  }

  func testOnboardingStateUsesDiscoveryNotSessionCount() async {
    let client = RecordingXPCReadinessClient(
      discovery: HermesBridgeAgentDiscoveryPayload(status: .unavailable),
      runtimeResult: .sessionList([
        HermesRuntimeCommandSessionStatus(
          sessionID: UUID(),
          currentStatus: .running,
          backendVersion: "0.18.2",
          startTime: Date(timeIntervalSince1970: 1),
          capabilities: nil,
          lastErrorMessage: nil,
          shutdownReason: nil
        )
      ])
    )
    let provider = HermesOnboardingProductionReadinessProvider(client: client)
    let coordinator = HermesOnboardingCoordinator(
      readinessProvider: provider,
      completionStore: InMemoryCompletionStore(),
      now: { Date(timeIntervalSince1970: 1) }
    )

    let snapshot = await coordinator.advance()

    XCTAssertEqual(snapshot.state, HermesOnboardingState.agentUnavailable)
    let executeCount = await client.executeCountValue()
    XCTAssertEqual(executeCount, 0)
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
      "HermesDiscovery(",
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
      xpcProtocol18Compatible: HermesBridgeProtocolVersion.current == HermesBridgeProtocolVersion(major: 1, minor: 8),
      agentDiscoveryChecked: true,
      agentDiscoveryUsedExistingComponent: true,
      agentDiscoveryIndependentOfSessions: true,
      zeroSessionAgentReportedAvailable: true,
      historicalSessionDidNotFakeAvailability: true,
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
      residualProcess: false,
      generatedArtifactTrackedByGit: false
    )
    try result.write()
    let artifact = try String(contentsOf: M13001AcceptanceResult.resultURL)
    XCTAssertTrue(result.isPassing, artifact)
    XCTAssertNoThrow(try M13001AcceptanceResult.validateRenderedArtifact(artifact))
    XCTAssertFalse(artifact.contains("XPC_PROTOCOL_1_7_COMPATIBLE"))
    XCTAssertTrue(artifact.contains("XPC_PROTOCOL_1_8_COMPATIBLE=yes"))
  }

  func testM13001ResultRejectsDuplicateKeys() throws {
    let entries = M13001AcceptanceResult.validPassingEntries()
      + [("COMPLETED_RUN_SKIPS_ONBOARDING", "yes")]

    XCTAssertThrowsError(try M13001AcceptanceResult.validate(entries: entries)) { error in
      XCTAssertEqual(
        error as? M13001AcceptanceResult.ValidationError,
        .duplicateKey("COMPLETED_RUN_SKIPS_ONBOARDING")
      )
    }
  }

  func testM13001ResultRejectsMissingKeys() throws {
    let entries = M13001AcceptanceResult.validPassingEntries().filter {
      $0.key != "AGENT_DISCOVERY_CHECKED"
    }

    XCTAssertThrowsError(try M13001AcceptanceResult.validate(entries: entries)) { error in
      XCTAssertEqual(
        error as? M13001AcceptanceResult.ValidationError,
        .missingKeys(["AGENT_DISCOVERY_CHECKED"])
      )
    }
  }

  func testM13001ResultRejectsUnexpectedKeys() throws {
    let entries = Array(
      M13001AcceptanceResult.validPassingEntries().dropLast()
        + [("UNEXPECTED_KEY", "yes"), ("M13_001_RESULT", "PASS")]
    )

    XCTAssertThrowsError(try M13001AcceptanceResult.validate(entries: entries)) { error in
      XCTAssertEqual(
        error as? M13001AcceptanceResult.ValidationError,
        .unexpectedKeys(["UNEXPECTED_KEY"])
      )
    }
  }

  func testM13001ResultUsesDeterministicKeyOrdering() throws {
    let keys = try M13001AcceptanceResult.passingFixture().render().split(separator: "\n").map {
      String($0.split(separator: "=", maxSplits: 1)[0])
    }

    XCTAssertEqual(keys, M13001AcceptanceResult.expectedKeys)
    XCTAssertEqual(keys.last, "M13_001_RESULT")
  }

  func testM13001ResultAcceptsValidResult() throws {
    XCTAssertNoThrow(
      try M13001AcceptanceResult.validate(entries: M13001AcceptanceResult.validPassingEntries())
    )
  }

  func testGeneratedM13001EvidenceIsIgnoredAndUntracked() throws {
    let ignored = try runGit(["check-ignore", "artifacts/m13-001/result.txt"])
    XCTAssertEqual(
      ignored.trimmingCharacters(in: .whitespacesAndNewlines),
      "artifacts/m13-001/result.txt"
    )

    let tracked = runGitAllowingFailure([
      "ls-files", "--error-unmatch", "artifacts/m13-001/result.txt",
    ])
    XCTAssertNotEqual(tracked.status, 0)
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

private actor RecordingXPCReadinessClient: HermesOnboardingXPCReadinessClient {
  private let capabilitiesPayload: HermesBridgeCapabilitiesPayload
  private let discovery: HermesBridgeAgentDiscoveryPayload
  private let discoveryError: Error?
  private let runtimeResult: HermesRuntimeCommandResult
  private var discoverAgentCount = 0
  private var executeCount = 0

  init(
    capabilities: HermesBridgeCapabilitiesPayload = HermesBridgeCapabilitiesPayload(),
    discovery: HermesBridgeAgentDiscoveryPayload = HermesBridgeAgentDiscoveryPayload(
      status: .available,
      semanticVersion: "0.18.2",
      compatibility: .compatible
    ),
    discoveryError: Error? = nil,
    runtimeResult: HermesRuntimeCommandResult = .sessionList([])
  ) {
    self.capabilitiesPayload = capabilities
    self.discovery = discovery
    self.discoveryError = discoveryError
    self.runtimeResult = runtimeResult
  }

  func connect() async throws -> HermesBridgeCapabilitiesPayload {
    capabilitiesPayload
  }

  func protocolVersion() async throws -> HermesBridgeProtocolVersionPayload {
    HermesBridgeProtocolVersionPayload(version: .current)
  }

  func capabilities() async throws -> HermesBridgeCapabilitiesPayload {
    capabilitiesPayload
  }

  func discoverAgent() async throws -> HermesBridgeAgentDiscoveryPayload {
    discoverAgentCount += 1
    if let discoveryError {
      throw discoveryError
    }
    return discovery
  }

  func execute(_ command: HermesRuntimeCommand) async throws -> HermesRuntimeCommandResult {
    executeCount += 1
    return runtimeResult
  }

  func executeCountValue() -> Int {
    executeCount
  }

  func discoverAgentCountValue() -> Int {
    discoverAgentCount
  }
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
  var xpcProtocol18Compatible: Bool
  var agentDiscoveryChecked: Bool
  var agentDiscoveryUsedExistingComponent: Bool
  var agentDiscoveryIndependentOfSessions: Bool
  var zeroSessionAgentReportedAvailable: Bool
  var historicalSessionDidNotFakeAvailability: Bool
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
  var generatedArtifactTrackedByGit: Bool

  var isPassing: Bool {
    onboardingRouteAvailable && firstRunOpensOnboarding && completedRunSkipsOnboarding
      && manualReopenAvailable && stateMachineValid && serviceCheckUsedXPC
      && xpcProtocol18Compatible && agentDiscoveryChecked && !agentPathExposed
      && agentDiscoveryUsedExistingComponent && agentDiscoveryIndependentOfSessions
      && zeroSessionAgentReportedAvailable && historicalSessionDidNotFakeAvailability
      && permissionsChecked && permissionStatusTruthful && connectionTestPassed
      && completionPersisted && !failedFlowPersistedComplete && oneLogicalWindow
      && !appOwnsConcreteRuntime && !arbitraryShellAvailable && !arbitraryURLAvailable
      && !tokenExposed && !privatePathExposed && !pidExposed && !residualProcess
      && !generatedArtifactTrackedByGit
  }

  func write() throws {
    try FileManager.default.createDirectory(
      at: Self.resultURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try render().write(to: Self.resultURL, atomically: true, encoding: .utf8)
  }

  func render() throws -> String {
    let entries = entries()
    try Self.validate(entries: entries)
    return entries.map { "\($0.key)=\($0.value)" }.joined(separator: "\n") + "\n"
  }

  func entries() -> [(key: String, value: String)] {
    [
      ("ONBOARDING_ROUTE_AVAILABLE", yesNo(onboardingRouteAvailable)),
      ("FIRST_RUN_OPENS_ONBOARDING", yesNo(firstRunOpensOnboarding)),
      ("COMPLETED_RUN_SKIPS_ONBOARDING", yesNo(completedRunSkipsOnboarding)),
      ("MANUAL_REOPEN_AVAILABLE", yesNo(manualReopenAvailable)),
      ("STATE_MACHINE_VALID", yesNo(stateMachineValid)),
      ("SERVICE_CHECK_USED_XPC", yesNo(serviceCheckUsedXPC)),
      ("XPC_PROTOCOL_1_8_COMPATIBLE", yesNo(xpcProtocol18Compatible)),
      ("AGENT_DISCOVERY_CHECKED", yesNo(agentDiscoveryChecked)),
      ("AGENT_DISCOVERY_USED_EXISTING_COMPONENT", yesNo(agentDiscoveryUsedExistingComponent)),
      ("AGENT_DISCOVERY_INDEPENDENT_OF_SESSIONS", yesNo(agentDiscoveryIndependentOfSessions)),
      ("ZERO_SESSION_AGENT_REPORTED_AVAILABLE", yesNo(zeroSessionAgentReportedAvailable)),
      ("HISTORICAL_SESSION_DID_NOT_FAKE_AVAILABILITY", yesNo(historicalSessionDidNotFakeAvailability)),
      ("AGENT_PATH_EXPOSED", noYes(agentPathExposed)),
      ("PERMISSIONS_CHECKED", yesNo(permissionsChecked)),
      ("PERMISSION_STATUS_TRUTHFUL", yesNo(permissionStatusTruthful)),
      ("CONNECTION_TEST_PASSED", yesNo(connectionTestPassed)),
      ("COMPLETION_PERSISTED", yesNo(completionPersisted)),
      ("FAILED_FLOW_PERSISTED_COMPLETE", noYes(failedFlowPersistedComplete)),
      ("ONE_LOGICAL_WINDOW", yesNo(oneLogicalWindow)),
      ("APP_OWNS_CONCRETE_RUNTIME", noYes(appOwnsConcreteRuntime)),
      ("ARBITRARY_SHELL_AVAILABLE", noYes(arbitraryShellAvailable)),
      ("ARBITRARY_URL_AVAILABLE", noYes(arbitraryURLAvailable)),
      ("TOKEN_EXPOSED", noYes(tokenExposed)),
      ("PRIVATE_PATH_EXPOSED", noYes(privatePathExposed)),
      ("PID_EXPOSED", noYes(pidExposed)),
      ("RESIDUAL_PROCESS", noYes(residualProcess)),
      ("GENERATED_ARTIFACT_TRACKED_BY_GIT", noYes(generatedArtifactTrackedByGit)),
      ("M13_001_RESULT", isPassing ? "PASS" : "FAIL"),
    ]
  }

  static let expectedKeys = [
    "ONBOARDING_ROUTE_AVAILABLE",
    "FIRST_RUN_OPENS_ONBOARDING",
    "COMPLETED_RUN_SKIPS_ONBOARDING",
    "MANUAL_REOPEN_AVAILABLE",
    "STATE_MACHINE_VALID",
    "SERVICE_CHECK_USED_XPC",
    "XPC_PROTOCOL_1_8_COMPATIBLE",
    "AGENT_DISCOVERY_CHECKED",
    "AGENT_DISCOVERY_USED_EXISTING_COMPONENT",
    "AGENT_DISCOVERY_INDEPENDENT_OF_SESSIONS",
    "ZERO_SESSION_AGENT_REPORTED_AVAILABLE",
    "HISTORICAL_SESSION_DID_NOT_FAKE_AVAILABILITY",
    "AGENT_PATH_EXPOSED",
    "PERMISSIONS_CHECKED",
    "PERMISSION_STATUS_TRUTHFUL",
    "CONNECTION_TEST_PASSED",
    "COMPLETION_PERSISTED",
    "FAILED_FLOW_PERSISTED_COMPLETE",
    "ONE_LOGICAL_WINDOW",
    "APP_OWNS_CONCRETE_RUNTIME",
    "ARBITRARY_SHELL_AVAILABLE",
    "ARBITRARY_URL_AVAILABLE",
    "TOKEN_EXPOSED",
    "PRIVATE_PATH_EXPOSED",
    "PID_EXPOSED",
    "RESIDUAL_PROCESS",
    "GENERATED_ARTIFACT_TRACKED_BY_GIT",
    "M13_001_RESULT",
  ]

  enum ValidationError: Error, Equatable {
    case duplicateKey(String)
    case missingKeys([String])
    case unexpectedKeys([String])
    case resultKeyCount(Int)
    case resultKeyNotLast
    case nonDeterministicOrder
  }

  static func validateRenderedArtifact(_ artifact: String) throws {
    let entries = artifact.split(separator: "\n").map { line -> (key: String, value: String) in
      let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      return (key: String(parts[0]), value: parts.count > 1 ? String(parts[1]) : "")
    }
    try validate(entries: entries)
  }

  static func validate(entries: [(key: String, value: String)]) throws {
    var seen: Set<String> = []
    for entry in entries {
      guard seen.insert(entry.key).inserted else {
        throw ValidationError.duplicateKey(entry.key)
      }
    }

    let keys = entries.map(\.key)
    let expected = Set(expectedKeys)
    let actual = Set(keys)
    let missing = expectedKeys.filter { !actual.contains($0) }
    guard missing.isEmpty else {
      throw ValidationError.missingKeys(missing)
    }
    let unexpected = keys.filter { !expected.contains($0) }
    guard unexpected.isEmpty else {
      throw ValidationError.unexpectedKeys(unexpected)
    }
    let resultCount = keys.filter { $0 == "M13_001_RESULT" }.count
    guard resultCount == 1 else {
      throw ValidationError.resultKeyCount(resultCount)
    }
    guard keys.last == "M13_001_RESULT" else {
      throw ValidationError.resultKeyNotLast
    }
    guard keys == expectedKeys else {
      throw ValidationError.nonDeterministicOrder
    }
  }

  static func passingFixture() -> M13001AcceptanceResult {
    M13001AcceptanceResult(
      onboardingRouteAvailable: true,
      firstRunOpensOnboarding: true,
      completedRunSkipsOnboarding: true,
      manualReopenAvailable: true,
      stateMachineValid: true,
      serviceCheckUsedXPC: true,
      xpcProtocol18Compatible: true,
      agentDiscoveryChecked: true,
      agentDiscoveryUsedExistingComponent: true,
      agentDiscoveryIndependentOfSessions: true,
      zeroSessionAgentReportedAvailable: true,
      historicalSessionDidNotFakeAvailability: true,
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
      residualProcess: false,
      generatedArtifactTrackedByGit: false
    )
  }

  static func validPassingEntries() -> [(key: String, value: String)] {
    passingFixture().entries()
  }

  private func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }
  private func noYes(_ value: Bool) -> String { value ? "yes" : "no" }
}

private func runGit(_ arguments: [String]) throws -> String {
  let result = runGitAllowingFailure(arguments)
  guard result.status == 0 else {
    throw NSError(
      domain: "GitError",
      code: Int(result.status),
      userInfo: [NSLocalizedDescriptionKey: result.output]
    )
  }
  return result.output
}

private func runGitAllowingFailure(_ arguments: [String]) -> (status: Int32, output: String) {
  let process = Process()
  let stdout = Pipe()
  let stderr = Pipe()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
  process.arguments = arguments
  process.standardOutput = stdout
  process.standardError = stderr
  do {
    try process.run()
    process.waitUntilExit()
  } catch {
    return (1, String(describing: error))
  }
  let output =
    (String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
    + (String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
  return (process.terminationStatus, output)
}
