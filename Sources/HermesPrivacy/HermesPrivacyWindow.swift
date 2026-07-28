import AppKit
import SwiftUI

public final class HermesPrivacyWindowController: NSWindowController {
  @MainActor
  public init(viewModel: HermesPrivacyViewModel) {
    let rootView = HermesPrivacyWindow(viewModel: viewModel)
    let hostingController = NSHostingController(rootView: rootView)
    let window = NSWindow(contentViewController: hostingController)
    window.title = "Hermes Privacy Center"
    window.setContentSize(NSSize(width: 760, height: 620))
    window.minSize = NSSize(width: 640, height: 520)
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) is unavailable")
  }
}

public struct HermesPrivacyWindow: View {
  @ObservedObject private var viewModel: HermesPrivacyViewModel

  public init(viewModel: HermesPrivacyViewModel) {
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
          consentSection
          preferencesSection
          policySection
          auditSection
        }
        .padding(18)
      }
    }
    .frame(minWidth: 640, minHeight: 520)
    .task {
      viewModel.load()
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: "hand.raised")
        .font(.title2)
        .foregroundStyle(Color.accentColor)
      VStack(alignment: .leading, spacing: 2) {
        Text("Hermes Privacy Center")
          .font(.title2)
        Text("\(viewModel.records.count) consent categories")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer()
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
  }

  private var consentSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Consent")
        .font(.headline)
      ForEach(viewModel.records) { record in
        HStack(alignment: .top, spacing: 10) {
          Image(systemName: icon(for: record.category))
            .frame(width: 22)
            .foregroundStyle(record.status == .allowed ? .green : .secondary)
          VStack(alignment: .leading, spacing: 2) {
            Toggle(
              categoryLabel(record.category),
              isOn: Binding(
                get: { viewModel.isAllowed(record.category) },
                set: { viewModel.setConsent(category: record.category, isAllowed: $0) }
              )
            )
            .toggleStyle(.switch)
            Text("\(statusLabel(record.status)) • \(sourceLabel(record.source))")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  private var preferencesSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Local Data")
        .font(.headline)
      Toggle("Privacy reminders", isOn: Binding(
        get: { viewModel.preferences.showPrivacyReminders },
        set: { viewModel.setShowPrivacyReminders($0) }
      ))
      Toggle("Retain local history", isOn: Binding(
        get: { viewModel.preferences.retainLocalHistory },
        set: { viewModel.setRetainLocalHistory($0) }
      ))
      Button {
        viewModel.openPolicyCenter()
      } label: {
        Label("Open Policy Center", systemImage: "building.2.crop.circle")
      }
      Button {
        viewModel.clearStoredLocalData()
      } label: {
        Label("Clear Stored Local Privacy Data", systemImage: "trash")
      }
    }
  }

  private var policySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Policy")
        .font(.headline)
      Text(viewModel.policySummary)
        .foregroundStyle(.secondary)
      Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
        GridRow {
          Text("Namespace").foregroundStyle(.secondary)
          Text(viewModel.safeMetadata.policyNamespace)
        }
        GridRow {
          Text("Application").foregroundStyle(.secondary)
          Text(viewModel.safeMetadata.applicationVersion ?? "unknown")
        }
        GridRow {
          Text("Build").foregroundStyle(.secondary)
          Text(viewModel.safeMetadata.buildVersion ?? "unknown")
        }
      }
    }
  }

  private var auditSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Consent Audit")
        .font(.headline)
      if viewModel.auditEvents.isEmpty {
        Text("No consent changes recorded")
          .foregroundStyle(.secondary)
      } else {
        ForEach(viewModel.auditEvents.prefix(8)) { event in
          HStack {
            Image(systemName: "clock.arrow.circlepath")
              .foregroundStyle(.secondary)
            Text(categoryLabel(event.category))
            Spacer()
            Text("\(statusLabel(event.oldStatus)) -> \(statusLabel(event.newStatus))")
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  private func categoryLabel(_ category: HermesPrivacyConsentCategory) -> String {
    switch category {
    case .diagnosticsCollection: return "Diagnostics Collection"
    case .usageAnalytics: return "Usage Analytics"
    case .crashInformation: return "Crash Information"
    case .updateCheckMetadata: return "Update Check Metadata"
    case .localHistoryRetention: return "Local History Retention"
    }
  }

  private func statusLabel(_ status: HermesPrivacyConsentStatus) -> String {
    switch status {
    case .unknown: return "denied"
    case .allowed: return "allowed"
    case .denied: return "denied"
    }
  }

  private func sourceLabel(_ source: HermesPrivacyConsentSource) -> String {
    switch source {
    case .defaultPolicy: return "default policy"
    case .privacyCenter: return "privacy center"
    case .onboarding: return "onboarding"
    case .settings: return "settings"
    case .diagnostics: return "diagnostics"
    }
  }

  private func icon(for category: HermesPrivacyConsentCategory) -> String {
    switch category {
    case .diagnosticsCollection: return "stethoscope"
    case .usageAnalytics: return "chart.xyaxis.line"
    case .crashInformation: return "exclamationmark.triangle"
    case .updateCheckMetadata: return "arrow.up.circle"
    case .localHistoryRetention: return "clock"
    }
  }
}
