import AppKit
import SwiftUI

public final class HermesUpdateWindowController: NSWindowController, NSWindowDelegate {
  private let viewModel: HermesUpdateViewModel

  @MainActor
  public init(viewModel: HermesUpdateViewModel) {
    self.viewModel = viewModel
    let rootView = HermesUpdateWindow(viewModel: viewModel)
    let hostingController = NSHostingController(rootView: rootView)
    let window = NSWindow(contentViewController: hostingController)
    window.title = "Hermes Update Center"
    window.setContentSize(NSSize(width: 760, height: 620))
    window.minSize = NSSize(width: 680, height: 540)
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    super.init(window: window)
    window.delegate = self
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) is unavailable")
  }

  public func windowWillClose(_: Notification) {
    viewModel.windowClosed()
  }
}

public struct HermesUpdateWindow: View {
  @ObservedObject private var viewModel: HermesUpdateViewModel

  public init(viewModel: HermesUpdateViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          if let failure = viewModel.snapshot.failure {
            failureBanner(failure)
          }
          versionSection
          releaseSection
          confirmationSection
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      Divider()
      controls
    }
    .frame(minWidth: 680, minHeight: 540)
    .task {
      if viewModel.snapshot.state == .idle {
        viewModel.checkForUpdate()
      }
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: iconName)
        .font(.title2)
        .foregroundStyle(iconColor)
      VStack(alignment: .leading, spacing: 2) {
        Text("Hermes Update Center")
          .font(.title2)
        Text(viewModel.snapshot.state.rawValue)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer()
      if viewModel.isWorking {
        ProgressView()
          .controlSize(.small)
      }
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
  }

  private var versionSection: some View {
    summarySection(
      title: "Installed Versions",
      rows: [
        ("App", viewModel.snapshot.current.appVersion),
        ("Service", viewModel.snapshot.current.serviceVersion),
        ("XPC Protocol", viewModel.snapshot.current.xpcProtocolVersion),
        ("Rollback", viewModel.snapshot.current.rollbackAvailable ? "available" : "unavailable"),
      ]
    )
  }

  private var releaseSection: some View {
    let release = viewModel.snapshot.availableRelease
    return summarySection(
      title: "Available Release",
      rows: [
        ("Version", release?.version ?? "none"),
        ("Minimum macOS", release?.minimumSupportedMacOS ?? "unknown"),
        ("Compatibility", release?.compatibility.rawValue ?? "unknown"),
        ("Signing", release?.signing.rawValue ?? "unknown"),
        ("Provenance", release?.provenance.rawValue ?? "unknown"),
        ("Source", release?.trustedSource.displayName ?? "repository-configured"),
        ("Notes", release?.releaseNotesSummary ?? "No update release notes"),
      ]
    )
  }

  @ViewBuilder
  private var confirmationSection: some View {
    if let confirmation = viewModel.snapshot.confirmation {
      VStack(alignment: .leading, spacing: 8) {
        Text("Confirmation")
          .font(.headline)
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
          GridRow {
            Text("Operation")
              .foregroundStyle(.secondary)
            Text(confirmation.operation.rawValue)
          }
          GridRow {
            Text("Current")
              .foregroundStyle(.secondary)
            Text(confirmation.currentVersion)
          }
          GridRow {
            Text("Target")
              .foregroundStyle(.secondary)
            Text(confirmation.targetVersion)
          }
          GridRow {
            Text("Reconnect")
              .foregroundStyle(.secondary)
            Text(confirmation.expectedReconnectBehavior)
              .fixedSize(horizontal: false, vertical: true)
          }
          GridRow {
            Text("Rollback")
              .foregroundStyle(.secondary)
            Text(confirmation.rollbackAvailable ? "available" : "unavailable")
          }
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
              .lineLimit(3)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  private func failureBanner(_ failure: HermesUpdateFailure) -> some View {
    Label("\(failure.category.rawValue): \(failure.safeMessage)", systemImage: "exclamationmark.triangle")
      .foregroundStyle(.orange)
      .lineLimit(3)
  }

  private var controls: some View {
    HStack(spacing: 10) {
      Button {
        viewModel.checkForUpdate()
      } label: {
        Label("Check", systemImage: "arrow.clockwise")
      }
      .disabled(viewModel.isWorking)

      Button {
        viewModel.validateAvailableUpdate()
      } label: {
        Label("Validate", systemImage: "checkmark.shield")
      }
      .disabled(viewModel.isWorking || viewModel.snapshot.availableRelease == nil)

      Button {
        viewModel.prepareRollback()
      } label: {
        Label("Rollback", systemImage: "arrow.uturn.backward")
      }
      .disabled(viewModel.isWorking || !viewModel.snapshot.current.rollbackAvailable)

      Spacer()

      Button {
        viewModel.showDiagnostics()
      } label: {
        Label("Diagnostics", systemImage: "stethoscope")
      }
      .disabled(viewModel.isWorking)

      if viewModel.snapshot.state == .recoveryRequired {
        Button {
          viewModel.showRecovery()
        } label: {
          Label("Recovery", systemImage: "wrench.and.screwdriver")
        }
      }

      Button {
        viewModel.reportUpdateFeedback()
      } label: {
        Label("Feedback", systemImage: "bubble.left.and.text.bubble.right")
      }
      .disabled(viewModel.isWorking)

      Button {
        if viewModel.snapshot.confirmation?.operation == .rollback {
          viewModel.rollbackConfirmed()
        } else {
          viewModel.activateConfirmed()
        }
      } label: {
        Label("Confirm", systemImage: "checkmark.seal")
      }
      .keyboardShortcut(.defaultAction)
      .disabled(viewModel.isWorking || viewModel.snapshot.confirmation == nil)
    }
    .padding(18)
  }

  private var iconName: String {
    switch viewModel.snapshot.state {
    case .completed, .upToDate:
      return "checkmark.seal"
    case .failed, .recoveryRequired:
      return "exclamationmark.triangle"
    case .rollbackAvailable, .rollingBack:
      return "arrow.uturn.backward.circle"
    default:
      return "arrow.up.circle"
    }
  }

  private var iconColor: Color {
    switch viewModel.snapshot.state {
    case .completed, .upToDate:
      return .green
    case .failed, .recoveryRequired:
      return .orange
    default:
      return .accentColor
    }
  }
}
