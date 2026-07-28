import Foundation

public enum HermesAnalyticsState: String, Codable, CaseIterable, Equatable, Sendable {
  case stable
  case attentionRequired
  case unreliable
  case unknown
}

public struct HermesRuntimeAnalyticsProviderSnapshot: Codable, Equatable, Sendable {
  public let uptimeSummary: String
  public let sessionStabilitySummary: String
  public let serviceAvailabilitySummary: String

  public init(
    uptimeSummary: String,
    sessionStabilitySummary: String,
    serviceAvailabilitySummary: String
  ) {
    self.uptimeSummary = HermesAnalyticsRedactor.safeText(uptimeSummary, limit: 160)
    self.sessionStabilitySummary = HermesAnalyticsRedactor.safeText(sessionStabilitySummary, limit: 160)
    self.serviceAvailabilitySummary = HermesAnalyticsRedactor.safeText(serviceAvailabilitySummary, limit: 160)
  }
}

public struct HermesOperationsAnalyticsProviderSnapshot: Codable, Equatable, Sendable {
  public let errorTrendSummary: String
  public let recoveryTrendSummary: String
  public let notificationTrendSummary: String
  public let updateReliabilitySummary: String

  public init(
    errorTrendSummary: String,
    recoveryTrendSummary: String,
    notificationTrendSummary: String,
    updateReliabilitySummary: String
  ) {
    self.errorTrendSummary = HermesAnalyticsRedactor.safeText(errorTrendSummary, limit: 160)
    self.recoveryTrendSummary = HermesAnalyticsRedactor.safeText(recoveryTrendSummary, limit: 160)
    self.notificationTrendSummary = HermesAnalyticsRedactor.safeText(notificationTrendSummary, limit: 160)
    self.updateReliabilitySummary = HermesAnalyticsRedactor.safeText(updateReliabilitySummary, limit: 160)
  }
}

public struct HermesGovernanceAnalyticsProviderSnapshot: Codable, Equatable, Sendable {
  public let policyComplianceSummary: String
  public let privacyPostureTrend: String
  public let auditCoverageSummary: String

  public init(
    policyComplianceSummary: String,
    privacyPostureTrend: String,
    auditCoverageSummary: String
  ) {
    self.policyComplianceSummary = HermesAnalyticsRedactor.safeText(policyComplianceSummary, limit: 160)
    self.privacyPostureTrend = HermesAnalyticsRedactor.safeText(privacyPostureTrend, limit: 160)
    self.auditCoverageSummary = HermesAnalyticsRedactor.safeText(auditCoverageSummary, limit: 160)
  }
}

public struct HermesRuntimeAnalyticsSummary: Codable, Equatable, Sendable {
  public let state: HermesAnalyticsState
  public let uptimeSummary: String
  public let sessionStabilitySummary: String
  public let serviceAvailabilitySummary: String
  public let summary: String

  public init(provider: HermesRuntimeAnalyticsProviderSnapshot) {
    uptimeSummary = provider.uptimeSummary
    sessionStabilitySummary = provider.sessionStabilitySummary
    serviceAvailabilitySummary = provider.serviceAvailabilitySummary
    state = Self.state(for: "\(uptimeSummary) \(sessionStabilitySummary) \(serviceAvailabilitySummary)")
    summary = HermesAnalyticsRedactor.safeText(
      "uptime \(uptimeSummary), sessions \(sessionStabilitySummary), service \(serviceAvailabilitySummary)",
      limit: 180
    )
  }
}

public struct HermesOperationsAnalyticsSummary: Codable, Equatable, Sendable {
  public let state: HermesAnalyticsState
  public let errorTrendSummary: String
  public let recoveryTrendSummary: String
  public let notificationTrendSummary: String
  public let updateReliabilitySummary: String
  public let summary: String

  public init(provider: HermesOperationsAnalyticsProviderSnapshot) {
    errorTrendSummary = provider.errorTrendSummary
    recoveryTrendSummary = provider.recoveryTrendSummary
    notificationTrendSummary = provider.notificationTrendSummary
    updateReliabilitySummary = provider.updateReliabilitySummary
    state = Self.state(for: "\(errorTrendSummary) \(recoveryTrendSummary) \(notificationTrendSummary) \(updateReliabilitySummary)")
    summary = HermesAnalyticsRedactor.safeText(
      "errors \(errorTrendSummary), recovery \(recoveryTrendSummary), notifications \(notificationTrendSummary), updates \(updateReliabilitySummary)",
      limit: 220
    )
  }
}

public struct HermesGovernanceAnalyticsSummary: Codable, Equatable, Sendable {
  public let state: HermesAnalyticsState
  public let policyComplianceSummary: String
  public let privacyPostureTrend: String
  public let auditCoverageSummary: String
  public let summary: String

  public init(provider: HermesGovernanceAnalyticsProviderSnapshot) {
    policyComplianceSummary = provider.policyComplianceSummary
    privacyPostureTrend = provider.privacyPostureTrend
    auditCoverageSummary = provider.auditCoverageSummary
    state = Self.state(for: "\(policyComplianceSummary) \(privacyPostureTrend) \(auditCoverageSummary)")
    summary = HermesAnalyticsRedactor.safeText(
      "policy \(policyComplianceSummary), privacy \(privacyPostureTrend), audit \(auditCoverageSummary)",
      limit: 180
    )
  }
}

public struct HermesAnalyticsSnapshot: Codable, Equatable, Sendable {
  public let runtime: HermesRuntimeAnalyticsSummary
  public let operations: HermesOperationsAnalyticsSummary
  public let governance: HermesGovernanceAnalyticsSummary
  public let overallState: HermesAnalyticsState
  public let readOnly: Bool
  public let appOwnsRuntime: Bool
  public let processExecutionAvailable: Bool
  public let shellAvailable: Bool
  public let uploadAvailable: Bool
  public let filesystemScanAvailable: Bool

  public init(
    runtime: HermesRuntimeAnalyticsSummary,
    operations: HermesOperationsAnalyticsSummary,
    governance: HermesGovernanceAnalyticsSummary,
    readOnly: Bool = true,
    appOwnsRuntime: Bool = false,
    processExecutionAvailable: Bool = false,
    shellAvailable: Bool = false,
    uploadAvailable: Bool = false,
    filesystemScanAvailable: Bool = false
  ) {
    self.runtime = runtime
    self.operations = operations
    self.governance = governance
    self.readOnly = readOnly
    self.appOwnsRuntime = appOwnsRuntime
    self.processExecutionAvailable = processExecutionAvailable
    self.shellAvailable = shellAvailable
    self.uploadAvailable = uploadAvailable
    self.filesystemScanAvailable = filesystemScanAvailable
    let states = [runtime.state, operations.state, governance.state]
    if states.contains(.unreliable) {
      overallState = .unreliable
    } else if states.contains(.attentionRequired) {
      overallState = .attentionRequired
    } else if states.contains(.unknown) {
      overallState = .unknown
    } else {
      overallState = .stable
    }
  }

  public static var empty: HermesAnalyticsSnapshot {
    HermesAnalyticsSnapshot(
      runtime: HermesRuntimeAnalyticsSummary(
        provider: HermesRuntimeAnalyticsProviderSnapshot(
          uptimeSummary: "unknown",
          sessionStabilitySummary: "unknown",
          serviceAvailabilitySummary: "unknown"
        )
      ),
      operations: HermesOperationsAnalyticsSummary(
        provider: HermesOperationsAnalyticsProviderSnapshot(
          errorTrendSummary: "unknown",
          recoveryTrendSummary: "unknown",
          notificationTrendSummary: "unknown",
          updateReliabilitySummary: "unknown"
        )
      ),
      governance: HermesGovernanceAnalyticsSummary(
        provider: HermesGovernanceAnalyticsProviderSnapshot(
          policyComplianceSummary: "unknown",
          privacyPostureTrend: "unknown",
          auditCoverageSummary: "unknown"
        )
      )
    )
  }
}

private extension HermesRuntimeAnalyticsSummary {
  static func state(for value: String) -> HermesAnalyticsState {
    HermesAnalyticsStateClassifier.state(for: value)
  }
}

private extension HermesOperationsAnalyticsSummary {
  static func state(for value: String) -> HermesAnalyticsState {
    HermesAnalyticsStateClassifier.state(for: value)
  }
}

private extension HermesGovernanceAnalyticsSummary {
  static func state(for value: String) -> HermesAnalyticsState {
    HermesAnalyticsStateClassifier.state(for: value)
  }
}

private enum HermesAnalyticsStateClassifier {
  static func state(for value: String) -> HermesAnalyticsState {
    let lowercased = value.lowercased()
    if lowercased.contains("failed") || lowercased.contains("unavailable")
      || lowercased.contains("disconnected") || lowercased.contains("unreliable")
    {
      return .unreliable
    }
    if lowercased.contains("attention") || lowercased.contains("degraded")
      || lowercased.contains("blocked") || lowercased.contains("critical")
      || lowercased.contains("elevated")
    {
      return .attentionRequired
    }
    if lowercased.contains("unknown") {
      return .unknown
    }
    return .stable
  }
}

public enum HermesAnalyticsRedactor {
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
}
