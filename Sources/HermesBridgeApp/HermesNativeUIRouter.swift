import Foundation

public enum HermesNativeUIRoute: CaseIterable, Equatable, Sendable {
  case onboarding
  case dashboard
  case logs
  case settings
  case diagnostics

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

  public func open(_ route: HermesNativeUIRoute) {
    windowCoordinator.open(route.windowIdentifier)
  }
}
