import Foundation
import SwiftUI

@MainActor
public final class HermesOperationsViewModel: ObservableObject {
  @Published public private(set) var snapshot: HermesOperationsSnapshot
  @Published public private(set) var isRefreshing = false
  @Published public private(set) var lastErrorMessage: String?

  private let center: HermesOperationsCenter
  private let openSettingsAction: @MainActor () -> Void
  private let openDiagnosticsAction: @MainActor () -> Void
  private let openAdministrationCenterAction: @MainActor () -> Void

  public init(
    center: HermesOperationsCenter,
    openSettings: @escaping @MainActor () -> Void = {},
    openDiagnostics: @escaping @MainActor () -> Void = {},
    openAdministrationCenter: @escaping @MainActor () -> Void = {}
  ) {
    self.center = center
    self.openSettingsAction = openSettings
    self.openDiagnosticsAction = openDiagnostics
    self.openAdministrationCenterAction = openAdministrationCenter
    self.snapshot = .empty
  }

  public func refresh() {
    guard !isRefreshing else { return }
    isRefreshing = true
    Task {
      snapshot = await center.snapshot()
      lastErrorMessage = nil
      isRefreshing = false
    }
  }

  public func openSettings() {
    openSettingsAction()
  }

  public func openDiagnostics() {
    openDiagnosticsAction()
  }

  public func openAdministrationCenter() {
    openAdministrationCenterAction()
  }

  public var boundarySummary: String {
    [
      "read only: \(snapshot.readOnly ? "yes" : "no")",
      "app owns runtime: \(snapshot.appOwnsRuntime ? "yes" : "no")",
      "process execution: \(snapshot.processExecutionAvailable ? "yes" : "no")",
      "shell: \(snapshot.shellAvailable ? "yes" : "no")",
      "upload: \(snapshot.uploadAvailable ? "yes" : "no")",
      "filesystem scan: \(snapshot.filesystemScanAvailable ? "yes" : "no")",
      "sensitive persistence: \(snapshot.sensitiveDataPersistenceAvailable ? "yes" : "no")",
    ].joined(separator: " | ")
  }
}
