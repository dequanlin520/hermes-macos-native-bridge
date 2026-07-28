import AppKit
import SwiftUI

public final class HermesComplianceWindowController: NSWindowController {
  @MainActor
  public init(viewModel: HermesComplianceViewModel) {
    let rootView = HermesComplianceWindow(viewModel: viewModel)
    let hostingController = NSHostingController(rootView: rootView)
    let window = NSWindow(contentViewController: hostingController)
    window.title = "Hermes Enterprise Compliance Center"
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

public struct HermesComplianceWindow: View {
  @ObservedObject private var viewModel: HermesComplianceViewModel

  public init(viewModel: HermesComplianceViewModel) {
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
          postureGrid
          boundarySection
          auditSection
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
      Image(systemName: "checkmark.seal")
        .font(.title2)
        .foregroundStyle(statusColor)
      VStack(alignment: .leading, spacing: 2) {
        Text("Hermes Enterprise Compliance Center")
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

  private var postureGrid: some View {
    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
      sectionRow(
        title: "Security",
        image: "lock.shield",
        state: viewModel.snapshot.security.state,
        rows: [
          ("Service", viewModel.snapshot.security.serviceAvailability.rawValue),
          ("Protocol", viewModel.snapshot.security.protocolVersion),
          ("Runtime", viewModel.snapshot.security.runtimeOwnership),
        ]
      )
      sectionRow(
        title: "Privacy",
        image: "hand.raised",
        state: viewModel.snapshot.privacy.state,
        rows: [
          ("Consent", viewModel.snapshot.privacy.summary),
          ("Upload", viewModel.snapshot.privacy.uploadAllowed ? "available" : "none"),
          ("Sensitive", viewModel.snapshot.privacy.sensitiveDataExposed ? "exposed" : "redacted"),
        ]
      )
      sectionRow(
        title: "Policy",
        image: "building.2.crop.circle",
        state: viewModel.snapshot.policy.state,
        rows: [
          ("Active", "\(viewModel.snapshot.policy.activePolicies)"),
          ("Restrictive", "\(viewModel.snapshot.policy.deniedPolicies)"),
          ("Version", viewModel.snapshot.policy.policyVersion),
        ]
      )
      sectionRow(
        title: "Release",
        image: "arrow.up.circle",
        state: viewModel.snapshot.release.state,
        rows: [
          ("Current", viewModel.snapshot.release.currentVersion),
          ("Availability", viewModel.snapshot.release.availability.rawValue),
          ("Available", viewModel.snapshot.release.availableVersion ?? "none"),
          ("Signing", viewModel.snapshot.release.signingState),
          ("Provenance", viewModel.snapshot.release.provenanceState),
        ]
      )
    }
  }

  private func sectionRow(
    title: String,
    image: String,
    state: HermesCompliancePostureState,
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

  private var auditSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Audit Evidence")
        .font(.headline)
      if viewModel.snapshot.auditEvidence.recentEvidence.isEmpty {
        Text("No recent audit evidence")
          .foregroundStyle(.secondary)
      } else {
        ForEach(viewModel.snapshot.auditEvidence.recentEvidence) { item in
          HStack {
            Image(systemName: item.source == .policy ? "checkmark.shield" : "hand.raised")
              .foregroundStyle(.secondary)
              .frame(width: 22)
            Text(item.source.rawValue)
              .foregroundStyle(.secondary)
              .frame(width: 56, alignment: .leading)
            Text(item.summary)
              .lineLimit(2)
            Spacer()
          }
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

  private var statusColor: Color {
    color(for: viewModel.snapshot.overallState)
  }

  private func color(for state: HermesCompliancePostureState) -> Color {
    switch state {
    case .compliant:
      return .green
    case .attentionRequired:
      return .orange
    case .unavailable:
      return .red
    }
  }
}
