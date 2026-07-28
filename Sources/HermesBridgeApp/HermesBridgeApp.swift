import AppKit
import SwiftUI

@MainActor
public final class HermesBridgeAppDelegate: NSObject, NSApplicationDelegate {
  public weak var compositionRoot: HermesAppCompositionRoot?
  private var isTerminating = false

  public override init() {
    super.init()
  }

  public func applicationDidFinishLaunching(_: Notification) {
    NSApp.setActivationPolicy(.accessory)
  }

  public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !isTerminating else { return .terminateNow }
    isTerminating = true
    Task { @MainActor [weak self, weak sender] in
      await self?.compositionRoot?.shutdown()
      sender?.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
}

public struct HermesBridgeMenuBarContent: View {
  @ObservedObject public var compositionRoot: HermesAppCompositionRoot

  public init(compositionRoot: HermesAppCompositionRoot) {
    self.compositionRoot = compositionRoot
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      statusHeader
      Divider()
      navigation
      Divider()
      runtimeControls
      Divider()
      Button("Quit") {
        NSApplication.shared.terminate(nil)
      }
    }
    .padding(12)
    .frame(width: 300)
  }

  private var statusHeader: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Hermes Bridge")
        .font(.headline)
      Text("Runtime: \(compositionRoot.menuBarViewModel.state.runtimeStatus?.rawValue ?? "unavailable")")
        .foregroundStyle(.secondary)
      Text("Health: \(compositionRoot.menuBarViewModel.state.healthState.rawValue)")
        .foregroundStyle(.secondary)
      if let message = compositionRoot.menuBarViewModel.state.lastErrorMessage {
        Text(message)
          .foregroundStyle(.red)
          .lineLimit(2)
      }
    }
  }

  private var navigation: some View {
    VStack(alignment: .leading, spacing: 6) {
      Button("Dashboard") {
        compositionRoot.router.openDashboard()
      }
      Button("Logs Viewer") {
        compositionRoot.router.openLogs()
      }
      Button("Activity Timeline") {
        compositionRoot.router.openTimeline()
      }
      Button("Search Center") {
        compositionRoot.router.openSearchCenter()
      }
      Button("Feedback Center") {
        compositionRoot.router.openFeedbackCenter()
      }
      Button("Privacy Center") {
        compositionRoot.router.openPrivacyCenter()
      }
      Button("Compliance Center") {
        compositionRoot.router.openComplianceCenter()
      }
      Button("Settings") {
        compositionRoot.router.openSettings()
      }
      Button("Diagnostics") {
        compositionRoot.router.openDiagnostics()
      }
      Button("Update Center") {
        compositionRoot.router.openUpdateCenter()
      }
      Button("First Run Onboarding") {
        compositionRoot.router.openOnboarding()
      }
    }
  }

  private var runtimeControls: some View {
    VStack(alignment: .leading, spacing: 6) {
      Button("Start Hermes") {
        compositionRoot.menuBarViewModel.startHermes()
      }
      .disabled(compositionRoot.menuBarViewModel.state.actionInFlight)

      Button("Stop Hermes") {
        compositionRoot.menuBarViewModel.stopHermes()
      }
      .disabled(compositionRoot.menuBarViewModel.state.actionInFlight)

      Button("Refresh Status") {
        compositionRoot.menuBarViewModel.refreshStatus()
      }
      .disabled(compositionRoot.menuBarViewModel.state.actionInFlight)
    }
  }
}
