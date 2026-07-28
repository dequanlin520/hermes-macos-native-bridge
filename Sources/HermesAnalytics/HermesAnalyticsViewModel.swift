import Foundation
import SwiftUI

@MainActor
public final class HermesAnalyticsViewModel: ObservableObject {
  @Published public private(set) var snapshot: HermesAnalyticsSnapshot
  @Published public private(set) var isRefreshing = false
  @Published public private(set) var lastErrorMessage: String?

  private let center: HermesAnalyticsCenter
  private let openSettingsAction: @MainActor () -> Void
  private let openAdministrationCenterAction: @MainActor () -> Void
  private let openOperationsCenterAction: @MainActor () -> Void
  private let openReportingCenterAction: @MainActor () -> Void

  public init(
    center: HermesAnalyticsCenter,
    openSettings: @escaping @MainActor () -> Void = {},
    openAdministrationCenter: @escaping @MainActor () -> Void = {},
    openOperationsCenter: @escaping @MainActor () -> Void = {},
    openReportingCenter: @escaping @MainActor () -> Void = {}
  ) {
    self.center = center
    self.openSettingsAction = openSettings
    self.openAdministrationCenterAction = openAdministrationCenter
    self.openOperationsCenterAction = openOperationsCenter
    self.openReportingCenterAction = openReportingCenter
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

  public func openAdministrationCenter() {
    openAdministrationCenterAction()
  }

  public func openOperationsCenter() {
    openOperationsCenterAction()
  }

  public func openReportingCenter() {
    openReportingCenterAction()
  }

  public var boundarySummary: String {
    [
      "read only: \(snapshot.readOnly ? "yes" : "no")",
      "app owns runtime: \(snapshot.appOwnsRuntime ? "yes" : "no")",
      "process execution: \(snapshot.processExecutionAvailable ? "yes" : "no")",
      "shell: \(snapshot.shellAvailable ? "yes" : "no")",
      "upload: \(snapshot.uploadAvailable ? "yes" : "no")",
      "filesystem scan: \(snapshot.filesystemScanAvailable ? "yes" : "no")",
    ].joined(separator: " | ")
  }
}
