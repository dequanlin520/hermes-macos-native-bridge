import Foundation
import HermesPolicy
import HermesPrivacy
import HermesUpdate

public enum HermesCompliancePostureState: String, Codable, CaseIterable, Equatable, Sendable {
  case compliant
  case attentionRequired
  case unavailable
}

public enum HermesComplianceServiceAvailability: String, Codable, CaseIterable, Equatable, Sendable {
  case available
  case unavailable
  case unknown
}

public struct HermesComplianceSystemStatus: Codable, Equatable, Sendable {
  public let applicationVersion: String
  public let protocolVersion: String
  public let serviceAvailability: HermesComplianceServiceAvailability

  public init(
    applicationVersion: String,
    protocolVersion: String,
    serviceAvailability: HermesComplianceServiceAvailability
  ) {
    self.applicationVersion = HermesComplianceRedactor.safeToken(
      applicationVersion,
      fallback: "unknown"
    )
    self.protocolVersion = HermesComplianceRedactor.safeToken(protocolVersion, fallback: "unknown")
    self.serviceAvailability = serviceAvailability
  }
}

public struct HermesComplianceSecurityPosture: Codable, Equatable, Sendable {
  public let state: HermesCompliancePostureState
  public let serviceAvailability: HermesComplianceServiceAvailability
  public let protocolVersion: String
  public let runtimeOwnership: String
  public let processExecutionAvailable: Bool
  public let shellAvailable: Bool
  public let summary: String

  public init(
    system: HermesComplianceSystemStatus,
    processExecutionAvailable: Bool = false,
    shellAvailable: Bool = false,
    runtimeOwnedByApp: Bool = false
  ) {
    self.serviceAvailability = system.serviceAvailability
    self.protocolVersion = HermesComplianceRedactor.safeToken(
      system.protocolVersion,
      fallback: "unknown"
    )
    self.runtimeOwnership = runtimeOwnedByApp ? "app" : "service"
    self.processExecutionAvailable = processExecutionAvailable
    self.shellAvailable = shellAvailable
    if system.serviceAvailability == .unavailable || processExecutionAvailable || shellAvailable
      || runtimeOwnedByApp
    {
      self.state = .attentionRequired
    } else {
      self.state = system.serviceAvailability == .unknown ? .unavailable : .compliant
    }
    self.summary = HermesComplianceRedactor.safeText(
      "service \(system.serviceAvailability.rawValue), protocol \(system.protocolVersion), runtime \(runtimeOwnership)",
      limit: 160
    )
  }
}

public struct HermesCompliancePrivacyPosture: Codable, Equatable, Sendable {
  public let state: HermesCompliancePostureState
  public let allowedConsentCount: Int
  public let deniedConsentCount: Int
  public let unknownConsentCount: Int
  public let uploadAllowed: Bool
  public let sensitiveDataExposed: Bool
  public let summary: String

  public init(
    records: [HermesPrivacyConsentRecord],
    uploadAllowed: Bool = false,
    sensitiveDataExposed: Bool = false
  ) {
    self.allowedConsentCount = records.filter { $0.status == .allowed }.count
    self.deniedConsentCount = records.filter { $0.status == .denied }.count
    self.unknownConsentCount = records.filter { $0.status == .unknown }.count
    self.uploadAllowed = uploadAllowed
    self.sensitiveDataExposed = sensitiveDataExposed
    self.state = unknownConsentCount == 0 && !uploadAllowed && !sensitiveDataExposed
      ? .compliant : .attentionRequired
    self.summary = HermesComplianceRedactor.safeText(
      "\(allowedConsentCount) allowed, \(deniedConsentCount) denied, \(unknownConsentCount) unknown",
      limit: 160
    )
  }
}

public struct HermesCompliancePolicyPosture: Codable, Equatable, Sendable {
  public let state: HermesCompliancePostureState
  public let activePolicies: Int
  public let deniedPolicies: Int
  public let policyVersion: String
  public let policyIDs: [String]
  public let summary: String

  public init(policies: [HermesPolicyDefinition]) {
    self.activePolicies = policies.count
    self.deniedPolicies = policies.filter { policy in
      switch policy.value {
      case .decision(.deny), .boolean(false):
        return true
      case .decision, .boolean, .integer, .text:
        return false
      }
    }.count
    self.policyVersion = Self.version(from: policies)
    self.policyIDs = policies.map { HermesComplianceRedactor.safeToken($0.id) }.sorted()
    self.state = policies.isEmpty ? .attentionRequired : .compliant
    self.summary = HermesComplianceRedactor.safeText(
      "\(activePolicies) active, \(deniedPolicies) restrictive, version \(policyVersion)",
      limit: 160
    )
  }

  private static func version(from policies: [HermesPolicyDefinition]) -> String {
    let versions = Set(
      policies.map { HermesComplianceRedactor.safeToken($0.version, fallback: "unknown", limit: 40) }
    )
    guard !versions.isEmpty else { return "unknown" }
    if versions.count == 1 { return versions.first ?? "unknown" }
    return versions.sorted().joined(separator: ",")
  }
}

public enum HermesComplianceReleaseAvailability: String, Codable, CaseIterable, Equatable,
  Sendable
{
  case current
  case updateAvailable
  case checking
  case failed
  case unknown
}

public struct HermesComplianceReleasePosture: Codable, Equatable, Sendable {
  public let state: HermesCompliancePostureState
  public let currentVersion: String
  public let availability: HermesComplianceReleaseAvailability
  public let availableVersion: String?
  public let signingState: String
  public let provenanceState: String
  public let summary: String

  public init(snapshot: HermesUpdateSnapshot) {
    self.currentVersion = HermesComplianceRedactor.safeToken(
      snapshot.current.appVersion,
      fallback: "unknown"
    )
    self.availableVersion = snapshot.availableRelease.map {
      HermesComplianceRedactor.safeToken($0.version, fallback: "unknown")
    }
    let release = snapshot.validatedRelease ?? snapshot.availableRelease
    self.signingState = HermesComplianceRedactor.safeToken(
      release?.signing.rawValue ?? "unknown",
      fallback: "unknown"
    )
    self.provenanceState = HermesComplianceRedactor.safeToken(
      release?.provenance.rawValue ?? "unknown",
      fallback: "unknown"
    )
    switch snapshot.state {
    case .checking, .validating:
      self.availability = .checking
      self.state = .unavailable
    case .updateAvailable, .awaitingConfirmation, .staging, .activating, .reconnecting:
      self.availability = .updateAvailable
      self.state = .attentionRequired
    case .failed, .recoveryRequired:
      self.availability = .failed
      self.state = .attentionRequired
    case .idle, .upToDate, .completed, .rollbackAvailable, .rollingBack:
      self.availability = .current
      self.state = .compliant
    }
    self.summary = HermesComplianceRedactor.safeText(snapshot.message, limit: 180)
  }
}

public enum HermesComplianceAuditSource: String, Codable, CaseIterable, Equatable, Sendable {
  case policy
  case privacy
}

public struct HermesComplianceAuditEvidenceItem: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let source: HermesComplianceAuditSource
  public let summary: String
  public let timestamp: Date

  public init(
    id: UUID = UUID(),
    source: HermesComplianceAuditSource,
    summary: String,
    timestamp: Date
  ) {
    self.id = id
    self.source = source
    self.summary = HermesComplianceRedactor.safeText(summary, limit: 180)
    self.timestamp = timestamp
  }
}

public struct HermesComplianceAuditEvidenceSummary: Codable, Equatable, Sendable {
  public let recentEventCount: Int
  public let recentEvidence: [HermesComplianceAuditEvidenceItem]
  public let readOnly: Bool

  public init(
    policyEvents: [HermesPolicyAuditEvent],
    privacyEvents: [HermesPrivacyAuditEvent],
    limit: Int = 8
  ) {
    let policyEvidence = policyEvents.map {
      HermesComplianceAuditEvidenceItem(
        id: $0.id,
        source: .policy,
        summary: "\($0.policyID) \($0.oldValue) to \($0.newValue)",
        timestamp: $0.timestamp
      )
    }
    let privacyEvidence = privacyEvents.map {
      HermesComplianceAuditEvidenceItem(
        id: $0.id,
        source: .privacy,
        summary: "\($0.category.rawValue) \($0.oldStatus.rawValue) to \($0.newStatus.rawValue)",
        timestamp: $0.timestamp
      )
    }
    let sorted = (policyEvidence + privacyEvidence).sorted {
      if $0.timestamp == $1.timestamp { return $0.id.uuidString < $1.id.uuidString }
      return $0.timestamp > $1.timestamp
    }
    self.recentEventCount = sorted.count
    self.recentEvidence = Array(sorted.prefix(min(max(0, limit), 25)))
    self.readOnly = true
  }
}

public struct HermesComplianceSnapshot: Codable, Equatable, Sendable {
  public let security: HermesComplianceSecurityPosture
  public let privacy: HermesCompliancePrivacyPosture
  public let policy: HermesCompliancePolicyPosture
  public let release: HermesComplianceReleasePosture
  public let auditEvidence: HermesComplianceAuditEvidenceSummary
  public let overallState: HermesCompliancePostureState
  public let readOnly: Bool
  public let appOwnsRuntime: Bool
  public let processExecutionAvailable: Bool
  public let shellAvailable: Bool
  public let uploadAvailable: Bool
  public let sensitiveDataExposed: Bool

  public init(
    security: HermesComplianceSecurityPosture,
    privacy: HermesCompliancePrivacyPosture,
    policy: HermesCompliancePolicyPosture,
    release: HermesComplianceReleasePosture,
    auditEvidence: HermesComplianceAuditEvidenceSummary,
    readOnly: Bool = true,
    appOwnsRuntime: Bool = false,
    processExecutionAvailable: Bool = false,
    shellAvailable: Bool = false,
    uploadAvailable: Bool = false,
    sensitiveDataExposed: Bool = false
  ) {
    self.security = security
    self.privacy = privacy
    self.policy = policy
    self.release = release
    self.auditEvidence = auditEvidence
    self.readOnly = readOnly
    self.appOwnsRuntime = appOwnsRuntime
    self.processExecutionAvailable = processExecutionAvailable
    self.shellAvailable = shellAvailable
    self.uploadAvailable = uploadAvailable
    self.sensitiveDataExposed = sensitiveDataExposed
    let states = [security.state, privacy.state, policy.state, release.state]
    if states.contains(.attentionRequired) {
      self.overallState = .attentionRequired
    } else if states.contains(.unavailable) {
      self.overallState = .unavailable
    } else {
      self.overallState = .compliant
    }
  }

  public static var empty: HermesComplianceSnapshot {
    HermesComplianceSnapshot(
      security: HermesComplianceSecurityPosture(
        system: HermesComplianceSystemStatus(
          applicationVersion: "unknown",
          protocolVersion: "unknown",
          serviceAvailability: .unknown
        )
      ),
      privacy: HermesCompliancePrivacyPosture(records: []),
      policy: HermesCompliancePolicyPosture(policies: []),
      release: HermesComplianceReleasePosture(snapshot: HermesUpdateSnapshot()),
      auditEvidence: HermesComplianceAuditEvidenceSummary(policyEvents: [], privacyEvents: [])
    )
  }
}

public enum HermesComplianceRedactor {
  public static func safeText(_ value: String, limit: Int = 320) -> String {
    var output = String(value.prefix(limit))
    let replacements: [(String, String)] = [
      (#"(?i)\b(token|password|api[_ -]?key|credential|secret|private[_ -]?key)\s*[:=]\s*[^,\s]+"#, "$1=<redacted>"),
      (#"(?i)\bbearer\s+[A-Za-z0-9._~+/\-=]+"#, "bearer <redacted>"),
      (#"(?is)-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----"#, "<redacted-private-key>"),
      (#"/(?:Applications|Users|Volumes|System|Library|private|var|tmp|usr|bin|sbin|opt)/[^\s,"')]+"#, "<redacted-path>"),
      (#"(?i)\bpid(?:\s*[=:]\s*|\s+)[0-9]+\b"#, "pid=<redacted>"),
      (#"(?i)\bprocess id(?:\s*[=:]\s*|\s+)[0-9]+\b"#, "process id=<redacted>"),
      (#"(?m)^\s*at\s+\S+\(.*\)\s*$"#, "<redacted-stack-frame>"),
    ]
    for (pattern, replacement) in replacements {
      output = output.replacingOccurrences(
        of: pattern,
        with: replacement,
        options: [.regularExpression, .caseInsensitive]
      )
    }
    return String(output.prefix(limit))
  }

  public static func safeToken(_ value: String, fallback: String = "unknown", limit: Int = 80)
    -> String
  {
    let safe = safeText(value, limit: limit)
    let filtered = safe.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-")
    }
    let token = String(filtered.prefix(limit))
    return token.isEmpty ? fallback : token
  }
}
