import AppKit
import SwiftUI

public final class HermesRecoveryWindowController: NSWindowController {
  @MainActor
  public init(viewModel: HermesRecoveryViewModel) {
    let rootView = HermesRecoveryWindow(viewModel: viewModel)
    let hostingController = NSHostingController(rootView: rootView)
    let window = NSWindow(contentViewController: hostingController)
    window.title = "Hermes Recovery"
    window.setContentSize(NSSize(width: 700, height: 520))
    window.minSize = NSSize(width: 620, height: 460)
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) is unavailable")
  }
}

public struct HermesRecoveryWindow: View {
  @ObservedObject private var viewModel: HermesRecoveryViewModel

  public init(viewModel: HermesRecoveryViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          summary
          actions
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .frame(minWidth: 620, minHeight: 460)
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: iconName)
        .font(.title2)
        .foregroundStyle(iconColor)
      VStack(alignment: .leading, spacing: 2) {
        Text("Hermes Recovery")
          .font(.title2)
        Text(viewModel.snapshot.state.rawValue)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer()
      if viewModel.isWorking || viewModel.snapshot.state == .evaluating
        || viewModel.snapshot.state == .executing || viewModel.snapshot.state == .verifying
      {
        ProgressView()
          .controlSize(.small)
      }
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
  }

  private var summary: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(viewModel.snapshot.issue?.rawValue ?? "No issue selected")
        .font(.headline)
      Text(viewModel.snapshot.message)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      if let compatibility = viewModel.snapshot.compatibilityStatus {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
          GridRow {
            Text("Client Protocol")
              .foregroundStyle(.secondary)
            Text(viewModel.snapshot.clientProtocolVersion)
          }
          GridRow {
            Text("Compatibility")
              .foregroundStyle(.secondary)
            Text(compatibility)
          }
        }
      }
    }
  }

  private var actions: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Actions")
        .font(.headline)
      if viewModel.snapshot.actions.isEmpty {
        Text("No recovery actions available")
          .foregroundStyle(.secondary)
      } else {
        ForEach(viewModel.snapshot.actions) { action in
          HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol(for: action.actionType))
              .frame(width: 22)
              .foregroundStyle(action.requiresConfirmation ? .orange : .accentColor)
            VStack(alignment: .leading, spacing: 4) {
              Text(title(for: action.actionType))
              Text(action.explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
              viewModel.perform(action.actionType, confirmed: action.requiresConfirmation)
            } label: {
              Label(action.requiresConfirmation ? "Confirm" : "Run", systemImage: action.requiresConfirmation ? "checkmark.shield" : "play")
            }
            .disabled(viewModel.isWorking)
          }
          .padding(.vertical, 4)
        }
      }
    }
  }

  private func title(for action: HermesRecoveryActionType) -> String {
    switch action {
    case .retryConnection: return "Retry Connection"
    case .restartBridgeService: return "Restart Bridge Service"
    case .refreshAgentDiscovery: return "Refresh Agent Discovery"
    case .rerunPermissionsCheck: return "Rerun Permissions Check"
    case .openSystemSettings(let permission): return "Open \(permission.rawValue)"
    case .openDiagnostics: return "Open Diagnostics"
    case .showUpgradeRequired: return "Upgrade Required"
    case .rerunReadiness: return "Rerun Readiness"
    case .dismiss: return "Dismiss"
    }
  }

  private func symbol(for action: HermesRecoveryActionType) -> String {
    switch action {
    case .retryConnection, .rerunPermissionsCheck, .rerunReadiness:
      return "arrow.clockwise"
    case .restartBridgeService:
      return "power"
    case .refreshAgentDiscovery:
      return "magnifyingglass"
    case .openSystemSettings:
      return "gearshape"
    case .openDiagnostics:
      return "stethoscope"
    case .showUpgradeRequired:
      return "arrow.up.circle"
    case .dismiss:
      return "xmark"
    }
  }

  private var iconName: String {
    switch viewModel.snapshot.state {
    case .recovered: return "checkmark.seal"
    case .stillBlocked, .failed: return "exclamationmark.triangle"
    default: return "wrench.and.screwdriver"
    }
  }

  private var iconColor: Color {
    switch viewModel.snapshot.state {
    case .recovered: return .green
    case .stillBlocked, .failed: return .orange
    default: return .accentColor
    }
  }
}
