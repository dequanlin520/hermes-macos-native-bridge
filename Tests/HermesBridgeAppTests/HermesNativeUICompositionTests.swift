import Foundation
@testable import HermesBridgeApp
import HermesRuntimeFoundation
import HermesSettings
import XCTest

@MainActor
final class HermesNativeUICompositionTests: XCTestCase {
  func testAppCompositionRootOwnsNoConcreteRuntimeGraphTypes() throws {
    let source = try String(
      contentsOfFile: "Sources/HermesBridgeApp/HermesAppCompositionRoot.swift",
      encoding: .utf8
    )

    XCTAssertFalse(source.contains("HermesRuntimeSessionManager("))
    XCTAssertFalse(source.contains("HermesRuntimeEventBus("))
    XCTAssertFalse(source.contains("HermesRuntimeCommandAPI("))
    XCTAssertFalse(source.contains("HermesProcessSupervisor("))
    XCTAssertFalse(source.contains("HermesBackendAdapter("))
    XCTAssertFalse(source.contains("HermesProtocolClient("))
  }

  func testRuntimeCommandsUseClientAbstraction() async {
    let client = RecordingRuntimeClient()
    let root = makeRoot(client: client)

    root.menuBarViewModel.startHermes()
    await client.waitForCommandCount(2)

    let commands = await client.commands()
    XCTAssertEqual(commands, [.createSession, .startSession(client.sessionID)])
  }

  func testRuntimeEventsUseClientSubscriptionAbstraction() async {
    let client = RecordingRuntimeClient()
    let root = makeRoot(client: client)

    root.start()
    await client.waitForSubscriptionCount(1)

    let subscriptionCount = await client.subscriptionCount()
    XCTAssertEqual(subscriptionCount, 1)
  }

  func testDashboardRouting() {
    let factory = RecordingWindowFactory()
    let root = makeRoot(factory: factory)

    root.router.openDashboard()

    XCTAssertEqual(factory.createdIdentifiers, [.dashboard])
    XCTAssertEqual(factory.window(for: .dashboard)?.showCount, 1)
  }

  func testOnboardingRouting() {
    let factory = RecordingWindowFactory()
    let root = makeRoot(factory: factory)

    root.router.openOnboarding()

    XCTAssertEqual(factory.createdIdentifiers, [.onboarding])
    XCTAssertEqual(factory.window(for: .onboarding)?.showCount, 1)
  }

  func testLogsRouting() {
    let factory = RecordingWindowFactory()
    let root = makeRoot(factory: factory)

    root.router.openLogs()

    XCTAssertEqual(factory.createdIdentifiers, [.logs])
    XCTAssertEqual(factory.window(for: .logs)?.showCount, 1)
  }

  func testSettingsRouting() {
    let factory = RecordingWindowFactory()
    let root = makeRoot(factory: factory)

    root.router.openSettings()

    XCTAssertEqual(factory.createdIdentifiers, [.settings])
    XCTAssertEqual(factory.window(for: .settings)?.showCount, 1)
  }

  func testDiagnosticsRouting() {
    let factory = RecordingWindowFactory()
    let root = makeRoot(factory: factory)

    root.router.openDiagnostics()

    XCTAssertEqual(factory.createdIdentifiers, [.diagnostics])
    XCTAssertEqual(factory.window(for: .diagnostics)?.showCount, 1)
  }

  func testRepeatedOpenFocusesExistingWindow() {
    let factory = RecordingWindowFactory()
    let root = makeRoot(factory: factory)

    root.router.openDashboard()
    root.router.openDashboard()

    XCTAssertEqual(factory.createdIdentifiers, [.dashboard])
    XCTAssertEqual(factory.window(for: .dashboard)?.showCount, 1)
    XCTAssertEqual(factory.window(for: .dashboard)?.focusCount, 1)
    XCTAssertEqual(root.windowCoordinator.windowCount(for: .dashboard), 1)
  }

  func testCloseAndReopenUsesSameLogicalWindow() {
    let factory = RecordingWindowFactory()
    let root = makeRoot(factory: factory)

    root.router.openLogs()
    root.windowCoordinator.close(.logs)
    root.router.openLogs()

    XCTAssertEqual(factory.createdIdentifiers, [.logs])
    XCTAssertEqual(factory.window(for: .logs)?.closeCount, 1)
    XCTAssertEqual(factory.window(for: .logs)?.showCount, 2)
    XCTAssertEqual(root.windowCoordinator.windowCount(for: .logs), 1)
  }

  func testAllFeatureWindowsShareSameClientGraph() {
    let factory = RecordingWindowFactory()
    let root = makeRoot(factory: factory)

    root.router.openDashboard()
    root.router.openOnboarding()
    root.router.openLogs()
    root.router.openSettings()
    root.router.openDiagnostics()
    root.router.openComplianceCenter()
    root.router.openHealthCenter()

    XCTAssertEqual(Set(factory.clientGraphIDs).count, 1)
    XCTAssertEqual(factory.clientGraphIDs.first, ObjectIdentifier(root.clientGraph))
  }

  func testApplicationShutdownInvalidatesClientResourcesAndDoesNotStopRuntime() async {
    let factory = RecordingWindowFactory()
    let client = RecordingRuntimeClient()
    let root = makeRoot(client: client, factory: factory)

    root.router.openSettings()
    await root.shutdown()
    await root.shutdown()

    XCTAssertEqual(factory.window(for: .settings)?.cleanupCount, 1)
    XCTAssertEqual(root.windowCoordinator.openedWindowIdentifiers, [])
    let invalidateCount = await client.invalidateCount()
    let commands = await client.commands()
    XCTAssertEqual(invalidateCount, 1)
    XCTAssertFalse(commands.contains { command in
      if case .stopSession = command { return true }
      return false
    })
  }

  func testExplicitStopHermesForwardsExactlyOneStopCommand() async {
    let client = RecordingRuntimeClient()
    let root = makeRoot(client: client)

    root.menuBarViewModel.startHermes()
    await client.waitForCommandCount(2)
    root.menuBarViewModel.stopHermes()
    await client.waitForCommandCount(3)

    let stopCommands = await client.commands().filter { command in
      if case .stopSession = command { return true }
      return false
    }
    XCTAssertEqual(stopCommands.count, 1)
  }

  func testNoDuplicateRuntimeGraphIsCreated() throws {
    let source = try String(
      contentsOfFile: "Sources/HermesBridgeApp/HermesAppCompositionRoot.swift",
      encoding: .utf8
    )

    XCTAssertFalse(source.contains("HermesAppRuntimeGraph"))
    XCTAssertFalse(source.contains("HermesRuntimeSessionManager("))
    XCTAssertFalse(source.contains("HermesRuntimeEventBus("))
    XCTAssertFalse(source.contains("HermesRuntimeCommandAPI("))
  }

  func testSafeWindowIdentifiers() {
    let identifiers = HermesNativeUIWindowIdentifier.allCases.map(\.rawValue)

    XCTAssertEqual(Set(identifiers).count, HermesNativeUIWindowIdentifier.allCases.count)
    for identifier in identifiers {
      XCTAssertTrue(identifier.hasPrefix("com.hermes.bridge.window."))
      XCTAssertFalse(identifier.contains("/"))
      XCTAssertFalse(identifier.localizedCaseInsensitiveContains("token"))
      XCTAssertFalse(identifier.localizedCaseInsensitiveContains("credential"))
      XCTAssertFalse(identifier.localizedCaseInsensitiveContains("pid"))
    }
  }

  func testComplianceRouting() {
    let factory = RecordingWindowFactory()
    let root = makeRoot(factory: factory)

    root.router.openComplianceCenter()

    XCTAssertEqual(factory.createdIdentifiers, [.compliance])
    XCTAssertEqual(factory.window(for: .compliance)?.showCount, 1)
  }

  func testHealthRouting() {
    let factory = RecordingWindowFactory()
    let root = makeRoot(factory: factory)

    root.router.openHealthCenter()

    XCTAssertEqual(factory.createdIdentifiers, [.health])
    XCTAssertEqual(factory.window(for: .health)?.showCount, 1)
  }

  private func makeRoot(
    client: RecordingRuntimeClient = RecordingRuntimeClient(),
    factory: RecordingWindowFactory = RecordingWindowFactory()
  ) -> HermesAppCompositionRoot {
    let graph = HermesAppClientGraph(
      runtimeClient: client,
      settingsStore: InMemorySettingsStore()
    )
    return HermesAppCompositionRoot(clientGraph: graph, windowFactory: factory)
  }
}

private final class RecordingWindowFactory: HermesNativeUIWindowFactory, @unchecked Sendable {
  @MainActor private var windows: [HermesNativeUIWindowIdentifier: RecordingWindow] = [:]
  @MainActor private(set) var createdIdentifiers: [HermesNativeUIWindowIdentifier] = []
  @MainActor private(set) var clientGraphIDs: [ObjectIdentifier] = []

  @MainActor
  func makeWindow(
    for identifier: HermesNativeUIWindowIdentifier,
    clientGraph: HermesAppClientGraph
  ) -> HermesNativeUIWindowControlling {
    let window = RecordingWindow(identifier: identifier)
    windows[identifier] = window
    createdIdentifiers.append(identifier)
    clientGraphIDs.append(ObjectIdentifier(clientGraph))
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
  private(set) var closeCount = 0
  private(set) var cleanupCount = 0

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
    closeCount += 1
  }

  func cleanup() {
    isOpen = false
    cleanupCount += 1
  }
}

private final class RecordingRuntimeClient: HermesAppRuntimeClienting, @unchecked Sendable {
  let sessionID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
  private let lock = NSLock()
  private var recordedCommands: [HermesRuntimeCommand] = []
  private var recordedSubscriptions = 0
  private var recordedInvalidations = 0

  func execute(_ command: HermesRuntimeCommand) async throws -> HermesRuntimeCommandResult {
    lock.withLock {
      recordedCommands.append(command)
    }
    switch command {
    case .createSession:
      return .sessionStatus(status(.created))
    case .startSession:
      return .sessionStatus(status(.running))
    case .stopSession:
      return .sessionStatus(status(.stopped))
    case .getSessionStatus:
      return .sessionStatus(status(.running))
    case .listSessions:
      return .sessionList([status(.running)])
    case .subscribeEvents:
      return .eventSubscription(try await subscribeRuntimeEvents())
    }
  }

  func subscribeRuntimeEvents() async throws -> HermesRuntimeCommandEventSubscription {
    lock.withLock {
      recordedSubscriptions += 1
    }
    return HermesRuntimeCommandEventSubscription(
      id: UUID(),
      events: AsyncStream { continuation in
        continuation.finish()
      }
    )
  }

  func invalidate() async {
    lock.withLock {
      recordedInvalidations += 1
    }
  }

  func commands() async -> [HermesRuntimeCommand] {
    lock.withLock { recordedCommands }
  }

  func subscriptionCount() async -> Int {
    lock.withLock { recordedSubscriptions }
  }

  func invalidateCount() async -> Int {
    lock.withLock { recordedInvalidations }
  }

  func waitForCommandCount(_ expected: Int) async {
    for _ in 0..<100 {
      if await commands().count >= expected { return }
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
  }

  func waitForSubscriptionCount(_ expected: Int) async {
    for _ in 0..<100 {
      if await subscriptionCount() >= expected { return }
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
  }

  private func status(_ currentStatus: HermesRuntimeSessionStatus) -> HermesRuntimeCommandSessionStatus {
    HermesRuntimeCommandSessionStatus(
      sessionID: sessionID,
      currentStatus: currentStatus,
      backendVersion: "0.1.0",
      startTime: Date(timeIntervalSince1970: 1),
      capabilities: nil,
      lastErrorMessage: nil,
      shutdownReason: currentStatus == .stopped ? .requested : nil
    )
  }
}

private final class InMemorySettingsStore: HermesConfigurationStoring, @unchecked Sendable {
  private var settings = HermesSettings.defaults

  func load() throws -> HermesSettings {
    settings
  }

  func save(_ settings: HermesSettings) throws {
    self.settings = settings
  }
}
