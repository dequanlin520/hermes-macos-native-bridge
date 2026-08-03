import Foundation

public enum HermesProductCapabilityIdentifier: String, Codable, CaseIterable, Equatable, Sendable {
  case nativeAppLaunch = "native-app-launch"
  case menuBarStatus = "menu-bar-status"
  case serviceConnectionState = "service-connection-state"
  case xpcProtocolCompatibility = "xpc-protocol-compatibility"
  case hermesExecutableDiscovery = "hermes-executable-discovery"
  case hermesVersionDiscovery = "hermes-version-discovery"
  case isolatedAgentStart = "isolated-agent-start"
  case agentReadinessStatus = "agent-readiness-status"
  case dynamicEndpointOwnership = "dynamic-endpoint-ownership"
  case controlledServiceRestartReconnect = "controlled-service-restart-reconnect"
  case appExitRuntimePolicy = "app-exit-runtime-policy"
  case exactAgentShutdown = "exact-agent-shutdown"
  case diagnostics = "diagnostics"
  case permissionStatus = "permission-status"
  case auditSecurityStatus = "audit-security-status"
  case emergencyStop = "emergency-stop"
  case installationUninstallation = "installation-uninstallation"
  case shortcutsSupportedOperations = "shortcuts-supported-operations"
  case requestSubmission = "request-submission"
  case requestStatus = "request-status"
  case requestCancellation = "request-cancellation"
  case approvalResponse = "approval-response"
  case arbitraryPrompts = "arbitrary-prompts"
  case toolExecution = "tool-execution"
  case arbitraryShell = "arbitrary-shell"
  case privateWebSocketRoute = "private-api-ws"
}

public enum HermesProductCapabilityStatus: String, Codable, Equatable, Sendable {
  case supported
  case unsupported
  case blocked
  case unavailable
}

public enum HermesProductRuntimeStatus: String, Codable, Equatable, Sendable {
  case stopped
  case starting
  case ready
  case stopping
  case error
  case unknown
}

public struct HermesProductCapability: Codable, Equatable, Sendable {
  public let identifier: HermesProductCapabilityIdentifier
  public let status: HermesProductCapabilityStatus
  public let exercised: Bool
  public let reasonCode: String
  public let observedHermesVersion: String?
  public let ownershipSource: String
  public let lastVerifiedTimestampCategory: String
  public let privacySafeExplanation: String

  public init(
    identifier: HermesProductCapabilityIdentifier,
    status: HermesProductCapabilityStatus,
    exercised: Bool,
    reasonCode: String,
    observedHermesVersion: String?,
    ownershipSource: String,
    lastVerifiedTimestampCategory: String,
    privacySafeExplanation: String
  ) {
    self.identifier = identifier
    self.status = status
    self.exercised = exercised
    self.reasonCode = Self.safeToken(reasonCode)
    self.observedHermesVersion = observedHermesVersion.map(Self.safeSemanticVersion)
    self.ownershipSource = Self.safeToken(ownershipSource)
    self.lastVerifiedTimestampCategory = Self.safeToken(lastVerifiedTimestampCategory)
    self.privacySafeExplanation = Self.safeExplanation(privacySafeExplanation)
  }

  private static func safeSemanticVersion(_ value: String) -> String {
    String(value.prefix(32).prefix { $0.isASCII && ($0.isNumber || $0 == ".") })
  }

  private static func safeToken(_ value: String) -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_")
    }
    return filtered.isEmpty ? "unknown" : String(filtered.prefix(96))
  }

  private static func safeExplanation(_ value: String) -> String {
    let filtered = value.unicodeScalars.filter { scalar in
      scalar.value >= 0x20 && scalar.value != 0x7F
        && scalar != "/" && scalar != ":" && scalar != "{" && scalar != "}"
    }
    return String(String.UnicodeScalarView(filtered)).prefixString(180)
  }
}

public struct HermesProductCapabilitySnapshot: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let xpcProtocolVersion: String
  public let runtimeStatus: HermesProductRuntimeStatus
  public let compatibilityLevel: HermesAgentCompatibilityLevel
  public let observedHermesVersion: String?
  public let capabilities: [HermesProductCapability]

  public init(
    schemaVersion: Int = 1,
    xpcProtocolVersion: String,
    runtimeStatus: HermesProductRuntimeStatus,
    compatibilityLevel: HermesAgentCompatibilityLevel,
    observedHermesVersion: String?,
    capabilities: [HermesProductCapability]
  ) {
    self.schemaVersion = schemaVersion
    self.xpcProtocolVersion = xpcProtocolVersion
    self.runtimeStatus = runtimeStatus
    self.compatibilityLevel = compatibilityLevel
    self.observedHermesVersion = observedHermesVersion.map(Self.safeSemanticVersion)
    self.capabilities = capabilities.sorted {
      Self.order[$0.identifier, default: Int.max] < Self.order[$1.identifier, default: Int.max]
    }
  }

  public func capability(_ identifier: HermesProductCapabilityIdentifier)
    -> HermesProductCapability?
  {
    capabilities.first { $0.identifier == identifier }
  }

  public static func rc1(
    xpcProtocolVersion: String,
    bridgeServiceConnected: Bool,
    executableAvailable: Bool,
    observedHermesVersion: String?,
    compatibilityLevel: HermesAgentCompatibilityLevel,
    runtimeStatus: HermesProductRuntimeStatus = .unknown,
    statusReady: Bool = false,
    endpointOwnershipProven: Bool = false,
    lifecycleExercised: Bool = false,
    controlledReconnectExercised: Bool = false,
    exactShutdownExercised: Bool = false
  ) -> Self {
    let version = observedHermesVersion.map(Self.safeSemanticVersion)
    let compatibleStatus: HermesProductCapabilityStatus =
      bridgeServiceConnected ? .supported : .unavailable
    let executableStatus: HermesProductCapabilityStatus =
      executableAvailable ? .supported : .unavailable
    let runtimeSupported =
      bridgeServiceConnected && executableAvailable
        && [.compatible, .partiallyCompatible].contains(compatibilityLevel)
    let runtimeCapabilityStatus: HermesProductCapabilityStatus =
      runtimeSupported ? .supported : (executableAvailable ? .blocked : .unavailable)
    let unsupportedReason = "transport.route-unsupported"

    return Self(
      xpcProtocolVersion: xpcProtocolVersion,
      runtimeStatus: runtimeStatus,
      compatibilityLevel: compatibilityLevel,
      observedHermesVersion: version,
      capabilities: [
        row(.nativeAppLaunch, .supported, true, "app.launch.supported", version, "native-app", "Native app launch is in RC scope."),
        row(.menuBarStatus, .supported, true, "menu.status.supported", version, "native-app", "Menu-bar status is in RC scope."),
        row(.serviceConnectionState, compatibleStatus, bridgeServiceConnected, bridgeServiceConnected ? "service.connected" : "service.unavailable", version, "xpc-service", "Service connection state is reported through XPC."),
        row(.xpcProtocolCompatibility, compatibleStatus, bridgeServiceConnected, "xpc.protocol.1_8", version, "xpc-service", "XPC protocol 1.8 is the RC compatibility boundary."),
        row(.hermesExecutableDiscovery, executableStatus, executableAvailable, executableAvailable ? "hermes.executable.available" : "hermes.executable.unavailable", version, "bridge-service", "Hermes executable discovery is owned by the service."),
        row(.hermesVersionDiscovery, version == nil ? .unavailable : .supported, version != nil, version == nil ? "hermes.version.unavailable" : "hermes.version.observed", version, "bridge-service", "Hermes version is observed by service-owned discovery."),
        row(.isolatedAgentStart, runtimeCapabilityStatus, lifecycleExercised, runtimeSupported ? "agent.start.service-owned" : "agent.start.blocked", version, "bridge-service", "Isolated Agent start is owned by HermesBridgeService."),
        row(.agentReadinessStatus, runtimeCapabilityStatus, statusReady, statusReady ? "agent.status.ready" : "agent.status.not-ready", version, "bridge-service", "Agent readiness is derived from service-owned status evidence."),
        row(.dynamicEndpointOwnership, runtimeCapabilityStatus, endpointOwnershipProven, endpointOwnershipProven ? "endpoint.ownership.proven" : "endpoint.ownership.not-exercised", version, "bridge-service", "Endpoint ownership evidence is service-owned and redacted."),
        row(.controlledServiceRestartReconnect, compatibleStatus, controlledReconnectExercised, controlledReconnectExercised ? "service.reconnect.exercised" : "service.reconnect.not-exercised", version, "xpc-service", "Controlled restart and reconnect are part of RC acceptance."),
        row(.appExitRuntimePolicy, .supported, lifecycleExercised, "app.exit.runtime-policy", version, "native-app", "App exit must follow the service-owned runtime policy."),
        row(.exactAgentShutdown, runtimeCapabilityStatus, exactShutdownExercised, exactShutdownExercised ? "agent.shutdown.exact-identity" : "agent.shutdown.not-exercised", version, "bridge-service", "Agent shutdown is exact-identity and service-owned."),
        row(.diagnostics, .supported, true, "diagnostics.supported", version, "bridge-service", "Diagnostics are in RC scope."),
        row(.permissionStatus, .supported, true, "permissions.status.supported", version, "native-app", "Permission status is in RC scope."),
        row(.auditSecurityStatus, .supported, true, "audit.security.supported", version, "bridge-service", "Audit and security status are in RC scope."),
        row(.emergencyStop, .supported, true, "emergency-stop.supported", version, "bridge-service", "Emergency stop is in RC scope."),
        row(.installationUninstallation, .supported, true, "install.uninstall.supported", version, "launchagent", "Installation and uninstallation are in RC scope."),
        row(.shortcutsSupportedOperations, .supported, true, "shortcuts.service-owned-supported-only", version, "app-intents", "Shortcuts expose only service-owned supported operations."),
        row(.requestSubmission, .unsupported, false, unsupportedReason, version, "bridge-service", "Hermes 0.18.2 has no public request transport advertised."),
        row(.requestStatus, .unsupported, false, unsupportedReason, version, "bridge-service", "Hermes 0.18.2 has no public request status transport advertised."),
        row(.requestCancellation, .unsupported, false, unsupportedReason, version, "bridge-service", "Hermes 0.18.2 has no public cancellation transport advertised."),
        row(.approvalResponse, .unsupported, false, unsupportedReason, version, "bridge-service", "Hermes 0.18.2 has no public approval response transport advertised."),
        row(.arbitraryPrompts, .unsupported, false, "rc.scope-unsupported", version, "product-scope", "Arbitrary prompts are outside RC scope."),
        row(.toolExecution, .unsupported, false, "rc.scope-unsupported", version, "product-scope", "Tool execution is outside RC scope."),
        row(.arbitraryShell, .unsupported, false, "security.boundary-unsupported", version, "product-scope", "Arbitrary shell execution is outside RC scope."),
        row(.privateWebSocketRoute, .unsupported, false, "private-route.not-assumed", version, "product-scope", "Private API websocket routes are not assumed."),
      ])
  }

  private static func row(
    _ identifier: HermesProductCapabilityIdentifier,
    _ status: HermesProductCapabilityStatus,
    _ exercised: Bool,
    _ reasonCode: String,
    _ observedHermesVersion: String?,
    _ ownershipSource: String,
    _ explanation: String
  ) -> HermesProductCapability {
    HermesProductCapability(
      identifier: identifier,
      status: status,
      exercised: exercised,
      reasonCode: reasonCode,
      observedHermesVersion: observedHermesVersion,
      ownershipSource: ownershipSource,
      lastVerifiedTimestampCategory: exercised ? "acceptance" : "contract",
      privacySafeExplanation: explanation
    )
  }

  private static func safeSemanticVersion(_ value: String) -> String {
    String(value.prefix(32).prefix { $0.isASCII && ($0.isNumber || $0 == ".") })
  }

  private static let order: [HermesProductCapabilityIdentifier: Int] =
    Dictionary(uniqueKeysWithValues: HermesProductCapabilityIdentifier.allCases.enumerated().map {
      ($0.element, $0.offset)
    })
}

extension String {
  fileprivate func prefixString(_ count: Int) -> String {
    String(prefix(count))
  }
}
