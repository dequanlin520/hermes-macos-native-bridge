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
  private let openFeedbackCenterAction: @MainActor () -> Void
  private let openPrivacyCenterAction: @MainActor () -> Void
  private let openPolicyCenterAction: @MainActor () -> Void
  private let openAdministrationCenterAction: @MainActor () -> Void

  public init(
    controller: HermesDiagnosticsController,
    reopenOnboarding: @escaping @MainActor () -> Void = {},
    openRecovery: @escaping @MainActor (HermesRecoveryIssueCategory) -> Void = { _ in },
    openUpdateCenter: @escaping @MainActor () -> Void = {},
    openFeedbackCenter: @escaping @MainActor () -> Void = {},
    openPrivacyCenter: @escaping @MainActor () -> Void = {},
    openPolicyCenter: @escaping @MainActor () -> Void = {},
    openAdministrationCenter: @escaping @MainActor () -> Void = {}
  ) {
    self.controller = controller
    self.reopenOnboardingAction = reopenOnboarding
    self.openRecoveryAction = openRecovery
    self.openUpdateCenterAction = openUpdateCenter
    self.openFeedbackCenterAction = openFeedbackCenter
    self.openPrivacyCenterAction = openPrivacyCenter
    self.openPolicyCenterAction = openPolicyCenter
    self.openAdministrationCenterAction = openAdministrationCenter
    self.state = HermesDiagnosticsState()
  }

  public convenience init(
    provider: HermesDiagnosticProviding,
    reopenOnboarding: @escaping @MainActor () -> Void = {},
    openRecovery: @escaping @MainActor (HermesRecoveryIssueCategory) -> Void = { _ in },
    openUpdateCenter: @escaping @MainActor () -> Void = {},
    openFeedbackCenter: @escaping @MainActor () -> Void = {},
    openPrivacyCenter: @escaping @MainActor () -> Void = {},
    openPolicyCenter: @escaping @MainActor () -> Void = {},
    openAdministrationCenter: @escaping @MainActor () -> Void = {}
  ) {
    self.init(
      controller: HermesDiagnosticsController(provider: provider),
      reopenOnboarding: reopenOnboarding,
      openRecovery: openRecovery,
      openUpdateCenter: openUpdateCenter,
      openFeedbackCenter: openFeedbackCenter,
      openPrivacyCenter: openPrivacyCenter,
      openPolicyCenter: openPolicyCenter,
      openAdministrationCenter: openAdministrationCenter
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

  public func openFeedbackCenter() {
    openFeedbackCenterAction()
  }

  public func openPrivacyCenter() {
    openPrivacyCenterAction()
  }

  public func openPolicyCenter() {
    openPolicyCenterAction()
  }

  public func openAdministrationCenter() {
    openAdministrationCenterAction()
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
