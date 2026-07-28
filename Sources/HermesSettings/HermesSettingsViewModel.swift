import Foundation
import SwiftUI

@MainActor
public final class HermesSettingsViewModel: ObservableObject {
  @Published public private(set) var state: HermesSettingsState
  @Published public var draftSettings: HermesSettings

  private let controller: HermesSettingsController
  private let reopenOnboardingAction: @MainActor () -> Void

  public init(
    controller: HermesSettingsController,
    reopenOnboarding: @escaping @MainActor () -> Void = {}
  ) {
    self.controller = controller
    self.reopenOnboardingAction = reopenOnboarding
    self.state = HermesSettingsState()
    self.draftSettings = .defaults
  }

  public convenience init(
    store: HermesConfigurationStoring = HermesConfigurationStore(),
    reopenOnboarding: @escaping @MainActor () -> Void = {}
  ) {
    self.init(
      controller: HermesSettingsController(store: store),
      reopenOnboarding: reopenOnboarding
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
}
