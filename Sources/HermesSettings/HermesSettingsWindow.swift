import AppKit
import SwiftUI

public final class HermesSettingsWindowController: NSWindowController {
  @MainActor
  public init(viewModel: HermesSettingsViewModel) {
    let rootView = HermesSettingsWindow(viewModel: viewModel)
    let hostingController = NSHostingController(rootView: rootView)
    let window = NSWindow(contentViewController: hostingController)
    window.title = "Hermes Settings"
    window.setContentSize(NSSize(width: 620, height: 520))
    window.minSize = NSSize(width: 540, height: 460)
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) is unavailable")
  }
}

public struct HermesSettingsWindow: View {
  @ObservedObject private var viewModel: HermesSettingsViewModel

  public init(viewModel: HermesSettingsViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      Form {
        Section("Runtime") {
          Toggle("Start Hermes automatically", isOn: $viewModel.draftSettings.runtime.autoStart)
          Stepper(
            value: $viewModel.draftSettings.runtime.healthCheckIntervalSeconds,
            in: 0...3600,
            step: 5
          ) {
            settingRow(
              "Health check interval",
              value: "\(viewModel.draftSettings.runtime.healthCheckIntervalSeconds) seconds"
            )
          }
          Stepper(
            value: $viewModel.draftSettings.runtime.startupTimeoutSeconds,
            in: 1...3600,
            step: 5
          ) {
            settingRow(
              "Startup timeout",
              value: "\(viewModel.draftSettings.runtime.startupTimeoutSeconds) seconds"
            )
          }
        }

        Section("Interface") {
          Toggle("Show menu bar icon", isOn: $viewModel.draftSettings.ui.showMenuBarIcon)
          Toggle("Enable notifications", isOn: $viewModel.draftSettings.ui.enableNotifications)
          Stepper(
            value: $viewModel.draftSettings.ui.dashboardRefreshIntervalSeconds,
            in: 0...3600,
            step: 1
          ) {
            settingRow(
              "Dashboard refresh interval",
              value: "\(viewModel.draftSettings.ui.dashboardRefreshIntervalSeconds) seconds"
            )
          }
        }

        Section("Alerts") {
          Toggle("Runtime alerts", isOn: $viewModel.draftSettings.ui.runtimeAlerts)
          Toggle("Update alerts", isOn: $viewModel.draftSettings.ui.updateAlerts)
          Toggle("Recovery alerts", isOn: $viewModel.draftSettings.ui.recoveryAlerts)
          Toggle("Permission alerts", isOn: $viewModel.draftSettings.ui.permissionAlerts)
        }

        Section("Logging") {
          Picker("Log level", selection: $viewModel.draftSettings.logLevel) {
            ForEach(HermesSettingsLogLevel.allCases, id: \.self) { level in
              Text(level.rawValue).tag(level)
            }
          }
          .pickerStyle(.segmented)
        }

        Section("Onboarding") {
          Button {
            viewModel.reopenOnboarding()
          } label: {
            Label("Open First Run Onboarding", systemImage: "checklist")
          }
        }

        Section("Updates") {
          Button {
            viewModel.openUpdateCenter()
          } label: {
            Label("Open Update Center", systemImage: "arrow.up.circle")
          }
        }

        Section("Privacy") {
          Button {
            viewModel.openPrivacyCenter()
          } label: {
            Label("Open Privacy Center", systemImage: "hand.raised")
          }
        }

        Section("Enterprise Policy") {
          Button {
            viewModel.openPolicyCenter()
          } label: {
            Label("Open Policy Center", systemImage: "building.2.crop.circle")
          }
        }

        Section("Enterprise Administration") {
          Button {
            viewModel.openAdministrationCenter()
          } label: {
            Label("Open Administration Center", systemImage: "building.columns")
          }
        }

        Section("Enterprise Compliance") {
          Button {
            viewModel.openComplianceCenter()
          } label: {
            Label("Open Compliance Center", systemImage: "checkmark.seal")
          }
        }

        Section("Enterprise Health") {
          Button {
            viewModel.openHealthCenter()
          } label: {
            Label("Open Health Center", systemImage: "heart.text.square")
          }
        }

        Section("Enterprise Operations") {
          Button {
            viewModel.openOperationsCenter()
          } label: {
            Label("Open Operations Center", systemImage: "command.circle")
          }
        }

        Section("Enterprise Analytics") {
          Button {
            viewModel.openAnalyticsCenter()
          } label: {
            Label("Open Analytics Center", systemImage: "chart.xyaxis.line")
          }
        }
      }
      .formStyle(.grouped)

      if let message = viewModel.state.lastErrorMessage {
        Divider()
        Label(message, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.red)
          .lineLimit(2)
          .padding(.horizontal, 18)
          .padding(.vertical, 10)
      }

      Divider()
      controls
    }
    .frame(minWidth: 540, minHeight: 460)
    .task {
      viewModel.load()
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: "gearshape.2")
        .font(.title2)
        .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 2) {
        Text("Hermes Settings")
          .font(.title2)
        Text("Runtime, interface, and logging preferences")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer()
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
  }

  private func settingRow(_ label: String, value: String) -> some View {
    HStack {
      Text(label)
      Spacer()
      Text(value)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
  }

  private var controls: some View {
    HStack(spacing: 10) {
      Button {
        viewModel.resetDraft()
      } label: {
        Label("Revert", systemImage: "arrow.uturn.backward")
      }

      Spacer()

      Button {
        viewModel.save()
      } label: {
        Label("Save", systemImage: "checkmark")
      }
      .keyboardShortcut(.defaultAction)
      .disabled(viewModel.state.isSaving)
    }
    .padding(18)
  }
}
