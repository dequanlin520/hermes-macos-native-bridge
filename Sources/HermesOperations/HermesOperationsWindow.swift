import AppKit
import SwiftUI

public final class HermesOperationsWindowController: NSWindowController {
  @MainActor
  public init(viewModel: HermesOperationsViewModel) {
    let rootView = HermesOperationsWindow(viewModel: viewModel)
    let hostingController = NSHostingController(rootView: rootView)
    let window = NSWindow(contentViewController: hostingController)
    window.title = "Hermes Enterprise Operations Center"
    window.setContentSize(NSSize(width: 880, height: 700))
    window.minSize = NSSize(width: 740, height: 560)
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) is unavailable")
  }
}

public struct HermesOperationsWindow: View {
  @ObservedObject private var viewModel: HermesOperationsViewModel

  public init(viewModel: HermesOperationsViewModel) {
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
          operationsGrid
          boundarySection
          eventSection
        }
        .padding(18)
      }
      Divider()
      controls
    }
    .frame(minWidth: 740, minHeight: 560)
    .task {
      viewModel.refresh()
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: "command.circle")
        .font(.title2)
        .foregroundStyle(color(for: viewModel.snapshot.overallState))
      VStack(alignment: .leading, spacing: 2) {
        Text("Hermes Enterprise Operations Center")
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

  private var operationsGrid: some View {
    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
      sectionRow(
        title: "Runtime Operations",
        image: "cpu",
        state: viewModel.snapshot.runtime.state,
        rows: [
          ("Runtime", viewModel.snapshot.runtime.runtimeStatus),
          ("Sessions", viewModel.snapshot.runtime.sessionStatus),
          ("Backend", viewModel.snapshot.runtime.backendStatus),
          ("Active", "\(viewModel.snapshot.runtime.activeOperationCount)"),
        ]
      )
      sectionRow(
        title: "Event Operations",
        image: "dot.radiowaves.left.and.right",
        state: viewModel.snapshot.events.state,
        rows: [
          ("Pipeline", viewModel.snapshot.events.eventPipelineStatus),
          ("Events", "\(viewModel.snapshot.events.recentEventCount)"),
          ("Notify", viewModel.snapshot.events.notificationStatus),
        ]
      )
      sectionRow(
        title: "Release Operations",
        image: "arrow.up.circle",
        state: viewModel.snapshot.release.state,
        rows: [
          ("Status", viewModel.snapshot.release.releaseStatus),
          ("Current", viewModel.snapshot.release.currentVersion),
          ("Available", viewModel.snapshot.release.availableVersion ?? "none"),
          ("Readiness", viewModel.snapshot.release.releaseReadiness),
        ]
      )
      sectionRow(
        title: "Governance Operations",
        image: "building.columns",
        state: viewModel.snapshot.governance.state,
        rows: [
          ("Policy", viewModel.snapshot.governance.policyStatus),
          ("Privacy", viewModel.snapshot.governance.privacyStatus),
          ("Audit", viewModel.snapshot.governance.auditStatus),
          ("Compliance", viewModel.snapshot.governance.complianceStatus),
        ]
      )
    }
  }

  private func sectionRow(
    title: String,
    image: String,
    state: HermesOperationsState,
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

  private var eventSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Recent Event Summaries")
        .font(.headline)
      if viewModel.snapshot.events.recentEventSummaries.isEmpty {
        Text("No recent event summaries")
          .foregroundStyle(.secondary)
      } else {
        ForEach(viewModel.snapshot.events.recentEventSummaries, id: \.self) { event in
          Label(event, systemImage: "circle.dotted")
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }
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
        viewModel.openDiagnostics()
      } label: {
        Label("Diagnostics", systemImage: "stethoscope")
      }
      Button {
        viewModel.openAdministrationCenter()
      } label: {
        Label("Administration", systemImage: "building.columns")
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

  private func color(for state: HermesOperationsState) -> Color {
    switch state {
    case .nominal:
      return .green
    case .attentionRequired:
      return .orange
    case .unavailable:
      return .red
    case .unknown:
      return .secondary
    }
  }
}
