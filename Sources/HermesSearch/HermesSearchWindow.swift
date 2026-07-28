import AppKit
import SwiftUI

public final class HermesSearchCenterWindowController: NSWindowController {
  @MainActor
  public init(viewModel: HermesSearchViewModel) {
    let rootView = HermesSearchCenterWindow(viewModel: viewModel)
    let hostingController = NSHostingController(rootView: rootView)
    let window = NSWindow(contentViewController: hostingController)
    window.title = "Hermes Search Center"
    window.setContentSize(NSSize(width: 820, height: 620))
    window.minSize = NSSize(width: 680, height: 480)
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) is unavailable")
  }
}

public struct HermesSearchCenterWindow: View {
  @ObservedObject private var viewModel: HermesSearchViewModel

  public init(viewModel: HermesSearchViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      filters
      Divider()
      resultsList
    }
    .frame(minWidth: 680, minHeight: 480)
    .task {
      viewModel.load()
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: "magnifyingglass")
        .font(.title2)
        .foregroundStyle(Color.accentColor)
      VStack(alignment: .leading, spacing: 2) {
        Text("Hermes Search Center")
          .font(.title2)
        Text("\(viewModel.results.count) results")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer()
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
  }

  private var filters: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        TextField("Search Hermes History", text: $viewModel.queryText)
          .textFieldStyle(.roundedBorder)
          .onSubmit { viewModel.search() }
        Button {
          viewModel.search()
        } label: {
          Label("Search", systemImage: "magnifyingglass")
        }
      }
      HStack(spacing: 8) {
        ForEach(HermesSearchCategory.allCases, id: \.self) { category in
          Toggle(category.rawValue.capitalized, isOn: Binding(
            get: { viewModel.selectedCategories.contains(category) },
            set: { viewModel.setCategory(category, enabled: $0) }
          ))
          .toggleStyle(.checkbox)
        }
        Spacer()
        Picker("Severity", selection: Binding<HermesSearchSeverity?>(
          get: { viewModel.minimumSeverity },
          set: { viewModel.setMinimumSeverity($0) }
        )) {
          Text("Any").tag(Optional<HermesSearchSeverity>.none)
          ForEach(HermesSearchSeverity.allCases, id: \.self) { severity in
            Text(severityLabel(severity)).tag(Optional(severity))
          }
        }
        .frame(width: 160)
      }
      if let message = viewModel.lastErrorMessage {
        Label(message, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.red)
          .lineLimit(2)
      }
    }
    .padding(18)
  }

  private var resultsList: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        if viewModel.results.isEmpty {
          Text("No search results")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        } else {
          ForEach(viewModel.results) { result in
            resultRow(result)
            Divider()
          }
        }
      }
    }
  }

  private func resultRow(_ result: HermesSearchRecord) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: icon(for: result.category))
        .foregroundStyle(color(for: result.severity))
        .frame(width: 20)
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(result.title)
            .font(.headline)
          Spacer()
          Text(severityLabel(result.severity))
            .foregroundStyle(color(for: result.severity))
        }
        Text(result.timestamp.formatted(date: .abbreviated, time: .standard))
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(result.summary)
          .foregroundStyle(.secondary)
          .lineLimit(3)
        Text("\(result.category.rawValue) • \(result.source.rawValue)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 12)
  }

  private func icon(for category: HermesSearchCategory) -> String {
    switch category {
    case .timeline:
      return "clock"
    case .logs:
      return "doc.text.magnifyingglass"
    case .notifications:
      return "bell"
    case .diagnostics:
      return "stethoscope"
    case .audit:
      return "checkmark.shield"
    }
  }

  private func color(for severity: HermesSearchSeverity) -> Color {
    switch severity {
    case .info:
      return .secondary
    case .warning:
      return .orange
    case .error:
      return .red
    case .critical:
      return .purple
    }
  }

  private func severityLabel(_ severity: HermesSearchSeverity) -> String {
    switch severity {
    case .info:
      return "Info"
    case .warning:
      return "Warning"
    case .error:
      return "Error"
    case .critical:
      return "Critical"
    }
  }
}
