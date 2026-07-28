import AppKit
import SwiftUI

public final class HermesFeedbackWindowController: NSWindowController {
  @MainActor
  public init(viewModel: HermesFeedbackViewModel) {
    let rootView = HermesFeedbackWindow(viewModel: viewModel)
    let hostingController = NSHostingController(rootView: rootView)
    let window = NSWindow(contentViewController: hostingController)
    window.title = "Hermes Feedback Center"
    window.setContentSize(NSSize(width: 780, height: 620))
    window.minSize = NSSize(width: 680, height: 520)
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) is unavailable")
  }
}

public struct HermesFeedbackWindow: View {
  @ObservedObject private var viewModel: HermesFeedbackViewModel

  public init(viewModel: HermesFeedbackViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          composer
          if let message = viewModel.lastErrorMessage {
            Label(message, systemImage: "exclamationmark.triangle")
              .foregroundStyle(.orange)
              .lineLimit(3)
          }
          feedbackList
        }
        .padding(18)
      }
    }
    .frame(minWidth: 680, minHeight: 520)
    .task {
      viewModel.load()
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: "bubble.left.and.text.bubble.right")
        .font(.title2)
        .foregroundStyle(Color.accentColor)
      VStack(alignment: .leading, spacing: 2) {
        Text("Hermes Feedback Center")
          .font(.title2)
        Text("\(viewModel.records.count) local items")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer()
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
  }

  private var composer: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 12) {
        Picker("Category", selection: $viewModel.selectedCategory) {
          ForEach(HermesFeedbackCategory.allCases, id: \.self) { category in
            Text(categoryLabel(category)).tag(category)
          }
        }
        Picker("Severity", selection: $viewModel.severity) {
          ForEach(HermesFeedbackSeverity.allCases, id: \.self) { severity in
            Text(severityLabel(severity)).tag(severity)
          }
        }
        Toggle("Safe Context", isOn: Binding(
          get: { viewModel.includeSafeRuntimeContext },
          set: { viewModel.setIncludeSafeRuntimeContext($0) }
        ))
        .toggleStyle(.checkbox)
      }
      TextField("Title", text: $viewModel.title)
        .textFieldStyle(.roundedBorder)
      TextField("Related Feature", text: $viewModel.relatedFeature)
        .textFieldStyle(.roundedBorder)
      TextEditor(text: $viewModel.description)
        .font(.body)
        .frame(minHeight: 110)
        .overlay(
          RoundedRectangle(cornerRadius: 6)
            .stroke(Color.secondary.opacity(0.25))
        )
      HStack {
        Spacer()
        Button {
          viewModel.createDraft()
        } label: {
          Label("Create Feedback", systemImage: "plus.circle")
        }
        .keyboardShortcut(.defaultAction)
      }
    }
  }

  private var feedbackList: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Local Feedback")
        .font(.headline)
      if viewModel.records.isEmpty {
        Text("No feedback recorded")
          .foregroundStyle(.secondary)
      } else {
        ForEach(viewModel.records) { record in
          feedbackRow(record)
          Divider()
        }
      }
    }
  }

  private func feedbackRow(_ record: HermesFeedbackRecord) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: icon(for: record.category))
        .frame(width: 22)
        .foregroundStyle(color(for: record.severity))
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(record.title.isEmpty ? "Untitled feedback" : record.title)
            .font(.headline)
          Spacer()
          Text(record.status.rawValue)
            .foregroundStyle(.secondary)
        }
        Text("\(categoryLabel(record.category)) • \(severityLabel(record.severity))")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(record.description)
          .lineLimit(3)
          .foregroundStyle(.secondary)
        if let context = record.safeRuntimeContext {
          Text(contextSummary(context))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
        HStack(spacing: 8) {
          lifecycleButton("Ready", systemImage: "checkmark.circle", record: record, status: .ready)
          lifecycleButton("Submit Locally", systemImage: "tray.and.arrow.down", record: record, status: .submitted)
          lifecycleButton("Resolved", systemImage: "checkmark.seal", record: record, status: .resolved)
          lifecycleButton("Archive", systemImage: "archivebox", record: record, status: .archived)
        }
      }
    }
    .padding(.vertical, 4)
  }

  private func lifecycleButton(
    _ title: String,
    systemImage: String,
    record: HermesFeedbackRecord,
    status: HermesFeedbackStatus
  ) -> some View {
    Button {
      viewModel.transition(record, to: status)
    } label: {
      Label(title, systemImage: systemImage)
    }
    .disabled(record.status == status)
  }

  private func categoryLabel(_ category: HermesFeedbackCategory) -> String {
    switch category {
    case .bugReport: return "Bug Report"
    case .featureRequest: return "Feature Request"
    case .runtimeIssueReport: return "Runtime Issue"
    case .recoveryFeedback: return "Recovery Feedback"
    case .updateFeedback: return "Update Feedback"
    }
  }

  private func severityLabel(_ severity: HermesFeedbackSeverity) -> String {
    switch severity {
    case .informational: return "Informational"
    case .low: return "Low"
    case .medium: return "Medium"
    case .high: return "High"
    case .critical: return "Critical"
    }
  }

  private func icon(for category: HermesFeedbackCategory) -> String {
    switch category {
    case .bugReport: return "exclamationmark.bubble"
    case .featureRequest: return "sparkles"
    case .runtimeIssueReport: return "exclamationmark.triangle"
    case .recoveryFeedback: return "wrench.and.screwdriver"
    case .updateFeedback: return "arrow.up.circle"
    }
  }

  private func color(for severity: HermesFeedbackSeverity) -> Color {
    switch severity {
    case .informational, .low:
      return .secondary
    case .medium:
      return .blue
    case .high:
      return .orange
    case .critical:
      return .red
    }
  }

  private func contextSummary(_ context: HermesFeedbackSafeRuntimeContext) -> String {
    [
      context.applicationVersion.map { "app \($0)" },
      context.runtimeStatusSummary,
      context.protocolVersion.map { "protocol \($0)" },
      context.featureName,
    ].compactMap { $0 }.joined(separator: " • ")
  }
}
