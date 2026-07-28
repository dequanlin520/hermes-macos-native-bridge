import Foundation
import HermesPrivacy
import HermesUpdate

public enum HermesAdminAvailability: String, Codable, CaseIterable, Equatable, Sendable {
  case available
  case unavailable
  case unknown
}

public enum HermesAdminPrivacyState: String, Codable, CaseIterable, Equatable, Sendable {
  case compliant
  case attentionRequired
  case unknown
}

public enum HermesAdminUpdateAvailability: String, Codable, CaseIterable, Equatable, Sendable {
  case available
  case unavailable
  case checking
  case failed
  case unknown
}

public enum HermesAdminComplianceState: String, Codable, CaseIterable, Equatable, Sendable {
  case compliant
  case attentionRequired
  case unavailable
}

public struct HermesAdminSystemStatus: Codable, Equatable, Sendable {
  public let applicationVersion: String
  public let protocolVersion: String
  public let serviceAvailability: HermesAdminAvailability

  public init(
    applicationVersion: String,
    protocolVersion: String,
    serviceAvailability: HermesAdminAvailability
  ) {
    self.applicationVersion = HermesAdminRedactor.safeToken(applicationVersion, fallback: "unknown")
    self.protocolVersion = HermesAdminRedactor.safeToken(protocolVersion, fallback: "unknown")
    self.serviceAvailability = serviceAvailability
  }
}

public struct HermesAdminPrivacySummary: Codable, Equatable, Sendable {
  public let allowedConsentCount: Int
  public let deniedConsentCount: Int
  public let unknownConsentCount: Int
  public let privacyState: HermesAdminPrivacyState
  public let consentSummary: String

  public init(records: [HermesPrivacyConsentRecord]) {
    allowedConsentCount = records.filter { $0.status == .allowed }.count
    deniedConsentCount = records.filter { $0.status == .denied }.count
    unknownConsentCount = records.filter { $0.status == .unknown }.count
    privacyState = unknownConsentCount == 0 ? .compliant : .attentionRequired
    consentSummary = HermesAdminRedactor.safeText(
      "\(allowedConsentCount) allowed, \(deniedConsentCount) denied, \(unknownConsentCount) unknown",
      limit: 120
    )
  }

  public init(
    allowedConsentCount: Int,
    deniedConsentCount: Int,
    unknownConsentCount: Int,
    privacyState: HermesAdminPrivacyState,
    consentSummary: String
  ) {
    self.allowedConsentCount = max(0, allowedConsentCount)
    self.deniedConsentCount = max(0, deniedConsentCount)
    self.unknownConsentCount = max(0, unknownConsentCount)
    self.privacyState = privacyState
    self.consentSummary = HermesAdminRedactor.safeText(consentSummary, limit: 120)
  }
}

public struct HermesAdminUpdateSummary: Codable, Equatable, Sendable {
  public let currentVersion: String
  public let updateAvailability: HermesAdminUpdateAvailability
  public let availableVersion: String?
  public let statusMessage: String

  public init(snapshot: HermesUpdateSnapshot) {
    currentVersion = HermesAdminRedactor.safeToken(snapshot.current.appVersion, fallback: "unknown")
    availableVersion = snapshot.availableRelease.map {
      HermesAdminRedactor.safeToken($0.version, fallback: "unknown")
    }
    statusMessage = HermesAdminRedactor.safeText(snapshot.message, limit: 180)
    switch snapshot.state {
    case .checking, .validating:
      updateAvailability = .checking
    case .updateAvailable, .awaitingConfirmation, .staging, .activating, .reconnecting:
      updateAvailability = .available
    case .failed, .recoveryRequired:
      updateAvailability = .failed
    case .idle, .upToDate, .completed, .rollbackAvailable, .rollingBack:
      updateAvailability = .unavailable
    }
  }

  public init(
    currentVersion: String,
    updateAvailability: HermesAdminUpdateAvailability,
    availableVersion: String? = nil,
    statusMessage: String
  ) {
    self.currentVersion = HermesAdminRedactor.safeToken(currentVersion, fallback: "unknown")
    self.updateAvailability = updateAvailability
    self.availableVersion = availableVersion.map {
      HermesAdminRedactor.safeToken($0, fallback: "unknown")
    }
    self.statusMessage = HermesAdminRedactor.safeText(statusMessage, limit: 180)
  }
}

public struct HermesAdminSnapshot: Codable, Equatable, Sendable {
  public let system: HermesAdminSystemStatus
  public let policy: HermesAdminPolicySummary
  public let privacy: HermesAdminPrivacySummary
  public let update: HermesAdminUpdateSummary
  public let audit: HermesAdminAuditSummary
  public let complianceState: HermesAdminComplianceState
  public let appOwnsRuntime: Bool
  public let arbitraryActionAvailable: Bool
  public let auditReadOnly: Bool

  public init(
    system: HermesAdminSystemStatus,
    policy: HermesAdminPolicySummary,
    privacy: HermesAdminPrivacySummary,
    update: HermesAdminUpdateSummary,
    audit: HermesAdminAuditSummary,
    complianceState: HermesAdminComplianceState,
    appOwnsRuntime: Bool = false,
    arbitraryActionAvailable: Bool = false,
    auditReadOnly: Bool = true
  ) {
    self.system = system
    self.policy = policy
    self.privacy = privacy
    self.update = update
    self.audit = audit
    self.complianceState = complianceState
    self.appOwnsRuntime = appOwnsRuntime
    self.arbitraryActionAvailable = arbitraryActionAvailable
    self.auditReadOnly = auditReadOnly
  }

  public static var empty: HermesAdminSnapshot {
    HermesAdminSnapshot(
      system: HermesAdminSystemStatus(
        applicationVersion: "unknown",
        protocolVersion: "unknown",
        serviceAvailability: .unknown
      ),
      policy: HermesAdminPolicySummary(activePolicies: 0, deniedPolicies: 0, policyVersion: "unknown"),
      privacy: HermesAdminPrivacySummary(
        allowedConsentCount: 0,
        deniedConsentCount: 0,
        unknownConsentCount: 0,
        privacyState: .unknown,
        consentSummary: "unknown"
      ),
      update: HermesAdminUpdateSummary(
        currentVersion: "unknown",
        updateAvailability: .unknown,
        statusMessage: "unknown"
      ),
      audit: HermesAdminAuditSummary(recentEventCount: 0, recentEvents: []),
      complianceState: .unavailable
    )
  }
}

public struct HermesAdminPreferences: Codable, Equatable, Sendable {
  public var showComplianceStatus: Bool
  public var visibleAuditLimit: Int

  public init(showComplianceStatus: Bool = true, visibleAuditLimit: Int = 8) {
    self.showComplianceStatus = showComplianceStatus
    self.visibleAuditLimit = min(max(0, visibleAuditLimit), 25)
  }
}

public protocol HermesAdminPreferenceStoring: Sendable {
  func loadPreferences() throws -> HermesAdminPreferences
  func savePreferences(_ preferences: HermesAdminPreferences) throws
}

public final class HermesAdminPreferenceStore: HermesAdminPreferenceStoring, @unchecked Sendable {
  public enum Namespace {
    public static let suiteName = "com.hermes.admin.v1"
  }

  private enum Keys {
    static let preferences = "com.hermes.admin.v1.preferences"
  }

  private let userDefaults: UserDefaults
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()
  private let lock = NSLock()

  public init(userDefaults: UserDefaults? = nil) {
    self.userDefaults = userDefaults ?? UserDefaults(suiteName: Namespace.suiteName) ?? .standard
  }

  public func loadPreferences() throws -> HermesAdminPreferences {
    try lock.withLock {
      guard let data = userDefaults.data(forKey: Keys.preferences) else {
        return HermesAdminPreferences()
      }
      return try decoder.decode(HermesAdminPreferences.self, from: data)
    }
  }

  public func savePreferences(_ preferences: HermesAdminPreferences) throws {
    try lock.withLock {
      let data = try encoder.encode(preferences)
      userDefaults.set(data, forKey: Keys.preferences)
    }
  }
}

public enum HermesAdminRedactor {
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

  public static func safeToken(_ value: String, fallback: String = "unknown", limit: Int = 80) -> String {
    let safe = safeText(value, limit: limit)
    let filtered = safe.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-")
    }
    let token = String(filtered.prefix(limit))
    return token.isEmpty ? fallback : token
  }
}
