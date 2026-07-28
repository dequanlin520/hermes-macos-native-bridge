import AppKit
import SwiftUI

public final class HermesPolicyWindowController: NSWindowController {
  @MainActor
  public init(viewModel: HermesPolicyViewModel) {
    let rootView = HermesPolicyWindow(viewModel: viewModel)
    let hostingController = NSHostingController(rootView: rootView)
    let window = NSWindow(contentViewController: hostingController)
    window.title = "Hermes Enterprise Policy Center"
    window.setContentSize(NSSize(width: 820, height: 660))
    window.minSize = NSSize(width: 700, height: 540)
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) is unavailable")
  }
}

public struct HermesPolicyWindow: View {
  @ObservedObject private var viewModel: HermesPolicyViewModel

  public init(viewModel: HermesPolicyViewModel) {
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
          policiesSection
          preferencesSection
          boundarySection
          evaluationSection
          auditSection
        }
        .padding(18)
      }
    }
    .frame(minWidth: 700, minHeight: 540)
    .task {
      viewModel.load()
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: "building.2.crop.circle")
        .font(.title2)
        .foregroundStyle(Color.accentColor)
      VStack(alignment: .leading, spacing: 2) {
        Text("Hermes Enterprise Policy Center")
          .font(.title2)
        Text("\(viewModel.policies.count) local policy definitions")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button {
        viewModel.openAdministrationCenter()
      } label: {
        Label("Admin", systemImage: "building.columns")
      }
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
  }

  private var policiesSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Policies")
        .font(.headline)
      ForEach(viewModel.policies) { policy in
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon(for: policy.category))
              .frame(width: 22)
              .foregroundStyle(color(for: viewModel.decision(for: policy.id)))
            VStack(alignment: .leading, spacing: 2) {
              Text(policy.name)
              Text("\(categoryLabel(policy.category)) - \(policy.source.rawValue) - v\(policy.version)")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Picker(
              "Decision",
              selection: Binding(
                get: { viewModel.decision(for: policy.id) },
                set: { viewModel.setDecision(policyID: policy.id, decision: $0) }
              )
            ) {
              Text("Allow").tag(HermesPolicyDecision.allow)
              Text("Deny").tag(HermesPolicyDecision.deny)
              Text("Confirm").tag(HermesPolicyDecision.requireConfirmation)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 260)
            Button {
              viewModel.evaluate(policyID: policy.id)
            } label: {
              Label("Evaluate", systemImage: "checkmark.shield")
            }
          }
        }
      }
    }
  }

  private var preferencesSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Preferences")
        .font(.headline)
      Toggle("Show managed policy metadata", isOn: Binding(
        get: { viewModel.preferences.showManagedPolicyMetadata },
        set: { viewModel.setShowManagedPolicyMetadata($0) }
      ))
      Toggle("Record local evaluation results", isOn: Binding(
        get: { viewModel.preferences.recordLocalEvaluationResults },
        set: { viewModel.setRecordLocalEvaluationResults($0) }
      ))
      Button {
        viewModel.clearStoredLocalPolicyData()
      } label: {
        Label("Clear Stored Local Policy Data", systemImage: "trash")
      }
    }
  }

  private var boundarySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Boundary")
        .font(.headline)
      Text(viewModel.policySummary)
        .foregroundStyle(.secondary)
    }
  }

  private var evaluationSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Evaluation Results")
        .font(.headline)
      if viewModel.evaluationResults.isEmpty {
        Text("No local evaluations recorded")
          .foregroundStyle(.secondary)
      } else {
        ForEach(viewModel.evaluationResults.prefix(8)) { result in
          HStack {
            Image(systemName: "checkmark.shield")
              .foregroundStyle(color(for: result.decision))
            Text(result.policyID)
              .lineLimit(1)
            Spacer()
            Text(decisionLabel(result.decision))
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  private var auditSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Policy Audit")
        .font(.headline)
      if viewModel.auditEvents.isEmpty {
        Text("No policy changes recorded")
          .foregroundStyle(.secondary)
      } else {
        ForEach(viewModel.auditEvents.prefix(8)) { event in
          HStack {
            Image(systemName: "clock.arrow.circlepath")
              .foregroundStyle(.secondary)
            Text(event.policyID)
              .lineLimit(1)
            Spacer()
            Text("\(event.oldValue) -> \(event.newValue)")
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  private func categoryLabel(_ category: HermesPolicyCategory) -> String {
    switch category {
    case .runtimeOperationRestrictions: return "Runtime Operation Restrictions"
    case .updatePolicy: return "Update Policy"
    case .notificationPolicy: return "Notification Policy"
    case .retentionPolicy: return "Retention Policy"
    case .privacyPolicy: return "Privacy Policy"
    case .featureAvailabilityPolicy: return "Feature Availability Policy"
    }
  }

  private func decisionLabel(_ decision: HermesPolicyDecision) -> String {
    switch decision {
    case .allow: return "allow"
    case .deny: return "deny"
    case .requireConfirmation: return "require confirmation"
    }
  }

  private func icon(for category: HermesPolicyCategory) -> String {
    switch category {
    case .runtimeOperationRestrictions: return "lock.shield"
    case .updatePolicy: return "arrow.up.circle"
    case .notificationPolicy: return "bell.badge"
    case .retentionPolicy: return "clock"
    case .privacyPolicy: return "hand.raised"
    case .featureAvailabilityPolicy: return "switch.2"
    }
  }

  private func color(for decision: HermesPolicyDecision) -> Color {
    switch decision {
    case .allow: return .green
    case .deny: return .red
    case .requireConfirmation: return .orange
    }
  }
}
