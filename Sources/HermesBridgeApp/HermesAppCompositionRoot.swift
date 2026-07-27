import Foundation
import HermesDashboard
import HermesDiagnostics
import HermesLogsViewer
import HermesMenuBar
import HermesRuntimeFoundation
import HermesSettings
import SwiftUI

public final class HermesAppRuntimeGraph: @unchecked Sendable {
  public let eventBus: HermesRuntimeEventBus
  public let sessionManager: HermesRuntimeSessionManager
  public let commandAPI: HermesRuntimeCommandAPI
  public let settingsStore: HermesConfigurationStoring

  private let shutdownHandler: @Sendable () async -> Void

  public init(
    eventBus: HermesRuntimeEventBus,
    sessionManager: HermesRuntimeSessionManager,
    commandAPI: HermesRuntimeCommandAPI,
    settingsStore: HermesConfigurationStoring = HermesConfigurationStore(),
    shutdownHandler: (@Sendable () async -> Void)? = nil
  ) {
    self.eventBus = eventBus
    self.sessionManager = sessionManager
    self.commandAPI = commandAPI
    self.settingsStore = settingsStore
    self.shutdownHandler = shutdownHandler ?? {
      let sessions = commandAPI.listSessions()
      for session in sessions where session.currentStatus != .stopped {
        _ = try? await commandAPI.stopSession(session.sessionID, reason: .requested)
      }
    }
  }

  public static func production() -> HermesAppRuntimeGraph {
    let eventBus = HermesRuntimeEventBus()
    let runtimeRoot = FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first?
      .appendingPathComponent("HermesBridgeApp", isDirectory: true)
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("HermesBridgeApp", isDirectory: true)

    let executableCandidates = [
      URL(fileURLWithPath: "/opt/homebrew/bin/hermes"),
      URL(fileURLWithPath: "/usr/local/bin/hermes"),
    ]
    let configuration = HermesBackendAdapterConfiguration(
      executableURL: executableCandidates[0],
      port: 19123,
      runtimeRoot: runtimeRoot
    )
    let sessionManager = HermesRuntimeSessionManager(
      backendFactory: {
        HermesBackendAdapter(
          allowlistedExecutableCandidates: executableCandidates,
          configuration: configuration
        )
      },
      eventBus: eventBus
    )
    let commandAPI = HermesRuntimeCommandAPI(sessionManager: sessionManager)
    return HermesAppRuntimeGraph(
      eventBus: eventBus,
      sessionManager: sessionManager,
      commandAPI: commandAPI
    )
  }

  public func shutdown() async {
    await shutdownHandler()
  }
}

@MainActor
public final class HermesAppCompositionRoot: ObservableObject {
  public let runtimeGraph: HermesAppRuntimeGraph
  public let menuBarViewModel: HermesMenuBarViewModel
  public let windowCoordinator: HermesWindowCoordinator
  public let router: HermesNativeUIRouter

  private var didShutdown = false

  public init(
    runtimeGraph: HermesAppRuntimeGraph = .production(),
    windowFactory: HermesNativeUIWindowFactory = HermesProductionNativeUIWindowFactory()
  ) {
    self.runtimeGraph = runtimeGraph
    self.menuBarViewModel = HermesMenuBarViewModel(commandAPI: runtimeGraph.commandAPI)
    self.windowCoordinator = HermesWindowCoordinator(
      runtimeGraph: runtimeGraph,
      windowFactory: windowFactory
    )
    self.router = HermesNativeUIRouter(windowCoordinator: windowCoordinator)
  }

  public func start() {
    menuBarViewModel.startEventSubscription()
    menuBarViewModel.refreshStatus()
  }

  public func shutdown() async {
    guard !didShutdown else { return }
    didShutdown = true
    menuBarViewModel.cancel()
    windowCoordinator.cleanup()
    await runtimeGraph.shutdown()
  }
}

public struct HermesProductionNativeUIWindowFactory: HermesNativeUIWindowFactory {
  public init() {}

  @MainActor
  public func makeWindow(
    for identifier: HermesNativeUIWindowIdentifier,
    runtimeGraph: HermesAppRuntimeGraph
  ) -> HermesNativeUIWindowControlling {
    let controller: NSWindowController
    switch identifier {
    case .dashboard:
      controller = HermesDashboardWindowController(
        viewModel: HermesDashboardViewModel(commandAPI: runtimeGraph.commandAPI)
      )
    case .logs:
      controller = HermesLogsViewerWindowController(
        viewModel: HermesLogsViewerViewModel(eventBus: runtimeGraph.eventBus)
      )
    case .settings:
      controller = HermesSettingsWindowController(
        viewModel: HermesSettingsViewModel(store: runtimeGraph.settingsStore)
      )
    case .diagnostics:
      controller = HermesDiagnosticsWindowController(
        viewModel: HermesDiagnosticsViewModel(
          provider: HermesDiagnosticProvider(
            commandAPI: runtimeGraph.commandAPI,
            eventBusState: { .ready }
          )
        )
      )
    }
    return HermesAppKitWindowControllerAdapter(
      identifier: identifier,
      controller: controller
    )
  }
}
