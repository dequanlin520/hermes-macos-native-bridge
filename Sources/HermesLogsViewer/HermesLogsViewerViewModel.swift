import Foundation
import HermesRuntimeFoundation
import SwiftUI

@MainActor
public final class HermesLogsViewerViewModel: ObservableObject {
  @Published public private(set) var state: HermesLogsViewerState

  private let controller: HermesLogsViewerController
  private var subscriptionStarted = false

  public init(controller: HermesLogsViewerController) {
    self.controller = controller
    self.state = HermesLogsViewerState()
  }

  public convenience init(eventBus: HermesRuntimeEventBus) {
    self.init(controller: HermesLogsViewerController(eventBus: eventBus))
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

  public func setFilter(_ filter: HermesRuntimeLogFilter) {
    Task {
      state = await controller.setFilter(filter)
    }
  }

  public func clearView() {
    Task {
      state = await controller.clearView()
    }
  }

  public func cancel() {
    Task {
      await controller.cancel()
    }
  }
}
