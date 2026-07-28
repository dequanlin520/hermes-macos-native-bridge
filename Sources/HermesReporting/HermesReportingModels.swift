import Foundation

public enum HermesReportFormat: String, Codable, CaseIterable, Equatable, Sendable {
  case markdown
  case html

  public var fileExtension: String {
    switch self {
    case .markdown:
      return "md"
    case .html:
      return "html"
    }
  }
}

public enum HermesReportingState: String, Codable, CaseIterable, Equatable, Sendable {
  case ready
  case attentionRequired
  case unavailable
  case unknown
}

public struct HermesReportDomainSummary: Codable, Equatable, Sendable {
  public let title: String
  public let state: HermesReportingState
  public let summary: String
  public let details: [String]

  public init(
    title: String,
    state: HermesReportingState,
    summary: String,
    details: [String] = []
  ) {
    self.title = HermesReportingRedactor.safeText(title, limit: 80)
    self.state = state
    self.summary = HermesReportingRedactor.safeText(summary, limit: 220)
    self.details = details.map { HermesReportingRedactor.safeText($0, limit: 180) }
  }
}

public struct HermesReportHistoryEntry: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let title: String
  public let format: HermesReportFormat
  public let createdAt: Date
  public let relativePath: String
  public let byteCount: Int

  public init(
    id: UUID = UUID(),
    title: String,
    format: HermesReportFormat,
    createdAt: Date = Date(),
    relativePath: String,
    byteCount: Int
  ) {
    self.id = id
    self.title = HermesReportingRedactor.safeText(title, limit: 120)
    self.format = format
    self.createdAt = createdAt
    self.relativePath = HermesReportingRedactor.safeRelativePath(relativePath)
    self.byteCount = max(0, byteCount)
  }
}

public struct HermesReportDocument: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let title: String
  public let format: HermesReportFormat
  public let createdAt: Date
  public let fileName: String
  public let body: String

  public init(
    id: UUID = UUID(),
    title: String,
    format: HermesReportFormat,
    createdAt: Date = Date(),
    fileName: String,
    body: String
  ) {
    self.id = id
    self.title = HermesReportingRedactor.safeText(title, limit: 120)
    self.format = format
    self.createdAt = createdAt
    self.fileName = HermesReportingRedactor.safeFileName(fileName, fallback: "hermes-report.\(format.fileExtension)")
    self.body = HermesReportingRedactor.safeText(body, limit: 32_000)
  }
}

public struct HermesReportingSnapshot: Codable, Equatable, Sendable {
  public let health: HermesReportDomainSummary
  public let operations: HermesReportDomainSummary
  public let analytics: HermesReportDomainSummary
  public let compliance: HermesReportDomainSummary
  public let audit: HermesReportDomainSummary
  public let overallState: HermesReportingState
  public let supportedFormats: [HermesReportFormat]
  public let history: [HermesReportHistoryEntry]
  public let readOnly: Bool
  public let appOwnsRuntime: Bool
  public let processExecutionAvailable: Bool
  public let shellAvailable: Bool
  public let uploadAvailable: Bool
  public let networkAvailable: Bool
  public let filesystemScanAvailable: Bool

  public init(
    health: HermesReportDomainSummary,
    operations: HermesReportDomainSummary,
    analytics: HermesReportDomainSummary,
    compliance: HermesReportDomainSummary,
    audit: HermesReportDomainSummary,
    supportedFormats: [HermesReportFormat] = HermesReportFormat.allCases,
    history: [HermesReportHistoryEntry] = [],
    readOnly: Bool = true,
    appOwnsRuntime: Bool = false,
    processExecutionAvailable: Bool = false,
    shellAvailable: Bool = false,
    uploadAvailable: Bool = false,
    networkAvailable: Bool = false,
    filesystemScanAvailable: Bool = false
  ) {
    self.health = health
    self.operations = operations
    self.analytics = analytics
    self.compliance = compliance
    self.audit = audit
    self.supportedFormats = supportedFormats
    self.history = history.sorted { $0.createdAt > $1.createdAt }
    self.readOnly = readOnly
    self.appOwnsRuntime = appOwnsRuntime
    self.processExecutionAvailable = processExecutionAvailable
    self.shellAvailable = shellAvailable
    self.uploadAvailable = uploadAvailable
    self.networkAvailable = networkAvailable
    self.filesystemScanAvailable = filesystemScanAvailable
    let states = [health.state, operations.state, analytics.state, compliance.state, audit.state]
    if states.contains(.unavailable) {
      overallState = .unavailable
    } else if states.contains(.attentionRequired) {
      overallState = .attentionRequired
    } else if states.contains(.unknown) {
      overallState = .unknown
    } else {
      overallState = .ready
    }
  }

  public static var empty: HermesReportingSnapshot {
    HermesReportingSnapshot(
      health: HermesReportDomainSummary(title: "Health", state: .unknown, summary: "unknown"),
      operations: HermesReportDomainSummary(title: "Operations", state: .unknown, summary: "unknown"),
      analytics: HermesReportDomainSummary(title: "Analytics", state: .unknown, summary: "unknown"),
      compliance: HermesReportDomainSummary(title: "Compliance", state: .unknown, summary: "unknown"),
      audit: HermesReportDomainSummary(title: "Audit", state: .unknown, summary: "unknown")
    )
  }
}

public enum HermesReportingRenderer {
  public static func render(snapshot: HermesReportingSnapshot, format: HermesReportFormat) -> HermesReportDocument {
    let createdAt = Date()
    let title = "Hermes Enterprise Report"
    let fileName = "hermes-enterprise-report-\(Int(createdAt.timeIntervalSince1970)).\(format.fileExtension)"
    let body: String
    switch format {
    case .markdown:
      body = markdown(snapshot: snapshot, title: title)
    case .html:
      body = html(snapshot: snapshot, title: title)
    }
    return HermesReportDocument(
      title: title,
      format: format,
      createdAt: createdAt,
      fileName: fileName,
      body: body
    )
  }

  private static func markdown(snapshot: HermesReportingSnapshot, title: String) -> String {
    let sections = domainSummaries(snapshot).map { domain in
      """
      ## \(domain.title)
      State: \(domain.state.rawValue)

      \(domain.summary)

      \(domain.details.map { "- \($0)" }.joined(separator: "\n"))
      """
    }.joined(separator: "\n\n")
    return HermesReportingRedactor.safeText(
      """
      # \(title)

      Overall: \(snapshot.overallState.rawValue)
      Read only: \(snapshot.readOnly ? "yes" : "no")

      \(sections)
      """,
      limit: 32_000
    )
  }

  private static func html(snapshot: HermesReportingSnapshot, title: String) -> String {
    let sections = domainSummaries(snapshot).map { domain in
      let details = domain.details.map { "<li>\(escapeHTML($0))</li>" }.joined()
      return """
      <section><h2>\(escapeHTML(domain.title))</h2><p><strong>State:</strong> \(escapeHTML(domain.state.rawValue))</p><p>\(escapeHTML(domain.summary))</p><ul>\(details)</ul></section>
      """
    }.joined(separator: "\n")
    return HermesReportingRedactor.safeText(
      """
      <!doctype html><html><head><meta charset="utf-8"><title>\(escapeHTML(title))</title></head><body><h1>\(escapeHTML(title))</h1><p><strong>Overall:</strong> \(escapeHTML(snapshot.overallState.rawValue))</p><p><strong>Read only:</strong> \(snapshot.readOnly ? "yes" : "no")</p>\(sections)</body></html>
      """,
      limit: 32_000
    )
  }

  private static func domainSummaries(_ snapshot: HermesReportingSnapshot) -> [HermesReportDomainSummary] {
    [snapshot.health, snapshot.operations, snapshot.analytics, snapshot.compliance, snapshot.audit]
  }

  private static func escapeHTML(_ value: String) -> String {
    value
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&#39;")
  }
}

public enum HermesReportingRedactor {
  public static func safeText(_ value: String, limit: Int = 320) -> String {
    var output = String(value.prefix(limit))
    let replacements: [(String, String)] = [
      (#"(?i)\b(token|password|api[_ -]?key|credential|secret|private[_ -]?key)\s*[:=]\s*[^,\s<]+"#, "$1=<redacted>"),
      (#"(?i)\bbearer\s+[A-Za-z0-9._~+/\-=]+"#, "bearer <redacted>"),
      (#"(?is)-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----"#, "<redacted-private-key>"),
      (#"/(?:Applications|Users|Volumes|System|Library|private|var|tmp|usr|bin|sbin|opt)/[^\s,"'<)]+"#, "<redacted-path>"),
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

  public static func safeFileName(_ value: String, fallback: String) -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-")
    }
    let fileName = String(filtered.prefix(120))
    return fileName.isEmpty ? fallback : fileName
  }

  public static func safeRelativePath(_ value: String) -> String {
    let components = value.split(separator: "/").map {
      safeFileName(String($0), fallback: "report")
    }
    let safe = components.joined(separator: "/")
    return safe.isEmpty ? "report" : safe
  }
}
