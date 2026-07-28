import Foundation
import HermesDiagnostics
import HermesLogsViewer
import HermesNotifications
import HermesRuntimeFoundation
import HermesTimeline

public enum HermesSearchCategory: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case timeline
  case logs
  case notifications
  case diagnostics
  case audit
}

public enum HermesSearchSeverity: Int, CaseIterable, Codable, Comparable, Equatable, Hashable,
  Sendable
{
  case info = 0
  case warning = 1
  case error = 2
  case critical = 3

  public static func < (lhs: HermesSearchSeverity, rhs: HermesSearchSeverity) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

public enum HermesSearchSource: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case timeline
  case logsViewer
  case notificationCenter
  case diagnostics
  case auditLog
}

public struct HermesSearchRecord: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let timestamp: Date
  public let category: HermesSearchCategory
  public let title: String
  public let summary: String
  public let severity: HermesSearchSeverity
  public let source: HermesSearchSource
  public let indexedAt: Date

  public init(
    id: String,
    timestamp: Date,
    category: HermesSearchCategory,
    title: String,
    summary: String,
    severity: HermesSearchSeverity,
    source: HermesSearchSource,
    indexedAt: Date = Date()
  ) {
    self.id = HermesSearchRedactor.safeIdentifier(id, fallback: "\(source.rawValue).\(timestamp.timeIntervalSince1970)")
    self.timestamp = timestamp
    self.category = category
    self.title = HermesSearchRedactor.safeText(title, limit: 120)
    self.summary = HermesSearchRedactor.safeText(summary, limit: 320)
    self.severity = severity
    self.source = source
    self.indexedAt = indexedAt
  }

  public var searchableText: String {
    "\(title) \(summary) \(category.rawValue) \(severity) \(source.rawValue)".lowercased()
  }

  public func replacingIndexedAt(_ date: Date) -> HermesSearchRecord {
    HermesSearchRecord(
      id: id,
      timestamp: timestamp,
      category: category,
      title: title,
      summary: summary,
      severity: severity,
      source: source,
      indexedAt: date
    )
  }
}

public struct HermesSearchPreferences: Codable, Equatable, Sendable {
  public var resultLimit: Int
  public var enabledCategories: Set<HermesSearchCategory>
  public var minimumSeverity: HermesSearchSeverity?

  public init(
    resultLimit: Int = 100,
    enabledCategories: Set<HermesSearchCategory> = Set(HermesSearchCategory.allCases),
    minimumSeverity: HermesSearchSeverity? = nil
  ) {
    self.resultLimit = min(max(1, resultLimit), 500)
    self.enabledCategories = enabledCategories
    self.minimumSeverity = minimumSeverity
  }
}

public struct HermesSearchQuery: Equatable, Sendable {
  public var text: String
  public var categories: Set<HermesSearchCategory>?
  public var minimumSeverity: HermesSearchSeverity?
  public var startDate: Date?
  public var endDate: Date?
  public var limit: Int

  public init(
    text: String = "",
    categories: Set<HermesSearchCategory>? = nil,
    minimumSeverity: HermesSearchSeverity? = nil,
    startDate: Date? = nil,
    endDate: Date? = nil,
    limit: Int = 100
  ) {
    self.text = HermesSearchRedactor.safeText(text, limit: 160).lowercased()
    self.categories = categories
    self.minimumSeverity = minimumSeverity
    self.startDate = startDate
    self.endDate = endDate
    self.limit = min(max(1, limit), 500)
  }
}

public enum HermesSearchRedactor {
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

  public static func safeIdentifier(_ value: String, fallback: String = "record") -> String {
    let filtered = value.map { character -> Character in
      if character.isASCII,
        character.isLetter || character.isNumber || character == "." || character == "-" || character == "_"
      {
        return character
      }
      return "-"
    }
    let output = String(filtered).trimmingCharacters(in: CharacterSet(charactersIn: ".-_"))
    return String((output.isEmpty ? fallback : output).prefix(200))
  }
}

extension HermesSearchRecord {
  public init(timeline item: HermesTimelineItem, indexedAt: Date = Date()) {
    self.init(
      id: "timeline.\(item.id.uuidString)",
      timestamp: item.timestamp,
      category: .timeline,
      title: item.title,
      summary: item.summary,
      severity: HermesSearchSeverity(timelineStatus: item.status),
      source: .timeline,
      indexedAt: indexedAt
    )
  }

  public init(log entry: HermesRuntimeLogEntry, indexedAt: Date = Date()) {
    self.init(
      id: "logs.\(entry.id)",
      timestamp: entry.timestamp,
      category: .logs,
      title: entry.eventType.rawValue,
      summary: entry.redactedSummary,
      severity: HermesSearchSeverity(logLevel: entry.severity),
      source: .logsViewer,
      indexedAt: indexedAt
    )
  }

  public init(notification record: HermesNotificationRecord, indexedAt: Date = Date()) {
    self.init(
      id: "notifications.\(record.id.uuidString)",
      timestamp: record.createdAt,
      category: .notifications,
      title: record.title,
      summary: record.body,
      severity: HermesSearchSeverity(notificationSeverity: record.severity),
      source: .notificationCenter,
      indexedAt: indexedAt
    )
  }

  public init(diagnostic result: HermesDiagnosticResult, indexedAt: Date = Date()) {
    let failed = [
      result.healthSummary.discoveryState,
      result.healthSummary.processState,
      result.healthSummary.backendState,
      result.healthSummary.sessionState,
      result.healthSummary.eventBusState,
    ].contains(.failed)
    let degraded = [
      result.healthSummary.discoveryState,
      result.healthSummary.processState,
      result.healthSummary.backendState,
      result.healthSummary.sessionState,
      result.healthSummary.eventBusState,
    ].contains(.degraded)
    let summary = result.issues.isEmpty
      ? "Diagnostics completed with \(result.sessionDiagnostics.runningSessions) running sessions."
      : result.issues.joined(separator: "; ")
    self.init(
      id: "diagnostics.\(Int(result.generatedAt.timeIntervalSince1970 * 1000))",
      timestamp: result.generatedAt,
      category: .diagnostics,
      title: "Hermes diagnostics result",
      summary: summary,
      severity: failed ? .error : (degraded || !result.issues.isEmpty ? .warning : .info),
      source: .diagnostics,
      indexedAt: indexedAt
    )
  }

  public init(audit event: HermesAuditEvent, indexedAt: Date = Date()) {
    let metadata = event.metadata.values.sorted { $0.key < $1.key }
      .map { "\($0.key)=\($0.value)" }
      .joined(separator: ", ")
    self.init(
      id: "audit.\(event.eventID.rawValue)",
      timestamp: event.timestamp,
      category: .audit,
      title: event.kind.rawValue,
      summary: metadata.isEmpty ? "\(event.actor.rawValue) \(event.outcome.rawValue) \(event.reasonCode)" : metadata,
      severity: HermesSearchSeverity(auditOutcome: event.outcome),
      source: .auditLog,
      indexedAt: indexedAt
    )
  }
}

extension HermesSearchSeverity {
  public init(timelineStatus: HermesTimelineStatus) {
    switch timelineStatus {
    case .failed:
      self = .error
    case .warning:
      self = .warning
    case .informational, .inProgress, .completed:
      self = .info
    }
  }

  public init(logLevel: HermesRuntimeLogLevel) {
    switch logLevel {
    case .info:
      self = .info
    case .warning:
      self = .warning
    case .error:
      self = .error
    }
  }

  public init(notificationSeverity: HermesNotificationSeverity) {
    switch notificationSeverity {
    case .info:
      self = .info
    case .warning:
      self = .warning
    case .critical:
      self = .critical
    }
  }

  public init(auditOutcome: HermesAuditOutcome) {
    switch auditOutcome {
    case .failed, .denied, .unavailable:
      self = .warning
    case .accepted, .started, .succeeded, .cancelled:
      self = .info
    }
  }
}
