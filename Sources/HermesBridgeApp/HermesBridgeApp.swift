import AppKit
import SwiftUI

@main
struct HermesBridgeApp: App {
  @NSApplicationDelegateAdaptor(HermesBridgeAppDelegate.self) private var appDelegate
  @StateObject private var compositionRoot = HermesAppCompositionRoot()
  @State private var acceptanceController: HermesM11003AcceptanceController?

  init() {
    if var controller = HermesM11003AcceptanceController.fromCommandLine() {
      _acceptanceController = State(initialValue: nil)
      Task { @MainActor in
        controller.startIfNeeded(compositionRoot: HermesAppCompositionRoot())
      }
    } else {
      _acceptanceController = State(initialValue: nil)
    }
  }

  var body: some Scene {
    MenuBarExtra("Hermes Bridge", systemImage: "point.3.connected.trianglepath.dotted") {
      HermesBridgeMenuBarContent(compositionRoot: compositionRoot)
        .onAppear {
          appDelegate.compositionRoot = compositionRoot
          compositionRoot.start()
          acceptanceController?.startIfNeeded(compositionRoot: compositionRoot)
        }
    }
    .menuBarExtraStyle(.window)
  }
}

@MainActor
final class HermesBridgeAppDelegate: NSObject, NSApplicationDelegate {
  weak var compositionRoot: HermesAppCompositionRoot?
  private var isTerminating = false

  func applicationDidFinishLaunching(_: Notification) {
    NSApp.setActivationPolicy(.accessory)
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !isTerminating else { return .terminateNow }
    isTerminating = true
    Task { @MainActor [weak self, weak sender] in
      await self?.compositionRoot?.shutdown()
      sender?.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
}

struct HermesBridgeMenuBarContent: View {
  @ObservedObject var compositionRoot: HermesAppCompositionRoot

  var body: some View {
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
      Button("Settings") {
        compositionRoot.router.openSettings()
      }
      Button("Diagnostics") {
        compositionRoot.router.openDiagnostics()
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
