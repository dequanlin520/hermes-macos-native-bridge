import Foundation
import HermesPolicy
import HermesPrivacy
import HermesUpdate

public struct HermesComplianceCenterInputs: Sendable {
  public var systemStatus: @Sendable () async -> HermesComplianceSystemStatus
  public var policies: @Sendable () throws -> [HermesPolicyDefinition]
  public var privacyRecords: @Sendable () throws -> [HermesPrivacyConsentRecord]
  public var updateSnapshot: @Sendable () async -> HermesUpdateSnapshot
  public var policyAuditEvents: @Sendable () throws -> [HermesPolicyAuditEvent]
  public var privacyAuditEvents: @Sendable () throws -> [HermesPrivacyAuditEvent]

  public init(
    systemStatus: @escaping @Sendable () async -> HermesComplianceSystemStatus,
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

public final class HermesComplianceCenter: @unchecked Sendable {
  private let inputs: HermesComplianceCenterInputs

  public init(inputs: HermesComplianceCenterInputs) {
    self.inputs = inputs
  }

  public func snapshot() async -> HermesComplianceSnapshot {
    let system = await inputs.systemStatus()
    let policies = (try? inputs.policies()) ?? []
    let privacyRecords = (try? inputs.privacyRecords()) ?? []
    let updateSnapshot = await inputs.updateSnapshot()
    let policyEvents = (try? inputs.policyAuditEvents()) ?? []
    let privacyEvents = (try? inputs.privacyAuditEvents()) ?? []
    let security = HermesComplianceSecurityPosture(system: system)
    let privacy = HermesCompliancePrivacyPosture(records: privacyRecords)
    let policy = HermesCompliancePolicyPosture(policies: policies)
    let release = HermesComplianceReleasePosture(snapshot: updateSnapshot)
    let auditEvidence = HermesComplianceAuditEvidenceSummary(
      policyEvents: policyEvents,
      privacyEvents: privacyEvents
    )
    return HermesComplianceSnapshot(
      security: security,
      privacy: privacy,
      policy: policy,
      release: release,
      auditEvidence: auditEvidence,
      readOnly: true,
      appOwnsRuntime: false,
      processExecutionAvailable: false,
      shellAvailable: false,
      uploadAvailable: false,
      sensitiveDataExposed: false
    )
  }

  public var readOnly: Bool { true }
  public var appOwnsRuntime: Bool { false }
  public var processExecutionAvailable: Bool { false }
  public var shellAvailable: Bool { false }
  public var uploadAvailable: Bool { false }
  public var sensitiveDataExposed: Bool { false }
}
