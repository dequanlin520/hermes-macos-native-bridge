import XCTest
import HermesBridgeApp
import HermesBridgeServiceManager
import HermesBridgeXPC
import HermesRecovery
import HermesRuntimeFoundation

final class HermesRecoveryTests: XCTestCase {
  func testIssueToActionMapping() {
    XCTAssertTrue(HermesRecoveryActionCatalog.actions(for: .xpcConnectionFailed).contains { $0.actionType == .retryConnection })
    XCTAssertTrue(HermesRecoveryActionCatalog.actions(for: .xpcConnectionFailed).contains { $0.actionType == .restartBridgeService })
    XCTAssertTrue(HermesRecoveryActionCatalog.actions(for: .protocolIncompatible).contains { $0.actionType == .showUpgradeRequired })
    XCTAssertTrue(HermesRecoveryActionCatalog.actions(for: .agentUnavailable).contains { $0.actionType == .refreshAgentDiscovery })
    XCTAssertTrue(HermesRecoveryActionCatalog.actions(for: .accessibilityPermissionMissing).contains { $0.actionType == .openSystemSettings(.accessibility) })
  }

  func testDeterministicRecoveryStateTransitions() async {
    let provider = RecordingRecoveryProvider()
    provider.reconnectResults = [true]
    let coordinator = HermesRecoveryCoordinator(provider: provider)

    let evaluated = await coordinator.evaluate(issue: .xpcConnectionFailed)
    XCTAssertEqual(evaluated.state, .actionAvailable)

    let recovered = await coordinator.perform(.retryConnection)
    XCTAssertEqual(recovered.state, .recovered)
    XCTAssertEqual(recovered.selectedAction, .retryConnection)
  }

  func testReconnectSucceedsWithoutRestart() async {
    let provider = RecordingRecoveryProvider()
    provider.reconnectResults = [true]
    let coordinator = HermesRecoveryCoordinator(provider: provider)
    await coordinator.evaluate(issue: .bridgeServiceUnavailable)

    let result = await coordinator.perform(.restartBridgeService, confirmed: true)

    XCTAssertEqual(result.state, .recovered)
    XCTAssertEqual(provider.calls, ["reconnect", "audit.restartBridgeService.recovered"])
    XCTAssertEqual(provider.restartCount, 0)
  }

  func testRestartOnlyAfterReconnectFailureWherePolicyAllows() async {
    let provider = RecordingRecoveryProvider()
    provider.reconnectResults = [false, true]
    provider.serviceStatusResult = .runningUnhealthy
    provider.restartResult = true
    let coordinator = HermesRecoveryCoordinator(provider: provider)
    await coordinator.evaluate(issue: .xpcConnectionFailed)

    let result = await coordinator.perform(.restartBridgeService, confirmed: true)

    XCTAssertEqual(result.state, .recovered)
    XCTAssertEqual(provider.calls.prefix(4), ["reconnect", "serviceStatus", "restart", "reconnect"])
  }

  func testRestartConfirmationRequired() async {
    let provider = RecordingRecoveryProvider()
    let coordinator = HermesRecoveryCoordinator(provider: provider)
    await coordinator.evaluate(issue: .xpcConnectionFailed)

    let result = await coordinator.perform(.restartBridgeService)

    XCTAssertEqual(result.state, .actionAvailable)
    XCTAssertEqual(result.message, "Typed confirmation is required before changing service state.")
    XCTAssertEqual(provider.restartCount, 0)
  }

  func testRestartForwardedExactlyOnce() async {
    let provider = RecordingRecoveryProvider()
    provider.reconnectResults = [false, true]
    provider.restartResult = true
    let coordinator = HermesRecoveryCoordinator(provider: provider)
    await coordinator.evaluate(issue: .xpcConnectionFailed)

    _ = await coordinator.perform(.restartBridgeService, confirmed: true)

    XCTAssertEqual(provider.restartCount, 1)
  }

  func testProtocolIncompatibilityProducesUpgradeRequiredActionAndNoUnsafeDowngrade() async {
    let provider = RecordingRecoveryProvider()
    provider.protocolCompatibilityResult = HermesRecoveryProtocolCompatibility(
      serviceProtocol: "2.0",
      compatible: false,
      status: "incompatible"
    )
    let coordinator = HermesRecoveryCoordinator(provider: provider)

    let snapshot = await coordinator.evaluate(issue: .protocolIncompatible)
    let result = await coordinator.perform(.showUpgradeRequired)

    XCTAssertTrue(snapshot.actions.contains { $0.actionType == .showUpgradeRequired })
    XCTAssertFalse(snapshot.actions.contains { $0.actionType.stableIdentifier.lowercased().contains("downgrade") })
    XCTAssertEqual(snapshot.clientProtocolVersion, "1.8")
    XCTAssertEqual(result.state, .stillBlocked)
  }

  func testAgentRefreshUsesDiscoverAgentAndNotSessions() async {
    let provider = RecordingRecoveryProvider()
    provider.agentPayload = HermesBridgeAgentDiscoveryPayload(status: .available, compatibility: .compatible)
    let coordinator = HermesRecoveryCoordinator(provider: provider)
    await coordinator.evaluate(issue: .agentUnavailable)

    let result = await coordinator.perform(.refreshAgentDiscovery)

    XCTAssertEqual(result.state, .recovered)
    XCTAssertEqual(provider.discoverAgentCount, 1)
    XCTAssertEqual(provider.listSessionsCount, 0)
  }

  func testMissingPermissionOpensOnlyFixedPaneAndOpeningDoesNotGrant() async {
    let provider = RecordingRecoveryProvider()
    provider.permissionStates = [.accessibility: .denied]
    let coordinator = HermesRecoveryCoordinator(provider: provider)
    await coordinator.evaluate(issue: .accessibilityPermissionMissing)

    let result = await coordinator.perform(.openSystemSettings(.accessibility))

    XCTAssertEqual(provider.openedPermissions, [.accessibility])
    XCTAssertEqual(result.state, .stillBlocked)
  }

  func testPermissionRecheckDrivesRecoveredAndStillBlockedResult() async {
    let blocked = RecordingRecoveryProvider()
    blocked.permissionStates = [.screenRecording: .denied]
    let blockedCoordinator = HermesRecoveryCoordinator(provider: blocked)
    await blockedCoordinator.evaluate(issue: .screenRecordingPermissionMissing)
    let blockedResult = await blockedCoordinator.perform(.rerunPermissionsCheck)
    XCTAssertEqual(blockedResult.state, .stillBlocked)

    let granted = RecordingRecoveryProvider()
    granted.permissionStates = [.screenRecording: .granted]
    let grantedCoordinator = HermesRecoveryCoordinator(provider: granted)
    await grantedCoordinator.evaluate(issue: .screenRecordingPermissionMissing)
    let grantedResult = await grantedCoordinator.perform(.rerunPermissionsCheck)
    XCTAssertEqual(grantedResult.state, .recovered)
  }

  @MainActor
  func testSuccessfulRecoveryRerunsReadiness() async {
    let provider = RecordingRecoveryProvider()
    provider.reconnectResults = [true]
    let coordinator = HermesRecoveryCoordinator(provider: provider)
    await coordinator.evaluate(issue: .xpcConnectionFailed)
    let viewModel = HermesRecoveryViewModel(coordinator: coordinator, rerunReadiness: {
      provider.viewModelReadinessRerunCount += 1
    })

    viewModel.perform(.retryConnection)
    await Task.yield()
    while viewModel.isWorking { await Task.yield() }

    XCTAssertEqual(provider.viewModelReadinessRerunCount, 1)
  }

  func testFailedRecoveryRemainsIncomplete() async {
    let provider = RecordingRecoveryProvider()
    provider.reconnectResults = [false]
    let coordinator = HermesRecoveryCoordinator(provider: provider)
    await coordinator.evaluate(issue: .xpcConnectionFailed)

    let result = await coordinator.perform(.retryConnection)
    XCTAssertEqual(result.state, .stillBlocked)
  }

  @MainActor
  func testOneLogicalRecoveryWindow() {
    let graph = HermesAppClientGraph(
      runtimeClient: AppRuntimeClientStub(),
      recoveryCoordinator: HermesRecoveryCoordinator(provider: RecordingRecoveryProvider())
    )
    let coordinator = HermesWindowCoordinator(
      clientGraph: graph,
      windowFactory: RecordingWindowFactory()
    )

    coordinator.open(.recovery)
    coordinator.open(.recovery)

    XCTAssertEqual(coordinator.windowCount(for: .recovery), 1)
  }

  func testAppOwnsNoConcreteRuntimeOrDiscovery() throws {
    let appSource = try String(contentsOfFile: "Sources/HermesBridgeApp/HermesAppCompositionRoot.swift")
    XCTAssertFalse(appSource.contains("HermesRuntimeSessionManager("))
    XCTAssertFalse(appSource.contains("HermesRuntimeEventBus("))
    XCTAssertFalse(appSource.contains("HermesRuntimeCommandAPI("))
    XCTAssertFalse(appSource.contains("HermesProcessSupervisor("))
    XCTAssertFalse(appSource.contains("HermesBackendAdapter("))
    XCTAssertFalse(appSource.contains("HermesProtocolClient("))
    XCTAssertFalse(appSource.contains("HermesDiscovery("))
  }

  func testAuditEventRedaction() async {
    let store = RecordingAuditStore()
    let recorder = HermesRecoveryAuditStoreRecorder(store: store)

    await recorder.recordRecovery(
      action: .restartBridgeService,
      target: .xpcConnectionFailed,
      result: .recovered,
      timestamp: Date(timeIntervalSince1970: 10)
    )

    XCTAssertEqual(store.events.count, 1)
    let encoded = String(data: try! JSONEncoder().encode(store.events[0]), encoding: .utf8)!
    XCTAssertFalse(encoded.contains("/Users/"))
    XCTAssertFalse(encoded.localizedCaseInsensitiveContains("token"))
    XCTAssertFalse(encoded.localizedCaseInsensitiveContains("pid"))
  }

  func testArbitraryCommandURLPathAndPIDCannotBeRepresented() {
    for action in HermesRecoveryActionCatalog.actions(for: .xpcConnectionFailed) {
      XCTAssertFalse(action.actionType.stableIdentifier.contains("/"))
      XCTAssertFalse(action.actionType.stableIdentifier.contains("://"))
      XCTAssertFalse(action.actionType.stableIdentifier.localizedCaseInsensitiveContains("pid"))
      XCTAssertFalse(action.actionType.stableIdentifier.localizedCaseInsensitiveContains("shell"))
    }
  }
}

private final class RecordingRecoveryProvider: HermesRecoveryProviding, @unchecked Sendable {
  var calls: [String] = []
  var reconnectResults: [Bool] = []
  var serviceStatusResult: HermesBridgeServiceStatus = .runningUnhealthy
  var restartResult = false
  var restartCount = 0
  var discoverAgentCount = 0
  var listSessionsCount = 0
  var openedPermissions: [HermesRecoveryPermissionPane] = []
  var permissionStates: [HermesRecoveryPermissionPane: HermesPermissionState] = [:]
  var viewModelReadinessRerunCount = 0
  var protocolCompatibilityResult = HermesRecoveryProtocolCompatibility(
    serviceProtocol: "1.8",
    compatible: true,
    status: "compatible"
  )
  var agentPayload = HermesBridgeAgentDiscoveryPayload(status: .unavailable)

  func serviceStatus() async -> HermesBridgeServiceStatus {
    calls.append("serviceStatus")
    return serviceStatusResult
  }

  func reconnect() async -> Bool {
    calls.append("reconnect")
    return reconnectResults.isEmpty ? false : reconnectResults.removeFirst()
  }

  func restartBridgeService() async -> Bool {
    calls.append("restart")
    restartCount += 1
    return restartResult
  }

  func protocolCompatibility() async -> HermesRecoveryProtocolCompatibility {
    calls.append("protocolCompatibility")
    return protocolCompatibilityResult
  }

  func discoverAgent() async -> HermesBridgeAgentDiscoveryPayload {
    calls.append("discoverAgent")
    discoverAgentCount += 1
    return agentPayload
  }

  func permissionState(for permission: HermesRecoveryPermissionPane) async -> HermesPermissionState {
    calls.append("permissionState.\(permission.rawValue)")
    return permissionStates[permission] ?? .unknown
  }

  @MainActor
  func openSystemSettings(permission: HermesRecoveryPermissionPane) {
    openedPermissions.append(permission)
  }

  func rerunReadiness() async -> Bool {
    calls.append("rerunReadiness")
    return false
  }

  func recordAudit(action: HermesRecoveryActionType, target _: HermesRecoveryIssueCategory, result: HermesRecoveryState) async {
    calls.append("audit.\(action.auditReasonCode).\(result.rawValue)")
  }
}

private final class RecordingAuditStore: HermesAuditStore, @unchecked Sendable {
  var events: [HermesAuditEvent] = []
  func append(_ event: HermesAuditEvent) async throws { events.append(event) }
  func query(_: HermesAuditQuery) async throws -> [HermesAuditEvent] { events }
}

@MainActor
private final class RecordingWindowController: HermesNativeUIWindowControlling {
  let identifier: HermesNativeUIWindowIdentifier
  var isOpen = false
  var showCount = 0
  var focusCount = 0

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

  func close() { isOpen = false }
  func cleanup() { isOpen = false }
}

private struct RecordingWindowFactory: HermesNativeUIWindowFactory {
  @MainActor
  func makeWindow(
    for identifier: HermesNativeUIWindowIdentifier,
    clientGraph _: HermesAppClientGraph
  ) -> HermesNativeUIWindowControlling {
    RecordingWindowController(identifier: identifier)
  }
}

private struct AppRuntimeClientStub: HermesAppRuntimeClienting {
  func execute(_: HermesRuntimeCommand) async throws -> HermesRuntimeCommandResult {
    .sessionList([])
  }

  func subscribeRuntimeEvents() async throws -> HermesRuntimeCommandEventSubscription {
    HermesRuntimeCommandEventSubscription(id: UUID(), events: AsyncStream { $0.finish() })
  }

  func invalidate() async {}
}
