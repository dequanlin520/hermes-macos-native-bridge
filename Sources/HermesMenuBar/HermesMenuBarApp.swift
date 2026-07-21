import AppKit
import HermesRuntimeFoundation
import SwiftUI

@main
struct HermesMenuBarApp: App {
  @NSApplicationDelegateAdaptor(HermesMenuBarAppDelegate.self) private var appDelegate
  @StateObject private var viewModel = HermesMenuBarViewModel(
    commandAPI: HermesMenuBarRuntimeFactory.productionCommandAPI()
  )
  @Environment(\.openWindow) private var openWindow

  var body: some Scene {
    MenuBarExtra("Hermes", systemImage: "point.3.connected.trianglepath.dotted") {
      HermesMenuBarContentView(viewModel: viewModel)
        .task {
          viewModel.startEventSubscription()
        }
        .onChange(of: viewModel.state.eventsViewOpenRequested) { requested in
          guard requested else { return }
          openWindow(id: "runtime-events")
          viewModel.acknowledgeEventsViewRequest()
        }
    }
    .menuBarExtraStyle(.window)

    WindowGroup("Runtime Events", id: "runtime-events") {
      HermesRuntimeEventsView(events: viewModel.state.recentEvents)
    }
    .defaultSize(width: 560, height: 420)
  }
}

final class HermesMenuBarAppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_: Notification) {
    NSApp.setActivationPolicy(.accessory)
  }
}

struct HermesMenuBarContentView: View {
  @ObservedObject var viewModel: HermesMenuBarViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Label("Hermes", systemImage: "point.3.connected.trianglepath.dotted")
          .font(.headline)
        Spacer()
        Text(viewModel.state.healthState.rawValue)
          .foregroundStyle(healthColor)
      }

      Divider()

      Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
        GridRow {
          Text("Runtime")
            .foregroundStyle(.secondary)
          Text(viewModel.state.runtimeStatus?.rawValue ?? "unavailable")
        }
        GridRow {
          Text("Health")
            .foregroundStyle(.secondary)
          Text(viewModel.state.healthState.rawValue)
        }
        GridRow {
          Text("Session")
            .foregroundStyle(.secondary)
          Text(sessionText)
            .lineLimit(1)
        }
        GridRow {
          Text("Backend")
            .foregroundStyle(.secondary)
          Text(viewModel.state.sessionSummary?.backendVersion ?? "unknown")
            .lineLimit(1)
        }
      }

      if let message = viewModel.state.lastErrorMessage {
        Divider()
        Label(message, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.red)
          .lineLimit(3)
      }

      Divider()

      VStack(alignment: .leading, spacing: 6) {
        Text("Recent Events")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        if viewModel.state.recentEvents.isEmpty {
          Text("None")
            .foregroundStyle(.secondary)
        } else {
          ForEach(viewModel.state.recentEvents.prefix(4)) { event in
            HStack {
              Text(event.kind.rawValue)
                .lineLimit(1)
              Spacer()
              Text(event.status.rawValue)
                .foregroundStyle(.secondary)
            }
          }
        }
      }

      Divider()

      HStack {
        Button {
          viewModel.startHermes()
        } label: {
          Label("Start Hermes", systemImage: "play.fill")
        }
        .disabled(viewModel.state.actionInFlight)

        Button {
          viewModel.stopHermes()
        } label: {
          Label("Stop Hermes", systemImage: "stop.fill")
        }
        .disabled(viewModel.state.actionInFlight)
      }

      HStack {
        Button {
          viewModel.refreshStatus()
        } label: {
          Label("Refresh Status", systemImage: "arrow.clockwise")
        }
        .disabled(viewModel.state.actionInFlight)

        Button {
          viewModel.openEventsView()
        } label: {
          Label("Open Events View", systemImage: "list.bullet.rectangle")
        }
      }

      Divider()

      Button("Quit") {
        viewModel.cancel()
        NSApplication.shared.terminate(nil)
      }
    }
    .padding(12)
    .frame(width: 340)
  }

  private var healthColor: Color {
    switch viewModel.state.healthState {
    case .healthy:
      return .green
    case .degraded:
      return .orange
    case .failed:
      return .red
    case .stopped, .unavailable:
      return .secondary
    }
  }

  private var sessionText: String {
    guard let summary = viewModel.state.sessionSummary else {
      return "none"
    }
    if let startedAt = summary.startedAt {
      return "started \(startedAt.formatted(date: .omitted, time: .shortened))"
    }
    return summary.status.rawValue
  }
}

struct HermesRuntimeEventsView: View {
  let events: [HermesMenuBarRuntimeEventViewState]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Runtime Events")
        .font(.title2)
      if events.isEmpty {
        Text("No runtime events")
          .foregroundStyle(.secondary)
      } else {
        List(events) { event in
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Text(event.kind.rawValue)
                .font(.headline)
              Spacer()
              Text(event.status.rawValue)
                .foregroundStyle(.secondary)
            }
            Text(event.occurredAt.formatted(date: .abbreviated, time: .standard))
              .font(.caption)
              .foregroundStyle(.secondary)
            if let message = event.lastErrorMessage {
              Text(message)
                .foregroundStyle(.red)
                .lineLimit(3)
            }
          }
          .padding(.vertical, 4)
        }
      }
    }
    .padding(16)
    .frame(minWidth: 480, minHeight: 320)
  }
}
