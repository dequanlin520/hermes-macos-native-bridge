import Foundation
import HermesAdministration
import HermesCompliance
import HermesHealth
import HermesPolicy
import HermesPrivacy
import HermesRecovery

public enum HermesNativeUIRoute: Equatable, Sendable {
  case onboarding
  case dashboard
  case logs
  case settings
  case diagnostics
  case update
  case notifications
  case timeline
  case search
  case feedback
  case privacy
  case policy
  case administration
  case compliance
  case health
  case recovery(HermesRecoveryIssueCategory)

  public static let allCases: [HermesNativeUIRoute] = [
    .onboarding, .dashboard, .logs, .settings, .diagnostics, .update, .notifications, .timeline,
    .search, .feedback, .privacy, .policy, .administration, .compliance, .health,
  ]

  public var windowIdentifier: HermesNativeUIWindowIdentifier {
    switch self {
    case .onboarding:
      return .onboarding
    case .dashboard:
      return .dashboard
    case .logs:
      return .logs
    case .settings:
      return .settings
    case .diagnostics:
      return .diagnostics
    case .update:
      return .update
    case .notifications:
      return .notifications
    case .timeline:
      return .timeline
    case .search:
      return .search
    case .feedback:
      return .feedback
    case .privacy:
      return .privacy
    case .policy:
      return .policy
    case .administration:
      return .administration
    case .compliance:
      return .compliance
    case .health:
      return .health
    case .recovery:
      return .recovery
    }
  }
}

@MainActor
public final class HermesNativeUIRouter {
  private let windowCoordinator: HermesWindowCoordinator

  public init(windowCoordinator: HermesWindowCoordinator) {
    self.windowCoordinator = windowCoordinator
  }

  public func openDashboard() {
    open(.dashboard)
  }

  public func openOnboarding() {
    open(.onboarding)
  }

  public func openLogs() {
    open(.logs)
  }

  public func openSettings() {
    open(.settings)
  }

  public func openDiagnostics() {
    open(.diagnostics)
  }

  public func openUpdateCenter() {
    open(.update)
  }

  public func openNotifications() {
    open(.notifications)
  }

  public func openTimeline() {
    open(.timeline)
  }

  public func openSearchCenter() {
    open(.search)
  }

  public func openFeedbackCenter() {
    open(.feedback)
  }

  public func openPrivacyCenter() {
    open(.privacy)
  }

  public func openPolicyCenter() {
    open(.policy)
  }

  public func openAdministrationCenter() {
    open(.administration)
  }

  public func openComplianceCenter() {
    open(.compliance)
  }

  public func openHealthCenter() {
    open(.health)
  }

  public func openRecovery(issue: HermesRecoveryIssueCategory) {
    open(.recovery(issue))
  }

  public func open(_ route: HermesNativeUIRoute) {
    if case .recovery(let issue) = route {
      Task {
        await windowCoordinator.clientGraph.recoveryCoordinator.evaluate(issue: issue)
        windowCoordinator.open(route.windowIdentifier)
      }
      return
    }
    windowCoordinator.open(route.windowIdentifier)
  }
}
