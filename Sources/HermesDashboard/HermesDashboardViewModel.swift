import Foundation
import SwiftUI

@MainActor
public final class HermesDashboardViewModel: ObservableObject {
  @Published public private(set) var state: HermesDashboardState

  private let controller: HermesDashboardController
  private var subscriptionStarted = false

  public init(controller: HermesDashboardController) {
    self.controller = controller
    self.state = HermesDashboardState()
  }

  public convenience init(commandAPI: HermesDashboardRuntimeCommandExecuting) {
    self.init(controller: HermesDashboardController(commandAPI: commandAPI))
  }

  public func load() {
    startEventSubscription()
    Task {
      state = await controller.load()
    }
  }

  public func startEventSubscription() {
    guard !subscriptionStarted else { return }
    subscriptionStarted = true
    let controller = controller
    Task { [weak self, controller] in
      await controller.startEventSubscription { [weak self] newState in
        await MainActor.run {
          self?.state = newState
        }
      }
      let currentState = await controller.currentState()
      await MainActor.run {
        self?.state = currentState
      }
    }
  }

  public func startHermes() {
    Task {
      state = await controller.startHermes()
    }
  }

  public func stopHermes() {
    Task {
      state = await controller.stopHermes()
    }
  }

  public func restartHermes() {
    Task {
      state = await controller.restartHermes()
    }
  }

  public func refreshStatus() {
    Task {
      state = await controller.refreshStatus()
    }
  }

  public func cancel() {
    Task {
      await controller.cancel()
    }
  }
}
