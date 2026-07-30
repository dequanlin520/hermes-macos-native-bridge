import Foundation

public enum HermesAgentCompatibilityLevel: String, Codable, CaseIterable, Equatable, Sendable {
  case compatible
  case partiallyCompatible = "partially-compatible"
  case incompatible
  case blocked
  case unverified
}

public enum HermesAgentCapabilityID: String, Codable, CaseIterable, Equatable, Sendable {
  case executableDiscovery = "executable-discovery"
  case versionQuery = "version-query"
  case helpQuery = "help-query"
  case isolatedProfileRoot = "isolated-profile-root"
  case isolatedConfigurationInspection = "isolated-configuration-inspection"
  case boundedAgentStartup = "bounded-agent-startup"
  case agentReadinessDetection = "agent-readiness-detection"
  case serviceOwnedAgentDiscovery = "service-owned-agent-discovery"
  case lifecycleStatusQuery = "lifecycle-status-query"
  case requestSubmissionHandshake = "request-submission-handshake"
  case requestCancellationHandshake = "request-cancellation-handshake"
  case approvalCapabilityDiscovery = "approval-capability-discovery"
  case gracefulAgentShutdown = "graceful-agent-shutdown"
  case forcedExactPIDCleanupFallback = "forced-exact-pid-cleanup-fallback"
  case realHomeIsolation = "real-home-isolation"
  case generatedArtifactCleanup = "generated-artifact-cleanup"
}

public struct HermesAgentVersionDescriptor: Codable, Equatable, Sendable {
  public let discoveryStatus: String
  public let executableFamily: String
  public let executableBasename: String
  public let semanticVersion: String?
  public let versionCommandExitStatus: String
  public let supportedInvocationStyle: String
  public let sourceCategory: String

  public init(
    discoveryStatus: String,
    executableFamily: String,
    executableBasename: String,
    semanticVersion: String?,
    versionCommandExitStatus: String,
    supportedInvocationStyle: String,
    sourceCategory: String
  ) {
    self.discoveryStatus = Self.safeToken(discoveryStatus)
    self.executableFamily = Self.safeToken(executableFamily)
    self.executableBasename = Self.safeBasename(executableBasename)
    self.semanticVersion = semanticVersion.map(Self.safeSemanticVersion)
    self.versionCommandExitStatus = Self.safeToken(versionCommandExitStatus)
    self.supportedInvocationStyle = Self.safeToken(supportedInvocationStyle)
    self.sourceCategory = Self.safeToken(sourceCategory)
  }

  public init(result: HermesDiscoveryResult, sourceCategory: String) {
    self.init(
      discoveryStatus: "available",
      executableFamily: "hermes-agent",
      executableBasename: URL(fileURLWithPath: result.candidate.originalPath).lastPathComponent,
      semanticVersion: result.versionInfo.semanticVersion,
      versionCommandExitStatus: "0",
      supportedInvocationStyle: "direct-executable",
      sourceCategory: sourceCategory
    )
  }

  public static func unavailable(sourceCategory: String = "unavailable") -> Self {
    Self(
      discoveryStatus: "unavailable",
      executableFamily: "unknown",
      executableBasename: "unknown",
      semanticVersion: nil,
      versionCommandExitStatus: "unknown",
      supportedInvocationStyle: "unknown",
      sourceCategory: sourceCategory
    )
  }

  private static func safeSemanticVersion(_ value: String) -> String {
    String(value.prefix(32)).filter { $0.isASCII && ($0.isNumber || $0 == ".") }
  }

  private static func safeBasename(_ value: String) -> String {
    let basename = URL(fileURLWithPath: value).lastPathComponent
    let filtered = basename.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_") }
    return filtered.isEmpty ? "unknown" : String(filtered.prefix(64))
  }

  private static func safeToken(_ value: String) -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_")
    }
    return filtered.isEmpty ? "unknown" : String(filtered.prefix(64))
  }
}

public struct HermesAgentCapabilityResult: Codable, Equatable, Sendable {
  public let capabilityIdentifier: HermesAgentCapabilityID
  public let compatibilityLevel: HermesAgentCompatibilityLevel
  public let exercised: Bool
  public let evidenceCategory: String
  public let reasonCode: String
  public let minimumDetectedVersion: String?
  public let observedVersion: String?
  public let blocking: Bool
  public let privacySafeNotes: String

  public init(
    capabilityIdentifier: HermesAgentCapabilityID,
    compatibilityLevel: HermesAgentCompatibilityLevel,
    exercised: Bool,
    evidenceCategory: String,
    reasonCode: String,
    minimumDetectedVersion: String? = nil,
    observedVersion: String? = nil,
    blocking: Bool,
    privacySafeNotes: String = ""
  ) {
    self.capabilityIdentifier = capabilityIdentifier
    self.compatibilityLevel = compatibilityLevel
    self.exercised = exercised
    self.evidenceCategory = Self.safeToken(evidenceCategory)
    self.reasonCode = Self.safeToken(reasonCode)
    self.minimumDetectedVersion = minimumDetectedVersion.map(Self.safeSemanticVersion)
    self.observedVersion = observedVersion.map(Self.safeSemanticVersion)
    self.blocking = blocking
    self.privacySafeNotes = Self.safeNote(privacySafeNotes)
  }

  private static func safeSemanticVersion(_ value: String) -> String {
    String(value.prefix(32)).filter { $0.isASCII && ($0.isNumber || $0 == ".") }
  }

  private static func safeToken(_ value: String) -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_")
    }
    return filtered.isEmpty ? "unknown" : String(filtered.prefix(96))
  }

  private static func safeNote(_ value: String) -> String {
    let filtered = value.filter { scalar in
      scalar.isASCII && scalar != "/" && scalar != ":" && scalar != "{" && scalar != "}"
    }
    return String(filtered.prefix(160))
  }
}

public struct HermesAgentCompatibilityReport: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let overallCompatibilityLevel: HermesAgentCompatibilityLevel
  public let versionDescriptor: HermesAgentVersionDescriptor
  public let capabilities: [HermesAgentCapabilityResult]

  public init(
    schemaVersion: Int = 1,
    overallCompatibilityLevel: HermesAgentCompatibilityLevel,
    versionDescriptor: HermesAgentVersionDescriptor,
    capabilities: [HermesAgentCapabilityResult]
  ) {
    self.schemaVersion = schemaVersion
    self.overallCompatibilityLevel = overallCompatibilityLevel
    self.versionDescriptor = versionDescriptor
    self.capabilities = capabilities.sorted {
      Self.capabilityOrder[$0.capabilityIdentifier, default: Int.max]
        < Self.capabilityOrder[$1.capabilityIdentifier, default: Int.max]
    }
  }

  public static func blocked(reasonCode: String) -> Self {
    let descriptor = HermesAgentVersionDescriptor.unavailable()
    return Self(
      overallCompatibilityLevel: .blocked,
      versionDescriptor: descriptor,
      capabilities: matrixRows(
        descriptor: descriptor,
        discoveryLevel: .blocked,
        discoveryExercised: true,
        discoveryReason: reasonCode
      )
    )
  }

  public static func discovered(
    _ result: HermesDiscoveryResult,
    sourceCategory: String = "PATH"
  ) -> Self {
    let descriptor = HermesAgentVersionDescriptor(result: result, sourceCategory: sourceCategory)
    let versionLevel = compatibilityLevel(forSemanticVersion: result.versionInfo.semanticVersion)
    let overall: HermesAgentCompatibilityLevel = versionLevel == .compatible ? .partiallyCompatible : versionLevel
    return Self(
      overallCompatibilityLevel: overall,
      versionDescriptor: descriptor,
      capabilities: matrixRows(
        descriptor: descriptor,
        discoveryLevel: .compatible,
        discoveryExercised: true,
        discoveryReason: "discovery.succeeded",
        versionLevel: versionLevel
      )
    )
  }

  public static func compatibilityLevel(forSemanticVersion version: String?) -> HermesAgentCompatibilityLevel {
    guard let version,
      let majorText = version.split(separator: ".").first,
      let major = Int(majorText)
    else {
      return .unverified
    }
    return major == 0 ? .compatible : .incompatible
  }

  private static func matrixRows(
    descriptor: HermesAgentVersionDescriptor,
    discoveryLevel: HermesAgentCompatibilityLevel,
    discoveryExercised: Bool,
    discoveryReason: String,
    versionLevel: HermesAgentCompatibilityLevel = .blocked
  ) -> [HermesAgentCapabilityResult] {
    let observed = descriptor.semanticVersion
    let versionExercised = observed != nil
    return [
      row(.executableDiscovery, discoveryLevel, discoveryExercised, discoveryReason, observed),
      row(.versionQuery, versionExercised ? versionLevel : .blocked, versionExercised, versionExercised ? "version.query.succeeded" : "version.query.blocked", observed),
      row(.helpQuery, .unverified, false, "help.query.not_exercised", observed),
      row(.isolatedProfileRoot, .unverified, false, "isolated.root.not_exercised", observed),
      row(.isolatedConfigurationInspection, .unverified, false, "config.inspect.not_exercised", observed),
      row(.boundedAgentStartup, .blocked, false, "agent.start.contract.unverified", observed, blocking: true),
      row(.agentReadinessDetection, .blocked, false, "agent.readiness.blocked", observed, blocking: true),
      row(.serviceOwnedAgentDiscovery, discoveryLevel, discoveryExercised, discoveryReason, observed),
      row(.lifecycleStatusQuery, .unverified, false, "lifecycle.status.not_exercised", observed),
      row(.requestSubmissionHandshake, .unverified, false, "request.submit.not_exercised", observed),
      row(.requestCancellationHandshake, .unverified, false, "request.cancel.not_exercised", observed),
      row(.approvalCapabilityDiscovery, .unverified, false, "approval.discovery.not_exercised", observed),
      row(.gracefulAgentShutdown, .blocked, false, "agent.shutdown.no_owned_process", observed),
      row(.forcedExactPIDCleanupFallback, .unverified, false, "cleanup.fallback.not_needed", observed),
      row(.realHomeIsolation, .compatible, true, "real_home.snapshot.required", observed),
      row(.generatedArtifactCleanup, .compatible, true, "artifacts.ignored.required", observed),
    ]
  }

  private static func row(
    _ id: HermesAgentCapabilityID,
    _ level: HermesAgentCompatibilityLevel,
    _ exercised: Bool,
    _ reason: String,
    _ observedVersion: String?,
    blocking: Bool = false
  ) -> HermesAgentCapabilityResult {
    HermesAgentCapabilityResult(
      capabilityIdentifier: id,
      compatibilityLevel: level,
      exercised: exercised,
      evidenceCategory: exercised ? "acceptance" : "contract",
      reasonCode: reason,
      minimumDetectedVersion: nil,
      observedVersion: observedVersion,
      blocking: blocking,
      privacySafeNotes: ""
    )
  }

  private static let capabilityOrder: [HermesAgentCapabilityID: Int] = {
    Dictionary(uniqueKeysWithValues: HermesAgentCapabilityID.allCases.enumerated().map { ($1, $0) })
  }()
}
