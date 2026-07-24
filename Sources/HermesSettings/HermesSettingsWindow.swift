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

        Section("Logging") {
          Picker("Log level", selection: $viewModel.draftSettings.logLevel) {
            ForEach(HermesSettingsLogLevel.allCases, id: \.self) { level in
              Text(level.rawValue).tag(level)
            }
          }
          .pickerStyle(.segmented)
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
