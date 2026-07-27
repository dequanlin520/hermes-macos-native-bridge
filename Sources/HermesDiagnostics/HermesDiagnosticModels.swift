import Foundation
import HermesRuntimeFoundation

public enum HermesDiagnosticComponentState: String, Codable, Equatable, Sendable {
  case unknown
  case unavailable
  case ready
  case degraded
  case failed
  case stopped
}

public struct HermesDiagnosticHealthSummary: Codable, Equatable, Sendable {
  public var discoveryState: HermesDiagnosticComponentState
  public var processState: HermesDiagnosticComponentState
  public var backendState: HermesDiagnosticComponentState
  public var sessionState: HermesDiagnosticComponentState
  public var eventBusState: HermesDiagnosticComponentState

  public init(
    discoveryState: HermesDiagnosticComponentState = .unknown,
    processState: HermesDiagnosticComponentState = .unknown,
    backendState: HermesDiagnosticComponentState = .unknown,
    sessionState: HermesDiagnosticComponentState = .unknown,
    eventBusState: HermesDiagnosticComponentState = .unknown
  ) {
    self.discoveryState = discoveryState
    self.processState = processState
    self.backendState = backendState
    self.sessionState = sessionState
    self.eventBusState = eventBusState
  }
}

public struct HermesDiagnosticEnvironmentInfo: Codable, Equatable, Sendable {
  public var macOSVersion: String
  public var architecture: String
  public var hermesVersion: String
  public var permissionStates: [HermesDiagnosticPermissionState]

  public init(
    macOSVersion: String,
    architecture: String,
    hermesVersion: String,
    permissionStates: [HermesDiagnosticPermissionState] = []
  ) {
    self.macOSVersion = HermesDiagnosticRedactor.safeDisplayText(macOSVersion, limit: 120)
    self.architecture = HermesDiagnosticRedactor.safeToken(architecture, fallback: "unknown")
    self.hermesVersion = HermesDiagnosticRedactor.safeDisplayText(hermesVersion, limit: 80)
    self.permissionStates = permissionStates
  }
}

public struct HermesDiagnosticPermissionState: Codable, Equatable, Identifiable, Sendable {
  public var id: String { kind }
  public let kind: String
  public let state: String
  public let detailCode: String

  public init(kind: String, state: String, detailCode: String) {
    self.kind = HermesDiagnosticRedactor.safeRedactedToken(kind, fallback: "unknown")
    self.state = HermesDiagnosticRedactor.safeRedactedToken(state, fallback: "unknown")
    self.detailCode = HermesDiagnosticRedactor.safeRedactedToken(detailCode, fallback: "unknown")
  }

  public init(check: HermesPermissionCheck) {
    self.init(
      kind: check.kind.rawValue,
      state: check.state.rawValue,
      detailCode: check.detailCode
    )
  }
}

public struct HermesDiagnosticSessionDiagnostics: Codable, Equatable, Sendable {
  public var activeSessions: Int
  public var runningSessions: Int
  public var failedSessions: Int

  public init(activeSessions: Int = 0, runningSessions: Int = 0, failedSessions: Int = 0) {
    self.activeSessions = max(0, activeSessions)
    self.runningSessions = max(0, runningSessions)
    self.failedSessions = max(0, failedSessions)
  }
}

public struct HermesDiagnosticResult: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public var schemaVersion: Int
  public var generatedAt: Date
  public var healthSummary: HermesDiagnosticHealthSummary
  public var environmentInfo: HermesDiagnosticEnvironmentInfo
  public var sessionDiagnostics: HermesDiagnosticSessionDiagnostics
  public var issues: [String]

  public init(
    schemaVersion: Int = currentSchemaVersion,
    generatedAt: Date = Date(),
    healthSummary: HermesDiagnosticHealthSummary,
    environmentInfo: HermesDiagnosticEnvironmentInfo,
    sessionDiagnostics: HermesDiagnosticSessionDiagnostics,
    issues: [String] = []
  ) {
    self.schemaVersion = schemaVersion
    self.generatedAt = generatedAt
    self.healthSummary = healthSummary
    self.environmentInfo = environmentInfo
    self.sessionDiagnostics = sessionDiagnostics
    self.issues = issues.map { HermesDiagnosticRedactor.safeDisplayText($0, limit: 180) }
  }
}

public struct HermesDiagnosticsState: Equatable, Sendable {
  public var result: HermesDiagnosticResult?
  public var lastErrorMessage: String?
  public var isRefreshing: Bool
  public var isRunningDiagnostics: Bool

  public init(
    result: HermesDiagnosticResult? = nil,
    lastErrorMessage: String? = nil,
    isRefreshing: Bool = false,
    isRunningDiagnostics: Bool = false
  ) {
    self.result = result
    self.lastErrorMessage = lastErrorMessage.map { HermesDiagnosticRedactor.safeDisplayText($0, limit: 180) }
    self.isRefreshing = isRefreshing
    self.isRunningDiagnostics = isRunningDiagnostics
  }
}

public enum HermesDiagnosticRedactor {
  public static func safeRedactedToken(
    _ value: String,
    fallback: String = "unknown",
    limit: Int = 80
  ) -> String {
    safeToken(safeDisplayText(value, limit: limit), fallback: fallback, limit: limit)
  }

  public static func safeToken(_ value: String, fallback: String = "unknown", limit: Int = 80) -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-")
    }
    let output = filtered.isEmpty ? fallback : filtered
    return String(output.prefix(limit))
  }

  public static func safeDisplayText(_ value: String, limit: Int = 240) -> String {
    var output = String(value.prefix(limit))
    let patterns = [
      (#"(?i)\b(token|password|credential|secret|private[_ -]?key|api[_ -]?key)\s*[:=]\s*[^,\s]+"#, "$1=<redacted>"),
      (#"(?i)\b(bearer)\s+[A-Za-z0-9._~+/\-=]+"#, "$1 <redacted>"),
      (#"(?is)-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----"#, "<redacted-private-key>"),
      (#"/(?:Users|private|var|tmp|Applications|System|Library)/[^\s,"')]+"#, "<redacted-path>"),
      (#"\bpid\s*[:=]\s*\d+\b"#, "<redacted-process-id>"),
      (#"\bprocess\s+id\s*[:=]\s*\d+\b"#, "<redacted-process-id>"),
    ]
    for (pattern, template) in patterns {
      output = output.replacingOccurrences(
        of: pattern,
        with: template,
        options: [.regularExpression, .caseInsensitive]
      )
    }
    return String(output.prefix(limit))
  }
}
