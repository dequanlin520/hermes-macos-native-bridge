import Foundation

public enum HermesFeedbackCategory: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case bugReport
  case featureRequest
  case runtimeIssueReport
  case recoveryFeedback
  case updateFeedback
}

public enum HermesFeedbackSeverity: Int, CaseIterable, Codable, Comparable, Equatable, Hashable,
  Sendable
{
  case informational = 0
  case low = 1
  case medium = 2
  case high = 3
  case critical = 4

  public static func < (lhs: HermesFeedbackSeverity, rhs: HermesFeedbackSeverity) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

public enum HermesFeedbackStatus: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case draft
  case ready
  case submitted
  case resolved
  case archived
}

public struct HermesFeedbackSafeRuntimeContext: Codable, Equatable, Sendable {
  public let applicationVersion: String?
  public let runtimeStatusSummary: String?
  public let protocolVersion: String?
  public let featureName: String?

  public init(
    applicationVersion: String? = nil,
    runtimeStatusSummary: String? = nil,
    protocolVersion: String? = nil,
    featureName: String? = nil
  ) {
    self.applicationVersion = applicationVersion.map {
      HermesFeedbackRedactor.safeToken($0, limit: 80)
    }
    self.runtimeStatusSummary = runtimeStatusSummary.map {
      HermesFeedbackRedactor.safeText($0, limit: 160)
    }
    self.protocolVersion = protocolVersion.map {
      HermesFeedbackRedactor.safeToken($0, limit: 40)
    }
    self.featureName = featureName.map {
      HermesFeedbackRedactor.safeText($0, limit: 80)
    }
  }
}

public struct HermesFeedbackRecord: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let category: HermesFeedbackCategory
  public var title: String
  public var description: String
  public let timestamp: Date
  public var severity: HermesFeedbackSeverity
  public var relatedFeature: String?
  public var status: HermesFeedbackStatus
  public var safeRuntimeContext: HermesFeedbackSafeRuntimeContext?

  public init(
    id: UUID = UUID(),
    category: HermesFeedbackCategory,
    title: String,
    description: String,
    timestamp: Date = Date(),
    severity: HermesFeedbackSeverity = .medium,
    relatedFeature: String? = nil,
    status: HermesFeedbackStatus = .draft,
    safeRuntimeContext: HermesFeedbackSafeRuntimeContext? = nil
  ) {
    self.id = id
    self.category = category
    self.title = HermesFeedbackRedactor.safeText(title, limit: 120)
    self.description = HermesFeedbackRedactor.safeText(description, limit: 2_000)
    self.timestamp = timestamp
    self.severity = severity
    self.relatedFeature = relatedFeature.map {
      HermesFeedbackRedactor.safeText($0, limit: 80)
    }
    self.status = status
    self.safeRuntimeContext = safeRuntimeContext
  }

  public var duplicateFingerprint: String {
    [
      category.rawValue,
      HermesFeedbackRedactor.normalized(title),
      HermesFeedbackRedactor.normalized(description),
      HermesFeedbackRedactor.normalized(relatedFeature ?? ""),
    ].joined(separator: "|")
  }

  public func replacing(status: HermesFeedbackStatus) -> HermesFeedbackRecord {
    HermesFeedbackRecord(
      id: id,
      category: category,
      title: title,
      description: description,
      timestamp: timestamp,
      severity: severity,
      relatedFeature: relatedFeature,
      status: status,
      safeRuntimeContext: safeRuntimeContext
    )
  }
}

public struct HermesFeedbackPreferences: Codable, Equatable, Sendable {
  public var includeSafeRuntimeContext: Bool
  public var defaultSeverity: HermesFeedbackSeverity
  public var defaultCategory: HermesFeedbackCategory

  public init(
    includeSafeRuntimeContext: Bool = true,
    defaultSeverity: HermesFeedbackSeverity = .medium,
    defaultCategory: HermesFeedbackCategory = .bugReport
  ) {
    self.includeSafeRuntimeContext = includeSafeRuntimeContext
    self.defaultSeverity = defaultSeverity
    self.defaultCategory = defaultCategory
  }
}

public enum HermesFeedbackValidationError: Error, Equatable, Sendable {
  case unsupportedCategory
  case descriptionTooShort(minimum: Int)
  case duplicateFeedback
  case invalidLifecycleTransition(from: HermesFeedbackStatus, to: HermesFeedbackStatus)
  case feedbackNotFound
}

public enum HermesFeedbackRedactor {
  public static func safeText(_ value: String, limit: Int = 320) -> String {
    var output = String(value.prefix(limit))
    let replacements: [(String, String)] = [
      (#"(?i)\b(token|password|api[_ -]?key|credential|secret|private[_ -]?key)\s*[:=]\s*[^,\s]+"#, "$1=<redacted>"),
      (#"(?i)\bbearer\s+[A-Za-z0-9._~+/\-=]+"#, "bearer <redacted>"),
      (#"(?is)-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----"#, "<redacted-private-key>"),
      (#"/(?:Applications|Users|Volumes|System|Library|private|var|tmp|usr|bin|sbin|opt)/[^\s,"')]+"#, "<redacted-path>"),
      (#"(?i)\bpid(?:\s*[=:]\s*|\s+)[0-9]+\b"#, "pid=<redacted>"),
      (#"(?i)\bprocess id(?:\s*[=:]\s*|\s+)[0-9]+\b"#, "process id=<redacted>"),
      (#"(?:[A-Za-z_][A-Za-z0-9_]*\.){2,}[A-Za-z_][A-Za-z0-9_]*\([^)]*\)"#, "<redacted-stack-frame>"),
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

  public static func normalized(_ value: String) -> String {
    safeText(value, limit: 500)
      .lowercased()
      .split(whereSeparator: { $0.isWhitespace })
      .joined(separator: " ")
  }
}
