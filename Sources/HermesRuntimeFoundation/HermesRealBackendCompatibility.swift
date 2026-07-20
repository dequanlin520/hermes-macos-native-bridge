import CryptoKit
import Darwin
import Foundation
import Security

public struct HermesExecutableIdentity: Codable, Equatable, Sendable {
  public let executableAvailable: Bool
  public let pathKind: String
  public let checksumSHA256: String?
  public let checksumPrefix: String?
  public let codeSigningClassification: String
  public let isSymlink: Bool
  public let resolvedInsideAllowedRoot: Bool

  public init(
    executableAvailable: Bool,
    pathKind: String,
    checksumSHA256: String?,
    codeSigningClassification: String,
    isSymlink: Bool,
    resolvedInsideAllowedRoot: Bool
  ) {
    self.executableAvailable = executableAvailable
    self.pathKind = Self.safeToken(pathKind)
    self.checksumSHA256 = checksumSHA256
    self.checksumPrefix = checksumSHA256.map { String($0.prefix(12)) }
    self.codeSigningClassification = Self.safeToken(codeSigningClassification)
    self.isSymlink = isSymlink
    self.resolvedInsideAllowedRoot = resolvedInsideAllowedRoot
  }

  private static func safeToken(_ value: String) -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-")
    }
    return String((filtered.isEmpty ? "unknown" : filtered).prefix(64))
  }
}

public struct HermesBackendVersion: Codable, Equatable, Sendable, Comparable {
  public let rawValue: String
  public let major: Int
  public let minor: Int
  public let patch: Int

  public init(rawValue: String, major: Int, minor: Int, patch: Int) {
    self.rawValue = rawValue
    self.major = major
    self.minor = minor
    self.patch = patch
  }

  public static func parse(_ output: String) -> HermesBackendVersion? {
    let pattern = #"(?i)(?:Hermes(?: Agent)?\s*)?v?([0-9]+)\.([0-9]+)(?:\.([0-9]+))?"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
      let majorRange = Range(match.range(at: 1), in: output),
      let minorRange = Range(match.range(at: 2), in: output)
    else {
      return nil
    }
    let patchText: String
    if match.range(at: 3).location != NSNotFound,
      let patchRange = Range(match.range(at: 3), in: output)
    {
      patchText = String(output[patchRange])
    } else {
      patchText = "0"
    }
    guard let major = Int(output[majorRange]),
      let minor = Int(output[minorRange]),
      let patch = Int(patchText)
    else {
      return nil
    }
    return HermesBackendVersion(rawValue: "\(major).\(minor).\(patch)", major: major, minor: minor, patch: patch)
  }

  public static func < (lhs: HermesBackendVersion, rhs: HermesBackendVersion) -> Bool {
    [lhs.major, lhs.minor, lhs.patch].lexicographicallyPrecedes([rhs.major, rhs.minor, rhs.patch])
  }
}

public struct HermesBackendCapability: Codable, Equatable, Hashable, Sendable {
  public let rawValue: String

  public init(_ rawValue: String) {
    let normalized = rawValue
      .lowercased()
      .map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "_" }
    self.rawValue = String(String(normalized).split(separator: "_").joined(separator: "_").prefix(64))
  }
}

public enum HermesBackendCompatibilityState: String, Codable, CaseIterable, Equatable, Sendable {
  case supported
  case supportedWithWarnings
  case unsupportedTooOld
  case unsupportedTooNew
  case incompatibleProtocol
  case executableUnavailable
  case versionUnknown
}

public struct HermesBackendCompatibilityPolicy: Codable, Equatable, Sendable {
  public let minimumSupported: HermesBackendVersion
  public let maximumTested: HermesBackendVersion
  public let requiredCapabilities: [HermesBackendCapability]

  public init(
    minimumSupported: HermesBackendVersion = HermesBackendVersion(rawValue: "0.18.0", major: 0, minor: 18, patch: 0),
    maximumTested: HermesBackendVersion = HermesBackendVersion(rawValue: "0.19.99", major: 0, minor: 19, patch: 99),
    requiredCapabilities: [HermesBackendCapability] = []
  ) {
    self.minimumSupported = minimumSupported
    self.maximumTested = maximumTested
    self.requiredCapabilities = requiredCapabilities
  }

  public func classify(
    executableAvailable: Bool,
    version: HermesBackendVersion?,
    capabilities: [HermesBackendCapability]
  ) -> HermesBackendCompatibilityState {
    guard executableAvailable else { return .executableUnavailable }
    guard let version else { return .versionUnknown }
    if version < minimumSupported { return .unsupportedTooOld }
    if maximumTested < version { return .unsupportedTooNew }
    let available = Set(capabilities)
    if requiredCapabilities.contains(where: { !available.contains($0) }) {
      return .incompatibleProtocol
    }
    return capabilities.isEmpty ? .supportedWithWarnings : .supported
  }
}

public struct HermesBackendCompatibilityReport: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public let executableAvailable: Bool
  public let version: String?
  public let compatibilityState: HermesBackendCompatibilityState
  public let capabilities: [String]
  public let checksumPrefix: String?
  public let codeSigningClassification: String
  public let lastProbeTimestamp: Date
  public let remediationCode: String
  public let absolutePathExposed: Bool

  public init(
    schemaVersion: Int = currentSchemaVersion,
    executableAvailable: Bool,
    version: String?,
    compatibilityState: HermesBackendCompatibilityState,
    capabilities: [HermesBackendCapability],
    checksumPrefix: String?,
    codeSigningClassification: String,
    lastProbeTimestamp: Date = Date(),
    remediationCode: String,
    absolutePathExposed: Bool = false
  ) {
    self.schemaVersion = schemaVersion
    self.executableAvailable = executableAvailable
    self.version = version.map { String($0.prefix(32)) }
    self.compatibilityState = compatibilityState
    self.capabilities = capabilities.map(\.rawValue).sorted()
    self.checksumPrefix = checksumPrefix.map { String($0.prefix(12)) }
    self.codeSigningClassification = String(codeSigningClassification.prefix(64))
    self.lastProbeTimestamp = lastProbeTimestamp
    self.remediationCode = String(remediationCode.prefix(64))
    self.absolutePathExposed = absolutePathExposed
  }

  public static func unavailable(now: Date = Date()) -> HermesBackendCompatibilityReport {
    HermesBackendCompatibilityReport(
      executableAvailable: false,
      version: nil,
      compatibilityState: .executableUnavailable,
      capabilities: [],
      checksumPrefix: nil,
      codeSigningClassification: "unavailable",
      lastProbeTimestamp: now,
      remediationCode: "INSTALL_HERMES"
    )
  }
}

public enum HermesBackendDiscoveryError: Error, Equatable, Sendable {
  case executableUnavailable
  case directoryRejected
  case nonExecutableRejected
  case unsafeSymlinkRejected
  case versionTimedOut
  case versionCommandFailed
}

public struct HermesBackendDiscovery: Sendable {
  public let explicitExecutablePath: URL?
  public let pathEnvironment: String
  public let knownExecutableLocations: [URL]
  public let allowedExecutableRoots: [URL]
  public let timeoutSeconds: TimeInterval
  public let outputLimitBytes: Int
  public let versionEnvironment: [String: String]?

  public init(
    explicitExecutablePath: URL? = nil,
    pathEnvironment: String = ProcessInfo.processInfo.environment["PATH"] ?? "",
    knownExecutableLocations: [URL] = Self.defaultKnownExecutableLocations(),
    allowedExecutableRoots: [URL] = Self.defaultAllowedExecutableRoots(),
    timeoutSeconds: TimeInterval = 3,
    outputLimitBytes: Int = 16 * 1024,
    versionEnvironment: [String: String]? = nil
  ) {
    self.explicitExecutablePath = explicitExecutablePath
    self.pathEnvironment = pathEnvironment
    self.knownExecutableLocations = knownExecutableLocations
    self.allowedExecutableRoots = allowedExecutableRoots
    self.timeoutSeconds = timeoutSeconds
    self.outputLimitBytes = max(1, outputLimitBytes)
    self.versionEnvironment = versionEnvironment
  }

  public static func defaultKnownExecutableLocations() -> [URL] {
    [
      "/opt/homebrew/bin/hermes",
      "/usr/local/bin/hermes",
      "/usr/bin/hermes",
      "/Applications/Hermes.app/Contents/MacOS/hermes",
      "artifacts/hermes-dev/bin/hermes",
      ".hermes-dev/bin/hermes",
    ].map { URL(fileURLWithPath: $0) }
  }

  public static func defaultAllowedExecutableRoots() -> [URL] {
    ["/opt/homebrew", "/usr/local", "/usr/bin", "/Applications"].map { URL(fileURLWithPath: $0, isDirectory: true) }
  }

  public func discover() throws -> (candidate: HermesExecutableCandidate, identity: HermesExecutableIdentity, versionOutput: String, backendVersion: HermesBackendVersion?) {
    if let explicitExecutablePath {
      return try validate(url: explicitExecutablePath, pathKind: "explicit")
    }
    for (url, kind) in candidateURLs() {
      if let result = try? validate(url: url, pathKind: kind) {
        return result
      }
    }
    throw HermesBackendDiscoveryError.executableUnavailable
  }

  public func validate(url: URL, pathKind: String = "explicit") throws -> (candidate: HermesExecutableCandidate, identity: HermesExecutableIdentity, versionOutput: String, backendVersion: HermesBackendVersion?) {
    let standardized = url.standardizedFileURL
    var isDirectory = ObjCBool(false)
    guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory) else {
      throw HermesBackendDiscoveryError.executableUnavailable
    }
    guard !isDirectory.boolValue else { throw HermesBackendDiscoveryError.directoryRejected }
    guard FileManager.default.isExecutableFile(atPath: standardized.path) else {
      throw HermesBackendDiscoveryError.nonExecutableRejected
    }

    let resolved = standardized.resolvingSymlinksInPath()
    let isSymlink = (try? FileManager.default.destinationOfSymbolicLink(atPath: standardized.path)) != nil
    let insideAllowedRoot = allowedExecutableRoots.map { $0.standardizedFileURL.resolvingSymlinksInPath().path }
      .contains { root in resolved.path == root || resolved.path.hasPrefix(root + "/") }
    if isSymlink, !insideAllowedRoot {
      throw HermesBackendDiscoveryError.unsafeSymlinkRejected
    }

    let output = try readVersionOutput(executable: resolved)
    let checksum = try sha256(url: resolved)
    let identity = HermesExecutableIdentity(
      executableAvailable: true,
      pathKind: pathKind,
      checksumSHA256: checksum,
      codeSigningClassification: Self.codeSigningClassification(url: resolved),
      isSymlink: isSymlink,
      resolvedInsideAllowedRoot: insideAllowedRoot
    )
    let candidate = HermesExecutableCandidate(
      allowlistedCandidatePath: standardized.path,
      originalPath: standardized.path,
      resolvedPath: resolved.path,
      symlinkStatus: isSymlink ? .symlink(resolved: true) : .notSymlink
    )
    return (candidate, identity, output, HermesBackendVersion.parse(output))
  }

  private func candidateURLs() -> [(URL, String)] {
    var values: [(URL, String)] = []
    if let explicitExecutablePath {
      values.append((explicitExecutablePath, "explicit"))
    }
    values += pathEnvironment.split(separator: ":").map {
      (URL(fileURLWithPath: String($0)).appendingPathComponent("hermes"), "path")
    }
    values += knownExecutableLocations.map { ($0, "known") }
    var seen = Set<String>()
    return values.filter { seen.insert($0.0.standardizedFileURL.path).inserted }
  }

  private func readVersionOutput(executable: URL) throws -> String {
    let process = Process()
    process.executableURL = executable
    process.arguments = ["--version"]
    process.environment = versionEnvironment ?? ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "C"]
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    let out = BoundedDataBox(limitBytes: outputLimitBytes)
    let err = BoundedDataBox(limitBytes: outputLimitBytes)
    stdout.fileHandleForReading.readabilityHandler = { out.append($0.availableData) }
    stderr.fileHandleForReading.readabilityHandler = { err.append($0.availableData) }
    let done = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in done.signal() }
    do {
      try process.run()
    } catch {
      throw HermesBackendDiscoveryError.versionCommandFailed
    }
    guard done.wait(timeout: .now() + timeoutSeconds) == .success else {
      process.terminate()
      _ = done.wait(timeout: .now() + 0.5)
      if process.isRunning { kill(process.processIdentifier, SIGKILL) }
      throw HermesBackendDiscoveryError.versionTimedOut
    }
    stdout.fileHandleForReading.readabilityHandler = nil
    stderr.fileHandleForReading.readabilityHandler = nil
    out.append(stdout.fileHandleForReading.readDataToEndOfFile())
    err.append(stderr.fileHandleForReading.readDataToEndOfFile())
    guard process.terminationStatus == 0 else { throw HermesBackendDiscoveryError.versionCommandFailed }
    return String(data: out.data + err.data, encoding: .utf8) ?? ""
  }

  private func sha256(url: URL) throws -> String {
    let data = try Data(contentsOf: url)
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func codeSigningClassification(url: URL) -> String {
    var staticCode: SecStaticCode?
    guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
      let staticCode
    else {
      return "unsigned"
    }
    var information: CFDictionary?
    let result = SecCodeCopySigningInformation(
      staticCode,
      SecCSFlags(rawValue: kSecCSSigningInformation),
      &information
    )
    guard result == errSecSuccess, let dictionary = information as? [String: Any] else {
      return "unsigned"
    }
    if dictionary[kSecCodeInfoTeamIdentifier as String] as? String != nil {
      return "developer_id_or_team_signed"
    }
    return "ad_hoc_or_locally_signed"
  }
}

public struct HermesIsolatedBackendEnvironment: Codable, Equatable, Sendable {
  public let root: String
  public let home: String
  public let xdgConfigHome: String
  public let xdgCacheHome: String
  public let xdgStateHome: String
  public let tmpdir: String
  public let realHermesProfileExcluded: Bool
  public let shellStartupFilesLoaded: Bool
  public let keychainAccessed: Bool

  public init(artifactRoot: URL, realHome: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
    let rootURL = artifactRoot.appendingPathComponent("runtime", isDirectory: true).standardizedFileURL
    let homeURL = rootURL.appendingPathComponent("home", isDirectory: true)
    let configURL = rootURL.appendingPathComponent("xdg-config", isDirectory: true)
    let cacheURL = rootURL.appendingPathComponent("xdg-cache", isDirectory: true)
    let stateURL = rootURL.appendingPathComponent("xdg-state", isDirectory: true)
    let tmpURL = rootURL.appendingPathComponent("tmp", isDirectory: true)
    for url in [rootURL, homeURL, configURL, cacheURL, stateURL, tmpURL] {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o700))], ofItemAtPath: url.path)
    }
    let realProfile = realHome.appendingPathComponent(".hermes", isDirectory: true)
      .standardizedFileURL.resolvingSymlinksInPath().path
    let roots = [homeURL, configURL, cacheURL, stateURL, tmpURL].map {
      $0.standardizedFileURL.resolvingSymlinksInPath().path
    }
    self.root = "artifacts/m9-001/runtime"
    self.home = "artifacts/m9-001/runtime/home"
    self.xdgConfigHome = "artifacts/m9-001/runtime/xdg-config"
    self.xdgCacheHome = "artifacts/m9-001/runtime/xdg-cache"
    self.xdgStateHome = "artifacts/m9-001/runtime/xdg-state"
    self.tmpdir = "artifacts/m9-001/runtime/tmp"
    self.realHermesProfileExcluded = !roots.contains { realProfile == $0 || realProfile.hasPrefix($0 + "/") }
    self.shellStartupFilesLoaded = false
    self.keychainAccessed = false
  }

  public var processEnvironment: [String: String] {
    [
      "HOME": home,
      "XDG_CONFIG_HOME": xdgConfigHome,
      "XDG_CACHE_HOME": xdgCacheHome,
      "XDG_STATE_HOME": xdgStateHome,
      "TMPDIR": tmpdir,
      "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
      "LANG": "C",
    ]
  }
}

public struct HermesRealBackendCleanupReport: Codable, Equatable, Sendable {
  public let exactPIDTracked: Bool
  public let exactPGIDTracked: Bool
  public let gracefulShutdownPassed: Bool
  public let controlledEscalationUsed: Bool
  public let broadProcessTerminationUsed: Bool
  public let residualProcess: Bool
}

public struct HermesRealBackendSmokeTestRunner: Sendable {
  public let discovery: HermesBackendDiscovery
  public let policy: HermesBackendCompatibilityPolicy
  public let artifactRoot: URL

  public init(
    discovery: HermesBackendDiscovery = HermesBackendDiscovery(),
    policy: HermesBackendCompatibilityPolicy = HermesBackendCompatibilityPolicy(),
    artifactRoot: URL
  ) {
    self.discovery = discovery
    self.policy = policy
    self.artifactRoot = artifactRoot
  }

  public func run(now: Date = Date()) throws -> HermesBackendCompatibilityReport {
    _ = try HermesIsolatedBackendEnvironment(artifactRoot: artifactRoot)
    let runtimeRoot = artifactRoot.appendingPathComponent("runtime", isDirectory: true)
    let isolatedDiscovery = HermesBackendDiscovery(
      explicitExecutablePath: discovery.explicitExecutablePath,
      pathEnvironment: discovery.pathEnvironment,
      knownExecutableLocations: discovery.knownExecutableLocations,
      allowedExecutableRoots: discovery.allowedExecutableRoots,
      timeoutSeconds: discovery.timeoutSeconds,
      outputLimitBytes: discovery.outputLimitBytes,
      versionEnvironment: [
        "HOME": runtimeRoot.appendingPathComponent("home", isDirectory: true).path,
        "HERMES_HOME": runtimeRoot.appendingPathComponent("hermes-home", isDirectory: true).path,
        "XDG_CONFIG_HOME": runtimeRoot.appendingPathComponent("xdg-config", isDirectory: true).path,
        "XDG_CACHE_HOME": runtimeRoot.appendingPathComponent("xdg-cache", isDirectory: true).path,
        "XDG_STATE_HOME": runtimeRoot.appendingPathComponent("xdg-state", isDirectory: true).path,
        "TMPDIR": runtimeRoot.appendingPathComponent("tmp", isDirectory: true).path,
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "LANG": "C",
      ]
    )
    let discovered = try isolatedDiscovery.discover()
    let capabilities = [HermesBackendCapability("version_output")]
    let state = policy.classify(
      executableAvailable: discovered.identity.executableAvailable,
      version: discovered.backendVersion,
      capabilities: capabilities
    )
    return HermesBackendCompatibilityReport(
      executableAvailable: discovered.identity.executableAvailable,
      version: discovered.backendVersion?.rawValue,
      compatibilityState: state,
      capabilities: capabilities,
      checksumPrefix: discovered.identity.checksumPrefix,
      codeSigningClassification: discovered.identity.codeSigningClassification,
      lastProbeTimestamp: now,
      remediationCode: remediationCode(for: state)
    )
  }

  private func remediationCode(for state: HermesBackendCompatibilityState) -> String {
    switch state {
    case .supported: return "NONE"
    case .supportedWithWarnings: return "VALIDATE_PROTOCOL_CAPABILITIES"
    case .unsupportedTooOld: return "UPGRADE_HERMES"
    case .unsupportedTooNew: return "UPDATE_BRIDGE_POLICY"
    case .incompatibleProtocol: return "CHECK_BACKEND_PROTOCOL"
    case .executableUnavailable: return "INSTALL_HERMES"
    case .versionUnknown: return "CHECK_VERSION_OUTPUT"
    }
  }
}

private final class BoundedDataBox: @unchecked Sendable {
  private let lock = NSLock()
  private let limitBytes: Int
  private var storage = Data()

  init(limitBytes: Int) {
    self.limitBytes = max(1, limitBytes)
  }

  var data: Data {
    lock.withLock { storage }
  }

  func append(_ data: Data) {
    guard !data.isEmpty else { return }
    lock.withLock {
      let remaining = limitBytes - storage.count
      if remaining > 0 {
        storage.append(data.prefix(remaining))
      }
    }
  }
}
