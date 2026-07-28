import AppKit
import SwiftUI

public final class HermesAnalyticsWindowController: NSWindowController {
  @MainActor
  public init(viewModel: HermesAnalyticsViewModel) {
    let rootView = HermesAnalyticsWindow(viewModel: viewModel)
    let hostingController = NSHostingController(rootView: rootView)
    let window = NSWindow(contentViewController: hostingController)
    window.title = "Hermes Enterprise Analytics Center"
    window.setContentSize(NSSize(width: 880, height: 680))
    window.minSize = NSSize(width: 740, height: 540)
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) is unavailable")
  }
}

public struct HermesAnalyticsWindow: View {
  @ObservedObject private var viewModel: HermesAnalyticsViewModel

  public init(viewModel: HermesAnalyticsViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          if let message = viewModel.lastErrorMessage {
            Label(message, systemImage: "exclamationmark.triangle")
              .foregroundStyle(.red)
              .lineLimit(3)
          }
          analyticsGrid
          boundarySection
        }
        .padding(18)
      }
      Divider()
      controls
    }
    .frame(minWidth: 740, minHeight: 540)
    .task {
      viewModel.refresh()
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: "chart.xyaxis.line")
        .font(.title2)
        .foregroundStyle(color(for: viewModel.snapshot.overallState))
      VStack(alignment: .leading, spacing: 2) {
        Text("Hermes Enterprise Analytics Center")
          .font(.title2)
        Text(viewModel.snapshot.overallState.rawValue)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer()
      if viewModel.isRefreshing {
        ProgressView()
          .controlSize(.small)
      }
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
  }

  private var analyticsGrid: some View {
    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
      sectionRow(
        title: "Runtime Analytics",
        image: "timer",
        state: viewModel.snapshot.runtime.state,
        rows: [
          ("Uptime", viewModel.snapshot.runtime.uptimeSummary),
          ("Sessions", viewModel.snapshot.runtime.sessionStabilitySummary),
          ("Service", viewModel.snapshot.runtime.serviceAvailabilitySummary),
        ]
      )
      sectionRow(
        title: "Operations Analytics",
        image: "waveform.path.ecg",
        state: viewModel.snapshot.operations.state,
        rows: [
          ("Errors", viewModel.snapshot.operations.errorTrendSummary),
          ("Recovery", viewModel.snapshot.operations.recoveryTrendSummary),
          ("Notify", viewModel.snapshot.operations.notificationTrendSummary),
          ("Updates", viewModel.snapshot.operations.updateReliabilitySummary),
        ]
      )
      sectionRow(
        title: "Governance Analytics",
        image: "checkmark.shield",
        state: viewModel.snapshot.governance.state,
        rows: [
          ("Policy", viewModel.snapshot.governance.policyComplianceSummary),
          ("Privacy", viewModel.snapshot.governance.privacyPostureTrend),
          ("Audit", viewModel.snapshot.governance.auditCoverageSummary),
        ]
      )
    }
  }

  private func sectionRow(
    title: String,
    image: String,
    state: HermesAnalyticsState,
    rows: [(String, String)]
  ) -> some View {
    GridRow {
      Label(title, systemImage: image)
        .font(.headline)
      VStack(alignment: .leading, spacing: 4) {
        Text(state.rawValue)
          .foregroundStyle(color(for: state))
        ForEach(rows, id: \.0) { label, value in
          HStack(alignment: .firstTextBaseline) {
            Text(label)
              .foregroundStyle(.secondary)
              .frame(width: 94, alignment: .leading)
            Text(value)
              .lineLimit(2)
          }
        }
      }
    }
  }

  private var boundarySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Boundary")
        .font(.headline)
      Text(viewModel.boundarySummary)
        .foregroundStyle(.secondary)
    }
  }

  private var controls: some View {
    HStack(spacing: 10) {
      Button {
        viewModel.openSettings()
      } label: {
        Label("Settings", systemImage: "gearshape.2")
      }
      Button {
        viewModel.openAdministrationCenter()
      } label: {
        Label("Administration", systemImage: "building.columns")
      }
      Button {
        viewModel.openOperationsCenter()
      } label: {
        Label("Operations", systemImage: "command.circle")
      }
      Spacer()
      Button {
        viewModel.refresh()
      } label: {
        Label("Refresh", systemImage: "arrow.clockwise")
      }
      .keyboardShortcut(.defaultAction)
      .disabled(viewModel.isRefreshing)
    }
    .padding(18)
  }

  private func color(for state: HermesAnalyticsState) -> Color {
    switch state {
    case .stable:
      return .green
    case .attentionRequired:
      return .orange
    case .unreliable:
      return .red
    case .unknown:
      return .secondary
    }
  }
}
