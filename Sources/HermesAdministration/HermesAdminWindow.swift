import AppKit
import SwiftUI

public final class HermesAdministrationWindowController: NSWindowController {
  @MainActor
  public init(viewModel: HermesAdminViewModel) {
    let rootView = HermesAdministrationWindow(viewModel: viewModel)
    let hostingController = NSHostingController(rootView: rootView)
    let window = NSWindow(contentViewController: hostingController)
    window.title = "Hermes Enterprise Administration Center"
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

public struct HermesAdministrationWindow: View {
  @ObservedObject private var viewModel: HermesAdminViewModel

  public init(viewModel: HermesAdminViewModel) {
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
          statusGrid
          preferencesSection
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
      Image(systemName: "building.columns")
        .font(.title2)
        .foregroundStyle(statusColor)
      VStack(alignment: .leading, spacing: 2) {
        Text("Hermes Enterprise Administration Center")
          .font(.title2)
        Text(viewModel.snapshot.complianceState.rawValue)
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

  private var statusGrid: some View {
    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
      sectionRow(
        title: "System",
        image: "desktopcomputer",
        rows: [
          ("Application", viewModel.snapshot.system.applicationVersion),
          ("Protocol", viewModel.snapshot.system.protocolVersion),
          ("Service", viewModel.snapshot.system.serviceAvailability.rawValue),
        ]
      )
      sectionRow(
        title: "Policy",
        image: "checkmark.shield",
        rows: [
          ("Active", "\(viewModel.snapshot.policy.activePolicies)"),
          ("Denied", "\(viewModel.snapshot.policy.deniedPolicies)"),
          ("Version", viewModel.snapshot.policy.policyVersion),
        ]
      )
      sectionRow(
        title: "Privacy",
        image: "hand.raised",
        rows: [
          ("Consent", viewModel.snapshot.privacy.consentSummary),
          ("State", viewModel.snapshot.privacy.privacyState.rawValue),
        ]
      )
      sectionRow(
        title: "Update",
        image: "arrow.up.circle",
        rows: [
          ("Current", viewModel.snapshot.update.currentVersion),
          ("Availability", viewModel.snapshot.update.updateAvailability.rawValue),
          ("Available", viewModel.snapshot.update.availableVersion ?? "none"),
        ]
      )
    }
  }

  private func sectionRow(title: String, image: String, rows: [(String, String)]) -> some View {
    GridRow {
      Label(title, systemImage: image)
        .font(.headline)
      VStack(alignment: .leading, spacing: 4) {
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

  private var preferencesSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Preferences")
        .font(.headline)
      Toggle("Show compliance status", isOn: Binding(
        get: { viewModel.preferences.showComplianceStatus },
        set: { viewModel.setShowComplianceStatus($0) }
      ))
      Stepper(
        value: Binding(
          get: { viewModel.preferences.visibleAuditLimit },
          set: { viewModel.setVisibleAuditLimit($0) }
        ),
        in: 0...25
      ) {
        Text("Audit rows: \(viewModel.preferences.visibleAuditLimit)")
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
      Text("Audit Summary")
        .font(.headline)
      if viewModel.snapshot.audit.recentEvents.isEmpty {
        Text("No recent audit events")
          .foregroundStyle(.secondary)
      } else {
        ForEach(viewModel.snapshot.audit.recentEvents) { event in
          HStack {
            Image(systemName: event.source == .policy ? "checkmark.shield" : "hand.raised")
              .foregroundStyle(.secondary)
              .frame(width: 22)
            Text(event.source.rawValue)
              .foregroundStyle(.secondary)
              .frame(width: 56, alignment: .leading)
            Text(event.summary)
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
        viewModel.openDiagnostics()
      } label: {
        Label("Diagnostics", systemImage: "stethoscope")
      }
      Button {
        viewModel.openPolicyCenter()
      } label: {
        Label("Policy", systemImage: "building.2.crop.circle")
      }
      Button {
        viewModel.openComplianceCenter()
      } label: {
        Label("Compliance", systemImage: "checkmark.seal")
      }
      Button {
        viewModel.openHealthCenter()
      } label: {
        Label("Health", systemImage: "heart.text.square")
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

  private var statusColor: Color {
    switch viewModel.snapshot.complianceState {
    case .compliant:
      return .green
    case .attentionRequired:
      return .orange
    case .unavailable:
      return .red
    }
  }
}
