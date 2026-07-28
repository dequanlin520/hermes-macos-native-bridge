import Foundation
import HermesRecovery
import SwiftUI

@MainActor
public final class HermesDiagnosticsViewModel: ObservableObject {
  @Published public private(set) var state: HermesDiagnosticsState

  private let controller: HermesDiagnosticsController
  private let reopenOnboardingAction: @MainActor () -> Void
  private let openRecoveryAction: @MainActor (HermesRecoveryIssueCategory) -> Void
  private let openUpdateCenterAction: @MainActor () -> Void

  public init(
    controller: HermesDiagnosticsController,
    reopenOnboarding: @escaping @MainActor () -> Void = {},
    openRecovery: @escaping @MainActor (HermesRecoveryIssueCategory) -> Void = { _ in },
    openUpdateCenter: @escaping @MainActor () -> Void = {}
  ) {
    self.controller = controller
    self.reopenOnboardingAction = reopenOnboarding
    self.openRecoveryAction = openRecovery
    self.openUpdateCenterAction = openUpdateCenter
    self.state = HermesDiagnosticsState()
  }

  public convenience init(
    provider: HermesDiagnosticProviding,
    reopenOnboarding: @escaping @MainActor () -> Void = {},
    openRecovery: @escaping @MainActor (HermesRecoveryIssueCategory) -> Void = { _ in },
    openUpdateCenter: @escaping @MainActor () -> Void = {}
  ) {
    self.init(
      controller: HermesDiagnosticsController(provider: provider),
      reopenOnboarding: reopenOnboarding,
      openRecovery: openRecovery,
      openUpdateCenter: openUpdateCenter
    )
  }

  public func refresh() {
    Task {
      state = await controller.refresh()
    }
  }

  public func runDiagnostics() {
    Task {
      state = await controller.runDiagnostics()
    }
  }

  public func reopenOnboarding() {
    reopenOnboardingAction()
  }

  public func openRecovery() {
    openRecoveryAction(recoveryIssue)
  }

  public func openUpdateCenter() {
    openUpdateCenterAction()
  }

  public var recoveryIssue: HermesRecoveryIssueCategory {
    guard let result = state.result else { return .unknownReadinessFailure }
    if let permission = result.environmentInfo.permissionStates.first(where: { permission in
      permission.state == "denied" || permission.state == "restricted"
        || permission.state == "notDetermined" || permission.state == "misconfigured"
    }) {
      switch permission.kind {
      case "accessibility": return .accessibilityPermissionMissing
      case "automation": return .automationPermissionMissing
      case "screenRecording": return .screenRecordingPermissionMissing
      case "notifications": return .notificationsPermissionMissing
      default: break
      }
    }
    if result.healthSummary.discoveryState == .unavailable {
      return .agentUnavailable
    }
    if result.healthSummary.processState == .unavailable || result.healthSummary.backendState == .unavailable {
      return .bridgeServiceUnavailable
    }
    if result.healthSummary.backendState == .failed {
      return .xpcConnectionFailed
    }
    return .unknownReadinessFailure
  }
}
