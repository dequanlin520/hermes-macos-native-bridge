import Foundation
import HermesRuntimeFoundation

public enum HermesRuntimeLogLevel: String, CaseIterable, Equatable, Sendable {
  case info
  case warning
  case error
}

public enum HermesRuntimeLogFilter: String, CaseIterable, Equatable, Sendable {
  case all
  case info
  case warning
  case error

  public func includes(_ entry: HermesRuntimeLogEntry) -> Bool {
    switch self {
    case .all:
      return true
    case .info:
      return entry.severity == .info
    case .warning:
      return entry.severity == .warning
    case .error:
      return entry.severity == .error
    }
  }
}

public struct HermesRuntimeLogEntry: Equatable, Identifiable, Sendable {
  public let id: UInt64
  public let timestamp: Date
  public let eventType: HermesRuntimeEventKind
  public let severity: HermesRuntimeLogLevel
  public let redactedSummary: String

  public init(
    id: UInt64,
    timestamp: Date,
    eventType: HermesRuntimeEventKind,
    severity: HermesRuntimeLogLevel,
    redactedSummary: String
  ) {
    self.id = id
    self.timestamp = timestamp
    self.eventType = eventType
    self.severity = severity
    self.redactedSummary = Self.redacted(redactedSummary, limit: 220)
  }

  public init(event: HermesRuntimeEvent) {
    self.init(
      id: event.sequenceNumber,
      timestamp: event.occurredAt,
      eventType: event.kind,
      severity: Self.severity(for: event),
      redactedSummary: Self.summary(for: event)
    )
  }

  public static func severity(for event: HermesRuntimeEvent) -> HermesRuntimeLogLevel {
    if event.kind == .sessionFailed || event.session.currentStatus == .failed {
      return .error
    }
    if event.session.currentStatus == .degraded || event.kind == .sessionHealthChanged {
      return .warning
    }
    return .info
  }

  public static func summary(for event: HermesRuntimeEvent) -> String {
    let status = event.session.currentStatus.rawValue
    var parts = ["Runtime session \(status)"]

    if let shutdownReason = event.session.shutdownReason {
      parts.append("shutdown: \(shutdownReason.description)")
    }
    if let lastErrorMessage = event.session.lastErrorMessage {
      parts.append("error: \(lastErrorMessage)")
    }

    return redacted(parts.joined(separator: "; "), limit: 220)
  }

  public static func redacted(_ value: String, limit: Int = 220) -> String {
    var sanitized = value

    let markers = [
      "token=",
      "access_token=",
      "refresh_token=",
      "credential=",
      "credentials=",
      "password=",
      "secret=",
      "api_key=",
      "X-Hermes-Session-Token=",
      "HERMES_DASHBOARD_SESSION_TOKEN=",
    ]
    for marker in markers {
      sanitized = replacingSensitiveValue(after: marker, in: sanitized)
    }

    sanitized = replacingMatches(
      in: sanitized,
      pattern: #"/(?:Applications|Users|Volumes|System|Library|private|var|tmp|usr|bin|sbin|opt)/[^\s,"')]+"#,
      template: "<redacted-path>"
    )
    sanitized = replacingMatches(
      in: sanitized,
      pattern: #"(?i)\bpid(?:\s*[=:]\s*|\s+)[0-9]+\b"#,
      template: "pid=<redacted>"
    )
    sanitized = replacingMatches(
      in: sanitized,
      pattern: #"(?i)\bprocess id(?:\s*[=:]\s*|\s+)[0-9]+\b"#,
      template: "process id=<redacted>"
    )

    return String(sanitized.prefix(limit))
  }

  private static func replacingSensitiveValue(after marker: String, in value: String) -> String {
    var sanitized = value
    var searchStart = sanitized.startIndex
    while searchStart < sanitized.endIndex,
      let range = sanitized.range(
        of: marker,
        options: [.caseInsensitive],
        range: searchStart..<sanitized.endIndex
      )
    {
      let valueStart = range.upperBound
      let valueEnd = sanitized[valueStart...].firstIndex {
        $0 == "&" || $0 == " " || $0 == "\n" || $0 == "\t" || $0 == ")" || $0 == ","
          || $0 == ";"
      } ?? sanitized.endIndex
      sanitized.replaceSubrange(valueStart..<valueEnd, with: "<redacted>")
      searchStart = sanitized.index(valueStart, offsetBy: "<redacted>".count)
    }
    return sanitized
  }

  private static func replacingMatches(
    in value: String,
    pattern: String,
    template: String
  ) -> String {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return value
    }
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return regex.stringByReplacingMatches(in: value, range: range, withTemplate: template)
  }
}
