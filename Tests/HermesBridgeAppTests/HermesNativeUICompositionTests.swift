import Foundation
@testable import HermesBridgeApp
import HermesRuntimeFoundation
import HermesSettings
import XCTest

@MainActor
final class HermesNativeUICompositionTests: XCTestCase {
  func testSharedRuntimeCommandAPIIdentity() {
    let root = makeRoot()

    XCTAssertTrue(root.runtimeGraph.commandAPI === root.runtimeGraph.commandAPI)
  }

  func testDashboardRouting() {
    let factory = RecordingWindowFactory()
    let root = makeRoot(factory: factory)

    root.router.openDashboard()

    XCTAssertEqual(factory.createdIdentifiers, [.dashboard])
    XCTAssertEqual(factory.window(for: .dashboard)?.showCount, 1)
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

  func testApplicationShutdownCleanup() async {
    let factory = RecordingWindowFactory()
    let shutdown = ShutdownRecorder()
    let root = makeRoot(factory: factory, shutdown: shutdown)

    root.router.openSettings()
    await root.shutdown()
    await root.shutdown()

    let shutdownCount = await shutdown.currentCount()
    XCTAssertEqual(factory.window(for: .settings)?.cleanupCount, 1)
    XCTAssertEqual(shutdownCount, 1)
    XCTAssertEqual(root.windowCoordinator.openedWindowIdentifiers, [])
  }

  func testNoDuplicateRuntimeGraph() {
    let factory = RecordingWindowFactory()
    let root = makeRoot(factory: factory)

    root.router.openDashboard()
    root.router.openLogs()
    root.router.openSettings()
    root.router.openDiagnostics()

    XCTAssertEqual(Set(factory.runtimeGraphIDs).count, 1)
    XCTAssertEqual(factory.runtimeGraphIDs.first, ObjectIdentifier(root.runtimeGraph))
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

  private func makeRoot(
    factory: RecordingWindowFactory = RecordingWindowFactory(),
    shutdown: ShutdownRecorder = ShutdownRecorder()
  ) -> HermesAppCompositionRoot {
    let eventBus = HermesRuntimeEventBus()
    let sessionManager = HermesRuntimeSessionManager(
      backendFactory: { StubBackend() },
      eventBus: eventBus
    )
    let commandAPI = HermesRuntimeCommandAPI(sessionManager: sessionManager)
    let graph = HermesAppRuntimeGraph(
      eventBus: eventBus,
      sessionManager: sessionManager,
      commandAPI: commandAPI,
      settingsStore: InMemorySettingsStore(),
      shutdownHandler: {
        await shutdown.record()
      }
    )
    return HermesAppCompositionRoot(runtimeGraph: graph, windowFactory: factory)
  }
}

private final class RecordingWindowFactory: HermesNativeUIWindowFactory, @unchecked Sendable {
  @MainActor private var windows: [HermesNativeUIWindowIdentifier: RecordingWindow] = [:]
  @MainActor private(set) var createdIdentifiers: [HermesNativeUIWindowIdentifier] = []
  @MainActor private(set) var runtimeGraphIDs: [ObjectIdentifier] = []

  @MainActor
  func makeWindow(
    for identifier: HermesNativeUIWindowIdentifier,
    runtimeGraph: HermesAppRuntimeGraph
  ) -> HermesNativeUIWindowControlling {
    let window = RecordingWindow(identifier: identifier)
    windows[identifier] = window
    createdIdentifiers.append(identifier)
    runtimeGraphIDs.append(ObjectIdentifier(runtimeGraph))
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

private actor ShutdownRecorder {
  private var count = 0

  func record() {
    count += 1
  }

  func currentCount() -> Int {
    count
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

private final class StubBackend: HermesBackendAdapting, @unchecked Sendable {
  func discover() throws -> HermesDiscoveryResult {
    HermesDiscoveryResult(
      candidate: HermesExecutableCandidate(
        allowlistedCandidatePath: "/usr/local/bin/hermes",
        originalPath: "/usr/local/bin/hermes",
        resolvedPath: "/usr/local/bin/hermes",
        symlinkStatus: .notSymlink
      ),
      versionInfo: HermesVersionInfo(
        semanticVersion: "0.1.0",
        displayVersion: "Hermes 0.1.0",
        buildDateText: nil,
        upstreamRevision: nil,
        installationMethod: "fixture",
        pythonVersion: nil,
        openAISDKVersion: nil,
        rawOutputSHA256Digest: "fixture",
        capturedOutputByteCount: 7,
        outputWasTruncated: false,
        sanitizedDiagnosticMetadata: [:]
      )
    )
  }

  func start() async throws -> HermesBackendStartResult {
    throw HermesBackendAdapterError.notStarted
  }

  func stop() async throws -> HermesBackendStopResult {
    throw HermesBackendAdapterError.notStarted
  }

  func health() async throws -> HermesBackendHealthSnapshot {
    throw HermesBackendAdapterError.notStarted
  }
}
