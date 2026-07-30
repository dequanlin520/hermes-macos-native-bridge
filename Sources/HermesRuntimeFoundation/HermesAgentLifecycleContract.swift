import Darwin
import Foundation

public enum HermesAgentLaunchContractStatus: String, Codable, CaseIterable, Equatable, Sendable {
  case supported
  case partiallySupported = "partially-supported"
  case unsupported
  case blocked
  case incompatible
}

public enum HermesAgentLaunchCapability: String, Codable, CaseIterable, Equatable, Sendable {
  case noninteractiveStartup = "noninteractive-startup"
  case isolatedWritableRoots = "isolated-writable-roots"
  case boundedReadiness = "bounded-readiness"
  case stableProcessIdentity = "stable-process-identity"
  case documentedStatus = "documented-status"
  case gracefulShutdown = "graceful-shutdown"
  case exactPIDFallback = "exact-pid-fallback"
}

public enum HermesAgentInvocationMode: String, Codable, Equatable, Sendable {
  case directExecutable = "direct-executable"
  case unsupported
}

public enum HermesAgentReadinessMechanism: String, Codable, Equatable, Sendable {
  case documentedStatusCommand = "documented-status-command"
  case productionDiscovery = "production-discovery"
  case unsupported
}

public enum HermesAgentShutdownMechanism: String, Codable, Equatable, Sendable {
  case documentedStopCommand = "documented-stop-command"
  case exactPIDTermFallback = "exact-pid-term-fallback"
  case unsupported
}

public enum HermesAgentLifecycleError: Error, Equatable, Sendable {
  case unsupportedContract(String)
  case incompatibleVersion(String)
  case invalidEnvironment(String)
  case forbiddenCommand(String)
  case launchFailed(String)
  case readinessTimeout
  case processExitedBeforeReady
  case malformedReadinessEvidence
  case unsupportedReadinessContract
  case identityMismatch
  case shutdownUnsupported
  case shutdownTimeout
}

public struct HermesSemanticVersion: Codable, Comparable, Equatable, Sendable {
  public let major: Int
  public let minor: Int
  public let patch: Int

  public init(_ value: String) throws {
    let pieces = value.split(separator: ".")
    guard pieces.count >= 2, pieces.count <= 3,
      let major = Int(pieces[0]),
      let minor = Int(pieces[1])
    else {
      throw HermesAgentLifecycleError.incompatibleVersion("malformed-semantic-version")
    }
    let patch = pieces.count == 3 ? Int(pieces[2]) : 0
    guard let patch else {
      throw HermesAgentLifecycleError.incompatibleVersion("malformed-semantic-version")
    }
    self.major = major
    self.minor = minor
    self.patch = patch
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
  }
}

public struct HermesSemanticVersionRange: Codable, Equatable, Sendable {
  public let lowerInclusive: String
  public let upperExclusive: String

  public init(lowerInclusive: String, upperExclusive: String) {
    self.lowerInclusive = lowerInclusive
    self.upperExclusive = upperExclusive
  }

  public func contains(_ version: String) -> Bool {
    guard let value = try? HermesSemanticVersion(version),
      let lower = try? HermesSemanticVersion(lowerInclusive),
      let upper = try? HermesSemanticVersion(upperExclusive)
    else {
      return false
    }
    return value >= lower && value < upper
  }
}

public struct HermesAgentLaunchDescriptor: Codable, Equatable, Sendable {
  public let invocationMode: HermesAgentInvocationMode
  public let requiredArguments: [String]
  public let statusArguments: [String]?
  public let shutdownArguments: [String]?

  public init(
    invocationMode: HermesAgentInvocationMode,
    requiredArguments: [String],
    statusArguments: [String]?,
    shutdownArguments: [String]?
  ) {
    self.invocationMode = invocationMode
    self.requiredArguments = requiredArguments
    self.statusArguments = statusArguments
    self.shutdownArguments = shutdownArguments
  }
}

public struct HermesAgentTimeoutPolicy: Codable, Equatable, Sendable {
  public let readinessSeconds: TimeInterval
  public let gracefulShutdownSeconds: TimeInterval
  public let forcedShutdownSeconds: TimeInterval

  public init(
    readinessSeconds: TimeInterval = 10,
    gracefulShutdownSeconds: TimeInterval = 5,
    forcedShutdownSeconds: TimeInterval = 2
  ) {
    self.readinessSeconds = max(0.001, readinessSeconds)
    self.gracefulShutdownSeconds = max(0.001, gracefulShutdownSeconds)
    self.forcedShutdownSeconds = max(0.001, forcedShutdownSeconds)
  }
}

public struct HermesAgentLaunchContract: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let executableFamily: String
  public let supportedVersionRange: HermesSemanticVersionRange
  public let observedVersion: String?
  public let status: HermesAgentLaunchContractStatus
  public let reasonCode: String
  public let descriptor: HermesAgentLaunchDescriptor
  public let requiredCapabilities: [HermesAgentLaunchCapability]
  public let advertisedCapabilities: [HermesAgentLaunchCapability]
  public let readinessMechanism: HermesAgentReadinessMechanism
  public let shutdownMechanism: HermesAgentShutdownMechanism
  public let timeoutPolicy: HermesAgentTimeoutPolicy
  public let cleanupFallbackPolicy: String

  public init(
    schemaVersion: Int = 1,
    executableFamily: String = "hermes-agent",
    supportedVersionRange: HermesSemanticVersionRange = .init(
      lowerInclusive: "0.18.0", upperExclusive: "0.19.0"),
    observedVersion: String?,
    status: HermesAgentLaunchContractStatus,
    reasonCode: String,
    descriptor: HermesAgentLaunchDescriptor,
    requiredCapabilities: [HermesAgentLaunchCapability] = HermesAgentLaunchCapability.allCases,
    advertisedCapabilities: [HermesAgentLaunchCapability],
    readinessMechanism: HermesAgentReadinessMechanism,
    shutdownMechanism: HermesAgentShutdownMechanism,
    timeoutPolicy: HermesAgentTimeoutPolicy = HermesAgentTimeoutPolicy(),
    cleanupFallbackPolicy: String = "exact-pid-term-then-exact-pid-kill"
  ) {
    self.schemaVersion = schemaVersion
    self.executableFamily = executableFamily
    self.supportedVersionRange = supportedVersionRange
    self.observedVersion = observedVersion
    self.status = status
    self.reasonCode = Self.safeToken(reasonCode)
    self.descriptor = descriptor
    self.requiredCapabilities = requiredCapabilities
    self.advertisedCapabilities = advertisedCapabilities.sorted { $0.rawValue < $1.rawValue }
    self.readinessMechanism = readinessMechanism
    self.shutdownMechanism = shutdownMechanism
    self.timeoutPolicy = timeoutPolicy
    self.cleanupFallbackPolicy = Self.safeToken(cleanupFallbackPolicy)
  }

  public var isStartable: Bool { status == .supported }

  private static func safeToken(_ value: String) -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_")
    }
    return filtered.isEmpty ? "unknown" : String(filtered.prefix(96))
  }
}

public struct HermesAgentCommandSurface: Equatable, Sendable {
  public let versionOutput: String
  public let rootHelpOutput: String
  public let subcommandHelp: [String: String]

  public init(versionOutput: String, rootHelpOutput: String, subcommandHelp: [String: String] = [:]) {
    self.versionOutput = versionOutput
    self.rootHelpOutput = rootHelpOutput
    self.subcommandHelp = subcommandHelp
  }

  public func advertisesSubcommand(_ name: String) -> Bool {
    let pattern = "(^|\\n)\\s*\(NSRegularExpression.escapedPattern(for: name))(\\s|\\n|$)"
    return rootHelpOutput.range(of: pattern, options: .regularExpression) != nil
  }

  public func help(for subcommand: String) -> String {
    subcommandHelp[subcommand] ?? ""
  }
}

public enum HermesAgentLaunchContractSelector {
  public static func select(
    discoveryResult: HermesDiscoveryResult,
    commandSurface: HermesAgentCommandSurface
  ) -> HermesAgentLaunchContract {
    let version = discoveryResult.versionInfo.semanticVersion
    let supportedRange = HermesSemanticVersionRange(
      lowerInclusive: "0.18.0",
      upperExclusive: "0.19.0"
    )
    guard supportedRange.contains(version) else {
      return unsupported(version: version, status: .incompatible, reason: "version.out_of_range")
    }

    let startup = advertisedStartup(commandSurface)
    let status = advertisedStatus(commandSurface)
    let shutdown = advertisedShutdown(commandSurface)
    var capabilities: [HermesAgentLaunchCapability] = [
      .isolatedWritableRoots,
      .stableProcessIdentity,
      .exactPIDFallback,
    ]
    if startup != nil { capabilities.append(.noninteractiveStartup) }
    if status != nil {
      capabilities.append(.documentedStatus)
      capabilities.append(.boundedReadiness)
    }
    if shutdown != nil { capabilities.append(.gracefulShutdown) }

    guard let startup else {
      return unsupported(version: version, reason: "startup.command.not_advertised")
    }
    guard let status else {
      return unsupported(version: version, reason: "status.command.not_advertised")
    }
    guard let shutdown else {
      return unsupported(version: version, reason: "shutdown.command.not_advertised")
    }

    return HermesAgentLaunchContract(
      observedVersion: version,
      status: .supported,
      reasonCode: "launch.contract.supported",
      descriptor: HermesAgentLaunchDescriptor(
        invocationMode: .directExecutable,
        requiredArguments: startup,
        statusArguments: status,
        shutdownArguments: shutdown
      ),
      advertisedCapabilities: capabilities,
      readinessMechanism: .documentedStatusCommand,
      shutdownMechanism: .documentedStopCommand
    )
  }

  public static func unsupported(
    version: String?,
    status: HermesAgentLaunchContractStatus = .unsupported,
    reason: String
  ) -> HermesAgentLaunchContract {
    HermesAgentLaunchContract(
      observedVersion: version,
      status: status,
      reasonCode: reason,
      descriptor: HermesAgentLaunchDescriptor(
        invocationMode: .unsupported,
        requiredArguments: [],
        statusArguments: nil,
        shutdownArguments: nil
      ),
      advertisedCapabilities: [.isolatedWritableRoots, .stableProcessIdentity, .exactPIDFallback],
      readinessMechanism: .unsupported,
      shutdownMechanism: .unsupported
    )
  }

  private static func advertisedStartup(_ surface: HermesAgentCommandSurface) -> [String]? {
    for candidate in ["serve", "agent", "daemon", "start"] {
      guard surface.advertisesSubcommand(candidate) else { continue }
      let help = surface.help(for: candidate)
      if help.contains("--isolated") || help.contains("HERMES_HOME") || help.contains("--home") {
        return [candidate]
      }
    }
    return nil
  }

  private static func advertisedStatus(_ surface: HermesAgentCommandSurface) -> [String]? {
    for candidate in ["status", "health"] where surface.advertisesSubcommand(candidate) {
      return [candidate]
    }
    return nil
  }

  private static func advertisedShutdown(_ surface: HermesAgentCommandSurface) -> [String]? {
    for candidate in ["stop", "shutdown"] where surface.advertisesSubcommand(candidate) {
      return [candidate]
    }
    return nil
  }
}

public struct HermesAgentLaunchEnvironment: Codable, Equatable, Sendable {
  public let runtimeRoot: URL
  public let variables: [String: String]

  public init(runtimeRoot: URL, variables: [String: String]) {
    self.runtimeRoot = runtimeRoot
    self.variables = variables
  }

  public static func construct(runtimeRoot: URL, inherited: [String: String] = [:]) throws -> Self {
    guard !runtimeRoot.pathComponents.contains("..") else {
      throw HermesAgentLifecycleError.invalidEnvironment("path-traversal")
    }
    let root = runtimeRoot.standardizedFileURL
    try validatePath(root, isolatedRoot: root, mustExist: false)
    if let realHome = inherited["HOME"] {
      let realHermes = URL(fileURLWithPath: realHome).appendingPathComponent(".hermes").standardizedFileURL
      if root.path == realHermes.path || root.path.hasPrefix(realHermes.path + "/") {
        throw HermesAgentLifecycleError.invalidEnvironment("runtime-root-inside-real-hermes-home")
      }
    }

    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try validateWorldWritableParents(root)
    try setPrivatePermissions(root)

    let children = [
      "home", "hermes-home", "xdg-config", "xdg-state", "xdg-cache", "tmp",
    ]
    var variables: [String: String] = [:]
    for child in children {
      let url = root.appendingPathComponent(child, isDirectory: true)
      try validatePath(url, isolatedRoot: root, mustExist: false)
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      try setPrivatePermissions(url)
      try validatePath(url, isolatedRoot: root, mustExist: true)
      switch child {
      case "home": variables["HOME"] = url.path
      case "hermes-home": variables["HERMES_HOME"] = url.path
      case "xdg-config": variables["XDG_CONFIG_HOME"] = url.path
      case "xdg-state": variables["XDG_STATE_HOME"] = url.path
      case "xdg-cache": variables["XDG_CACHE_HOME"] = url.path
      case "tmp": variables["TMPDIR"] = url.path
      default: break
      }
    }
    variables["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
    variables["LANG"] = "C"
    guard Set(variables.keys).count == variables.keys.count else {
      throw HermesAgentLifecycleError.invalidEnvironment("duplicate-environment-key")
    }
    for key in ["HOME", "HERMES_HOME", "XDG_CONFIG_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME", "TMPDIR"] {
      guard let value = variables[key], value.hasPrefix(root.path + "/") else {
        throw HermesAgentLifecycleError.invalidEnvironment("conflicting-environment-key")
      }
    }
    return Self(runtimeRoot: root, variables: variables)
  }

  private static func validatePath(_ url: URL, isolatedRoot: URL, mustExist: Bool) throws {
    guard !url.pathComponents.contains("..") else {
      throw HermesAgentLifecycleError.invalidEnvironment("path-traversal")
    }
    let standardized = url.standardizedFileURL
    guard standardized.isFileURL, !standardized.pathComponents.contains("..") else {
      throw HermesAgentLifecycleError.invalidEnvironment("path-traversal")
    }
    if mustExist {
      let resolved = standardized.resolvingSymlinksInPath()
      let root = isolatedRoot.standardizedFileURL.resolvingSymlinksInPath()
      guard resolved.path == root.path || resolved.path.hasPrefix(root.path + "/") else {
        throw HermesAgentLifecycleError.invalidEnvironment("symlink-escape")
      }
    } else {
      let parent = standardized.deletingLastPathComponent()
      if FileManager.default.fileExists(atPath: parent.path) {
        let resolvedParent = parent.resolvingSymlinksInPath()
        let rootParent = isolatedRoot.standardizedFileURL.deletingLastPathComponent()
          .resolvingSymlinksInPath()
        guard resolvedParent.path == rootParent.path || resolvedParent.path.hasPrefix(rootParent.path + "/")
        else {
          throw HermesAgentLifecycleError.invalidEnvironment("unresolved-path")
        }
      }
    }
  }

  private static func validateWorldWritableParents(_ url: URL) throws {
    var current = url.deletingLastPathComponent()
    while current.path != "/" {
      let attributes = try FileManager.default.attributesOfItem(atPath: current.path)
      let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
      let isWorldWritable = (permissions & 0o002) != 0
      let hasStickyBit = (permissions & 0o1000) != 0
      if isWorldWritable && !hasStickyBit {
        throw HermesAgentLifecycleError.invalidEnvironment("unsafe-world-writable-parent")
      }
      current.deleteLastPathComponent()
    }
  }

  private static func setPrivatePermissions(_ url: URL) throws {
    try FileManager.default.setAttributes(
      [.posixPermissions: NSNumber(value: Int16(0o700))],
      ofItemAtPath: url.path
    )
  }
}

public struct HermesAgentProcessIdentity: Codable, Equatable, Sendable {
  public let pid: pid_t
  public let ppid: pid_t
  public let pgid: pid_t
  public let uid: uid_t
  public let executableBasename: String
  public let executableFileIdentity: String
  public let processStartTime: String
  public let launchRunIdentifier: String

  public init(
    pid: pid_t,
    ppid: pid_t,
    pgid: pid_t,
    uid: uid_t,
    executableBasename: String,
    executableFileIdentity: String,
    processStartTime: String,
    launchRunIdentifier: String
  ) {
    self.pid = pid
    self.ppid = ppid
    self.pgid = pgid
    self.uid = uid
    self.executableBasename = URL(fileURLWithPath: executableBasename).lastPathComponent
    self.executableFileIdentity = executableFileIdentity
    self.processStartTime = processStartTime
    self.launchRunIdentifier = launchRunIdentifier
  }
}

public enum HermesAgentShutdownStatus: String, Codable, Equatable, Sendable {
  case graceful
  case exactTerm = "exact-term"
  case exactKill = "exact-kill"
  case alreadyExited = "already-exited"
  case identityMismatch = "identity-mismatch"
  case timeout
  case unsupported
}

public struct HermesAgentReadinessEvidence: Codable, Equatable, Sendable {
  public let mechanism: HermesAgentReadinessMechanism
  public let status: String
  public let serviceDiscoveryMatched: Bool

  public init(
    mechanism: HermesAgentReadinessMechanism,
    status: String,
    serviceDiscoveryMatched: Bool
  ) {
    self.mechanism = mechanism
    self.status = status
    self.serviceDiscoveryMatched = serviceDiscoveryMatched
  }
}

public struct HermesAgentShutdownResult: Codable, Equatable, Sendable {
  public let status: HermesAgentShutdownStatus
  public let exactTermUsed: Bool
  public let exactKillUsed: Bool

  public init(status: HermesAgentShutdownStatus, exactTermUsed: Bool, exactKillUsed: Bool) {
    self.status = status
    self.exactTermUsed = exactTermUsed
    self.exactKillUsed = exactKillUsed
  }
}

public protocol HermesAgentProcessIdentityValidating: Sendable {
  func capture(pid: pid_t, executableURL: URL, launchRunIdentifier: String) throws -> HermesAgentProcessIdentity
  func validate(_ identity: HermesAgentProcessIdentity) -> Bool
}

public struct DarwinHermesAgentProcessIdentityValidator: HermesAgentProcessIdentityValidating {
  public init() {}

  public func capture(
    pid: pid_t,
    executableURL: URL,
    launchRunIdentifier: String
  ) throws -> HermesAgentProcessIdentity {
    guard let info = Self.info(pid: pid) else {
      throw HermesAgentLifecycleError.identityMismatch
    }
    return HermesAgentProcessIdentity(
      pid: pid,
      ppid: info.ppid,
      pgid: getpgid(pid),
      uid: info.uid,
      executableBasename: executableURL.lastPathComponent,
      executableFileIdentity: try Self.fileIdentity(executableURL),
      processStartTime: "\(info.startSec).\(info.startUsec)",
      launchRunIdentifier: launchRunIdentifier
    )
  }

  public func validate(_ identity: HermesAgentProcessIdentity) -> Bool {
    guard kill(identity.pid, 0) == 0, let info = Self.info(pid: identity.pid) else {
      return false
    }
    return info.uid == identity.uid
      && getpgid(identity.pid) == identity.pgid
      && "\(info.startSec).\(info.startUsec)" == identity.processStartTime
  }

  private static func info(pid: pid_t) -> (ppid: pid_t, uid: uid_t, startSec: Int64, startUsec: Int64)? {
    var info = proc_bsdinfo()
    let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
    guard size == Int32(MemoryLayout<proc_bsdinfo>.size) else {
      return nil
    }
    return (
      pid_t(info.pbi_ppid),
      uid_t(info.pbi_uid),
      Int64(info.pbi_start_tvsec),
      Int64(info.pbi_start_tvusec)
    )
  }

  private static func fileIdentity(_ url: URL) throws -> String {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let device = attributes[.systemNumber] as? NSNumber
    let inode = attributes[.systemFileNumber] as? NSNumber
    return "dev:\(device?.stringValue ?? "unknown"),ino:\(inode?.stringValue ?? "unknown")"
  }
}

public enum HermesAgentCommandSafetyPolicy {
  public static func validateProbeArguments(_ arguments: [String]) throws {
    guard !arguments.isEmpty else {
      throw HermesAgentLifecycleError.forbiddenCommand("bare-hermes")
    }
    if arguments == ["--version"] || arguments == ["--help"] {
      return
    }
    guard arguments.last == "--help", arguments.count == 2 else {
      throw HermesAgentLifecycleError.forbiddenCommand("mutating-or-interactive-command")
    }
    let forbidden = ["login", "auth", "setup", "import", "upgrade", "update", "restart", "stop"]
    if forbidden.contains(arguments[0]) {
      throw HermesAgentLifecycleError.forbiddenCommand("forbidden-subcommand")
    }
  }

  public static func validateNoBroadSignal(pid: pid_t) throws {
    guard pid > 1 else {
      throw HermesAgentLifecycleError.identityMismatch
    }
  }
}
