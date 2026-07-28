import Foundation
import AppKit
import HermesAdministration
import HermesAnalytics
import HermesBridgeXPC
import HermesCompliance
import HermesDashboard
import HermesDiagnostics
import HermesFeedback
import HermesHealth
import HermesLogsViewer
import HermesMenuBar
import HermesNotifications
import HermesOnboarding
import HermesOperations
import HermesPolicy
import HermesPrivacy
import HermesRecovery
import HermesSearch
import HermesSettings
import HermesTimeline
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
  public let notificationCenter: HermesNotificationCenter
  public let timelineStore: HermesTimelineStore
  public let searchStore: HermesSearchStore
  public let searchIndexer: HermesSearchIndexer
  public let feedbackCenter: HermesFeedbackCenter
  public let policyCenter: HermesPolicyCenter
  public let privacyCenter: HermesPrivacyCenter
  public let adminCenter: HermesAdminCenter
  public let complianceCenter: HermesComplianceCenter
  public let healthCenter: HermesHealthCenter
  public let operationsCenter: HermesOperationsCenter
  public let analyticsCenter: HermesAnalyticsCenter
  public let navigationActions = HermesAppNavigationActions()

  private let shutdownHandler: @Sendable () async -> Void

  public init(
    runtimeClient: any HermesAppRuntimeClienting,
    settingsStore: HermesConfigurationStoring = HermesConfigurationStore(),
    onboardingCoordinator: HermesOnboardingCoordinator? = nil,
    recoveryCoordinator: HermesRecoveryCoordinator? = nil,
    updateCoordinator: HermesUpdateCoordinator? = nil,
    notificationCenter: HermesNotificationCenter = HermesNotificationCenter(),
    timelineStore: HermesTimelineStore = HermesTimelineStore(),
    searchStore: HermesSearchStore = HermesSearchStore(),
    searchIndexer: HermesSearchIndexer? = nil,
    feedbackCenter: HermesFeedbackCenter = HermesFeedbackCenter(),
    policyCenter: HermesPolicyCenter = HermesPolicyCenter(),
    privacyCenter: HermesPrivacyCenter = HermesPrivacyCenter(),
    adminCenter: HermesAdminCenter? = nil,
    complianceCenter: HermesComplianceCenter? = nil,
    healthCenter: HermesHealthCenter? = nil,
    operationsCenter: HermesOperationsCenter? = nil,
    analyticsCenter: HermesAnalyticsCenter? = nil,
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
    self.notificationCenter = notificationCenter
    self.timelineStore = timelineStore
    self.searchStore = searchStore
    self.searchIndexer = searchIndexer ?? HermesSearchIndexer(store: searchStore)
    self.feedbackCenter = feedbackCenter
    self.policyCenter = policyCenter
    self.privacyCenter = privacyCenter
    self.adminCenter = adminCenter ?? Self.makeAdminCenter(
      policyCenter: policyCenter,
      privacyCenter: privacyCenter,
      updateCoordinator: self.updateCoordinator
    )
    self.complianceCenter = complianceCenter ?? Self.makeComplianceCenter(
      policyCenter: policyCenter,
      privacyCenter: privacyCenter,
      updateCoordinator: self.updateCoordinator
    )
    self.healthCenter = healthCenter ?? Self.makeHealthCenter(
      policyCenter: policyCenter,
      privacyCenter: privacyCenter,
      updateCoordinator: self.updateCoordinator,
      notificationCenter: notificationCenter,
      recoveryCoordinator: self.recoveryCoordinator,
      complianceCenter: self.complianceCenter
    )
    self.operationsCenter = operationsCenter ?? Self.makeOperationsCenter(
      policyCenter: policyCenter,
      privacyCenter: privacyCenter,
      updateCoordinator: self.updateCoordinator,
      notificationCenter: notificationCenter,
      complianceCenter: self.complianceCenter
    )
    self.analyticsCenter = analyticsCenter ?? Self.makeAnalyticsCenter(
      policyCenter: policyCenter,
      privacyCenter: privacyCenter,
      updateCoordinator: self.updateCoordinator,
      notificationCenter: notificationCenter,
      recoveryCoordinator: self.recoveryCoordinator,
      complianceCenter: self.complianceCenter,
      healthCenter: self.healthCenter,
      operationsCenter: self.operationsCenter
    )
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

  private static func makeAdminCenter(
    policyCenter: HermesPolicyCenter,
    privacyCenter: HermesPrivacyCenter,
    updateCoordinator: HermesUpdateCoordinator
  ) -> HermesAdminCenter {
    HermesAdminCenter(
      inputs: HermesAdminCenterInputs(
        systemStatus: {
          let snapshot = await updateCoordinator.currentSnapshot
          let serviceAvailable = snapshot.current.serviceVersion == "unknown"
            ? HermesAdminAvailability.unknown
            : .available
          return HermesAdminSystemStatus(
            applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0",
            protocolVersion: snapshot.current.xpcProtocolVersion,
            serviceAvailability: serviceAvailable
          )
        },
        policies: {
          try policyCenter.listPolicies()
        },
        privacyRecords: {
          try privacyCenter.listConsentRecords()
        },
        updateSnapshot: {
          await updateCoordinator.currentSnapshot
        },
        policyAuditEvents: {
          try policyCenter.loadAuditEvents()
        },
        privacyAuditEvents: {
          try privacyCenter.loadAuditEvents()
        }
      )
    )
  }

  private static func makeComplianceCenter(
    policyCenter: HermesPolicyCenter,
    privacyCenter: HermesPrivacyCenter,
    updateCoordinator: HermesUpdateCoordinator
  ) -> HermesComplianceCenter {
    HermesComplianceCenter(
      inputs: HermesComplianceCenterInputs(
        systemStatus: {
          let snapshot = await updateCoordinator.currentSnapshot
          let serviceAvailable = snapshot.current.serviceVersion == "unknown"
            ? HermesComplianceServiceAvailability.unknown
            : .available
          return HermesComplianceSystemStatus(
            applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0",
            protocolVersion: snapshot.current.xpcProtocolVersion,
            serviceAvailability: serviceAvailable
          )
        },
        policies: {
          try policyCenter.listPolicies()
        },
        privacyRecords: {
          try privacyCenter.listConsentRecords()
        },
        updateSnapshot: {
          await updateCoordinator.currentSnapshot
        },
        policyAuditEvents: {
          try policyCenter.loadAuditEvents()
        },
        privacyAuditEvents: {
          try privacyCenter.loadAuditEvents()
        }
      )
    )
  }

  private static func makeHealthCenter(
    policyCenter: HermesPolicyCenter,
    privacyCenter: HermesPrivacyCenter,
    updateCoordinator: HermesUpdateCoordinator,
    notificationCenter: HermesNotificationCenter,
    recoveryCoordinator: HermesRecoveryCoordinator,
    complianceCenter: HermesComplianceCenter
  ) -> HermesHealthCenter {
    HermesHealthCenter(
      inputs: HermesHealthCenterInputs(
        systemHealth: {
          let snapshot = await updateCoordinator.currentSnapshot
          let serviceAvailability: HermesHealthAvailability = snapshot.current.serviceVersion == "unknown"
            ? .unknown
            : .available
          let xpcConnectivity: HermesHealthConnectivity = snapshot.current.xpcProtocolVersion == "unknown"
            ? .unknown
            : .connected
          return HermesHealthSystemProviderSnapshot(
            applicationAvailability: .available,
            serviceAvailability: serviceAvailability,
            xpcConnectivity: xpcConnectivity,
            applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0",
            protocolVersion: snapshot.current.xpcProtocolVersion
          )
        },
        runtimeHealth: {
          let snapshot = await updateCoordinator.currentSnapshot
          let serviceKnown = snapshot.current.serviceVersion != "unknown"
          return HermesHealthRuntimeProviderSnapshot(
            runtimeStatusSummary: serviceKnown ? "runtime visible through service-owned provider" : "runtime unknown",
            sessionAvailabilitySummary: "session availability owned by Bridge Service",
            backendAvailabilitySummary: serviceKnown ? "backend available" : "backend unknown"
          )
        },
        operationalHealth: {
          let update = await updateCoordinator.currentSnapshot
          let recovery = recoveryCoordinator.currentSnapshot
          let notifications = await notificationCenter.currentNotifications()
          var failures = notifications.filter { $0.severity == .critical || $0.category == .updateFailed }
            .map { "\($0.category.rawValue) \($0.title)" }
          if let failure = update.failure {
            failures.append("\(failure.category.rawValue) \(failure.safeMessage)")
          }
          return HermesHealthOperationalProviderSnapshot(
            recentFailures: failures,
            recoveryStatus: recovery.state.rawValue,
            updateStatus: update.state.rawValue,
            notificationStatus: "\(notifications.count) notifications"
          )
        },
        complianceHealth: {
          let compliance = await complianceCenter.snapshot()
          let policyCount = (try? policyCenter.listPolicies().count) ?? 0
          let privacyCount = (try? privacyCenter.listConsentRecords().count) ?? 0
          return HermesHealthComplianceProviderSnapshot(
            policyStatus: "\(compliance.policy.state.rawValue) \(policyCount) policies",
            privacyStatus: "\(compliance.privacy.state.rawValue) \(privacyCount) records",
            auditStatus: "\(compliance.auditEvidence.recentEventCount) audit events"
          )
        }
      )
    )
  }

  private static func makeOperationsCenter(
    policyCenter: HermesPolicyCenter,
    privacyCenter: HermesPrivacyCenter,
    updateCoordinator: HermesUpdateCoordinator,
    notificationCenter: HermesNotificationCenter,
    complianceCenter: HermesComplianceCenter
  ) -> HermesOperationsCenter {
    HermesOperationsCenter(
      inputs: HermesOperationsCenterInputs(
        runtimeOperations: {
          let update = await updateCoordinator.currentSnapshot
          let serviceKnown = update.current.serviceVersion != "unknown"
          return HermesRuntimeOperationsProviderSnapshot(
            runtimeStatus: serviceKnown ? "runtime visible through service-owned provider" : "runtime unknown",
            sessionStatus: "sessions owned by Bridge Service",
            backendStatus: serviceKnown ? "backend available" : "backend unknown",
            activeOperationCount: 0
          )
        },
        eventOperations: {
          let notifications = await notificationCenter.currentNotifications()
          return HermesEventOperationsProviderSnapshot(
            eventPipelineStatus: "event summaries available",
            recentEventCount: notifications.count,
            notificationStatus: "\(notifications.count) notifications",
            recentEventSummaries: notifications.prefix(8).map { "\($0.category.rawValue) \($0.title)" }
          )
        },
        releaseOperations: {
          let update = await updateCoordinator.currentSnapshot
          return HermesReleaseOperationsProviderSnapshot(
            releaseStatus: update.state.rawValue,
            currentVersion: update.current.appVersion,
            availableVersion: update.availableRelease?.version,
            releaseReadiness: update.message
          )
        },
        governanceOperations: {
          let compliance = await complianceCenter.snapshot()
          let policyCount = (try? policyCenter.listPolicies().count) ?? 0
          let privacyCount = (try? privacyCenter.listConsentRecords().count) ?? 0
          return HermesGovernanceOperationsProviderSnapshot(
            policyStatus: "\(compliance.policy.state.rawValue) \(policyCount) policies",
            privacyStatus: "\(compliance.privacy.state.rawValue) \(privacyCount) records",
            auditStatus: "\(compliance.auditEvidence.recentEventCount) audit events",
            complianceStatus: compliance.overallState.rawValue
          )
        }
      )
    )
  }

  private static func makeAnalyticsCenter(
    policyCenter: HermesPolicyCenter,
    privacyCenter: HermesPrivacyCenter,
    updateCoordinator: HermesUpdateCoordinator,
    notificationCenter: HermesNotificationCenter,
    recoveryCoordinator: HermesRecoveryCoordinator,
    complianceCenter: HermesComplianceCenter,
    healthCenter: HermesHealthCenter,
    operationsCenter: HermesOperationsCenter
  ) -> HermesAnalyticsCenter {
    HermesAnalyticsCenter(
      inputs: HermesAnalyticsCenterInputs(
        runtimeAnalytics: {
          let health = await healthCenter.snapshot()
          return HermesRuntimeAnalyticsProviderSnapshot(
            uptimeSummary: health.system.serviceAvailability.rawValue,
            sessionStabilitySummary: health.runtime.sessionAvailabilitySummary,
            serviceAvailabilitySummary: health.runtime.backendAvailabilitySummary
          )
        },
        operationsAnalytics: {
          let operations = await operationsCenter.snapshot()
          let update = await updateCoordinator.currentSnapshot
          let recovery = recoveryCoordinator.currentSnapshot
          let notifications = await notificationCenter.currentNotifications()
          let criticalCount = notifications.filter {
            $0.severity == .critical || $0.category == .updateFailed
          }.count
          let errorTrend = criticalCount == 0
            ? "0 high severity notifications, operations \(operations.overallState.rawValue)"
            : "\(criticalCount) critical notifications, operations \(operations.overallState.rawValue)"
          return HermesOperationsAnalyticsProviderSnapshot(
            errorTrendSummary: errorTrend,
            recoveryTrendSummary: recovery.state.rawValue,
            notificationTrendSummary: "\(notifications.count) notifications",
            updateReliabilitySummary: update.state.rawValue
          )
        },
        governanceAnalytics: {
          let compliance = await complianceCenter.snapshot()
          let policyCount = (try? policyCenter.listPolicies().count) ?? 0
          let privacyCount = (try? privacyCenter.listConsentRecords().count) ?? 0
          return HermesGovernanceAnalyticsProviderSnapshot(
            policyComplianceSummary: "\(compliance.policy.state.rawValue) \(policyCount) policies",
            privacyPostureTrend: "\(compliance.privacy.state.rawValue) \(privacyCount) records",
            auditCoverageSummary: "\(compliance.auditEvidence.recentEventCount) audit events"
          )
        }
      )
    )
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
    clientGraph.navigationActions.openSettings = { [weak windowCoordinator] in
      windowCoordinator?.open(.settings)
    }
    clientGraph.navigationActions.openUpdateCenter = { [weak windowCoordinator] in
      windowCoordinator?.open(.update)
    }
    clientGraph.navigationActions.openNotifications = { [weak windowCoordinator] in
      windowCoordinator?.open(.notifications)
    }
    clientGraph.navigationActions.openTimeline = { [weak windowCoordinator] in
      windowCoordinator?.open(.timeline)
    }
    clientGraph.navigationActions.openSearchCenter = { [weak windowCoordinator] in
      windowCoordinator?.open(.search)
    }
    clientGraph.navigationActions.openFeedbackCenter = { [weak windowCoordinator] in
      windowCoordinator?.open(.feedback)
    }
    clientGraph.navigationActions.openPrivacyCenter = { [weak windowCoordinator] in
      windowCoordinator?.open(.privacy)
    }
    clientGraph.navigationActions.openPolicyCenter = { [weak windowCoordinator] in
      windowCoordinator?.open(.policy)
    }
    clientGraph.navigationActions.openAdministrationCenter = { [weak windowCoordinator] in
      windowCoordinator?.open(.administration)
    }
    clientGraph.navigationActions.openComplianceCenter = { [weak windowCoordinator] in
      windowCoordinator?.open(.compliance)
    }
    clientGraph.navigationActions.openHealthCenter = { [weak windowCoordinator] in
      windowCoordinator?.open(.health)
    }
    clientGraph.navigationActions.openOperationsCenter = { [weak windowCoordinator] in
      windowCoordinator?.open(.operations)
    }
    clientGraph.navigationActions.openAnalyticsCenter = { [weak windowCoordinator] in
      windowCoordinator?.open(.analytics)
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
          openPrivacyCenter: {
            clientGraph.navigationActions.openPrivacyCenter()
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
        viewModel: HermesDashboardViewModel(
          commandAPI: clientGraph.runtimeClient,
          timelineReader: clientGraph.timelineStore,
          openSearchCenter: {
            clientGraph.navigationActions.openSearchCenter()
          },
          openFeedbackCenter: {
            clientGraph.navigationActions.openFeedbackCenter()
          }
        )
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
          },
          openPrivacyCenter: {
            clientGraph.navigationActions.openPrivacyCenter()
          },
          openPolicyCenter: {
            clientGraph.navigationActions.openPolicyCenter()
          },
          openAdministrationCenter: {
            clientGraph.navigationActions.openAdministrationCenter()
          },
          openComplianceCenter: {
            clientGraph.navigationActions.openComplianceCenter()
          },
          openHealthCenter: {
            clientGraph.navigationActions.openHealthCenter()
          },
          openOperationsCenter: {
            clientGraph.navigationActions.openOperationsCenter()
          },
          openAnalyticsCenter: {
            clientGraph.navigationActions.openAnalyticsCenter()
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
          },
          openFeedbackCenter: {
            clientGraph.navigationActions.openFeedbackCenter()
          },
          openPrivacyCenter: {
            clientGraph.navigationActions.openPrivacyCenter()
          },
          openPolicyCenter: {
            clientGraph.navigationActions.openPolicyCenter()
          },
          openAdministrationCenter: {
            clientGraph.navigationActions.openAdministrationCenter()
          },
          openHealthCenter: {
            clientGraph.navigationActions.openHealthCenter()
          },
          openOperationsCenter: {
            clientGraph.navigationActions.openOperationsCenter()
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
          },
          openFeedbackCenter: {
            clientGraph.navigationActions.openFeedbackCenter()
          }
        )
      )
    case .notifications:
      controller = HermesNotificationWindowController(
        viewModel: HermesNotificationViewModel(center: clientGraph.notificationCenter)
      )
    case .timeline:
      controller = HermesActivityTimelineWindowController(
        viewModel: HermesTimelineViewModel(store: clientGraph.timelineStore)
      )
    case .search:
      controller = HermesSearchCenterWindowController(
        viewModel: HermesSearchViewModel(store: clientGraph.searchStore)
      )
    case .feedback:
      controller = HermesFeedbackWindowController(
        viewModel: HermesFeedbackViewModel(
          center: clientGraph.feedbackCenter,
          contextProvider: {
            HermesFeedbackSafeRuntimeContext(
              applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              runtimeStatusSummary: "app-managed-runtime=no",
              protocolVersion: "feedback.v1",
              featureName: "Feedback Center"
            )
          }
        )
      )
    case .privacy:
      controller = HermesPrivacyWindowController(
        viewModel: HermesPrivacyViewModel(
          center: clientGraph.privacyCenter,
          openPolicyCenter: {
            clientGraph.navigationActions.openPolicyCenter()
          },
          metadataProvider: {
            HermesPrivacySafeApplicationMetadata(
              applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              buildVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            )
          }
        )
      )
    case .policy:
      controller = HermesPolicyWindowController(
        viewModel: HermesPolicyViewModel(
          center: clientGraph.policyCenter,
          openAdministrationCenter: {
            clientGraph.navigationActions.openAdministrationCenter()
          }
        )
      )
    case .administration:
      controller = HermesAdministrationWindowController(
        viewModel: HermesAdminViewModel(
          center: clientGraph.adminCenter,
          openSettings: {
            clientGraph.navigationActions.openSettings()
          },
          openDiagnostics: {
            clientGraph.navigationActions.openDiagnostics()
          },
          openPolicyCenter: {
            clientGraph.navigationActions.openPolicyCenter()
          },
          openComplianceCenter: {
            clientGraph.navigationActions.openComplianceCenter()
          },
          openHealthCenter: {
            clientGraph.navigationActions.openHealthCenter()
          },
          openOperationsCenter: {
            clientGraph.navigationActions.openOperationsCenter()
          },
          openAnalyticsCenter: {
            clientGraph.navigationActions.openAnalyticsCenter()
          }
        )
      )
    case .compliance:
      controller = HermesComplianceWindowController(
        viewModel: HermesComplianceViewModel(
          center: clientGraph.complianceCenter,
          openSettings: {
            clientGraph.navigationActions.openSettings()
          },
          openAdministrationCenter: {
            clientGraph.navigationActions.openAdministrationCenter()
          }
        )
      )
    case .health:
      controller = HermesHealthWindowController(
        viewModel: HermesHealthViewModel(
          center: clientGraph.healthCenter,
          openSettings: {
            clientGraph.navigationActions.openSettings()
          },
          openDiagnostics: {
            clientGraph.navigationActions.openDiagnostics()
          },
          openAdministrationCenter: {
            clientGraph.navigationActions.openAdministrationCenter()
          }
        )
      )
    case .operations:
      controller = HermesOperationsWindowController(
        viewModel: HermesOperationsViewModel(
          center: clientGraph.operationsCenter,
          openSettings: {
            clientGraph.navigationActions.openSettings()
          },
          openDiagnostics: {
            clientGraph.navigationActions.openDiagnostics()
          },
          openAdministrationCenter: {
            clientGraph.navigationActions.openAdministrationCenter()
          },
          openAnalyticsCenter: {
            clientGraph.navigationActions.openAnalyticsCenter()
          }
        )
      )
    case .analytics:
      controller = HermesAnalyticsWindowController(
        viewModel: HermesAnalyticsViewModel(
          center: clientGraph.analyticsCenter,
          openSettings: {
            clientGraph.navigationActions.openSettings()
          },
          openAdministrationCenter: {
            clientGraph.navigationActions.openAdministrationCenter()
          },
          openOperationsCenter: {
            clientGraph.navigationActions.openOperationsCenter()
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
          openFeedbackCenter: {
            clientGraph.navigationActions.openFeedbackCenter()
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
  public var openNotifications: () -> Void = {}
  public var openTimeline: () -> Void = {}
  public var openSearchCenter: () -> Void = {}
  public var openFeedbackCenter: () -> Void = {}
  public var openPrivacyCenter: () -> Void = {}
  public var openPolicyCenter: () -> Void = {}
  public var openSettings: () -> Void = {}
  public var openAdministrationCenter: () -> Void = {}
  public var openComplianceCenter: () -> Void = {}
  public var openHealthCenter: () -> Void = {}
  public var openOperationsCenter: () -> Void = {}
  public var openAnalyticsCenter: () -> Void = {}
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
