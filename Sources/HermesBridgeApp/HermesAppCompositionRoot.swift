import Foundation
import AppKit
import HermesBridgeXPC
import HermesDashboard
import HermesDiagnostics
import HermesLogsViewer
import HermesMenuBar
import HermesSettings
import SwiftUI

extension HermesBridgeRuntimeClientAdapter: HermesRuntimeCommandExecuting,
  HermesDashboardRuntimeCommandExecuting, HermesDiagnosticsRuntimeCommandExecuting,
  HermesLogsRuntimeEventSubscribing
{}

public protocol HermesAppRuntimeClienting: HermesRuntimeCommandExecuting,
  HermesDashboardRuntimeCommandExecuting, HermesDiagnosticsRuntimeCommandExecuting,
  HermesLogsRuntimeEventSubscribing, Sendable
{
  func invalidate() async
}

extension HermesBridgeRuntimeClientAdapter: HermesAppRuntimeClienting {}

public final class HermesAppClientGraph: @unchecked Sendable {
  public let runtimeClient: any HermesAppRuntimeClienting
  public let settingsStore: HermesConfigurationStoring

  private let shutdownHandler: @Sendable () async -> Void

  public init(
    runtimeClient: any HermesAppRuntimeClienting,
    settingsStore: HermesConfigurationStoring = HermesConfigurationStore(),
    shutdownHandler: (@Sendable () async -> Void)? = nil
  ) {
    self.runtimeClient = runtimeClient
    self.settingsStore = settingsStore
    self.shutdownHandler = shutdownHandler ?? {
      await runtimeClient.invalidate()
    }
  }

  public static func production() -> HermesAppClientGraph {
    let serviceName = try! HermesBridgeMachServiceName("com.hermes.bridge.xpc")
    let client = HermesBridgeXPCClient(machServiceName: serviceName)
    return HermesAppClientGraph(
      runtimeClient: HermesBridgeRuntimeClientAdapter(client: client)
    )
  }

  public func shutdown() async {
    await shutdownHandler()
  }
}

@MainActor
public final class HermesAppCompositionRoot: ObservableObject {
  public let clientGraph: HermesAppClientGraph
  public let menuBarViewModel: HermesMenuBarViewModel
  public let windowCoordinator: HermesWindowCoordinator
  public let router: HermesNativeUIRouter

  private var didShutdown = false

  public init(
    clientGraph: HermesAppClientGraph = .production(),
    windowFactory: HermesNativeUIWindowFactory = HermesProductionNativeUIWindowFactory()
  ) {
    self.clientGraph = clientGraph
    self.menuBarViewModel = HermesMenuBarViewModel(commandAPI: clientGraph.runtimeClient)
    self.windowCoordinator = HermesWindowCoordinator(
      clientGraph: clientGraph,
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
    await clientGraph.shutdown()
  }
}

public struct HermesProductionNativeUIWindowFactory: HermesNativeUIWindowFactory {
  public init() {}

  @MainActor
  public func makeWindow(
    for identifier: HermesNativeUIWindowIdentifier,
    clientGraph: HermesAppClientGraph
  ) -> HermesNativeUIWindowControlling {
    let controller: NSWindowController
    switch identifier {
    case .dashboard:
      controller = HermesDashboardWindowController(
        viewModel: HermesDashboardViewModel(commandAPI: clientGraph.runtimeClient)
      )
    case .logs:
      controller = HermesLogsViewerWindowController(
        viewModel: HermesLogsViewerViewModel(eventSource: clientGraph.runtimeClient)
      )
    case .settings:
      controller = HermesSettingsWindowController(
        viewModel: HermesSettingsViewModel(store: clientGraph.settingsStore)
      )
    case .diagnostics:
      controller = HermesDiagnosticsWindowController(
        viewModel: HermesDiagnosticsViewModel(
          provider: HermesDiagnosticProvider(
            commandAPI: clientGraph.runtimeClient,
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
