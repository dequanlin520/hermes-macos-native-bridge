import Foundation

public enum HermesOperationsState: String, Codable, CaseIterable, Equatable, Sendable {
  case nominal
  case attentionRequired
  case unavailable
  case unknown
}

public struct HermesRuntimeOperationsProviderSnapshot: Codable, Equatable, Sendable {
  public let runtimeStatus: String
  public let sessionStatus: String
  public let backendStatus: String
  public let activeOperationCount: Int

  public init(
    runtimeStatus: String,
    sessionStatus: String,
    backendStatus: String,
    activeOperationCount: Int
  ) {
    self.runtimeStatus = HermesOperationsRedactor.safeText(runtimeStatus, limit: 160)
    self.sessionStatus = HermesOperationsRedactor.safeText(sessionStatus, limit: 160)
    self.backendStatus = HermesOperationsRedactor.safeText(backendStatus, limit: 160)
    self.activeOperationCount = max(0, activeOperationCount)
  }
}

public struct HermesEventOperationsProviderSnapshot: Codable, Equatable, Sendable {
  public let eventPipelineStatus: String
  public let recentEventCount: Int
  public let notificationStatus: String
  public let recentEventSummaries: [String]

  public init(
    eventPipelineStatus: String,
    recentEventCount: Int,
    notificationStatus: String,
    recentEventSummaries: [String]
  ) {
    self.eventPipelineStatus = HermesOperationsRedactor.safeText(eventPipelineStatus, limit: 160)
    self.recentEventCount = max(0, recentEventCount)
    self.notificationStatus = HermesOperationsRedactor.safeText(notificationStatus, limit: 160)
    self.recentEventSummaries = recentEventSummaries.map {
      HermesOperationsRedactor.safeText($0, limit: 160)
    }
  }
}

public struct HermesReleaseOperationsProviderSnapshot: Codable, Equatable, Sendable {
  public let releaseStatus: String
  public let currentVersion: String
  public let availableVersion: String?
  public let releaseReadiness: String

  public init(
    releaseStatus: String,
    currentVersion: String,
    availableVersion: String? = nil,
    releaseReadiness: String
  ) {
    self.releaseStatus = HermesOperationsRedactor.safeText(releaseStatus, limit: 160)
    self.currentVersion = HermesOperationsRedactor.safeToken(currentVersion, fallback: "unknown")
    self.availableVersion = availableVersion.map {
      HermesOperationsRedactor.safeToken($0, fallback: "unknown")
    }
    self.releaseReadiness = HermesOperationsRedactor.safeText(releaseReadiness, limit: 160)
  }
}

public struct HermesGovernanceOperationsProviderSnapshot: Codable, Equatable, Sendable {
  public let policyStatus: String
  public let privacyStatus: String
  public let auditStatus: String
  public let complianceStatus: String

  public init(
    policyStatus: String,
    privacyStatus: String,
    auditStatus: String,
    complianceStatus: String
  ) {
    self.policyStatus = HermesOperationsRedactor.safeText(policyStatus, limit: 160)
    self.privacyStatus = HermesOperationsRedactor.safeText(privacyStatus, limit: 160)
    self.auditStatus = HermesOperationsRedactor.safeText(auditStatus, limit: 160)
    self.complianceStatus = HermesOperationsRedactor.safeText(complianceStatus, limit: 160)
  }
}

public struct HermesRuntimeOperationsSummary: Codable, Equatable, Sendable {
  public let state: HermesOperationsState
  public let runtimeStatus: String
  public let sessionStatus: String
  public let backendStatus: String
  public let activeOperationCount: Int
  public let summary: String

  public init(provider: HermesRuntimeOperationsProviderSnapshot) {
    runtimeStatus = provider.runtimeStatus
    sessionStatus = provider.sessionStatus
    backendStatus = provider.backendStatus
    activeOperationCount = provider.activeOperationCount
    state = Self.state(for: "\(runtimeStatus) \(sessionStatus) \(backendStatus)")
    summary = HermesOperationsRedactor.safeText(
      "\(activeOperationCount) active operations, runtime \(runtimeStatus), sessions \(sessionStatus)",
      limit: 180
    )
  }
}

public struct HermesEventOperationsSummary: Codable, Equatable, Sendable {
  public let state: HermesOperationsState
  public let eventPipelineStatus: String
  public let recentEventCount: Int
  public let notificationStatus: String
  public let recentEventSummaries: [String]
  public let summary: String

  public init(provider: HermesEventOperationsProviderSnapshot) {
    eventPipelineStatus = provider.eventPipelineStatus
    recentEventCount = provider.recentEventCount
    notificationStatus = provider.notificationStatus
    recentEventSummaries = Array(provider.recentEventSummaries.prefix(8))
    state = Self.state(for: "\(eventPipelineStatus) \(notificationStatus)")
    summary = HermesOperationsRedactor.safeText(
      "\(recentEventCount) recent events, notifications \(notificationStatus)",
      limit: 180
    )
  }
}

public struct HermesReleaseOperationsSummary: Codable, Equatable, Sendable {
  public let state: HermesOperationsState
  public let releaseStatus: String
  public let currentVersion: String
  public let availableVersion: String?
  public let releaseReadiness: String
  public let summary: String

  public init(provider: HermesReleaseOperationsProviderSnapshot) {
    releaseStatus = provider.releaseStatus
    currentVersion = provider.currentVersion
    availableVersion = provider.availableVersion
    releaseReadiness = provider.releaseReadiness
    state = Self.state(for: "\(releaseStatus) \(releaseReadiness)")
    summary = HermesOperationsRedactor.safeText(
      "current \(currentVersion), available \(availableVersion ?? "none"), status \(releaseStatus)",
      limit: 180
    )
  }
}

public struct HermesGovernanceOperationsSummary: Codable, Equatable, Sendable {
  public let state: HermesOperationsState
  public let policyStatus: String
  public let privacyStatus: String
  public let auditStatus: String
  public let complianceStatus: String
  public let summary: String

  public init(provider: HermesGovernanceOperationsProviderSnapshot) {
    policyStatus = provider.policyStatus
    privacyStatus = provider.privacyStatus
    auditStatus = provider.auditStatus
    complianceStatus = provider.complianceStatus
    state = Self.state(for: "\(policyStatus) \(privacyStatus) \(auditStatus) \(complianceStatus)")
    summary = HermesOperationsRedactor.safeText(
      "policy \(policyStatus), privacy \(privacyStatus), audit \(auditStatus)",
      limit: 180
    )
  }
}

public struct HermesOperationsSnapshot: Codable, Equatable, Sendable {
  public let runtime: HermesRuntimeOperationsSummary
  public let events: HermesEventOperationsSummary
  public let release: HermesReleaseOperationsSummary
  public let governance: HermesGovernanceOperationsSummary
  public let overallState: HermesOperationsState
  public let readOnly: Bool
  public let appOwnsRuntime: Bool
  public let processExecutionAvailable: Bool
  public let shellAvailable: Bool
  public let uploadAvailable: Bool
  public let filesystemScanAvailable: Bool
  public let sensitiveDataPersistenceAvailable: Bool

  public init(
    runtime: HermesRuntimeOperationsSummary,
    events: HermesEventOperationsSummary,
    release: HermesReleaseOperationsSummary,
    governance: HermesGovernanceOperationsSummary,
    readOnly: Bool = true,
    appOwnsRuntime: Bool = false,
    processExecutionAvailable: Bool = false,
    shellAvailable: Bool = false,
    uploadAvailable: Bool = false,
    filesystemScanAvailable: Bool = false,
    sensitiveDataPersistenceAvailable: Bool = false
  ) {
    self.runtime = runtime
    self.events = events
    self.release = release
    self.governance = governance
    self.readOnly = readOnly
    self.appOwnsRuntime = appOwnsRuntime
    self.processExecutionAvailable = processExecutionAvailable
    self.shellAvailable = shellAvailable
    self.uploadAvailable = uploadAvailable
    self.filesystemScanAvailable = filesystemScanAvailable
    self.sensitiveDataPersistenceAvailable = sensitiveDataPersistenceAvailable
    let states = [runtime.state, events.state, release.state, governance.state]
    if states.contains(.unavailable) {
      overallState = .unavailable
    } else if states.contains(.attentionRequired) {
      overallState = .attentionRequired
    } else if states.contains(.unknown) {
      overallState = .unknown
    } else {
      overallState = .nominal
    }
  }

  public static var empty: HermesOperationsSnapshot {
    HermesOperationsSnapshot(
      runtime: HermesRuntimeOperationsSummary(
        provider: HermesRuntimeOperationsProviderSnapshot(
          runtimeStatus: "unknown",
          sessionStatus: "unknown",
          backendStatus: "unknown",
          activeOperationCount: 0
        )
      ),
      events: HermesEventOperationsSummary(
        provider: HermesEventOperationsProviderSnapshot(
          eventPipelineStatus: "unknown",
          recentEventCount: 0,
          notificationStatus: "unknown",
          recentEventSummaries: []
        )
      ),
      release: HermesReleaseOperationsSummary(
        provider: HermesReleaseOperationsProviderSnapshot(
          releaseStatus: "unknown",
          currentVersion: "unknown",
          releaseReadiness: "unknown"
        )
      ),
      governance: HermesGovernanceOperationsSummary(
        provider: HermesGovernanceOperationsProviderSnapshot(
          policyStatus: "unknown",
          privacyStatus: "unknown",
          auditStatus: "unknown",
          complianceStatus: "unknown"
        )
      )
    )
  }
}

private extension HermesRuntimeOperationsSummary {
  static func state(for value: String) -> HermesOperationsState {
    HermesOperationsStateClassifier.state(for: value)
  }
}

private extension HermesEventOperationsSummary {
  static func state(for value: String) -> HermesOperationsState {
    HermesOperationsStateClassifier.state(for: value)
  }
}

private extension HermesReleaseOperationsSummary {
  static func state(for value: String) -> HermesOperationsState {
    HermesOperationsStateClassifier.state(for: value)
  }
}

private extension HermesGovernanceOperationsSummary {
  static func state(for value: String) -> HermesOperationsState {
    HermesOperationsStateClassifier.state(for: value)
  }
}

private enum HermesOperationsStateClassifier {
  static func state(for value: String) -> HermesOperationsState {
    let lowercased = value.lowercased()
    if lowercased.contains("failed") || lowercased.contains("unavailable")
      || lowercased.contains("disconnected")
    {
      return .unavailable
    }
    if lowercased.contains("attention") || lowercased.contains("degraded")
      || lowercased.contains("blocked") || lowercased.contains("critical")
    {
      return .attentionRequired
    }
    if lowercased.contains("unknown") {
      return .unknown
    }
    return .nominal
  }
}

public enum HermesOperationsRedactor {
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
