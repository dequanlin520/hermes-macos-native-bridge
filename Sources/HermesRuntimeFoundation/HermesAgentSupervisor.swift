import Darwin
import Foundation

public enum HermesAgentSupervisorCompatibilityLevel: String, Codable, Equatable, Sendable {
  case supported = "SUPPORTED"
  case partiallySupported = "PARTIALLY_SUPPORTED"
  case unsupported = "UNSUPPORTED"
  case blocked = "BLOCKED"
  case fail = "FAIL"
}

public enum HermesAgentSupervisorError: Error, Equatable, Sendable {
  case blocked(String)
  case unsupported(String)
  case fail(String)
}

public enum HermesAgentSupervisorState: String, Codable, Equatable, Sendable {
  case idle
  case starting
  case ready
  case shuttingDown = "shutting-down"
  case stopped
  case blocked
  case unsupported
  case failed
}

public enum HermesAgentProcessTopologyStatus: String, Codable, Equatable, Sendable {
  case foregroundSingleProcess = "foreground-single-process"
  case foregroundWithHelpers = "foreground-with-helpers"
  case launcherExitedChildRemains = "launcher-exited-child-remains"
  case daemonized
  case processExited = "process-exited"
  case ambiguousTopology = "ambiguous-topology"
}

public enum HermesAgentEndpointCategory: String, Codable, Equatable, Sendable {
  case loopbackTCP = "loopback-tcp"
  case unixSocket = "unix-socket"
  case documentedStatus = "documented-status"
  case serviceDiscovery = "service-discovery"
  case none
}

public struct HermesAgentSupervisorConfiguration: Codable, Equatable, Sendable {
  public let executableURL: URL
  public let observedVersion: String?
  public let isolatedArguments: [String]
  public let statusArguments: [String]?
  public let environment: HermesAgentLaunchEnvironment
  public let timeoutPolicy: HermesAgentTimeoutPolicy
  public let runIdentifier: String

  public init(
    executableURL: URL,
    observedVersion: String?,
    isolatedArguments: [String],
    statusArguments: [String]?,
    environment: HermesAgentLaunchEnvironment,
    timeoutPolicy: HermesAgentTimeoutPolicy = HermesAgentTimeoutPolicy(),
    runIdentifier: String
  ) {
    self.executableURL = executableURL
    self.observedVersion = observedVersion
    self.isolatedArguments = isolatedArguments
    self.statusArguments = statusArguments
    self.environment = environment
    self.timeoutPolicy = timeoutPolicy
    self.runIdentifier = Self.safeToken(runIdentifier)
  }

  public static func from018CommandSurface(
    executableURL: URL,
    discoveryResult: HermesDiscoveryResult,
    commandSurface: HermesAgentCommandSurface,
    environment: HermesAgentLaunchEnvironment,
    runIdentifier: String
  ) -> Result<Self, HermesAgentSupervisorError> {
    let version = discoveryResult.versionInfo.semanticVersion
    let supportedRange = HermesSemanticVersionRange(lowerInclusive: "0.18.0", upperExclusive: "0.19.0")
    guard supportedRange.contains(version) else {
      return .failure(.unsupported("version.out_of_range"))
    }
    guard commandSurface.isolatedStartupAdvertised,
      commandSurface.help(for: "serve").contains("--isolated")
    else {
      return .failure(.unsupported("startup.command.not_advertised"))
    }
    guard commandSurface.statusMechanismAdvertised else {
      return .failure(.unsupported("status.command.not_advertised"))
    }
    return .success(
      Self(
        executableURL: executableURL,
        observedVersion: version,
        isolatedArguments: ["serve", "--isolated"],
        statusArguments: HermesAgentLaunchContractSelector.advertisedStatus(commandSurface),
        environment: environment,
        runIdentifier: runIdentifier
      ))
  }

  private static func safeToken(_ value: String) -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_")
    }
    return filtered.isEmpty ? "m14-006" : String(filtered.prefix(96))
  }
}

public struct HermesAgentSupervisedProcess: Codable, Equatable, Sendable {
  public let identity: HermesAgentProcessIdentity
  public let state: String

  public init(identity: HermesAgentProcessIdentity, state: String) {
    self.identity = identity
    self.state = state
  }
}

public struct HermesAgentProcessTree: Codable, Equatable, Sendable {
  public let root: HermesAgentSupervisedProcess?
  public let descendants: [HermesAgentSupervisedProcess]
  public let topologyStatus: HermesAgentProcessTopologyStatus

  public init(
    root: HermesAgentSupervisedProcess?,
    descendants: [HermesAgentSupervisedProcess],
    topologyStatus: HermesAgentProcessTopologyStatus
  ) {
    self.root = root
    self.descendants = descendants.sorted { $0.identity.pid < $1.identity.pid }
    self.topologyStatus = topologyStatus
  }

  public var acceptanceOwnedIdentities: [HermesAgentProcessIdentity] {
    ([root?.identity].compactMap { $0 } + descendants.map(\.identity))
      .sorted { $0.pid < $1.pid }
  }
}

public struct HermesAgentEndpointIdentity: Codable, Equatable, Sendable {
  public let category: HermesAgentEndpointCategory
  public let isLoopback: Bool
  public let isUnixSocket: Bool
  public let owningPID: pid_t?
  public let owningPIDRelationship: String
  public let readinessTimestamp: String?
  public let protocolStatusOutcome: String

  public init(
    category: HermesAgentEndpointCategory,
    isLoopback: Bool,
    isUnixSocket: Bool,
    owningPID: pid_t?,
    owningPIDRelationship: String,
    readinessTimestamp: String?,
    protocolStatusOutcome: String
  ) {
    self.category = category
    self.isLoopback = isLoopback
    self.isUnixSocket = isUnixSocket
    self.owningPID = owningPID
    self.owningPIDRelationship = owningPIDRelationship
    self.readinessTimestamp = readinessTimestamp
    self.protocolStatusOutcome = protocolStatusOutcome
  }

  public var ownershipProven: Bool {
    owningPIDRelationship == "acceptance-owned-root"
      || owningPIDRelationship == "acceptance-owned-descendant"
      || owningPIDRelationship == "service-owned-status"
  }
}

public struct HermesAgentSupervisorResult: Codable, Equatable, Sendable {
  public let compatibilityLevel: HermesAgentSupervisorCompatibilityLevel
  public let reasonCode: String
  public let processTree: HermesAgentProcessTree
  public let endpointIdentity: HermesAgentEndpointIdentity
  public let serviceDiscoveryObserved: Bool
  public let statusQueryResult: String
  public let exactRootTermUsed: Bool
  public let exactDescendantTermUsed: Bool
  public let exactKillUsed: Bool
  public let broadStopInvoked: Bool
  public let broadProcessKillUsed: Bool
  public let acceptanceProcessRemaining: Bool
  public let orphanProcessFound: Bool
  public let realHomeModified: Bool
  public let supervisedProcessRealHomeAccessObserved: Bool
  public let rawExternalMutationObserved: Bool

  public init(
    compatibilityLevel: HermesAgentSupervisorCompatibilityLevel,
    reasonCode: String,
    processTree: HermesAgentProcessTree,
    endpointIdentity: HermesAgentEndpointIdentity,
    serviceDiscoveryObserved: Bool,
    statusQueryResult: String,
    exactRootTermUsed: Bool,
    exactDescendantTermUsed: Bool,
    exactKillUsed: Bool,
    broadStopInvoked: Bool,
    broadProcessKillUsed: Bool,
    acceptanceProcessRemaining: Bool,
    orphanProcessFound: Bool,
    realHomeModified: Bool,
    supervisedProcessRealHomeAccessObserved: Bool,
    rawExternalMutationObserved: Bool
  ) {
    self.compatibilityLevel = compatibilityLevel
    self.reasonCode = reasonCode
    self.processTree = processTree
    self.endpointIdentity = endpointIdentity
    self.serviceDiscoveryObserved = serviceDiscoveryObserved
    self.statusQueryResult = statusQueryResult
    self.exactRootTermUsed = exactRootTermUsed
    self.exactDescendantTermUsed = exactDescendantTermUsed
    self.exactKillUsed = exactKillUsed
    self.broadStopInvoked = broadStopInvoked
    self.broadProcessKillUsed = broadProcessKillUsed
    self.acceptanceProcessRemaining = acceptanceProcessRemaining
    self.orphanProcessFound = orphanProcessFound
    self.realHomeModified = realHomeModified
    self.supervisedProcessRealHomeAccessObserved = supervisedProcessRealHomeAccessObserved
    self.rawExternalMutationObserved = rawExternalMutationObserved
  }
}

public protocol HermesAgentSupervisorProcessControlling: Sendable {
  func launchIsolatedAgent(configuration: HermesAgentSupervisorConfiguration) throws
    -> HermesAgentProcessIdentity
  func captureProcessTree(root: HermesAgentProcessIdentity) -> HermesAgentProcessTree
  func waitForReadiness(
    root: HermesAgentProcessIdentity,
    processTree: HermesAgentProcessTree,
    configuration: HermesAgentSupervisorConfiguration
  ) -> HermesAgentEndpointIdentity
  func serviceDiscoveryMatches(
    endpoint: HermesAgentEndpointIdentity,
    configuration: HermesAgentSupervisorConfiguration
  ) -> Bool
  func runStatus(configuration: HermesAgentSupervisorConfiguration) -> String
  func validate(identity: HermesAgentProcessIdentity) -> Bool
  func signalExactPID(_ identity: HermesAgentProcessIdentity, signal: Int32) throws
  func waitForExit(identity: HermesAgentProcessIdentity, timeout: TimeInterval) -> Bool
  func realHomeAccessObserved(for identities: [HermesAgentProcessIdentity]) -> Bool
  func rawExternalRealHomeMutationObserved() -> Bool
}

public final class HermesAgentSupervisor: @unchecked Sendable {
  private let controller: HermesAgentSupervisorProcessControlling
  private let lock = NSLock()
  private var currentState: HermesAgentSupervisorState = .idle

  public init(controller: HermesAgentSupervisorProcessControlling = UnsupportedHermesAgentSupervisorProcessController()) {
    self.controller = controller
  }

  public var state: HermesAgentSupervisorState {
    lock.withLock { currentState }
  }

  public func supervise(configuration: HermesAgentSupervisorConfiguration) throws -> HermesAgentSupervisorResult {
    guard let version = configuration.observedVersion else {
      lock.withLock { currentState = .blocked }
      throw HermesAgentSupervisorError.blocked("version.unknown")
    }
    guard HermesSemanticVersionRange(lowerInclusive: "0.18.0", upperExclusive: "0.19.0").contains(version)
    else {
      lock.withLock { currentState = .unsupported }
      throw HermesAgentSupervisorError.unsupported("version.out_of_range")
    }
    guard configuration.isolatedArguments == ["serve", "--isolated"] else {
      lock.withLock { currentState = .unsupported }
      throw HermesAgentSupervisorError.unsupported("startup.command.not_exact_isolated")
    }

    lock.withLock { currentState = .starting }
    let root = try controller.launchIsolatedAgent(configuration: configuration)
    let initialTree = controller.captureProcessTree(root: root)
    guard initialTree.topologyStatus != .ambiguousTopology else {
      lock.withLock { currentState = .failed }
      throw HermesAgentSupervisorError.fail("identity.ambiguous_after_launch")
    }
    guard initialTree.topologyStatus != .daemonized else {
      _ = try shutdown(root: root, initialTree: initialTree, configuration: configuration)
      lock.withLock { currentState = .unsupported }
      throw HermesAgentSupervisorError.unsupported("topology.daemonized")
    }
    guard initialTree.topologyStatus != .processExited else {
      lock.withLock { currentState = .unsupported }
      throw HermesAgentSupervisorError.unsupported("topology.process_exited")
    }

    let endpoint = controller.waitForReadiness(
      root: root,
      processTree: initialTree,
      configuration: configuration
    )
    guard endpoint.ownershipProven else {
      _ = try shutdown(root: root, initialTree: initialTree, configuration: configuration)
      lock.withLock { currentState = .unsupported }
      throw HermesAgentSupervisorError.unsupported("endpoint.ownership_not_proven")
    }
    let serviceDiscoveryObserved = controller.serviceDiscoveryMatches(
      endpoint: endpoint,
      configuration: configuration
    )
    let status = controller.runStatus(configuration: configuration)
    let shutdownEvidence = try shutdown(root: root, initialTree: initialTree, configuration: configuration)
    let finalTree = controller.captureProcessTree(root: root)
    let remaining = !finalTree.acceptanceOwnedIdentities.isEmpty
    let realHomeAccess = controller.realHomeAccessObserved(for: initialTree.acceptanceOwnedIdentities)
    let externalMutation = controller.rawExternalRealHomeMutationObserved()
    let compatibility: HermesAgentSupervisorCompatibilityLevel =
      remaining || realHomeAccess
      ? .fail
      : (status == "unavailable" ? .partiallySupported : .supported)
    lock.withLock { currentState = remaining || realHomeAccess ? .failed : .stopped }
    return HermesAgentSupervisorResult(
      compatibilityLevel: compatibility,
      reasonCode: compatibility == .supported ? "supervisor.supported" : "supervisor.partial_or_failed",
      processTree: initialTree,
      endpointIdentity: endpoint,
      serviceDiscoveryObserved: serviceDiscoveryObserved,
      statusQueryResult: status,
      exactRootTermUsed: shutdownEvidence.rootTerm,
      exactDescendantTermUsed: shutdownEvidence.descendantTerm,
      exactKillUsed: shutdownEvidence.kill,
      broadStopInvoked: false,
      broadProcessKillUsed: false,
      acceptanceProcessRemaining: remaining,
      orphanProcessFound: remaining,
      realHomeModified: realHomeAccess,
      supervisedProcessRealHomeAccessObserved: realHomeAccess,
      rawExternalMutationObserved: externalMutation
    )
  }

  private func shutdown(
    root: HermesAgentProcessIdentity,
    initialTree: HermesAgentProcessTree,
    configuration: HermesAgentSupervisorConfiguration
  ) throws -> (rootTerm: Bool, descendantTerm: Bool, kill: Bool) {
    lock.withLock { currentState = .shuttingDown }
    var rootTerm = false
    var descendantTerm = false
    var exactKill = false

    if controller.validate(identity: root) {
      try controller.signalExactPID(root, signal: SIGTERM)
      rootTerm = true
      _ = controller.waitForExit(identity: root, timeout: configuration.timeoutPolicy.gracefulShutdownSeconds)
    }

    let afterRoot = controller.captureProcessTree(root: root)
    for identity in afterRoot.descendants.map(\.identity) where controller.validate(identity: identity) {
      try controller.signalExactPID(identity, signal: SIGTERM)
      descendantTerm = true
      _ = controller.waitForExit(identity: identity, timeout: configuration.timeoutPolicy.gracefulShutdownSeconds)
    }

    let afterTerm = controller.captureProcessTree(root: root)
    for identity in afterTerm.acceptanceOwnedIdentities where controller.validate(identity: identity) {
      try controller.signalExactPID(identity, signal: SIGKILL)
      exactKill = true
      _ = controller.waitForExit(identity: identity, timeout: configuration.timeoutPolicy.forcedShutdownSeconds)
    }
    _ = initialTree
    return (rootTerm, descendantTerm, exactKill)
  }
}

public enum HermesAgentProcessTopology {
  public static func classify(
    root: HermesAgentProcessIdentity?,
    descendants: [HermesAgentProcessIdentity],
    launcherExited: Bool,
    unprovenChildRemains: Bool
  ) -> HermesAgentProcessTopologyStatus {
    if unprovenChildRemains {
      return .ambiguousTopology
    }
    if root == nil && descendants.isEmpty {
      return .processExited
    }
    if root == nil && !descendants.isEmpty {
      return launcherExited ? .launcherExitedChildRemains : .daemonized
    }
    if descendants.isEmpty {
      return .foregroundSingleProcess
    }
    return .foregroundWithHelpers
  }

  public static func isProvenDescendant(
    _ child: HermesAgentProcessIdentity,
    parent: HermesAgentProcessIdentity
  ) -> Bool {
    child.ppid == parent.pid
      && child.uid == parent.uid
      && child.launchRunIdentifier == parent.launchRunIdentifier
      && startTime(child.processStartTime) >= startTime(parent.processStartTime)
  }

  private static func startTime(_ value: String) -> Double {
    Double(value) ?? 0
  }
}

public final class UnsupportedHermesAgentSupervisorProcessController:
  HermesAgentSupervisorProcessControlling, @unchecked Sendable
{
  public init() {}

  public func launchIsolatedAgent(configuration _: HermesAgentSupervisorConfiguration) throws
    -> HermesAgentProcessIdentity
  {
    throw HermesAgentSupervisorError.blocked("platform.controller.unavailable")
  }

  public func captureProcessTree(root _: HermesAgentProcessIdentity) -> HermesAgentProcessTree {
    HermesAgentProcessTree(root: nil, descendants: [], topologyStatus: .processExited)
  }

  public func waitForReadiness(
    root _: HermesAgentProcessIdentity,
    processTree _: HermesAgentProcessTree,
    configuration _: HermesAgentSupervisorConfiguration
  ) -> HermesAgentEndpointIdentity {
    HermesAgentEndpointIdentity(
      category: .none,
      isLoopback: false,
      isUnixSocket: false,
      owningPID: nil,
      owningPIDRelationship: "none",
      readinessTimestamp: nil,
      protocolStatusOutcome: "unavailable"
    )
  }

  public func serviceDiscoveryMatches(
    endpoint _: HermesAgentEndpointIdentity,
    configuration _: HermesAgentSupervisorConfiguration
  ) -> Bool { false }

  public func runStatus(configuration _: HermesAgentSupervisorConfiguration) -> String { "unavailable" }
  public func validate(identity _: HermesAgentProcessIdentity) -> Bool { false }
  public func signalExactPID(_: HermesAgentProcessIdentity, signal _: Int32) throws {}
  public func waitForExit(identity _: HermesAgentProcessIdentity, timeout _: TimeInterval) -> Bool { true }
  public func realHomeAccessObserved(for _: [HermesAgentProcessIdentity]) -> Bool { false }
  public func rawExternalRealHomeMutationObserved() -> Bool { false }
}
