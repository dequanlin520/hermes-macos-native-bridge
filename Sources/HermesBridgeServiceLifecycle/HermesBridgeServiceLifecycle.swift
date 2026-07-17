import Foundation
import HermesBridgeServiceManager

@main
struct HermesBridgeServiceLifecycleCLI {
  static func main() async {
    do {
      let invocation = try Invocation(arguments: Array(CommandLine.arguments.dropFirst()))
      let output = try await run(invocation)
      if !output.isEmpty {
        print(output)
      }
    } catch {
      fputs("HermesBridgeServiceLifecycle failed: \(redacted(error))\n", stderr)
      exit(1)
    }
  }

  private static func run(_ invocation: Invocation) async throws -> String {
    if invocation.usesProductionHome && invocation.requiresRealUserFlag
      && !invocation.installUserService
    {
      throw HermesBridgeServiceManagerError.realUserOperationRequiresExplicitFlag
    }

    let layout = invocation.layout
    let manager = HermesBridgeServiceManager(
      layout: layout,
      launchctl: invocation.fakeLaunchctl
        ? RecordingLaunchctlAdapter(log: invocation.fakeLaunchctlLog) : FixedLaunchctlAdapter(),
      architectureValidator: invocation.fakeLaunchctl
        ? PermissiveTestArchitectureValidator() : CurrentHostArchitectureValidator(),
      healthChecker: invocation.fakeLaunchctl
        ? ConstantHermesBridgeServiceHealthChecker() : DefaultHermesBridgeServiceHealthChecker()
    )

    switch invocation.command {
    case "plan":
      let binary = try invocation.requiredBinary()
      return try encode(
        try manager.planInstall(serviceBinary: binary, options: invocation.installOptions))
    case "install":
      let binary = try invocation.requiredBinary()
      return try await encode(
        manager.install(serviceBinary: binary, options: invocation.installOptions))
    case "validate":
      return try await encode(manager.validateInstallation())
    case "bootstrap":
      try manager.bootstrap()
      return "bootstrapped"
    case "status":
      return await manager.status().rawValue
    case "stop":
      try manager.stop()
      return "stopped"
    case "restart":
      return try await encode(manager.restart())
    case "upgrade":
      let binary = try invocation.requiredBinary()
      return try await encode(
        manager.upgrade(serviceBinary: binary, options: invocation.installOptions))
    case "rollback":
      return try await encode(manager.rollback(bootstrapAfterRollback: invocation.bootstrap))
    case "uninstall":
      try manager.uninstall(purgeState: invocation.purgeState, purgeLogs: invocation.purgeLogs)
      return "uninstalled"
    default:
      throw CLIError.usage
    }
  }

  private static func encode<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return String(data: try encoder.encode(value), encoding: .utf8) ?? ""
  }

  private static func redacted(_ error: Error) -> String {
    String(describing: error)
      .filter {
        $0.isASCII
          && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "." || $0 == ":" || $0 == "-")
      }
      .prefix(160)
      .description
  }
}

private enum CLIError: Error {
  case usage
  case missingValue(String)
  case missingBinary
  case invalidArgument(String)
}

private struct Invocation {
  let command: String
  let serviceBinary: URL?
  let layout: HermesBridgeInstallationLayout
  let installUserService: Bool
  let bootstrap: Bool
  let purgeState: Bool
  let purgeLogs: Bool
  let fakeLaunchctl: Bool
  let fakeLaunchctlLog: URL
  let version: String?
  let keepVersions: Int

  var installOptions: HermesBridgeServiceManager.InstallOptions {
    HermesBridgeServiceManager.InstallOptions(
      version: version,
      bootstrap: bootstrap,
      keepVersions: keepVersions,
      requireHealthyWhenBootstrapped: !fakeLaunchctl
    )
  }

  var usesProductionHome: Bool {
    layout.homeRoot.standardizedFileURL.path
      == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
  }

  var requiresRealUserFlag: Bool {
    ["install", "bootstrap", "stop", "restart", "upgrade", "rollback", "uninstall"].contains(
      command)
  }

  init(arguments: [String]) throws {
    guard let command = arguments.first else {
      throw CLIError.usage
    }
    let allowed = Set([
      "plan", "install", "validate", "bootstrap", "status", "stop", "restart", "upgrade",
      "rollback", "uninstall",
    ])
    guard allowed.contains(command) else {
      throw CLIError.usage
    }

    var serviceBinary: URL?
    var artifactRoot: URL?
    var installUserService = false
    var bootstrap = false
    var purgeState = false
    var purgeLogs = false
    var fakeLaunchctl = false
    var fakeLaunchctlLog: URL?
    var version: String?
    var keepVersions = 3

    var index = 1
    while index < arguments.count {
      let arg = arguments[index]
      switch arg {
      case "--service-binary":
        index += 1
        guard index < arguments.count else { throw CLIError.missingValue(arg) }
        serviceBinary = URL(fileURLWithPath: arguments[index]).standardizedFileURL
      case "--artifact-root":
        index += 1
        guard index < arguments.count else { throw CLIError.missingValue(arg) }
        artifactRoot = URL(fileURLWithPath: arguments[index]).standardizedFileURL
      case "--install-user-service":
        installUserService = true
      case "--bootstrap":
        bootstrap = true
      case "--purge-state":
        purgeState = true
      case "--purge-logs":
        purgeLogs = true
      case "--fake-launchctl":
        fakeLaunchctl = true
      case "--fake-launchctl-log":
        index += 1
        guard index < arguments.count else { throw CLIError.missingValue(arg) }
        fakeLaunchctlLog = URL(fileURLWithPath: arguments[index]).standardizedFileURL
      case "--version":
        index += 1
        guard index < arguments.count else { throw CLIError.missingValue(arg) }
        version = arguments[index]
      case "--keep-versions":
        index += 1
        guard index < arguments.count, let parsed = Int(arguments[index]), parsed > 0 else {
          throw CLIError.invalidArgument(arg)
        }
        keepVersions = parsed
      default:
        throw CLIError.invalidArgument(arg)
      }
      index += 1
    }

    let layout: HermesBridgeInstallationLayout
    if let artifactRoot {
      let home = artifactRoot.appendingPathComponent("fake-home", isDirectory: true)
      layout = HermesBridgeInstallationLayout(
        homeRoot: home,
        label: "com.hermes.bridge.test.m3-001",
        machService: "com.hermes.bridge.test.m3-001.xpc"
      )
    } else {
      layout = .production()
    }

    self.command = command
    self.serviceBinary = serviceBinary
    self.layout = layout
    self.installUserService = installUserService
    self.bootstrap = bootstrap
    self.purgeState = purgeState
    self.purgeLogs = purgeLogs
    self.fakeLaunchctl = fakeLaunchctl
    self.fakeLaunchctlLog =
      fakeLaunchctlLog ?? layout.applicationSupportRoot.appendingPathComponent("fake-launchctl.log")
    self.version = version
    self.keepVersions = keepVersions
  }

  func requiredBinary() throws -> URL {
    guard let serviceBinary else {
      throw CLIError.missingBinary
    }
    return serviceBinary
  }
}

private struct RecordingLaunchctlAdapter: HermesBridgeLaunchctlAdapter {
  let log: URL

  func bootstrap(plist: URL, layout: HermesBridgeInstallationLayout) throws {
    try append("bootstrap gui/\(getuid()) \(plist.path)")
    try append("visible \(layout.label)")
  }

  func bootout(plist: URL, layout: HermesBridgeInstallationLayout) throws {
    try append("bootout gui/\(getuid()) \(plist.path)")
    try append("absent \(layout.label)")
  }

  func kickstart(layout: HermesBridgeInstallationLayout) throws {
    try append("kickstart -k gui/\(getuid())/\(layout.label)")
  }

  func printService(layout: HermesBridgeInstallationLayout) throws -> String {
    let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
    let lines = text.split(separator: "\n").map(String.init)
    let latestState = lines.last { line in
      line == "visible \(layout.label)" || line == "absent \(layout.label)"
    }
    guard latestState == "visible \(layout.label)" else {
      throw HermesBridgeServiceManagerError.launchctlFailed("not_visible")
    }
    return "label=\(layout.label)"
  }

  private func append(_ line: String) throws {
    try FileManager.default.createDirectory(
      at: log.deletingLastPathComponent(),
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
    )
    let data = Data((line + "\n").utf8)
    if FileManager.default.fileExists(atPath: log.path) {
      let handle = try FileHandle(forWritingTo: log)
      try handle.seekToEnd()
      try handle.write(contentsOf: data)
      try handle.close()
    } else {
      try data.write(to: log)
    }
  }
}
