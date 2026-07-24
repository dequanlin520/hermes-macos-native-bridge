import AppKit
import HermesRuntimeFoundation
import SwiftUI

public final class HermesLogsViewerWindowController: NSWindowController {
  @MainActor
  public init(viewModel: HermesLogsViewerViewModel) {
    let rootView = HermesLogsViewerWindow(viewModel: viewModel)
    let hostingController = NSHostingController(rootView: rootView)
    let window = NSWindow(contentViewController: hostingController)
    window.title = "Hermes Runtime Logs"
    window.setContentSize(NSSize(width: 760, height: 520))
    window.minSize = NSSize(width: 620, height: 420)
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) is unavailable")
  }
}

public struct HermesLogsViewerWindow: View {
  @ObservedObject private var viewModel: HermesLogsViewerViewModel

  public init(viewModel: HermesLogsViewerViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      filterBar
      Divider()
      logsList
    }
    .frame(minWidth: 620, minHeight: 420)
    .task {
      viewModel.startEventSubscription()
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: "list.bullet.rectangle")
        .font(.title2)
      VStack(alignment: .leading, spacing: 2) {
        Text("Hermes Runtime Logs")
          .font(.title2)
        Text("\(viewModel.state.filteredEntries.count) visible of \(viewModel.state.entries.count)")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button {
        viewModel.clearView()
      } label: {
        Label("Clear", systemImage: "trash")
      }
      .disabled(viewModel.state.entries.isEmpty)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
  }

  private var filterBar: some View {
    Picker("Severity", selection: Binding(
      get: { viewModel.state.filter },
      set: { viewModel.setFilter($0) }
    )) {
      ForEach(HermesRuntimeLogFilter.allCases, id: \.self) { filter in
        Text(filter.rawValue.capitalized).tag(filter)
      }
    }
    .pickerStyle(.segmented)
    .padding(18)
  }

  private var logsList: some View {
    Group {
      if viewModel.state.filteredEntries.isEmpty {
        VStack(spacing: 8) {
          Image(systemName: "doc.text.magnifyingglass")
            .font(.largeTitle)
            .foregroundStyle(.secondary)
          Text("No runtime events")
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List(viewModel.state.filteredEntries) { entry in
          HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon(for: entry.severity))
              .foregroundStyle(color(for: entry.severity))
              .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
              HStack(alignment: .firstTextBaseline) {
                Text(entry.eventType.rawValue)
                  .font(.headline)
                Text(entry.severity.rawValue)
                  .font(.caption)
                  .foregroundStyle(color(for: entry.severity))
                Spacer()
                Text(entry.timestamp.formatted(date: .abbreviated, time: .standard))
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Text(entry.redactedSummary)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(3)
            }
          }
          .padding(.vertical, 4)
        }
      }
    }
  }

  private func icon(for severity: HermesRuntimeLogLevel) -> String {
    switch severity {
    case .info:
      return "info.circle"
    case .warning:
      return "exclamationmark.triangle"
    case .error:
      return "xmark.octagon"
    }
  }

  private func color(for severity: HermesRuntimeLogLevel) -> Color {
    switch severity {
    case .info:
      return .secondary
    case .warning:
      return .orange
    case .error:
      return .red
    }
  }
}
