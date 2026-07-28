import Foundation
import SwiftUI

@MainActor
public final class HermesReportingViewModel: ObservableObject {
  @Published public private(set) var snapshot: HermesReportingSnapshot
  @Published public private(set) var lastGeneratedDocument: HermesReportDocument?
  @Published public private(set) var isRefreshing = false
  @Published public private(set) var lastErrorMessage: String?

  private let center: HermesReportingCenter
  private let openSettingsAction: @MainActor () -> Void
  private let openAdministrationCenterAction: @MainActor () -> Void

  public init(
    center: HermesReportingCenter,
    openSettings: @escaping @MainActor () -> Void = {},
    openAdministrationCenter: @escaping @MainActor () -> Void = {}
  ) {
    self.center = center
    self.openSettingsAction = openSettings
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

  public func generate(format: HermesReportFormat) {
    guard !isRefreshing else { return }
    isRefreshing = true
    Task {
      do {
        lastGeneratedDocument = try await center.generate(format: format)
        snapshot = await center.snapshot()
        lastErrorMessage = nil
      } catch {
        lastErrorMessage = HermesReportingRedactor.safeText(String(describing: error), limit: 180)
      }
      isRefreshing = false
    }
  }

  public func saveLastGeneratedReport() {
    guard let document = lastGeneratedDocument else { return }
    do {
      _ = try center.save(document)
      Task {
        snapshot = await center.snapshot()
      }
      lastErrorMessage = nil
    } catch {
      lastErrorMessage = HermesReportingRedactor.safeText(String(describing: error), limit: 180)
    }
  }

  public func openSettings() {
    openSettingsAction()
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
      "network: \(snapshot.networkAvailable ? "yes" : "no")",
      "filesystem scan: \(snapshot.filesystemScanAvailable ? "yes" : "no")",
    ].joined(separator: " | ")
  }
}
