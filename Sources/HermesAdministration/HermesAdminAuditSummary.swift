import Foundation
import HermesPolicy
import HermesPrivacy

public enum HermesAdminAuditSource: String, Codable, CaseIterable, Equatable, Sendable {
  case policy
  case privacy
}

public struct HermesAdminAuditEventSummary: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let source: HermesAdminAuditSource
  public let summary: String
  public let timestamp: Date

  public init(
    id: UUID = UUID(),
    source: HermesAdminAuditSource,
    summary: String,
    timestamp: Date
  ) {
    self.id = id
    self.source = source
    self.summary = HermesAdminRedactor.safeText(summary, limit: 180)
    self.timestamp = timestamp
  }
}

public struct HermesAdminAuditSummary: Codable, Equatable, Sendable {
  public let recentEventCount: Int
  public let recentEvents: [HermesAdminAuditEventSummary]

  public init(
    policyEvents: [HermesPolicyAuditEvent],
    privacyEvents: [HermesPrivacyAuditEvent],
    limit: Int = 8
  ) {
    let policySummaries = policyEvents.map {
      HermesAdminAuditEventSummary(
        id: $0.id,
        source: .policy,
        summary: "\($0.policyID) \($0.oldValue) to \($0.newValue)",
        timestamp: $0.timestamp
      )
    }
    let privacySummaries = privacyEvents.map {
      HermesAdminAuditEventSummary(
        id: $0.id,
        source: .privacy,
        summary: "\($0.category.rawValue) \($0.oldStatus.rawValue) to \($0.newStatus.rawValue)",
        timestamp: $0.timestamp
      )
    }
    let sorted = (policySummaries + privacySummaries).sorted {
      if $0.timestamp == $1.timestamp { return $0.id.uuidString < $1.id.uuidString }
      return $0.timestamp > $1.timestamp
    }
    recentEventCount = sorted.count
    recentEvents = Array(sorted.prefix(min(max(0, limit), 25)))
  }

  public init(recentEventCount: Int, recentEvents: [HermesAdminAuditEventSummary]) {
    self.recentEventCount = max(0, recentEventCount)
    self.recentEvents = recentEvents.map {
      HermesAdminAuditEventSummary(
        id: $0.id,
        source: $0.source,
        summary: $0.summary,
        timestamp: $0.timestamp
      )
    }
  }
}
