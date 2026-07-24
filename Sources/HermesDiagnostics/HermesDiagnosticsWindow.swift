import AppKit
import SwiftUI

public final class HermesDiagnosticsWindowController: NSWindowController {
  @MainActor
  public init(viewModel: HermesDiagnosticsViewModel) {
    let rootView = HermesDiagnosticsWindow(viewModel: viewModel)
    let hostingController = NSHostingController(rootView: rootView)
    let window = NSWindow(contentViewController: hostingController)
    window.title = "Hermes Diagnostics"
    window.setContentSize(NSSize(width: 760, height: 620))
    window.minSize = NSSize(width: 640, height: 520)
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) is unavailable")
  }
}

public struct HermesDiagnosticsWindow: View {
  @ObservedObject private var viewModel: HermesDiagnosticsViewModel

  public init(viewModel: HermesDiagnosticsViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          if let message = viewModel.state.lastErrorMessage {
            errorBanner(message)
          }
          healthSummary
          environmentInfo
          sessionDiagnostics
          issues
        }
        .padding(18)
      }
      Divider()
      controls
    }
    .frame(minWidth: 640, minHeight: 520)
    .task {
      viewModel.refresh()
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: "stethoscope")
        .font(.title2)
        .foregroundStyle(healthColor)
      VStack(alignment: .leading, spacing: 2) {
        Text("Hermes Diagnostics")
          .font(.title2)
        Text(viewModel.state.result?.healthSummary.backendState.rawValue ?? "not run")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer()
      if viewModel.state.isRefreshing || viewModel.state.isRunningDiagnostics {
        ProgressView()
          .controlSize(.small)
      }
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
  }

  private var healthSummary: some View {
    summarySection(
      title: "Runtime Health",
      rows: [
        ("Discovery", result?.healthSummary.discoveryState.rawValue ?? "unknown"),
        ("Process", result?.healthSummary.processState.rawValue ?? "unknown"),
        ("Backend", result?.healthSummary.backendState.rawValue ?? "unknown"),
        ("Session", result?.healthSummary.sessionState.rawValue ?? "unknown"),
        ("Event Bus", result?.healthSummary.eventBusState.rawValue ?? "unknown"),
      ]
    )
  }

  private var environmentInfo: some View {
    VStack(alignment: .leading, spacing: 10) {
      summarySection(
        title: "Environment",
        rows: [
          ("macOS", result?.environmentInfo.macOSVersion ?? "unknown"),
          ("Architecture", result?.environmentInfo.architecture ?? "unknown"),
          ("Hermes", result?.environmentInfo.hermesVersion ?? "unknown"),
        ]
      )
      permissionList
    }
  }

  private var permissionList: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Permissions")
        .font(.headline)
      let permissions = result?.environmentInfo.permissionStates ?? []
      if permissions.isEmpty {
        Text("No permission states")
          .foregroundStyle(.secondary)
      } else {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
          ForEach(permissions) { permission in
            GridRow {
              Text(permission.kind)
              Text(permission.state)
                .foregroundStyle(.secondary)
              Text(permission.detailCode)
                .foregroundStyle(.secondary)
            }
          }
        }
      }
    }
  }

  private var sessionDiagnostics: some View {
    summarySection(
      title: "Sessions",
      rows: [
        ("Active", countText(result?.sessionDiagnostics.activeSessions)),
        ("Running", countText(result?.sessionDiagnostics.runningSessions)),
        ("Failed", countText(result?.sessionDiagnostics.failedSessions)),
      ]
    )
  }

  private var issues: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Diagnostic Issues")
        .font(.headline)
      let issueRows = result?.issues ?? []
      if issueRows.isEmpty {
        Text("No diagnostic issues")
          .foregroundStyle(.secondary)
      } else {
        ForEach(issueRows, id: \.self) { issue in
          Label(issue, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.orange)
        }
      }
    }
  }

  private func summarySection(title: String, rows: [(String, String)]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.headline)
      Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
        ForEach(rows, id: \.0) { label, value in
          GridRow {
            Text(label)
              .foregroundStyle(.secondary)
            Text(value)
              .lineLimit(2)
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

  private var controls: some View {
    HStack(spacing: 10) {
      Button {
        viewModel.runDiagnostics()
      } label: {
        Label("Run Diagnostics", systemImage: "play.circle")
      }
      .keyboardShortcut(.defaultAction)
      .disabled(viewModel.state.isRefreshing || viewModel.state.isRunningDiagnostics)

      Spacer()

      Button {
        viewModel.refresh()
      } label: {
        Label("Refresh", systemImage: "arrow.clockwise")
      }
      .disabled(viewModel.state.isRefreshing || viewModel.state.isRunningDiagnostics)
    }
    .padding(18)
  }

  private var result: HermesDiagnosticResult? {
    viewModel.state.result
  }

  private var healthColor: Color {
    switch result?.healthSummary.backendState {
    case .ready:
      return .green
    case .degraded:
      return .orange
    case .failed:
      return .red
    case .stopped, .unavailable, .unknown, nil:
      return .secondary
    }
  }

  private func countText(_ value: Int?) -> String {
    value.map(String.init) ?? "0"
  }
}
