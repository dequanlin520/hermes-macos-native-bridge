import AppKit
import Foundation
import HermesRecovery
import HermesRuntimeFoundation
import SwiftUI

@MainActor
public final class HermesOnboardingViewModel: ObservableObject {
  @Published public private(set) var snapshot: HermesOnboardingSnapshot
  @Published public private(set) var isWorking = false

  private let coordinator: HermesOnboardingCoordinator
  private let openDiagnostics: @MainActor () -> Void
  private let openPrivacyCenter: @MainActor () -> Void
  private let openRecovery: @MainActor (HermesRecoveryIssueCategory) -> Void
  private let finishHandler: @MainActor () -> Void
  private let systemSettingsOpener: @MainActor (HermesOnboardingPermissionKind) -> Void

  public init(
    coordinator: HermesOnboardingCoordinator,
    openDiagnostics: @escaping @MainActor () -> Void = {},
    openPrivacyCenter: @escaping @MainActor () -> Void = {},
    openRecovery: @escaping @MainActor (HermesRecoveryIssueCategory) -> Void = { _ in },
    finishHandler: @escaping @MainActor () -> Void = {},
    systemSettingsOpener: @escaping @MainActor (HermesOnboardingPermissionKind) -> Void = {
      HermesOnboardingSystemSettings.open(permission: $0)
    }
  ) {
    self.coordinator = coordinator
    self.openDiagnostics = openDiagnostics
    self.openPrivacyCenter = openPrivacyCenter
    self.openRecovery = openRecovery
    self.finishHandler = finishHandler
    self.systemSettingsOpener = systemSettingsOpener
    self.snapshot = coordinator.currentSnapshot
  }

  public func continueOnboarding() {
    guard !isWorking else { return }
    isWorking = true
    Task {
      snapshot = await coordinator.advance()
      isWorking = false
    }
  }

  public func retry() {
    guard !isWorking else { return }
    isWorking = true
    Task {
      snapshot = await coordinator.retry()
      isWorking = false
    }
  }

  public func finish() {
    snapshot = coordinator.finish()
    finishHandler()
  }

  public func perform(_ action: HermesOnboardingRemediationAction) {
    switch action {
    case .retry:
      retry()
    case .continue:
      continueOnboarding()
    case .openSystemSettings(let permission):
      systemSettingsOpener(permission)
    case .openDiagnostics:
      openDiagnostics()
    case .openPrivacyCenter:
      openPrivacyCenter()
    case .openRecovery(let issue):
      openRecovery(issue)
    case .reopenOnboarding:
      snapshot = coordinator.beginManualReopen()
    case .finish:
      finish()
    }
  }
}

public enum HermesOnboardingSystemSettings {
  @MainActor
  public static func open(permission: HermesOnboardingPermissionKind) {
    let url: URL
    switch permission {
    case .accessibility:
      url = HermesSystemSettingsRemediationURL.accessibility
    case .automation:
      url = HermesSystemSettingsRemediationURL.automation
    case .screenRecording:
      url = HermesSystemSettingsRemediationURL.screenRecording
    case .notifications:
      url = HermesSystemSettingsRemediationURL.notifications
    case .inputMonitoring, .fullDiskAccess, .microphone, .camera:
      return
    }
    NSWorkspace.shared.open(url)
  }
}
