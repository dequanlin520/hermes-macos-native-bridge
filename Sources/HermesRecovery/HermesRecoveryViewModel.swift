import Foundation
import SwiftUI

@MainActor
public final class HermesRecoveryViewModel: ObservableObject {
  @Published public private(set) var snapshot: HermesRecoverySnapshot
  @Published public private(set) var isWorking = false

  private let coordinator: HermesRecoveryCoordinator
  private let openDiagnostics: @MainActor () -> Void
  private let openUpdateCenter: @MainActor () -> Void
  private let rerunReadiness: @MainActor () -> Void
  private let dismiss: @MainActor () -> Void

  public init(
    coordinator: HermesRecoveryCoordinator,
    openDiagnostics: @escaping @MainActor () -> Void = {},
    openUpdateCenter: @escaping @MainActor () -> Void = {},
    rerunReadiness: @escaping @MainActor () -> Void = {},
    dismiss: @escaping @MainActor () -> Void = {}
  ) {
    self.coordinator = coordinator
    self.openDiagnostics = openDiagnostics
    self.openUpdateCenter = openUpdateCenter
    self.rerunReadiness = rerunReadiness
    self.dismiss = dismiss
    self.snapshot = coordinator.currentSnapshot
  }

  public func evaluate(issue: HermesRecoveryIssueCategory) {
    guard !isWorking else { return }
    isWorking = true
    Task {
      snapshot = await coordinator.evaluate(issue: issue)
      isWorking = false
    }
  }

  public func perform(_ action: HermesRecoveryActionType, confirmed: Bool = false) {
    switch action {
    case .openDiagnostics:
      openDiagnostics()
      return
    case .showUpgradeRequired:
      openUpdateCenter()
      return
    case .dismiss:
      dismiss()
      return
    default:
      break
    }
    guard !isWorking else { return }
    isWorking = true
    Task {
      snapshot = await coordinator.perform(action, confirmed: confirmed)
      if snapshot.state == .recovered {
        rerunReadiness()
      }
      isWorking = false
    }
  }
}
