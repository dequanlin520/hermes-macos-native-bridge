import AppKit
import SwiftUI

public final class HermesReportingWindowController: NSWindowController {
  @MainActor
  public init(viewModel: HermesReportingViewModel) {
    let rootView = HermesReportingWindow(viewModel: viewModel)
    let hostingController = NSHostingController(rootView: rootView)
    let window = NSWindow(contentViewController: hostingController)
    window.title = "Hermes Enterprise Reporting Center"
    window.setContentSize(NSSize(width: 920, height: 720))
    window.minSize = NSSize(width: 760, height: 560)
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) is unavailable")
  }
}

public struct HermesReportingWindow: View {
  @ObservedObject private var viewModel: HermesReportingViewModel

  public init(viewModel: HermesReportingViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          if let message = viewModel.lastErrorMessage {
            Label(message, systemImage: "exclamationmark.triangle")
              .foregroundStyle(.red)
              .lineLimit(3)
          }
          reportGrid
          generatedSection
          historySection
          boundarySection
        }
        .padding(18)
      }
      Divider()
      controls
    }
    .frame(minWidth: 760, minHeight: 560)
    .task {
      viewModel.refresh()
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: "doc.text.magnifyingglass")
        .font(.title2)
        .foregroundStyle(color(for: viewModel.snapshot.overallState))
      VStack(alignment: .leading, spacing: 2) {
        Text("Hermes Enterprise Reporting Center")
          .font(.title2)
        Text(viewModel.snapshot.overallState.rawValue)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer()
      if viewModel.isRefreshing {
        ProgressView()
          .controlSize(.small)
      }
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
  }

  private var reportGrid: some View {
    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
      sectionRow(viewModel.snapshot.health)
      sectionRow(viewModel.snapshot.operations)
      sectionRow(viewModel.snapshot.analytics)
      sectionRow(viewModel.snapshot.compliance)
      sectionRow(viewModel.snapshot.audit)
    }
  }

  private func sectionRow(_ summary: HermesReportDomainSummary) -> some View {
    GridRow {
      Label(summary.title, systemImage: icon(for: summary.title))
        .font(.headline)
      VStack(alignment: .leading, spacing: 4) {
        Text(summary.state.rawValue)
          .foregroundStyle(color(for: summary.state))
        Text(summary.summary)
          .lineLimit(2)
        ForEach(summary.details.prefix(3), id: \.self) { detail in
          Text(detail)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
    }
  }

  private var generatedSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Generated Report")
        .font(.headline)
      if let document = viewModel.lastGeneratedDocument {
        Text("\(document.fileName) | \(document.format.rawValue) | \(document.body.utf8.count) bytes")
          .foregroundStyle(.secondary)
        Text(document.body)
          .font(.system(.caption, design: .monospaced))
          .lineLimit(8)
      } else {
        Text("No generated report")
          .foregroundStyle(.secondary)
      }
    }
  }

  private var historySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Report History")
        .font(.headline)
      if viewModel.snapshot.history.isEmpty {
        Text("No saved reports")
          .foregroundStyle(.secondary)
      } else {
        ForEach(viewModel.snapshot.history.prefix(8)) { entry in
          Label("\(entry.relativePath) | \(entry.format.rawValue) | \(entry.byteCount) bytes", systemImage: "doc.text")
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
    }
  }

  private var boundarySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Boundary")
        .font(.headline)
      Text(viewModel.boundarySummary)
        .foregroundStyle(.secondary)
    }
  }

  private var controls: some View {
    HStack(spacing: 10) {
      Button {
        viewModel.openSettings()
      } label: {
        Label("Settings", systemImage: "gearshape.2")
      }
      Button {
        viewModel.openAdministrationCenter()
      } label: {
        Label("Administration", systemImage: "building.columns")
      }
      Spacer()
      Button {
        viewModel.generate(format: .markdown)
      } label: {
        Label("Markdown", systemImage: "doc.plaintext")
      }
      .disabled(viewModel.isRefreshing)
      Button {
        viewModel.generate(format: .html)
      } label: {
        Label("HTML", systemImage: "globe")
      }
      .disabled(viewModel.isRefreshing)
      Button {
        viewModel.saveLastGeneratedReport()
      } label: {
        Label("Save", systemImage: "square.and.arrow.down")
      }
      .disabled(viewModel.lastGeneratedDocument == nil)
      Button {
        viewModel.refresh()
      } label: {
        Label("Refresh", systemImage: "arrow.clockwise")
      }
      .keyboardShortcut(.defaultAction)
      .disabled(viewModel.isRefreshing)
    }
    .padding(18)
  }

  private func icon(for title: String) -> String {
    switch title {
    case "Health":
      return "heart.text.square"
    case "Operations":
      return "command.circle"
    case "Analytics":
      return "chart.xyaxis.line"
    case "Compliance":
      return "checkmark.seal"
    default:
      return "doc.text.magnifyingglass"
    }
  }

  private func color(for state: HermesReportingState) -> Color {
    switch state {
    case .ready:
      return .green
    case .attentionRequired:
      return .orange
    case .unavailable:
      return .red
    case .unknown:
      return .secondary
    }
  }
}
