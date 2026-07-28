import AppKit
import SwiftUI

public final class HermesHealthWindowController: NSWindowController {
  @MainActor
  public init(viewModel: HermesHealthViewModel) {
    let rootView = HermesHealthWindow(viewModel: viewModel)
    let hostingController = NSHostingController(rootView: rootView)
    let window = NSWindow(contentViewController: hostingController)
    window.title = "Hermes Enterprise Health Center"
    window.setContentSize(NSSize(width: 860, height: 680))
    window.minSize = NSSize(width: 720, height: 560)
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) is unavailable")
  }
}

public struct HermesHealthWindow: View {
  @ObservedObject private var viewModel: HermesHealthViewModel

  public init(viewModel: HermesHealthViewModel) {
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
          healthGrid
          boundarySection
          failuresSection
        }
        .padding(18)
      }
      Divider()
      controls
    }
    .frame(minWidth: 720, minHeight: 560)
    .task {
      viewModel.refresh()
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: "heart.text.square")
        .font(.title2)
        .foregroundStyle(color(for: viewModel.snapshot.overallState))
      VStack(alignment: .leading, spacing: 2) {
        Text("Hermes Enterprise Health Center")
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

  private var healthGrid: some View {
    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
      sectionRow(
        title: "System Health",
        image: "desktopcomputer",
        state: viewModel.snapshot.system.state,
        rows: [
          ("Application", viewModel.snapshot.system.applicationAvailability.rawValue),
          ("Service", viewModel.snapshot.system.serviceAvailability.rawValue),
          ("XPC", viewModel.snapshot.system.xpcConnectivity.rawValue),
          ("Version", viewModel.snapshot.system.applicationVersion),
          ("Protocol", viewModel.snapshot.system.protocolVersion),
        ]
      )
      sectionRow(
        title: "Runtime Health",
        image: "cpu",
        state: viewModel.snapshot.runtime.state,
        rows: [
          ("Runtime", viewModel.snapshot.runtime.runtimeStatusSummary),
          ("Sessions", viewModel.snapshot.runtime.sessionAvailabilitySummary),
          ("Backend", viewModel.snapshot.runtime.backendAvailabilitySummary),
        ]
      )
      sectionRow(
        title: "Operational Health",
        image: "waveform.path.ecg",
        state: viewModel.snapshot.operational.state,
        rows: [
          ("Failures", viewModel.snapshot.operational.recentFailuresSummary),
          ("Recovery", viewModel.snapshot.operational.recoveryStatus),
          ("Updates", viewModel.snapshot.operational.updateStatus),
          ("Notify", viewModel.snapshot.operational.notificationStatus),
        ]
      )
      sectionRow(
        title: "Compliance Health",
        image: "checkmark.seal",
        state: viewModel.snapshot.compliance.state,
        rows: [
          ("Policy", viewModel.snapshot.compliance.policyStatus),
          ("Privacy", viewModel.snapshot.compliance.privacyStatus),
          ("Audit", viewModel.snapshot.compliance.auditStatus),
        ]
      )
    }
  }

  private func sectionRow(
    title: String,
    image: String,
    state: HermesHealthState,
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
              .frame(width: 92, alignment: .leading)
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

  private var failuresSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Recent Failures")
        .font(.headline)
      if viewModel.snapshot.operational.recentFailures.isEmpty {
        Text("No recent failures")
          .foregroundStyle(.secondary)
      } else {
        ForEach(viewModel.snapshot.operational.recentFailures, id: \.self) { failure in
          Label(failure, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.orange)
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

  private func color(for state: HermesHealthState) -> Color {
    switch state {
    case .healthy:
      return .green
    case .degraded:
      return .orange
    case .unavailable:
      return .red
    case .unknown:
      return .secondary
    }
  }
}
