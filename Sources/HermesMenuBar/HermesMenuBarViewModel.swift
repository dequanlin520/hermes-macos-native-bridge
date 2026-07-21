import Foundation
import HermesRuntimeFoundation
import SwiftUI

@MainActor
public final class HermesMenuBarViewModel: ObservableObject {
  @Published public private(set) var state: HermesMenuBarState

  private let controller: HermesMenuBarController
  private var subscriptionStarted = false

  public init(controller: HermesMenuBarController) {
    self.controller = controller
    self.state = HermesMenuBarState()
  }

  public convenience init(commandAPI: HermesRuntimeCommandExecuting) {
    self.init(controller: HermesMenuBarController(commandAPI: commandAPI))
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

  public func refreshStatus() {
    Task {
      state = await controller.refreshStatus()
    }
  }

  public func openEventsView() {
    state.eventsViewOpenRequested = true
    Task {
      state = await controller.openEventsView()
    }
  }

  public func acknowledgeEventsViewRequest() {
    Task {
      await controller.acknowledgeEventsViewRequest()
      state = await controller.currentState()
    }
  }

  public func cancel() {
    Task {
      await controller.cancel()
    }
  }
}

public enum HermesMenuBarRuntimeFactory {
  public static func productionCommandAPI() -> HermesRuntimeCommandAPI {
    let runtimeRoot = FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first?
      .appendingPathComponent("HermesMenuBar", isDirectory: true)
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("HermesMenuBar", isDirectory: true)

    let executableCandidates = [
      URL(fileURLWithPath: "/opt/homebrew/bin/hermes"),
      URL(fileURLWithPath: "/usr/local/bin/hermes"),
    ]
    let configuration = HermesBackendAdapterConfiguration(
      executableURL: executableCandidates[0],
      port: 19123,
      runtimeRoot: runtimeRoot
    )
    let manager = HermesRuntimeSessionManager(
      backendFactory: {
        HermesBackendAdapter(
          allowlistedExecutableCandidates: executableCandidates,
          configuration: configuration
        )
      }
    )
    return HermesRuntimeCommandAPI(sessionManager: manager)
  }
}
