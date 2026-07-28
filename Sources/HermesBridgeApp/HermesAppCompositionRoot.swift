import Foundation
import AppKit
import HermesBridgeXPC
import HermesDashboard
import HermesDiagnostics
import HermesLogsViewer
import HermesMenuBar
import HermesOnboarding
import HermesRecovery
import HermesSettings
import HermesUpdate
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
  public let onboardingCoordinator: HermesOnboardingCoordinator
  public let recoveryCoordinator: HermesRecoveryCoordinator
  public let updateCoordinator: HermesUpdateCoordinator
  public let navigationActions = HermesAppNavigationActions()

  private let shutdownHandler: @Sendable () async -> Void

  public init(
    runtimeClient: any HermesAppRuntimeClienting,
    settingsStore: HermesConfigurationStoring = HermesConfigurationStore(),
    onboardingCoordinator: HermesOnboardingCoordinator? = nil,
    recoveryCoordinator: HermesRecoveryCoordinator? = nil,
    updateCoordinator: HermesUpdateCoordinator? = nil,
    shutdownHandler: (@Sendable () async -> Void)? = nil
  ) {
    self.runtimeClient = runtimeClient
    self.settingsStore = settingsStore
    if let onboardingCoordinator {
      self.onboardingCoordinator = onboardingCoordinator
    } else if let readinessClient = runtimeClient as? HermesOnboardingXPCReadinessClient {
      self.onboardingCoordinator = HermesOnboardingCoordinator(
        readinessProvider: HermesOnboardingProductionReadinessProvider(client: readinessClient)
      )
    } else {
      self.onboardingCoordinator = HermesOnboardingCoordinator(
        readinessProvider: HermesOnboardingUnavailableReadinessProvider()
      )
    }
    if let recoveryCoordinator {
      self.recoveryCoordinator = recoveryCoordinator
    } else if let xpc = runtimeClient as? any HermesRecoveryXPCConnecting {
      self.recoveryCoordinator = HermesRecoveryCoordinator(
        provider: HermesRecoveryProductionProvider(
          xpc: xpc,
          readiness: HermesAppOnboardingReadinessRerunner(coordinator: self.onboardingCoordinator)
        )
      )
    } else {
      self.recoveryCoordinator = HermesRecoveryCoordinator(
        provider: HermesRecoveryProductionProvider(
          xpc: HermesRecoveryUnavailableXPC(),
          readiness: HermesAppOnboardingReadinessRerunner(coordinator: self.onboardingCoordinator)
        )
      )
    }
    if let updateCoordinator {
      self.updateCoordinator = updateCoordinator
    } else if let updateClient = runtimeClient as? HermesBridgeRuntimeClientAdapter {
      self.updateCoordinator = HermesUpdateCoordinator(
        provider: HermesUpdateProductionProvider(client: updateClient.client)
      )
    } else {
      self.updateCoordinator = HermesUpdateCoordinator(provider: HermesUpdateUnavailableProvider())
    }
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
    clientGraph.navigationActions.reopenOnboarding = { [weak windowCoordinator] in
      windowCoordinator?.open(.onboarding)
    }
    clientGraph.navigationActions.openDiagnostics = { [weak windowCoordinator] in
      windowCoordinator?.open(.diagnostics)
    }
    clientGraph.navigationActions.openUpdateCenter = { [weak windowCoordinator] in
      windowCoordinator?.open(.update)
    }
    clientGraph.navigationActions.openRecovery = { [weak clientGraph, weak windowCoordinator] issue in
      Task { @MainActor in
        await clientGraph?.recoveryCoordinator.evaluate(issue: issue)
        windowCoordinator?.open(.recovery)
      }
    }
  }

  public func start() {
    menuBarViewModel.startEventSubscription()
    menuBarViewModel.refreshStatus()
    if clientGraph.onboardingCoordinator.shouldOpenOnFirstRun() {
      router.openOnboarding()
    }
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
    case .onboarding:
      controller = HermesOnboardingWindowController(
        viewModel: HermesOnboardingViewModel(
          coordinator: clientGraph.onboardingCoordinator,
          openDiagnostics: {
            clientGraph.navigationActions.openDiagnostics()
          },
          openRecovery: { issue in
            clientGraph.navigationActions.openRecovery(issue)
          },
          finishHandler: {
            NSApp.keyWindow?.close()
          }
        )
      )
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
        viewModel: HermesSettingsViewModel(
          store: clientGraph.settingsStore,
          reopenOnboarding: {
            clientGraph.navigationActions.reopenOnboarding()
          },
          openUpdateCenter: {
            clientGraph.navigationActions.openUpdateCenter()
          }
        )
      )
    case .diagnostics:
      controller = HermesDiagnosticsWindowController(
        viewModel: HermesDiagnosticsViewModel(
          provider: HermesDiagnosticProvider(
            commandAPI: clientGraph.runtimeClient,
            eventBusState: { .ready }
          ),
          reopenOnboarding: {
            clientGraph.navigationActions.reopenOnboarding()
          },
          openRecovery: { issue in
            clientGraph.navigationActions.openRecovery(issue)
          },
          openUpdateCenter: {
            clientGraph.navigationActions.openUpdateCenter()
          }
        )
      )
    case .update:
      controller = HermesUpdateWindowController(
        viewModel: HermesUpdateViewModel(
          coordinator: clientGraph.updateCoordinator,
          openDiagnostics: {
            clientGraph.navigationActions.openDiagnostics()
          },
          openRecovery: {
            clientGraph.navigationActions.openRecovery(.unknownReadinessFailure)
          }
        )
      )
    case .recovery:
      controller = HermesRecoveryWindowController(
        viewModel: HermesRecoveryViewModel(
          coordinator: clientGraph.recoveryCoordinator,
          openDiagnostics: {
            clientGraph.navigationActions.openDiagnostics()
          },
          openUpdateCenter: {
            clientGraph.navigationActions.openUpdateCenter()
          },
          rerunReadiness: {
            Task {
              _ = await clientGraph.onboardingCoordinator.retry()
            }
          },
          dismiss: {
            NSApp.keyWindow?.close()
          }
        )
      )
    }
    return HermesAppKitWindowControllerAdapter(
      identifier: identifier,
      controller: controller
    )
  }
}

public final class HermesAppNavigationActions {
  public var reopenOnboarding: () -> Void = {}
  public var openDiagnostics: () -> Void = {}
  public var openUpdateCenter: () -> Void = {}
  public var openRecovery: (HermesRecoveryIssueCategory) -> Void = { _ in }

  public init() {}
}

private struct HermesAppOnboardingReadinessRerunner: HermesRecoveryReadinessRerunning {
  private let coordinator: HermesOnboardingCoordinator

  init(coordinator: HermesOnboardingCoordinator) {
    self.coordinator = coordinator
  }

  func rerunReadiness() async -> Bool {
    let snapshot = await coordinator.retry()
    return snapshot.state == .ready
  }
}

private struct HermesRecoveryUnavailableXPC: HermesRecoveryXPCConnecting {
  func connect() async throws -> HermesBridgeCapabilitiesPayload {
    throw HermesBridgeXPCClientError.service(.serviceUnavailable)
  }

  func protocolVersion() async throws -> HermesBridgeProtocolVersionPayload {
    throw HermesBridgeXPCClientError.service(.serviceUnavailable)
  }

  func capabilities() async throws -> HermesBridgeCapabilitiesPayload {
    throw HermesBridgeXPCClientError.service(.serviceUnavailable)
  }

  func discoverAgent() async throws -> HermesBridgeAgentDiscoveryPayload {
    HermesBridgeAgentDiscoveryPayload(status: .unknown)
  }
}

private struct HermesOnboardingUnavailableReadinessProvider: HermesOnboardingReadinessProviding {
  func checkService() async -> HermesOnboardingServiceReadiness {
    HermesOnboardingServiceReadiness(
      serviceAvailable: false,
      xpcConnected: false,
      protocolVersion: nil,
      protocolCompatible: false,
      healthStatus: .unavailable,
      safeMessage: "Bridge Service is unavailable."
    )
  }

  func checkAgent() async -> HermesOnboardingAgentReadiness {
    HermesOnboardingAgentReadiness(status: .unknown, safeMessage: "Agent status is unknown.")
  }

  func checkPermissions() async -> HermesOnboardingPermissionReadiness {
    HermesOnboardingPermissionReadiness(permissions: [])
  }

  func testConnection() async -> HermesOnboardingConnectionReadiness {
    HermesOnboardingConnectionReadiness(
      requestSucceeded: false,
      protocolCompatible: false,
      healthStatus: .unavailable,
      safeMessage: "Connection test failed."
    )
  }
}
