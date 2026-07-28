import Foundation
import SwiftUI

@MainActor
public final class HermesHealthViewModel: ObservableObject {
  @Published public private(set) var snapshot: HermesHealthSnapshot
  @Published public private(set) var isRefreshing = false
  @Published public private(set) var lastErrorMessage: String?

  private let center: HermesHealthCenter
  private let openSettingsAction: @MainActor () -> Void
  private let openDiagnosticsAction: @MainActor () -> Void
  private let openAdministrationCenterAction: @MainActor () -> Void

  public init(
    center: HermesHealthCenter,
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
      "automatic repair: \(snapshot.automaticRepairAvailable ? "yes" : "no")",
      "process execution: \(snapshot.processExecutionAvailable ? "yes" : "no")",
      "shell: \(snapshot.shellAvailable ? "yes" : "no")",
      "upload: \(snapshot.uploadAvailable ? "yes" : "no")",
      "filesystem scan: \(snapshot.filesystemScanAvailable ? "yes" : "no")",
    ].joined(separator: " | ")
  }
}
