import Foundation

public enum HermesHealthState: String, Codable, CaseIterable, Equatable, Sendable {
  case healthy
  case degraded
  case unavailable
  case unknown
}

public enum HermesHealthAvailability: String, Codable, CaseIterable, Equatable, Sendable {
  case available
  case unavailable
  case unknown
}

public enum HermesHealthConnectivity: String, Codable, CaseIterable, Equatable, Sendable {
  case connected
  case disconnected
  case unknown
}

public struct HermesHealthSystemProviderSnapshot: Codable, Equatable, Sendable {
  public let applicationAvailability: HermesHealthAvailability
  public let serviceAvailability: HermesHealthAvailability
  public let xpcConnectivity: HermesHealthConnectivity
  public let applicationVersion: String
  public let protocolVersion: String

  public init(
    applicationAvailability: HermesHealthAvailability,
    serviceAvailability: HermesHealthAvailability,
    xpcConnectivity: HermesHealthConnectivity,
    applicationVersion: String = "unknown",
    protocolVersion: String = "unknown"
  ) {
    self.applicationAvailability = applicationAvailability
    self.serviceAvailability = serviceAvailability
    self.xpcConnectivity = xpcConnectivity
    self.applicationVersion = HermesHealthRedactor.safeToken(applicationVersion, fallback: "unknown")
    self.protocolVersion = HermesHealthRedactor.safeToken(protocolVersion, fallback: "unknown")
  }
}

public struct HermesHealthRuntimeProviderSnapshot: Codable, Equatable, Sendable {
  public let runtimeStatusSummary: String
  public let sessionAvailabilitySummary: String
  public let backendAvailabilitySummary: String

  public init(
    runtimeStatusSummary: String,
    sessionAvailabilitySummary: String,
    backendAvailabilitySummary: String
  ) {
    self.runtimeStatusSummary = HermesHealthRedactor.safeText(runtimeStatusSummary, limit: 160)
    self.sessionAvailabilitySummary = HermesHealthRedactor.safeText(
      sessionAvailabilitySummary,
      limit: 160
    )
    self.backendAvailabilitySummary = HermesHealthRedactor.safeText(
      backendAvailabilitySummary,
      limit: 160
    )
  }
}

public struct HermesHealthOperationalProviderSnapshot: Codable, Equatable, Sendable {
  public let recentFailures: [String]
  public let recoveryStatus: String
  public let updateStatus: String
  public let notificationStatus: String

  public init(
    recentFailures: [String],
    recoveryStatus: String,
    updateStatus: String,
    notificationStatus: String
  ) {
    self.recentFailures = recentFailures.map { HermesHealthRedactor.safeText($0, limit: 160) }
    self.recoveryStatus = HermesHealthRedactor.safeText(recoveryStatus, limit: 160)
    self.updateStatus = HermesHealthRedactor.safeText(updateStatus, limit: 160)
    self.notificationStatus = HermesHealthRedactor.safeText(notificationStatus, limit: 160)
  }
}

public struct HermesHealthComplianceProviderSnapshot: Codable, Equatable, Sendable {
  public let policyStatus: String
  public let privacyStatus: String
  public let auditStatus: String

  public init(policyStatus: String, privacyStatus: String, auditStatus: String) {
    self.policyStatus = HermesHealthRedactor.safeText(policyStatus, limit: 160)
    self.privacyStatus = HermesHealthRedactor.safeText(privacyStatus, limit: 160)
    self.auditStatus = HermesHealthRedactor.safeText(auditStatus, limit: 160)
  }
}

public struct HermesHealthSystemSummary: Codable, Equatable, Sendable {
  public let state: HermesHealthState
  public let applicationAvailability: HermesHealthAvailability
  public let serviceAvailability: HermesHealthAvailability
  public let xpcConnectivity: HermesHealthConnectivity
  public let applicationVersion: String
  public let protocolVersion: String
  public let summary: String

  public init(provider: HermesHealthSystemProviderSnapshot) {
    applicationAvailability = provider.applicationAvailability
    serviceAvailability = provider.serviceAvailability
    xpcConnectivity = provider.xpcConnectivity
    applicationVersion = provider.applicationVersion
    protocolVersion = provider.protocolVersion
    if applicationAvailability == .unavailable || serviceAvailability == .unavailable
      || xpcConnectivity == .disconnected
    {
      state = .unavailable
    } else if applicationAvailability == .unknown || serviceAvailability == .unknown
      || xpcConnectivity == .unknown
    {
      state = .unknown
    } else {
      state = .healthy
    }
    summary = HermesHealthRedactor.safeText(
      "app \(applicationAvailability.rawValue), service \(serviceAvailability.rawValue), xpc \(xpcConnectivity.rawValue)",
      limit: 160
    )
  }
}

public struct HermesHealthRuntimeSummary: Codable, Equatable, Sendable {
  public let state: HermesHealthState
  public let runtimeStatusSummary: String
  public let sessionAvailabilitySummary: String
  public let backendAvailabilitySummary: String

  public init(provider: HermesHealthRuntimeProviderSnapshot) {
    runtimeStatusSummary = provider.runtimeStatusSummary
    sessionAvailabilitySummary = provider.sessionAvailabilitySummary
    backendAvailabilitySummary = provider.backendAvailabilitySummary
    let joined = "\(runtimeStatusSummary) \(sessionAvailabilitySummary) \(backendAvailabilitySummary)"
      .lowercased()
    if joined.contains("failed") || joined.contains("unavailable") {
      state = .unavailable
    } else if joined.contains("degraded") || joined.contains("unknown") {
      state = .degraded
    } else {
      state = .healthy
    }
  }
}

public struct HermesHealthOperationalSummary: Codable, Equatable, Sendable {
  public let state: HermesHealthState
  public let recentFailuresSummary: String
  public let recoveryStatus: String
  public let updateStatus: String
  public let notificationStatus: String
  public let recentFailures: [String]

  public init(provider: HermesHealthOperationalProviderSnapshot) {
    recentFailures = Array(provider.recentFailures.prefix(8))
    recentFailuresSummary = HermesHealthRedactor.safeText(
      recentFailures.isEmpty ? "no recent failures" : "\(recentFailures.count) recent failures",
      limit: 120
    )
    recoveryStatus = provider.recoveryStatus
    updateStatus = provider.updateStatus
    notificationStatus = provider.notificationStatus
    let joined = "\(recentFailures.joined(separator: " ")) \(recoveryStatus) \(updateStatus) \(notificationStatus)"
      .lowercased()
    if joined.contains("failed") || joined.contains("recoveryrequired") || joined.contains("critical") {
      state = .degraded
    } else {
      state = recentFailures.isEmpty ? .healthy : .degraded
    }
  }
}

public struct HermesHealthComplianceSummary: Codable, Equatable, Sendable {
  public let state: HermesHealthState
  public let policyStatus: String
  public let privacyStatus: String
  public let auditStatus: String

  public init(provider: HermesHealthComplianceProviderSnapshot) {
    policyStatus = provider.policyStatus
    privacyStatus = provider.privacyStatus
    auditStatus = provider.auditStatus
    let joined = "\(policyStatus) \(privacyStatus) \(auditStatus)".lowercased()
    if joined.contains("failed") || joined.contains("unavailable") {
      state = .unavailable
    } else if joined.contains("attention") || joined.contains("unknown") {
      state = .degraded
    } else {
      state = .healthy
    }
  }
}

public struct HermesHealthSnapshot: Codable, Equatable, Sendable {
  public let system: HermesHealthSystemSummary
  public let runtime: HermesHealthRuntimeSummary
  public let operational: HermesHealthOperationalSummary
  public let compliance: HermesHealthComplianceSummary
  public let overallState: HermesHealthState
  public let readOnly: Bool
  public let appOwnsRuntime: Bool
  public let automaticRepairAvailable: Bool
  public let processExecutionAvailable: Bool
  public let shellAvailable: Bool
  public let uploadAvailable: Bool
  public let filesystemScanAvailable: Bool

  public init(
    system: HermesHealthSystemSummary,
    runtime: HermesHealthRuntimeSummary,
    operational: HermesHealthOperationalSummary,
    compliance: HermesHealthComplianceSummary,
    readOnly: Bool = true,
    appOwnsRuntime: Bool = false,
    automaticRepairAvailable: Bool = false,
    processExecutionAvailable: Bool = false,
    shellAvailable: Bool = false,
    uploadAvailable: Bool = false,
    filesystemScanAvailable: Bool = false
  ) {
    self.system = system
    self.runtime = runtime
    self.operational = operational
    self.compliance = compliance
    self.readOnly = readOnly
    self.appOwnsRuntime = appOwnsRuntime
    self.automaticRepairAvailable = automaticRepairAvailable
    self.processExecutionAvailable = processExecutionAvailable
    self.shellAvailable = shellAvailable
    self.uploadAvailable = uploadAvailable
    self.filesystemScanAvailable = filesystemScanAvailable
    let states = [system.state, runtime.state, operational.state, compliance.state]
    if states.contains(.unavailable) {
      overallState = .unavailable
    } else if states.contains(.degraded) {
      overallState = .degraded
    } else if states.contains(.unknown) {
      overallState = .unknown
    } else {
      overallState = .healthy
    }
  }

  public static var empty: HermesHealthSnapshot {
    HermesHealthSnapshot(
      system: HermesHealthSystemSummary(
        provider: HermesHealthSystemProviderSnapshot(
          applicationAvailability: .unknown,
          serviceAvailability: .unknown,
          xpcConnectivity: .unknown
        )
      ),
      runtime: HermesHealthRuntimeSummary(
        provider: HermesHealthRuntimeProviderSnapshot(
          runtimeStatusSummary: "unknown",
          sessionAvailabilitySummary: "unknown",
          backendAvailabilitySummary: "unknown"
        )
      ),
      operational: HermesHealthOperationalSummary(
        provider: HermesHealthOperationalProviderSnapshot(
          recentFailures: [],
          recoveryStatus: "unknown",
          updateStatus: "unknown",
          notificationStatus: "unknown"
        )
      ),
      compliance: HermesHealthComplianceSummary(
        provider: HermesHealthComplianceProviderSnapshot(
          policyStatus: "unknown",
          privacyStatus: "unknown",
          auditStatus: "unknown"
        )
      )
    )
  }
}

public enum HermesHealthRedactor {
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
