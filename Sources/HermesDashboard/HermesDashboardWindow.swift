import AppKit
import HermesRuntimeFoundation
import SwiftUI

public final class HermesDashboardWindowController: NSWindowController {
  @MainActor
  public init(viewModel: HermesDashboardViewModel) {
    let rootView = HermesDashboardWindow(viewModel: viewModel)
    let hostingController = NSHostingController(rootView: rootView)
    let window = NSWindow(contentViewController: hostingController)
    window.title = "Hermes Dashboard"
    window.setContentSize(NSSize(width: 760, height: 560))
    window.minSize = NSSize(width: 640, height: 460)
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) is unavailable")
  }
}

public struct HermesDashboardWindow: View {
  @ObservedObject private var viewModel: HermesDashboardViewModel

  public init(viewModel: HermesDashboardViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          summaryGrid
          if let message = viewModel.state.lastErrorMessage {
            errorBanner(message)
          }
          eventsList
        }
        .padding(18)
      }
      Divider()
      controls
    }
    .frame(minWidth: 640, minHeight: 460)
    .task {
      viewModel.load()
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: "point.3.connected.trianglepath.dotted")
        .font(.title2)
        .foregroundStyle(healthColor)
      VStack(alignment: .leading, spacing: 2) {
        Text("Hermes Dashboard")
          .font(.title2)
        Text(viewModel.state.runtimeStatus?.rawValue ?? "runtime unavailable")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Text(viewModel.state.backendHealthSummary?.healthState.rawValue ?? "unavailable")
        .font(.subheadline)
        .foregroundStyle(healthColor)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
  }

  private var summaryGrid: some View {
    Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
      GridRow {
        summarySection(
          title: "Runtime Status",
          rows: [
            ("Status", viewModel.state.runtimeStatus?.rawValue ?? "unavailable"),
            ("Loading", viewModel.state.isLoading ? "yes" : "no"),
          ]
        )
        summarySection(
          title: "Session Summary",
          rows: [
            ("State", viewModel.state.sessionSummary?.status.rawValue ?? "none"),
            ("Started", startedText),
            ("Shutdown", viewModel.state.sessionSummary?.shutdownReason ?? "none"),
          ]
        )
      }
      GridRow {
        summarySection(
          title: "Backend Health",
          rows: [
            ("Health", viewModel.state.backendHealthSummary?.healthState.rawValue ?? "unavailable"),
            ("Version", viewModel.state.backendHealthSummary?.backendVersion ?? "unknown"),
            ("Gateway", gatewayText),
          ]
        )
        summarySection(
          title: "Backend Summary",
          rows: [
            ("Agents", countText(viewModel.state.backendHealthSummary?.activeAgentCount)),
            ("Busy", boolText(viewModel.state.backendHealthSummary?.gatewayBusy)),
            ("Drainable", boolText(viewModel.state.backendHealthSummary?.gatewayDrainable)),
            ("Contract", countText(viewModel.state.backendHealthSummary?.desktopContract)),
          ]
        )
      }
    }
  }

  private func summarySection(title: String, rows: [(String, String)]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.headline)
      Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
        ForEach(rows, id: \.0) { label, value in
          GridRow {
            Text(label)
              .foregroundStyle(.secondary)
            Text(value)
              .lineLimit(1)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  private func errorBanner(_ message: String) -> some View {
    Label(message, systemImage: "exclamationmark.triangle")
      .foregroundStyle(.red)
      .lineLimit(3)
  }

  private var eventsList: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Recent Runtime Events")
        .font(.headline)

      if viewModel.state.recentEvents.isEmpty {
        Text("No runtime events")
          .foregroundStyle(.secondary)
      } else {
        ForEach(viewModel.state.recentEvents) { event in
          HStack(alignment: .top, spacing: 12) {
            Image(systemName: eventIcon(for: event.kind))
              .foregroundStyle(.secondary)
              .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
              HStack {
                Text(event.kind.rawValue)
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
          }
          .padding(.vertical, 4)
        }
      }
    }
  }

  private var controls: some View {
    HStack(spacing: 10) {
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

      Button {
        viewModel.restartHermes()
      } label: {
        Label("Restart Hermes", systemImage: "arrow.triangle.2.circlepath")
      }
      .disabled(viewModel.state.actionInFlight)

      Spacer()

      Button {
        viewModel.refreshStatus()
      } label: {
        Label("Refresh", systemImage: "arrow.clockwise")
      }
      .disabled(viewModel.state.actionInFlight)
    }
    .padding(18)
  }

  private var healthColor: Color {
    switch viewModel.state.backendHealthSummary?.healthState {
    case .healthy:
      return .green
    case .degraded:
      return .orange
    case .failed:
      return .red
    case .stopped, .unavailable, nil:
      return .secondary
    }
  }

  private var startedText: String {
    guard let startedAt = viewModel.state.sessionSummary?.startedAt else {
      return "not started"
    }
    return startedAt.formatted(date: .abbreviated, time: .standard)
  }

  private var gatewayText: String {
    guard let summary = viewModel.state.backendHealthSummary else {
      return "unknown"
    }
    if let gatewayState = summary.gatewayState {
      return gatewayState
    }
    return boolText(summary.gatewayRunning)
  }

  private func boolText(_ value: Bool?) -> String {
    guard let value else {
      return "unknown"
    }
    return value ? "yes" : "no"
  }

  private func countText(_ value: Int?) -> String {
    value.map(String.init) ?? "unknown"
  }

  private func eventIcon(for kind: HermesRuntimeEventKind) -> String {
    switch kind {
    case .sessionCreated:
      return "plus.circle"
    case .sessionStarting:
      return "play.circle"
    case .sessionRunning:
      return "checkmark.circle"
    case .sessionHealthChanged:
      return "waveform.path.ecg"
    case .sessionFailed:
      return "exclamationmark.triangle"
    case .sessionStopping:
      return "pause.circle"
    case .sessionStopped:
      return "stop.circle"
    }
  }
}
