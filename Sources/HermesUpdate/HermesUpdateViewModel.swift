import Foundation
import SwiftUI

@MainActor
public final class HermesUpdateViewModel: ObservableObject {
  @Published public private(set) var snapshot: HermesUpdateSnapshot
  @Published public private(set) var isWorking = false

  private let coordinator: HermesUpdateCoordinator
  private let openDiagnostics: @MainActor () -> Void
  private let openRecovery: @MainActor () -> Void

  public init(
    coordinator: HermesUpdateCoordinator,
    openDiagnostics: @escaping @MainActor () -> Void = {},
    openRecovery: @escaping @MainActor () -> Void = {}
  ) {
    self.coordinator = coordinator
    self.openDiagnostics = openDiagnostics
    self.openRecovery = openRecovery
    self.snapshot = HermesUpdateSnapshot()
    Task {
      snapshot = await coordinator.currentSnapshot
    }
  }

  public func checkForUpdate() {
    run { [coordinator] in
      await coordinator.checkForUpdate()
    }
  }

  public func validateAvailableUpdate() {
    run { [coordinator] in
      await coordinator.validateAvailableUpdate()
    }
  }

  public func activateConfirmed() {
    run { [coordinator] in
      await coordinator.activateConfirmed()
    }
  }

  public func prepareRollback() {
    run { [coordinator] in
      await coordinator.prepareRollback()
    }
  }

  public func rollbackConfirmed() {
    run { [coordinator] in
      await coordinator.rollbackConfirmed()
    }
  }

  public func windowClosed() {
    Task {
      snapshot = await coordinator.windowClosed()
    }
  }

  public func showDiagnostics() {
    openDiagnostics()
  }

  public func showRecovery() {
    openRecovery()
  }

  private func run(_ action: @escaping @Sendable () async -> HermesUpdateSnapshot) {
    guard !isWorking else { return }
    isWorking = true
    Task {
      snapshot = await action()
      isWorking = false
    }
  }
}
