import Foundation
import SwiftUI

@MainActor
public final class HermesPolicyViewModel: ObservableObject {
  @Published public private(set) var policies: [HermesPolicyDefinition] = []
  @Published public private(set) var evaluationResults: [HermesPolicyEvaluationResult] = []
  @Published public private(set) var auditEvents: [HermesPolicyAuditEvent] = []
  @Published public private(set) var preferences: HermesPolicyPreferences
  @Published public private(set) var lastErrorMessage: String?

  private let center: HermesPolicyCenter
  private let openAdministrationCenterAction: @MainActor () -> Void

  public init(
    center: HermesPolicyCenter = HermesPolicyCenter(),
    openAdministrationCenter: @escaping @MainActor () -> Void = {}
  ) {
    self.center = center
    self.openAdministrationCenterAction = openAdministrationCenter
    self.preferences = (try? center.loadPreferences()) ?? HermesPolicyPreferences()
  }

  public func load() {
    do {
      policies = try center.listPolicies()
      evaluationResults = try center.loadEvaluationResults()
      auditEvents = try center.loadAuditEvents()
      preferences = try center.loadPreferences()
      lastErrorMessage = nil
    } catch {
      lastErrorMessage = Self.userFacing(error)
    }
  }

  public func setDecision(policyID: String, decision: HermesPolicyDecision) {
    do {
      guard let policy = policies.first(where: { $0.id == policyID }) else {
        throw HermesPolicyValidationError.policyNotFound
      }
      _ = try center.savePolicy(
        HermesPolicyDefinition(
          id: policy.id,
          name: policy.name,
          category: policy.category,
          value: .decision(decision),
          source: .enterprisePolicyCenter,
          version: policy.version,
          timestamp: Date()
        )
      )
      load()
    } catch {
      lastErrorMessage = Self.userFacing(error)
    }
  }

  public func evaluate(policyID: String) {
    do {
      _ = try center.evaluate(policyID: policyID)
      load()
    } catch {
      lastErrorMessage = Self.userFacing(error)
    }
  }

  public func setShowManagedPolicyMetadata(_ show: Bool) {
    preferences.showManagedPolicyMetadata = show
    savePreferences()
  }

  public func setRecordLocalEvaluationResults(_ record: Bool) {
    preferences.recordLocalEvaluationResults = record
    savePreferences()
  }

  public func clearStoredLocalPolicyData() {
    do {
      try center.clearStoredLocalPolicyData()
      load()
    } catch {
      lastErrorMessage = Self.userFacing(error)
    }
  }

  public func openAdministrationCenter() {
    openAdministrationCenterAction()
  }

  public var policySummary: String {
    [
      "deny by default",
      "local metadata only",
      "sanitized audit only",
      "app owns runtime: no",
      "arbitrary action: no",
    ].joined(separator: " | ")
  }

  public func decision(for policyID: String) -> HermesPolicyDecision {
    guard let policy = policies.first(where: { $0.id == policyID }) else { return .deny }
    switch policy.value {
    case .decision(let decision): return decision
    case .boolean(let value): return value ? .allow : .deny
    case .integer, .text: return .deny
    }
  }

  private func savePreferences() {
    do {
      try center.savePreferences(preferences)
      lastErrorMessage = nil
    } catch {
      lastErrorMessage = Self.userFacing(error)
    }
  }

  private static func userFacing(_ error: Error) -> String {
    switch error {
    case HermesPolicyValidationError.sensitivePolicyMetadataRejected:
      return "Sensitive policy metadata was rejected."
    case HermesPolicyValidationError.unsupportedPolicyID:
      return "Policy is not supported."
    case HermesPolicyValidationError.policyNotFound:
      return "Policy was not found."
    default:
      return HermesPolicyRedactor.safeText(String(describing: error), limit: 180)
    }
  }
}
