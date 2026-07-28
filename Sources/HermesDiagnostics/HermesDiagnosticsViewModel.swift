import Foundation
import SwiftUI

@MainActor
public final class HermesDiagnosticsViewModel: ObservableObject {
  @Published public private(set) var state: HermesDiagnosticsState

  private let controller: HermesDiagnosticsController
  private let reopenOnboardingAction: @MainActor () -> Void

  public init(
    controller: HermesDiagnosticsController,
    reopenOnboarding: @escaping @MainActor () -> Void = {}
  ) {
    self.controller = controller
    self.reopenOnboardingAction = reopenOnboarding
    self.state = HermesDiagnosticsState()
  }

  public convenience init(
    provider: HermesDiagnosticProviding,
    reopenOnboarding: @escaping @MainActor () -> Void = {}
  ) {
    self.init(
      controller: HermesDiagnosticsController(provider: provider),
      reopenOnboarding: reopenOnboarding
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
}
