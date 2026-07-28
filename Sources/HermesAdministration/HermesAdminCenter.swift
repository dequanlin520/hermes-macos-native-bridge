import Foundation
import HermesPolicy
import HermesPrivacy
import HermesUpdate

public struct HermesAdminCenterInputs: Sendable {
  public var systemStatus: @Sendable () async -> HermesAdminSystemStatus
  public var policies: @Sendable () throws -> [HermesPolicyDefinition]
  public var privacyRecords: @Sendable () throws -> [HermesPrivacyConsentRecord]
  public var updateSnapshot: @Sendable () async -> HermesUpdateSnapshot
  public var policyAuditEvents: @Sendable () throws -> [HermesPolicyAuditEvent]
  public var privacyAuditEvents: @Sendable () throws -> [HermesPrivacyAuditEvent]

  public init(
    systemStatus: @escaping @Sendable () async -> HermesAdminSystemStatus,
    policies: @escaping @Sendable () throws -> [HermesPolicyDefinition],
    privacyRecords: @escaping @Sendable () throws -> [HermesPrivacyConsentRecord],
    updateSnapshot: @escaping @Sendable () async -> HermesUpdateSnapshot,
    policyAuditEvents: @escaping @Sendable () throws -> [HermesPolicyAuditEvent],
    privacyAuditEvents: @escaping @Sendable () throws -> [HermesPrivacyAuditEvent]
  ) {
    self.systemStatus = systemStatus
    self.policies = policies
    self.privacyRecords = privacyRecords
    self.updateSnapshot = updateSnapshot
    self.policyAuditEvents = policyAuditEvents
    self.privacyAuditEvents = privacyAuditEvents
  }
}

public final class HermesAdminCenter: @unchecked Sendable {
  private let inputs: HermesAdminCenterInputs
  private let preferenceStore: any HermesAdminPreferenceStoring
  private let lock = NSLock()

  public init(
    inputs: HermesAdminCenterInputs,
    preferenceStore: any HermesAdminPreferenceStoring = HermesAdminPreferenceStore()
  ) {
    self.inputs = inputs
    self.preferenceStore = preferenceStore
  }

  public func snapshot() async -> HermesAdminSnapshot {
    let preferences = (try? loadPreferences()) ?? HermesAdminPreferences()
    let system = await inputs.systemStatus()
    let policies = (try? inputs.policies()) ?? []
    let privacyRecords = (try? inputs.privacyRecords()) ?? []
    let updateSnapshot = await inputs.updateSnapshot()
    let policyEvents = (try? inputs.policyAuditEvents()) ?? []
    let privacyEvents = (try? inputs.privacyAuditEvents()) ?? []
    let policy = HermesAdminPolicySummary(policies: policies)
    let privacy = HermesAdminPrivacySummary(records: privacyRecords)
    let update = HermesAdminUpdateSummary(snapshot: updateSnapshot)
    let audit = HermesAdminAuditSummary(
      policyEvents: policyEvents,
      privacyEvents: privacyEvents,
      limit: preferences.visibleAuditLimit
    )
    return HermesAdminSnapshot(
      system: system,
      policy: policy,
      privacy: privacy,
      update: update,
      audit: audit,
      complianceState: complianceState(system: system, policy: policy, privacy: privacy, update: update),
      appOwnsRuntime: false,
      arbitraryActionAvailable: false,
      auditReadOnly: true
    )
  }

  public func loadPreferences() throws -> HermesAdminPreferences {
    try lock.withLock {
      try preferenceStore.loadPreferences()
    }
  }

  public func savePreferences(_ preferences: HermesAdminPreferences) throws {
    try lock.withLock {
      try preferenceStore.savePreferences(preferences)
    }
  }

  public var appOwnsRuntime: Bool { false }
  public var arbitraryActionAvailable: Bool { false }
  public var auditReadOnly: Bool { true }

  private func complianceState(
    system: HermesAdminSystemStatus,
    policy: HermesAdminPolicySummary,
    privacy: HermesAdminPrivacySummary,
    update: HermesAdminUpdateSummary
  ) -> HermesAdminComplianceState {
    if system.serviceAvailability == .unavailable || update.updateAvailability == .failed {
      return .unavailable
    }
    if policy.activePolicies == 0 || privacy.privacyState != .compliant {
      return .attentionRequired
    }
    return .compliant
  }
}
