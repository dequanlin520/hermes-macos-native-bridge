import Foundation
import HermesRecovery

public enum HermesNativeUIRoute: Equatable, Sendable {
  case onboarding
  case dashboard
  case logs
  case settings
  case diagnostics
  case update
  case notifications
  case recovery(HermesRecoveryIssueCategory)

  public static let allCases: [HermesNativeUIRoute] = [
    .onboarding, .dashboard, .logs, .settings, .diagnostics, .update, .notifications,
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
