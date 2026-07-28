import AppKit
import SwiftUI

public final class HermesActivityTimelineWindowController: NSWindowController {
  @MainActor
  public init(viewModel: HermesTimelineViewModel) {
    let rootView = HermesActivityTimelineWindow(viewModel: viewModel)
    let hostingController = NSHostingController(rootView: rootView)
    let window = NSWindow(contentViewController: hostingController)
    window.title = "Hermes Activity Timeline"
    window.setContentSize(NSSize(width: 720, height: 560))
    window.minSize = NSSize(width: 580, height: 420)
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) is unavailable")
  }
}

public struct HermesActivityTimelineWindow: View {
  @ObservedObject private var viewModel: HermesTimelineViewModel

  public init(viewModel: HermesTimelineViewModel) {
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
    .frame(minWidth: 580, minHeight: 420)
    .task {
      viewModel.refresh()
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: "timeline.selection")
        .font(.title2)
        .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 2) {
        Text("Hermes Activity Timeline")
          .font(.title2)
        Text("Chronological runtime activity")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer()
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
  }

  private var content: some View {
    List(viewModel.snapshot.items) { item in
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: icon(for: item.category))
          .foregroundStyle(color(for: item.status))
          .frame(width: 20)
        VStack(alignment: .leading, spacing: 5) {
          HStack(alignment: .firstTextBaseline) {
            Text(item.title)
              .font(.headline)
            Spacer()
            Text(item.timestamp.formatted(date: .abbreviated, time: .standard))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Text(item.summary)
            .foregroundStyle(.secondary)
            .lineLimit(3)
          HStack(spacing: 8) {
            Text(item.category.rawValue)
            Text(item.status.rawValue)
            if item.duplicateCount > 1 {
              Text("x\(item.duplicateCount)")
            }
          }
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }
      .padding(.vertical, 6)
    }
    .overlay {
      if viewModel.snapshot.items.isEmpty {
        Text("No timeline activity")
          .foregroundStyle(.secondary)
      }
    }
  }

  private var controls: some View {
    HStack {
      if let message = viewModel.lastErrorMessage {
        Text(message)
          .foregroundStyle(.red)
          .lineLimit(1)
      }
      Spacer()
      Button {
        viewModel.refresh()
      } label: {
        Label("Refresh", systemImage: "arrow.clockwise")
      }
      Button {
        viewModel.clearHistory()
      } label: {
        Label("Clear History", systemImage: "trash")
      }
    }
    .padding(18)
  }

  private func icon(for category: HermesTimelineCategory) -> String {
    switch category {
    case .runtimeStarted:
      return "play.circle"
    case .runtimeStopped:
      return "stop.circle"
    case .connectionEstablished:
      return "link.circle"
    case .connectionLost:
      return "link.badge.plus"
    case .runtimeDegraded:
      return "exclamationmark.triangle"
    case .runtimeRecovered:
      return "checkmark.circle"
    case .notificationCreated:
      return "bell"
    case .recoveryStarted, .recoveryCompleted:
      return "cross.case"
    case .updateAvailable, .updateStarted, .updateCompleted, .updateRolledBack:
      return "arrow.down.circle"
    }
  }

  private func color(for status: HermesTimelineStatus) -> Color {
    switch status {
    case .informational:
      return .secondary
    case .inProgress:
      return .blue
    case .completed:
      return .green
    case .warning:
      return .orange
    case .failed:
      return .red
    }
  }
}
