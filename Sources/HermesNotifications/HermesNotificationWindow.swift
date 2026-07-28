import AppKit
import SwiftUI

public final class HermesNotificationWindowController: NSWindowController {
  @MainActor
  public init(viewModel: HermesNotificationViewModel) {
    let rootView = HermesNotificationWindow(viewModel: viewModel)
    let hostingController = NSHostingController(rootView: rootView)
    let window = NSWindow(contentViewController: hostingController)
    window.title = "Hermes Notifications"
    window.setContentSize(NSSize(width: 680, height: 520))
    window.minSize = NSSize(width: 560, height: 420)
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) is unavailable")
  }
}

public struct HermesNotificationWindow: View {
  @ObservedObject private var viewModel: HermesNotificationViewModel

  public init(viewModel: HermesNotificationViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      List(viewModel.notifications) { notification in
        VStack(alignment: .leading, spacing: 6) {
          HStack {
            Text(notification.title)
              .font(.headline)
            Spacer()
            Text(notification.category.rawValue)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Text(notification.body)
            .foregroundStyle(.secondary)
            .lineLimit(3)
          HStack {
            Text(notification.lifecycle.rawValue)
              .font(.caption)
              .foregroundStyle(.secondary)
            Spacer()
            Button {
              viewModel.acknowledge(notification.id)
            } label: {
              Label("Acknowledge", systemImage: "checkmark.circle")
            }
            Button {
              viewModel.resolve(notification.id)
            } label: {
              Label("Resolve", systemImage: "checkmark.seal")
            }
          }
        }
        .padding(.vertical, 6)
      }
    }
    .frame(minWidth: 560, minHeight: 420)
    .task {
      viewModel.refresh()
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: "bell.badge")
        .font(.title2)
        .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 2) {
        Text("Hermes Notifications")
          .font(.title2)
        Text("Runtime, update, permission, and recovery alerts")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer()
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
  }
}
