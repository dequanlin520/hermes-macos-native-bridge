import AppKit
import SwiftUI

public final class HermesOnboardingWindowController: NSWindowController {
  @MainActor
  public init(viewModel: HermesOnboardingViewModel) {
    let rootView = HermesOnboardingWindow(viewModel: viewModel)
    let hostingController = NSHostingController(rootView: rootView)
    let window = NSWindow(contentViewController: hostingController)
    window.title = "Hermes First Run"
    window.setContentSize(NSSize(width: 680, height: 560))
    window.minSize = NSSize(width: 580, height: 500)
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) is unavailable")
  }
}

public struct HermesOnboardingWindow: View {
  @ObservedObject private var viewModel: HermesOnboardingViewModel

  public init(viewModel: HermesOnboardingViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      content
      Divider()
      controls
    }
    .frame(minWidth: 580, minHeight: 500)
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: iconName)
        .font(.title2)
        .foregroundStyle(iconColor)
      VStack(alignment: .leading, spacing: 2) {
        Text("Hermes First Run")
          .font(.title2)
        Text(viewModel.snapshot.status)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer()
      if viewModel.isWorking || viewModel.snapshot.state.rawValue.hasPrefix("checking")
        || viewModel.snapshot.state == .testingConnection
      {
        ProgressView()
          .controlSize(.small)
      }
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
  }

  private var content: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        stepList
        explanation
        readinessDetails
      }
      .padding(18)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
  }

  private var stepList: some View {
    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
      ForEach(HermesOnboardingStep.allCases, id: \.self) { step in
        GridRow {
          Image(systemName: marker(for: step))
            .foregroundStyle(step == viewModel.snapshot.step ? iconColor : .secondary)
          Text(title(for: step))
          Text(status(for: step))
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private var explanation: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Status")
        .font(.headline)
      Text(viewModel.snapshot.explanation)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  @ViewBuilder
  private var readinessDetails: some View {
    if let service = viewModel.snapshot.service {
      detailSection(
        title: "Bridge Service",
        rows: [
          ("XPC", service.xpcConnected ? "available" : "unavailable"),
          ("Protocol", service.protocolVersion ?? "unknown"),
          ("Compatible", service.protocolCompatible ? "yes" : "no"),
          ("Health", service.healthStatus.rawValue),
        ]
      )
    }
    if let agent = viewModel.snapshot.agent {
      detailSection(title: "Hermes Agent", rows: [("Status", agent.status.rawValue)])
    }
    if let permissions = viewModel.snapshot.permissions {
      VStack(alignment: .leading, spacing: 8) {
        Text("Permissions")
          .font(.headline)
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
          ForEach(permissions.permissions) { permission in
            GridRow {
              Text(permission.kind.rawValue)
              Text(permission.status.rawValue)
                .foregroundStyle(.secondary)
              Text(permission.classification)
                .foregroundStyle(.secondary)
              Text(permission.blocksFirstRun ? "blocks First Run" : "does not block")
                .foregroundStyle(.secondary)
            }
          }
        }
      }
    }
    if let connection = viewModel.snapshot.connection {
      detailSection(
        title: "Connection Test",
        rows: [
          ("Request", connection.requestSucceeded ? "succeeded" : "failed"),
          ("Protocol", connection.protocolCompatible ? "compatible" : "incompatible"),
          ("Health", connection.healthStatus.rawValue),
        ]
      )
    }
  }

  private func detailSection(title: String, rows: [(String, String)]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.headline)
      Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
        ForEach(rows, id: \.0) { label, value in
          GridRow {
            Text(label)
              .foregroundStyle(.secondary)
            Text(value)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var controls: some View {
    HStack(spacing: 10) {
      if hasAction(.openDiagnostics) {
        Button {
          viewModel.perform(.openDiagnostics)
        } label: {
          Label("Diagnostics", systemImage: "stethoscope")
        }
      }
      if hasAction(.openPrivacyCenter) {
        Button {
          viewModel.perform(.openPrivacyCenter)
        } label: {
          Label("Privacy", systemImage: "hand.raised")
        }
      }
      ForEach(recoveryActions, id: \.self) { action in
        if case .openRecovery = action {
          Button {
            viewModel.perform(action)
          } label: {
            Label("Recovery", systemImage: "wrench.and.screwdriver")
          }
        }
      }
      ForEach(systemSettingsActions, id: \.self) { action in
        if case .openSystemSettings(let permission) = action {
          Button {
            viewModel.perform(action)
          } label: {
            Label(permission.rawValue, systemImage: "gearshape")
          }
        }
      }
      Spacer()
      if hasAction(.retry) {
        Button {
          viewModel.perform(.retry)
        } label: {
          Label("Retry", systemImage: "arrow.clockwise")
        }
        .disabled(viewModel.isWorking)
      }
      if hasAction(.continue) {
        Button {
          viewModel.perform(.continue)
        } label: {
          Label("Continue", systemImage: "arrow.right")
        }
        .keyboardShortcut(.defaultAction)
        .disabled(viewModel.isWorking)
      }
      if hasAction(.finish) {
        Button {
          viewModel.perform(.finish)
        } label: {
          Label("Finish", systemImage: "checkmark")
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(18)
  }

  private var systemSettingsActions: [HermesOnboardingRemediationAction] {
    viewModel.snapshot.availableActions.filter {
      if case .openSystemSettings = $0 { return true }
      return false
    }
  }

  private var recoveryActions: [HermesOnboardingRemediationAction] {
    viewModel.snapshot.availableActions.filter {
      if case .openRecovery = $0 { return true }
      return false
    }
  }

  private func hasAction(_ action: HermesOnboardingRemediationAction) -> Bool {
    viewModel.snapshot.availableActions.contains(action)
  }

  private func marker(for step: HermesOnboardingStep) -> String {
    let all = HermesOnboardingStep.allCases
    let currentIndex = all.firstIndex(of: viewModel.snapshot.step) ?? 0
    let stepIndex = all.firstIndex(of: step) ?? 0
    if step == viewModel.snapshot.step { return "largecircle.fill.circle" }
    return stepIndex < currentIndex ? "checkmark.circle.fill" : "circle"
  }

  private func title(for step: HermesOnboardingStep) -> String {
    switch step {
    case .welcome: "Welcome"
    case .service: "Bridge Service"
    case .agent: "Hermes Agent"
    case .permissions: "Permissions"
    case .connection: "Connection"
    case .ready: "Ready"
    }
  }

  private func status(for step: HermesOnboardingStep) -> String {
    step == viewModel.snapshot.step ? "current" : ""
  }

  private var iconName: String {
    switch viewModel.snapshot.state {
    case .ready: return "checkmark.seal"
    case .serviceUnavailable, .agentUnavailable, .permissionsRequired, .connectionFailed:
      return "exclamationmark.triangle"
    default:
      return "point.3.connected.trianglepath.dotted"
    }
  }

  private var iconColor: Color {
    switch viewModel.snapshot.state {
    case .ready: return .green
    case .serviceUnavailable, .agentUnavailable, .permissionsRequired, .connectionFailed:
      return .orange
    default:
      return .accentColor
    }
  }
}
