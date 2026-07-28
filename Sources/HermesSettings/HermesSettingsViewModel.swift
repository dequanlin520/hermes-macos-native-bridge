import Foundation
import SwiftUI

@MainActor
public final class HermesSettingsViewModel: ObservableObject {
  @Published public private(set) var state: HermesSettingsState
  @Published public var draftSettings: HermesSettings

  private let controller: HermesSettingsController
  private let reopenOnboardingAction: @MainActor () -> Void
  private let openUpdateCenterAction: @MainActor () -> Void
  private let openPrivacyCenterAction: @MainActor () -> Void
  private let openPolicyCenterAction: @MainActor () -> Void
  private let openAdministrationCenterAction: @MainActor () -> Void
  private let openComplianceCenterAction: @MainActor () -> Void
  private let openHealthCenterAction: @MainActor () -> Void
  private let openOperationsCenterAction: @MainActor () -> Void
  private let openAnalyticsCenterAction: @MainActor () -> Void
  private let openReportingCenterAction: @MainActor () -> Void

  public init(
    controller: HermesSettingsController,
    reopenOnboarding: @escaping @MainActor () -> Void = {},
    openUpdateCenter: @escaping @MainActor () -> Void = {},
    openPrivacyCenter: @escaping @MainActor () -> Void = {},
    openPolicyCenter: @escaping @MainActor () -> Void = {},
    openAdministrationCenter: @escaping @MainActor () -> Void = {},
    openComplianceCenter: @escaping @MainActor () -> Void = {},
    openHealthCenter: @escaping @MainActor () -> Void = {},
    openOperationsCenter: @escaping @MainActor () -> Void = {},
    openAnalyticsCenter: @escaping @MainActor () -> Void = {},
    openReportingCenter: @escaping @MainActor () -> Void = {}
  ) {
    self.controller = controller
    self.reopenOnboardingAction = reopenOnboarding
    self.openUpdateCenterAction = openUpdateCenter
    self.openPrivacyCenterAction = openPrivacyCenter
    self.openPolicyCenterAction = openPolicyCenter
    self.openAdministrationCenterAction = openAdministrationCenter
    self.openComplianceCenterAction = openComplianceCenter
    self.openHealthCenterAction = openHealthCenter
    self.openOperationsCenterAction = openOperationsCenter
    self.openAnalyticsCenterAction = openAnalyticsCenter
    self.openReportingCenterAction = openReportingCenter
    self.state = HermesSettingsState()
    self.draftSettings = .defaults
  }

  public convenience init(
    store: HermesConfigurationStoring = HermesConfigurationStore(),
    reopenOnboarding: @escaping @MainActor () -> Void = {},
    openUpdateCenter: @escaping @MainActor () -> Void = {},
    openPrivacyCenter: @escaping @MainActor () -> Void = {},
    openPolicyCenter: @escaping @MainActor () -> Void = {},
    openAdministrationCenter: @escaping @MainActor () -> Void = {},
    openComplianceCenter: @escaping @MainActor () -> Void = {},
    openHealthCenter: @escaping @MainActor () -> Void = {},
    openOperationsCenter: @escaping @MainActor () -> Void = {},
    openAnalyticsCenter: @escaping @MainActor () -> Void = {},
    openReportingCenter: @escaping @MainActor () -> Void = {}
  ) {
    self.init(
      controller: HermesSettingsController(store: store),
      reopenOnboarding: reopenOnboarding,
      openUpdateCenter: openUpdateCenter,
      openPrivacyCenter: openPrivacyCenter,
      openPolicyCenter: openPolicyCenter,
      openAdministrationCenter: openAdministrationCenter,
      openComplianceCenter: openComplianceCenter,
      openHealthCenter: openHealthCenter,
      openOperationsCenter: openOperationsCenter,
      openAnalyticsCenter: openAnalyticsCenter,
      openReportingCenter: openReportingCenter
    )
  }

  public func load() {
    Task {
      let newState = await controller.load()
      state = newState
      draftSettings = newState.settings
    }
  }

  public func save() {
    let draft = draftSettings
    Task {
      var newState = await controller.update(draft)
      if newState.lastErrorMessage == nil {
        newState = await controller.save()
      }
      state = newState
      draftSettings = newState.settings
    }
  }

  public func resetDraft() {
    draftSettings = state.settings
  }

  public func reopenOnboarding() {
    reopenOnboardingAction()
  }

  public func openUpdateCenter() {
    openUpdateCenterAction()
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

  public func openComplianceCenter() {
    openComplianceCenterAction()
  }

  public func openHealthCenter() {
    openHealthCenterAction()
  }

  public func openOperationsCenter() {
    openOperationsCenterAction()
  }

  public func openAnalyticsCenter() {
    openAnalyticsCenterAction()
  }

  public func openReportingCenter() {
    openReportingCenterAction()
  }
}
