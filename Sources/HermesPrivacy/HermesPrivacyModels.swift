import Foundation

public enum HermesPrivacyConsentCategory: String, CaseIterable, Codable, Equatable, Hashable,
  Sendable
{
  case diagnosticsCollection
  case usageAnalytics
  case crashInformation
  case updateCheckMetadata
  case localHistoryRetention
}

public enum HermesPrivacyConsentStatus: String, CaseIterable, Codable, Equatable, Hashable,
  Sendable
{
  case unknown
  case allowed
  case denied
}

public enum HermesPrivacyConsentSource: String, CaseIterable, Codable, Equatable, Hashable,
  Sendable
{
  case defaultPolicy
  case privacyCenter
  case onboarding
  case settings
  case diagnostics
}

public struct HermesPrivacyConsentRecord: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let category: HermesPrivacyConsentCategory
  public var status: HermesPrivacyConsentStatus
  public var updatedAt: Date
  public var source: HermesPrivacyConsentSource

  public init(
    id: UUID = UUID(),
    category: HermesPrivacyConsentCategory,
    status: HermesPrivacyConsentStatus = .denied,
    updatedAt: Date = Date(),
    source: HermesPrivacyConsentSource = .defaultPolicy
  ) {
    self.id = id
    self.category = category
    self.status = status == .unknown ? .denied : status
    self.updatedAt = updatedAt
    self.source = source
  }
}

public struct HermesPrivacyPreferences: Codable, Equatable, Sendable {
  public var showPrivacyReminders: Bool
  public var retainLocalHistory: Bool

  public init(
    showPrivacyReminders: Bool = true,
    retainLocalHistory: Bool = false
  ) {
    self.showPrivacyReminders = showPrivacyReminders
    self.retainLocalHistory = retainLocalHistory
  }
}

public struct HermesPrivacySafeApplicationMetadata: Codable, Equatable, Sendable {
  public let applicationVersion: String?
  public let buildVersion: String?
  public let policyNamespace: String

  public init(
    applicationVersion: String? = nil,
    buildVersion: String? = nil,
    policyNamespace: String = HermesPrivacyStore.Namespace.suiteName
  ) {
    self.applicationVersion = applicationVersion.map {
      HermesPrivacyRedactor.safeToken($0, limit: 80)
    }
    self.buildVersion = buildVersion.map {
      HermesPrivacyRedactor.safeToken($0, limit: 80)
    }
    self.policyNamespace = HermesPrivacyRedactor.safeToken(policyNamespace, limit: 120)
  }
}

public struct HermesPrivacyAuditEvent: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let category: HermesPrivacyConsentCategory
  public let oldStatus: HermesPrivacyConsentStatus
  public let newStatus: HermesPrivacyConsentStatus
  public let timestamp: Date

  public init(
    id: UUID = UUID(),
    category: HermesPrivacyConsentCategory,
    oldStatus: HermesPrivacyConsentStatus,
    newStatus: HermesPrivacyConsentStatus,
    timestamp: Date = Date()
  ) {
    self.id = id
    self.category = category
    self.oldStatus = oldStatus == .unknown ? .denied : oldStatus
    self.newStatus = newStatus == .unknown ? .denied : newStatus
    self.timestamp = timestamp
  }
}

public enum HermesPrivacyValidationError: Error, Equatable, Sendable {
  case unsupportedCategory(String)
  case sensitiveCategoryRejected(String)
  case consentRecordNotFound
}

public enum HermesPrivacyRedactor {
  public static func safeText(_ value: String, limit: Int = 320) -> String {
    var output = String(value.prefix(limit))
    let replacements: [(String, String)] = [
      (#"(?i)\b(token|password|api[_ -]?key|credential|secret|private[_ -]?key)\s*[:=]\s*[^,\s]+"#, "$1=<redacted>"),
      (#"(?i)\bbearer\s+[A-Za-z0-9._~+/\-=]+"#, "bearer <redacted>"),
      (#"(?is)-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----"#, "<redacted-private-key>"),
      (#"/(?:Applications|Users|Volumes|System|Library|private|var|tmp|usr|bin|sbin|opt)/[^\s,"')]+"#, "<redacted-path>"),
      (#"(?i)\bpid(?:\s*[=:]\s*|\s+)[0-9]+\b"#, "pid=<redacted>"),
      (#"(?i)\bprocess id(?:\s*[=:]\s*|\s+)[0-9]+\b"#, "process id=<redacted>"),
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

  public static func safeToken(_ value: String, limit: Int = 80) -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-")
    }
    return String(filtered.prefix(limit))
  }
}
