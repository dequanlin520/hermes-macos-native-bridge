import Foundation
import SwiftUI

@MainActor
public final class HermesAdminViewModel: ObservableObject {
  @Published public private(set) var snapshot: HermesAdminSnapshot
  @Published public private(set) var preferences: HermesAdminPreferences
  @Published public private(set) var isRefreshing = false
  @Published public private(set) var lastErrorMessage: String?

  private let center: HermesAdminCenter
  private let openSettingsAction: @MainActor () -> Void
  private let openDiagnosticsAction: @MainActor () -> Void
  private let openPolicyCenterAction: @MainActor () -> Void
  private let openComplianceCenterAction: @MainActor () -> Void
  private let openHealthCenterAction: @MainActor () -> Void
  private let openOperationsCenterAction: @MainActor () -> Void
  private let openAnalyticsCenterAction: @MainActor () -> Void

  public init(
    center: HermesAdminCenter,
    openSettings: @escaping @MainActor () -> Void = {},
    openDiagnostics: @escaping @MainActor () -> Void = {},
    openPolicyCenter: @escaping @MainActor () -> Void = {},
    openComplianceCenter: @escaping @MainActor () -> Void = {},
    openHealthCenter: @escaping @MainActor () -> Void = {},
    openOperationsCenter: @escaping @MainActor () -> Void = {},
    openAnalyticsCenter: @escaping @MainActor () -> Void = {}
  ) {
    self.center = center
    self.openSettingsAction = openSettings
    self.openDiagnosticsAction = openDiagnostics
    self.openPolicyCenterAction = openPolicyCenter
    self.openComplianceCenterAction = openComplianceCenter
    self.openHealthCenterAction = openHealthCenter
    self.openOperationsCenterAction = openOperationsCenter
    self.openAnalyticsCenterAction = openAnalyticsCenter
    self.snapshot = .empty
    self.preferences = (try? center.loadPreferences()) ?? HermesAdminPreferences()
  }

  public func refresh() {
    guard !isRefreshing else { return }
    isRefreshing = true
    Task {
      snapshot = await center.snapshot()
      preferences = (try? center.loadPreferences()) ?? preferences
      lastErrorMessage = nil
      isRefreshing = false
    }
  }

  public func setShowComplianceStatus(_ show: Bool) {
    preferences.showComplianceStatus = show
    savePreferences()
  }

  public func setVisibleAuditLimit(_ limit: Int) {
    preferences.visibleAuditLimit = min(max(0, limit), 25)
    savePreferences()
    refresh()
  }

  public func openSettings() {
    openSettingsAction()
  }

  public func openDiagnostics() {
    openDiagnosticsAction()
  }

  public func openPolicyCenter() {
    openPolicyCenterAction()
  }

  public func openComplianceCenter() {
    openComplianceCenterAction()
  }

  public func openHealthCenter() {
    openHealthCenterAction()
  }

  public func openOperationsCenter() {
    openOperationsCenterAction()
  }

  public func openAnalyticsCenter() {
    openAnalyticsCenterAction()
  }

  public var boundarySummary: String {
    [
      "safe DTO only",
      "audit read only: \(snapshot.auditReadOnly ? "yes" : "no")",
      "app owns runtime: \(snapshot.appOwnsRuntime ? "yes" : "no")",
      "arbitrary action: \(snapshot.arbitraryActionAvailable ? "yes" : "no")",
    ].joined(separator: " | ")
  }

  private func savePreferences() {
    do {
      try center.savePreferences(preferences)
      lastErrorMessage = nil
    } catch {
      lastErrorMessage = HermesAdminRedactor.safeText(String(describing: error), limit: 180)
    }
  }
}
