import AppIntents
import HermesAppIntents
import HermesBridgeMenuBar
import SwiftUI

@main
struct HermesBridgeApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var model = HermesBridgeAppModel()

  var body: some Scene {
    MenuBarExtra("Hermes Bridge", systemImage: "point.3.connected.trianglepath.dotted") {
      VStack(alignment: .leading, spacing: 8) {
        Text("Hermes Bridge")
          .font(.headline)
        Text("Status: \(model.state.serviceStatus.rawValue)")
        Text("Installed: \(model.state.installed ? "yes" : "no")")
        Text("Running: \(model.state.running ? "yes" : "no")")
        Text("Healthy: \(model.state.healthy ? "yes" : "no")")
        Text("Protocol: \(model.state.protocolVersion ?? "unavailable")")
        Text("Compatible: \(model.state.protocolCompatible ? "yes" : "no")")
        Text("Capabilities: \(model.state.capabilities.joined(separator: ", "))")
          .lineLimit(2)
        Text("Enabled bindings: \(model.state.enabledBindingCount)")
        Divider()
        if model.state.recentRequests.isEmpty {
          Text("Recent requests: none")
        } else {
          ForEach(model.state.recentRequests, id: \.requestID) { request in
            Text("\(request.requestID) \(request.lifecycleState)")
              .lineLimit(1)
          }
        }
        if let message = model.state.lastActionMessage {
          Divider()
          Text(message)
        }
        Divider()
        Button("Refresh") {
          model.refresh()
        }
        Button("Start Service") {
          model.start()
        }
        Button("Restart Service") {
          model.restart()
        }
        Button("Run Doctor") {
          model.doctor()
        }
        Button("Open Shortcuts") {
          NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
        }
        Divider()
        Button("Quit") {
          model.cancel()
          NSApplication.shared.terminate(nil)
        }
      }
      .padding(12)
      .frame(width: 320)
      .task {
        await model.load()
      }
    }
    .menuBarExtraStyle(.window)
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_: Notification) {
    NSApp.setActivationPolicy(.accessory)
  }
}

@MainActor
final class HermesBridgeAppModel: ObservableObject {
  @Published var state = HermesBridgeMenuBarState()
  private let viewModel = HermesBridgeMenuBarViewModel(environment: .production())

  func load() async {
    await viewModel.load()
    state = await viewModel.state
  }

  func refresh() {
    Task {
      await viewModel.refresh()
      state = await viewModel.state
    }
  }

  func start() {
    Task {
      _ = await viewModel.startService()
      state = await viewModel.state
    }
  }

  func restart() {
    Task {
      _ = await viewModel.restartService()
      state = await viewModel.state
    }
  }

  func doctor() {
    Task {
      _ = await viewModel.runDoctor()
      state = await viewModel.state
    }
  }

  func cancel() {
    Task {
      await viewModel.cancelRefresh()
    }
  }
}
