import CryptoKit
import Darwin
import Foundation
import HermesBridgeService
import HermesBridgeXPC

public struct HermesBridgeInstallationLayout: Codable, Equatable, Sendable {
  public static let serviceBinaryName = "HermesBridgeService"
  public static let productionLabel = HermesBridgeServiceConfiguration.productionLabel
  public static let productionMachService = HermesBridgeServiceConfiguration
    .productionMachServiceName

  public let homeRoot: URL
  public let applicationSupportRoot: URL
  public let versionsRoot: URL
  public let currentLink: URL
  public let runtimeRoot: URL
  public let stateRoot: URL
  public let logsRoot: URL
  public let backupsRoot: URL
  public let installState: URL
  public let launchAgentsRoot: URL
  public let launchAgentPlist: URL
  public let label: String
  public let machService: String

  public init(
    homeRoot: URL, label: String = Self.productionLabel,
    machService: String = Self.productionMachService
  ) {
    let home = homeRoot.standardizedFileURL
    let support =
      home
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent("Application Support", isDirectory: true)
      .appendingPathComponent("HermesBridge", isDirectory: true)
    let launchAgents =
      home
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent("LaunchAgents", isDirectory: true)
    self.homeRoot = home
    self.applicationSupportRoot = support
    self.versionsRoot = support.appendingPathComponent("Versions", isDirectory: true)
    self.currentLink = support.appendingPathComponent("Current", isDirectory: true)
    self.runtimeRoot = support.appendingPathComponent("Runtime", isDirectory: true)
    self.stateRoot = support.appendingPathComponent("State", isDirectory: true)
    self.logsRoot = support.appendingPathComponent("Logs", isDirectory: true)
    self.backupsRoot = support.appendingPathComponent("Backups", isDirectory: true)
    self.installState = support.appendingPathComponent("install-state.json")
    self.launchAgentsRoot = launchAgents
    self.launchAgentPlist = launchAgents.appendingPathComponent("\(label).plist")
    self.label = label
    self.machService = machService
  }

  public static func production() -> HermesBridgeInstallationLayout {
    HermesBridgeInstallationLayout(homeRoot: FileManager.default.homeDirectoryForCurrentUser)
  }
}

public struct HermesBridgeInstalledVersion: Codable, Equatable, Sendable {
  public let version: String
  public let installedAt: Date
  public let binaryPath: String
  public let binarySHA256: String
  public let sourcePathHash: String
}

public struct HermesBridgeInstallationState: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public var activeVersion: String?
  public var previousVersion: String?
  public var installedVersions: [HermesBridgeInstalledVersion]
  public let launchAgentPath: String
  public let applicationSupportRoot: String
  public var lastOperation: String
  public var updatedAt: Date

  public init(
    activeVersion: String?,
    previousVersion: String?,
    installedVersions: [HermesBridgeInstalledVersion],
    launchAgentPath: String,
    applicationSupportRoot: String,
    lastOperation: String,
    updatedAt: Date = Date()
  ) {
    self.schemaVersion = Self.currentSchemaVersion
    self.activeVersion = activeVersion
    self.previousVersion = previousVersion
    self.installedVersions = installedVersions
    self.launchAgentPath = launchAgentPath
    self.applicationSupportRoot = applicationSupportRoot
    self.lastOperation = lastOperation
    self.updatedAt = updatedAt
  }
}

public enum HermesBridgeServiceStatus: String, Codable, Equatable, Sendable {
  case notInstalled
  case installedStopped
  case starting
  case runningHealthy
  case runningUnhealthy
  case upgradePending
  case rollbackAvailable
  case invalidInstallation
}

public struct HermesBridgeInstallPlan: Codable, Equatable, Sendable {
  public let version: String
  public let sourceBinaryPath: String
  public let stagedBinaryPath: String
  public let launchAgentPath: String
  public let willBootstrap: Bool
  public let operation: String
}

public struct HermesBridgeHealthCheckResult: Codable, Equatable, Sendable {
  public let filesValid: Bool
  public let plistValid: Bool
  public let launchdVisible: Bool
  public let processPresent: Bool
  public let xpcHandshakeSucceeded: Bool
  public let capabilitiesSucceeded: Bool
  public let failureCode: String?

  public var isHealthy: Bool {
    filesValid && plistValid && launchdVisible && xpcHandshakeSucceeded && capabilitiesSucceeded
  }

  public static func healthy(processPresent: Bool = true) -> HermesBridgeHealthCheckResult {
    HermesBridgeHealthCheckResult(
      filesValid: true,
      plistValid: true,
      launchdVisible: true,
      processPresent: processPresent,
      xpcHandshakeSucceeded: true,
      capabilitiesSucceeded: true,
      failureCode: nil
    )
  }

  public static func unhealthy(_ code: String) -> HermesBridgeHealthCheckResult {
    HermesBridgeHealthCheckResult(
      filesValid: false,
      plistValid: false,
      launchdVisible: false,
      processPresent: false,
      xpcHandshakeSucceeded: false,
      capabilitiesSucceeded: false,
      failureCode: code
    )
  }
}

public enum HermesBridgeServiceManagerError: Error, Equatable, Sendable {
  case invalidLayout(String)
  case symlinkEscape(String)
  case invalidServiceBinary(String)
  case unsupportedArchitecture(String)
  case invalidPlist(String)
  case invalidLaunchctlBoundary(String)
  case launchctlFailed(String)
  case healthCheckFailed(String)
  case rollbackUnavailable
  case statePersistenceFailed(String)
  case realUserOperationRequiresExplicitFlag
}

public protocol HermesBridgeLaunchctlAdapter: Sendable {
  func bootstrap(plist: URL, layout: HermesBridgeInstallationLayout) throws
  func bootout(plist: URL, layout: HermesBridgeInstallationLayout) throws
  func kickstart(layout: HermesBridgeInstallationLayout) throws
  func printService(layout: HermesBridgeInstallationLayout) throws -> String
}

public protocol HermesBridgeArchitectureValidating: Sendable {
  func validate(binary: URL) throws
}

public protocol HermesBridgePlistValidating: Sendable {
  func validate(plist: URL) throws
}

public protocol HermesBridgeServiceHealthChecking: Sendable {
  func check(layout: HermesBridgeInstallationLayout, launchctl: HermesBridgeLaunchctlAdapter) async
    -> HermesBridgeHealthCheckResult
}

public struct HermesBridgeServiceManager {
  public struct InstallOptions: Sendable {
    public let version: String?
    public let bootstrap: Bool
    public let keepVersions: Int
    public let requireHealthyWhenBootstrapped: Bool

    public init(
      version: String? = nil,
      bootstrap: Bool = false,
      keepVersions: Int = 3,
      requireHealthyWhenBootstrapped: Bool = true
    ) {
      self.version = version
      self.bootstrap = bootstrap
      self.keepVersions = max(1, keepVersions)
      self.requireHealthyWhenBootstrapped = requireHealthyWhenBootstrapped
    }
  }

  private let layout: HermesBridgeInstallationLayout
  private let fileManager: FileManager
  private let launchctl: HermesBridgeLaunchctlAdapter
  private let architectureValidator: HermesBridgeArchitectureValidating
  private let plistValidator: HermesBridgePlistValidating
  private let healthChecker: HermesBridgeServiceHealthChecking
  private let now: @Sendable () -> Date

  public init(
    layout: HermesBridgeInstallationLayout = .production(),
    fileManager: FileManager = .default,
    launchctl: HermesBridgeLaunchctlAdapter = FixedLaunchctlAdapter(),
    architectureValidator: HermesBridgeArchitectureValidating = CurrentHostArchitectureValidator(),
    plistValidator: HermesBridgePlistValidating = PlutilPlistValidator(),
    healthChecker: HermesBridgeServiceHealthChecking = DefaultHermesBridgeServiceHealthChecker(),
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.layout = layout
    self.fileManager = fileManager
    self.launchctl = launchctl
    self.architectureValidator = architectureValidator
    self.plistValidator = plistValidator
    self.healthChecker = healthChecker
    self.now = now
  }

  public func planInstall(serviceBinary: URL, options: InstallOptions = InstallOptions()) throws
    -> HermesBridgeInstallPlan
  {
    try validateLayoutRoots()
    try validateServiceBinary(serviceBinary)
    let version = try normalizedVersion(options.version, serviceBinary: serviceBinary)
    return HermesBridgeInstallPlan(
      version: version,
      sourceBinaryPath: serviceBinary.standardizedFileURL.path,
      stagedBinaryPath: layout.versionsRoot.appendingPathComponent(version, isDirectory: true)
        .appendingPathComponent(HermesBridgeInstallationLayout.serviceBinaryName).path,
      launchAgentPath: layout.launchAgentPlist.path,
      willBootstrap: options.bootstrap,
      operation: "install"
    )
  }

  @discardableResult
  public func install(serviceBinary: URL, options: InstallOptions = InstallOptions()) async throws
    -> HermesBridgeInstallationState
  {
    let plan = try planInstall(serviceBinary: serviceBinary, options: options)
    let previous = try loadState()
    let previousActive = previous?.activeVersion
    let installed = try stageVersion(serviceBinary: serviceBinary, version: plan.version)
    try writeLaunchAgent(activeBinary: URL(fileURLWithPath: installed.binaryPath))

    do {
      try activate(version: plan.version)
      var state = try mergedState(
        previous: previous,
        installed: installed,
        previousActive: previousActive,
        operation: "install"
      )
      try persistState(state)
      if options.bootstrap {
        try bootstrap()
        let health = await healthChecker.check(layout: layout, launchctl: launchctl)
        guard !options.requireHealthyWhenBootstrapped || health.isHealthy else {
          throw HermesBridgeServiceManagerError.healthCheckFailed(health.failureCode ?? "unhealthy")
        }
      }
      try pruneVersions(
        keep: options.keepVersions, active: state.activeVersion, previous: state.previousVersion)
      state.installedVersions = try loadState()?.installedVersions ?? state.installedVersions
      return state
    } catch {
      if let previousActive {
        try? activate(version: previousActive)
        if let previous {
          try? persistState(previous)
        }
      }
      throw error
    }
  }

  public func validateInstallation() async -> HermesBridgeHealthCheckResult {
    guard (try? validateLayoutRoots()) != nil else {
      return .unhealthy("invalid_layout")
    }
    guard let state = try? loadState(), let active = state.activeVersion else {
      return .unhealthy("not_installed")
    }
    let binary = layout.versionsRoot.appendingPathComponent(active, isDirectory: true)
      .appendingPathComponent(HermesBridgeInstallationLayout.serviceBinaryName)
    guard isExecutableRegularFile(binary), (try? validatePlistContents(binary: binary)) != nil
    else {
      return .unhealthy("invalid_files")
    }
    return await healthChecker.check(layout: layout, launchctl: launchctl)
  }

  public func bootstrap() throws {
    try validateInstalledPlistBoundary()
    try launchctl.bootstrap(plist: layout.launchAgentPlist, layout: layout)
  }

  public func status() async -> HermesBridgeServiceStatus {
    guard let state = try? loadState() else {
      return .notInstalled
    }
    guard let active = state.activeVersion else {
      return .invalidInstallation
    }
    let activeBinary = layout.versionsRoot.appendingPathComponent(active, isDirectory: true)
      .appendingPathComponent(HermesBridgeInstallationLayout.serviceBinaryName)
    guard isExecutableRegularFile(activeBinary),
      fileManager.fileExists(atPath: layout.launchAgentPlist.path)
    else {
      return .invalidInstallation
    }
    let launchdVisible = (try? launchctl.printService(layout: layout)) != nil
    if !launchdVisible {
      return state.previousVersion == nil ? .installedStopped : .rollbackAvailable
    }
    let health = await healthChecker.check(layout: layout, launchctl: launchctl)
    if health.isHealthy {
      return .runningHealthy
    }
    if health.launchdVisible {
      return .runningUnhealthy
    }
    return .starting
  }

  public func stop() throws {
    try validateInstalledPlistBoundary()
    try? launchctl.bootout(plist: layout.launchAgentPlist, layout: layout)
  }

  public func restart() async throws -> HermesBridgeHealthCheckResult {
    try stop()
    try bootstrap()
    try launchctl.kickstart(layout: layout)
    return await healthChecker.check(layout: layout, launchctl: launchctl)
  }

  @discardableResult
  public func upgrade(serviceBinary: URL, options: InstallOptions = InstallOptions(bootstrap: true))
    async throws -> HermesBridgeInstallationState
  {
    let previous = try loadState()
    try stop()
    do {
      return try await install(serviceBinary: serviceBinary, options: options)
    } catch {
      if let previousActive = previous?.activeVersion {
        try? activate(version: previousActive)
        if let previous {
          try? persistState(previous)
        }
        try? bootstrap()
      }
      throw error
    }
  }

  @discardableResult
  public func rollback(bootstrapAfterRollback: Bool = true) async throws
    -> HermesBridgeInstallationState
  {
    guard var state = try loadState(), let previous = state.previousVersion else {
      throw HermesBridgeServiceManagerError.rollbackUnavailable
    }
    let previousBinary = layout.versionsRoot.appendingPathComponent(previous, isDirectory: true)
      .appendingPathComponent(HermesBridgeInstallationLayout.serviceBinaryName)
    guard isExecutableRegularFile(previousBinary) else {
      throw HermesBridgeServiceManagerError.rollbackUnavailable
    }
    try stop()
    let oldActive = state.activeVersion
    try activate(version: previous)
    try writeLaunchAgent(activeBinary: previousBinary)
    state.activeVersion = previous
    state.previousVersion = oldActive
    state.lastOperation = "rollback"
    state.updatedAt = now()
    try persistState(state)
    if bootstrapAfterRollback {
      try bootstrap()
      let health = await healthChecker.check(layout: layout, launchctl: launchctl)
      guard health.isHealthy else {
        throw HermesBridgeServiceManagerError.healthCheckFailed(
          health.failureCode ?? "rollback_unhealthy")
      }
    }
    return state
  }

  public func uninstall(purgeState: Bool = false, purgeLogs: Bool = false) throws {
    try? stop()
    if (try? launchctl.printService(layout: layout)) != nil {
      throw HermesBridgeServiceManagerError.launchctlFailed("service_still_visible")
    }
    if fileManager.fileExists(atPath: layout.launchAgentPlist.path) {
      try removeOwnedFile(layout.launchAgentPlist)
    }
    if fileManager.fileExists(atPath: layout.versionsRoot.path) {
      try removeOwnedDirectory(layout.versionsRoot)
    }
    if fileManager.fileExists(atPath: layout.currentLink.path) {
      try removeOwnedFile(layout.currentLink)
    }
    if fileManager.fileExists(atPath: layout.installState.path) {
      try removeOwnedFile(layout.installState)
    }
    if purgeState, fileManager.fileExists(atPath: layout.stateRoot.path) {
      try removeOwnedDirectory(layout.stateRoot)
    }
    if purgeLogs, fileManager.fileExists(atPath: layout.logsRoot.path) {
      try removeOwnedDirectory(layout.logsRoot)
    }
  }

  private func validateLayoutRoots() throws {
    guard layout.homeRoot.isFileURL, layout.applicationSupportRoot.isFileURL,
      layout.launchAgentPlist.isFileURL
    else {
      throw HermesBridgeServiceManagerError.invalidLayout("non_file_url")
    }
    guard
      layout.label == HermesBridgeInstallationLayout.productionLabel
        || layout.label.hasPrefix("com.hermes.bridge.test.")
    else {
      throw HermesBridgeServiceManagerError.invalidLayout("invalid_label")
    }
    guard
      layout.machService == HermesBridgeInstallationLayout.productionMachService
        || layout.machService.hasPrefix("com.hermes.bridge.test.")
    else {
      throw HermesBridgeServiceManagerError.invalidLayout("invalid_mach_service")
    }
    try createSecureDirectory(layout.homeRoot)
    for directory in [
      layout.applicationSupportRoot, layout.versionsRoot, layout.runtimeRoot, layout.stateRoot,
      layout.logsRoot, layout.backupsRoot, layout.launchAgentsRoot,
    ] {
      try createSecureDirectory(directory)
    }
    try rejectSymlinkComponents(layout.applicationSupportRoot)
    try rejectSymlinkComponents(layout.launchAgentsRoot)
  }

  private func validateServiceBinary(_ serviceBinary: URL) throws {
    let binary = serviceBinary.standardizedFileURL
    guard binary.isFileURL else {
      throw HermesBridgeServiceManagerError.invalidServiceBinary("non_file_url")
    }
    guard binary.lastPathComponent == HermesBridgeInstallationLayout.serviceBinaryName else {
      throw HermesBridgeServiceManagerError.invalidServiceBinary("unexpected_name")
    }
    guard !isSymlink(binary), isExecutableRegularFile(binary) else {
      throw HermesBridgeServiceManagerError.invalidServiceBinary("not_regular_executable")
    }
    try architectureValidator.validate(binary: binary)
  }

  private func normalizedVersion(_ requested: String?, serviceBinary: URL) throws -> String {
    if let requested, !requested.isEmpty {
      guard
        requested.allSatisfy({
          $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-")
        })
      else {
        throw HermesBridgeServiceManagerError.invalidServiceBinary("invalid_version")
      }
      return requested
    }
    let hash = try sha256(serviceBinary).prefix(12)
    return "dev-\(hash)"
  }

  private func stageVersion(serviceBinary: URL, version: String) throws
    -> HermesBridgeInstalledVersion
  {
    let staging = layout.versionsRoot.appendingPathComponent(
      ".staging-\(UUID().uuidString)", isDirectory: true)
    let final = layout.versionsRoot.appendingPathComponent(version, isDirectory: true)
    let binary = final.appendingPathComponent(HermesBridgeInstallationLayout.serviceBinaryName)
    if fileManager.fileExists(atPath: final.path) {
      try removeOwnedDirectory(final)
    }
    try createSecureDirectory(staging)
    let stagedBinary = staging.appendingPathComponent(
      HermesBridgeInstallationLayout.serviceBinaryName)
    try fileManager.copyItem(at: serviceBinary.standardizedFileURL, to: stagedBinary)
    try setPermissions(stagedBinary, 0o500)
    try fileManager.moveItem(at: staging, to: final)
    try setPermissions(final, 0o700)
    return HermesBridgeInstalledVersion(
      version: version,
      installedAt: now(),
      binaryPath: binary.path,
      binarySHA256: try sha256(binary),
      sourcePathHash: stablePathHash(serviceBinary.standardizedFileURL.path)
    )
  }

  private func writeLaunchAgent(activeBinary: URL) throws {
    let plist = launchAgentDictionary(binary: activeBinary)
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    let tmp = layout.launchAgentPlist.deletingLastPathComponent()
      .appendingPathComponent(
        ".\(layout.launchAgentPlist.lastPathComponent).tmp.\(UUID().uuidString)")
    try data.write(to: tmp, options: [.atomic])
    try setPermissions(tmp, 0o600)
    try plistValidator.validate(plist: tmp)
    try validatePlistContents(binary: activeBinary, plist: tmp)
    if fileManager.fileExists(atPath: layout.launchAgentPlist.path) {
      try removeOwnedFile(layout.launchAgentPlist)
    }
    try fileManager.moveItem(at: tmp, to: layout.launchAgentPlist)
    try setPermissions(layout.launchAgentPlist, 0o600)
  }

  private func launchAgentDictionary(binary: URL) -> [String: Any] {
    [
      "Label": layout.label,
      "MachServices": [layout.machService: true],
      "ProgramArguments": [binary.path],
      "RunAtLoad": true,
      "KeepAlive": false,
      "ProcessType": "Background",
      "ThrottleInterval": 30,
      "StandardOutPath": layout.logsRoot.appendingPathComponent("service.stdout.log").path,
      "StandardErrorPath": layout.logsRoot.appendingPathComponent("service.stderr.log").path,
    ]
  }

  private func validatePlistContents(binary: URL? = nil, plist: URL? = nil) throws {
    let plistURL = plist ?? layout.launchAgentPlist
    let data = try Data(contentsOf: plistURL)
    guard
      let dictionary = try PropertyListSerialization.propertyList(
        from: data, options: [], format: nil) as? [String: Any]
    else {
      throw HermesBridgeServiceManagerError.invalidPlist("not_dictionary")
    }
    guard dictionary["Label"] as? String == layout.label else {
      throw HermesBridgeServiceManagerError.invalidPlist("label")
    }
    guard let mach = dictionary["MachServices"] as? [String: Bool],
      mach == [layout.machService: true]
    else {
      throw HermesBridgeServiceManagerError.invalidPlist("mach_service")
    }
    guard let args = dictionary["ProgramArguments"] as? [String], args.count == 1 else {
      throw HermesBridgeServiceManagerError.invalidPlist("program_arguments")
    }
    if let binary {
      guard args[0] == binary.path else {
        throw HermesBridgeServiceManagerError.invalidPlist("binary")
      }
    }
    let text = String(data: data, encoding: .utf8) ?? ""
    guard !text.localizedCaseInsensitiveContains("token"),
      !text.localizedCaseInsensitiveContains("prompt"),
      !text.contains("HERMES_DASHBOARD_SESSION_TOKEN")
    else {
      throw HermesBridgeServiceManagerError.invalidPlist("secret")
    }
  }

  private func activate(version: String) throws {
    let target = layout.versionsRoot.appendingPathComponent(version, isDirectory: true)
    guard fileManager.fileExists(atPath: target.path) else {
      throw HermesBridgeServiceManagerError.invalidLayout("missing_version")
    }
    let tmp = layout.applicationSupportRoot.appendingPathComponent(
      ".Current.tmp.\(UUID().uuidString)")
    try? fileManager.removeItem(at: tmp)
    try fileManager.createSymbolicLink(atPath: tmp.path, withDestinationPath: "Versions/\(version)")
    if rename(tmp.path, layout.currentLink.path) != 0 {
      throw HermesBridgeServiceManagerError.invalidLayout("activate_failed")
    }
  }

  private func mergedState(
    previous: HermesBridgeInstallationState?,
    installed: HermesBridgeInstalledVersion,
    previousActive: String?,
    operation: String
  ) throws -> HermesBridgeInstallationState {
    var versions = previous?.installedVersions.filter { $0.version != installed.version } ?? []
    versions.append(installed)
    return HermesBridgeInstallationState(
      activeVersion: installed.version,
      previousVersion: previousActive,
      installedVersions: versions.sorted { $0.installedAt < $1.installedAt },
      launchAgentPath: layout.launchAgentPlist.path,
      applicationSupportRoot: layout.applicationSupportRoot.path,
      lastOperation: operation,
      updatedAt: now()
    )
  }

  private func persistState(_ state: HermesBridgeInstallationState) throws {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      let data = try encoder.encode(state)
      let tmp = layout.installState.deletingLastPathComponent()
        .appendingPathComponent(".install-state.json.tmp.\(UUID().uuidString)")
      try data.write(to: tmp, options: [.atomic])
      try setPermissions(tmp, 0o600)
      if fileManager.fileExists(atPath: layout.installState.path) {
        try removeOwnedFile(layout.installState)
      }
      try fileManager.moveItem(at: tmp, to: layout.installState)
      try setPermissions(layout.installState, 0o600)
    } catch {
      throw HermesBridgeServiceManagerError.statePersistenceFailed(safeCode(error))
    }
  }

  public func loadState() throws -> HermesBridgeInstallationState? {
    guard fileManager.fileExists(atPath: layout.installState.path) else {
      return nil
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let state = try decoder.decode(
      HermesBridgeInstallationState.self, from: Data(contentsOf: layout.installState))
    guard state.schemaVersion == HermesBridgeInstallationState.currentSchemaVersion,
      state.launchAgentPath == layout.launchAgentPlist.path,
      state.applicationSupportRoot == layout.applicationSupportRoot.path
    else {
      throw HermesBridgeServiceManagerError.invalidLayout("state_mismatch")
    }
    return state
  }

  private func pruneVersions(keep: Int, active: String?, previous: String?) throws {
    guard var state = try loadState() else {
      return
    }
    let protected = Set([active, previous].compactMap { $0 })
    var versions = state.installedVersions.sorted { $0.installedAt < $1.installedAt }
    while versions.count > keep,
      let victim = versions.first(where: { !protected.contains($0.version) })
    {
      try removeOwnedDirectory(
        layout.versionsRoot.appendingPathComponent(victim.version, isDirectory: true))
      versions.removeAll { $0.version == victim.version }
    }
    state.installedVersions = versions
    try persistState(state)
  }

  private func validateInstalledPlistBoundary() throws {
    try validateLayoutRoots()
    guard fileManager.fileExists(atPath: layout.launchAgentPlist.path) else {
      throw HermesBridgeServiceManagerError.invalidLaunchctlBoundary("missing_plist")
    }
    try rejectSymlinkComponents(layout.launchAgentPlist)
    try validatePlistContents()
  }

  private func createSecureDirectory(_ url: URL) throws {
    try fileManager.createDirectory(
      at: url,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
    )
    try rejectSymlinkComponents(url)
    try setPermissions(url, 0o700)
  }

  private func setPermissions(_ url: URL, _ mode: Int16) throws {
    try fileManager.setAttributes(
      [.posixPermissions: NSNumber(value: mode)], ofItemAtPath: url.path)
    chmod(url.path, mode_t(mode))
  }

  private func isExecutableRegularFile(_ url: URL) -> Bool {
    var info = stat()
    guard lstat(url.path, &info) == 0 else {
      return false
    }
    guard (info.st_mode & S_IFMT) == S_IFREG else {
      return false
    }
    return access(url.path, X_OK) == 0
  }

  private func isSymlink(_ url: URL) -> Bool {
    var info = stat()
    guard lstat(url.path, &info) == 0 else {
      return false
    }
    return (info.st_mode & S_IFMT) == S_IFLNK
  }

  private func rejectSymlinkComponents(_ url: URL) throws {
    var current = URL(fileURLWithPath: "/", isDirectory: true)
    for component in url.standardizedFileURL.pathComponents.dropFirst() {
      current.appendPathComponent(component)
      var info = stat()
      guard lstat(current.path, &info) == 0 else {
        continue
      }
      if (info.st_mode & S_IFMT) == S_IFLNK {
        throw HermesBridgeServiceManagerError.symlinkEscape(stablePathHash(current.path))
      }
    }
  }

  private func removeOwnedFile(_ url: URL) throws {
    guard
      url.path.hasPrefix(layout.applicationSupportRoot.path)
        || url.path == layout.launchAgentPlist.path
    else {
      throw HermesBridgeServiceManagerError.invalidLayout("refusing_unowned_file")
    }
    try fileManager.removeItem(at: url)
  }

  private func removeOwnedDirectory(_ url: URL) throws {
    guard url.path.hasPrefix(layout.applicationSupportRoot.path) else {
      throw HermesBridgeServiceManagerError.invalidLayout("refusing_unowned_directory")
    }
    try rejectSymlinkComponents(url.deletingLastPathComponent())
    try fileManager.removeItem(at: url)
  }

  private func sha256(_ url: URL) throws -> String {
    let data = try Data(contentsOf: url)
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func stablePathHash(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  private func safeCode(_ error: Error) -> String {
    String(describing: type(of: error))
      .filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == ".") }
  }
}

public struct FixedLaunchctlAdapter: HermesBridgeLaunchctlAdapter {
  public init() {}

  public func bootstrap(plist: URL, layout: HermesBridgeInstallationLayout) throws {
    try ensureBoundary(plist: plist, layout: layout)
    try run(["bootstrap", domain(), plist.path])
  }

  public func bootout(plist: URL, layout: HermesBridgeInstallationLayout) throws {
    try ensureBoundary(plist: plist, layout: layout)
    try run(["bootout", domain(), plist.path])
  }

  public func kickstart(layout: HermesBridgeInstallationLayout) throws {
    try ensureProductionOrTestLabel(layout)
    try run(["kickstart", "-k", "\(domain())/\(layout.label)"])
  }

  public func printService(layout: HermesBridgeInstallationLayout) throws -> String {
    try ensureProductionOrTestLabel(layout)
    return try run(["print", "\(domain())/\(layout.label)"])
  }

  private func ensureBoundary(plist: URL, layout: HermesBridgeInstallationLayout) throws {
    try ensureProductionOrTestLabel(layout)
    guard plist.standardizedFileURL.path == layout.launchAgentPlist.standardizedFileURL.path else {
      throw HermesBridgeServiceManagerError.invalidLaunchctlBoundary("plist")
    }
  }

  private func ensureProductionOrTestLabel(_ layout: HermesBridgeInstallationLayout) throws {
    guard
      layout.label == HermesBridgeInstallationLayout.productionLabel
        || layout.label.hasPrefix("com.hermes.bridge.test.")
    else {
      throw HermesBridgeServiceManagerError.invalidLaunchctlBoundary("label")
    }
  }

  private func domain() -> String {
    "gui/\(getuid())"
  }

  @discardableResult
  private func run(_ arguments: [String]) throws -> String {
    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = arguments
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    let output =
      String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let error =
      String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    guard process.terminationStatus == 0 else {
      throw HermesBridgeServiceManagerError.launchctlFailed(redacted(output + error))
    }
    return output
  }
}

public struct CurrentHostArchitectureValidator: HermesBridgeArchitectureValidating {
  public init() {}

  public func validate(binary: URL) throws {
    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/file")
    process.arguments = [binary.path]
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    let output =
      String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    _ = stderr.fileHandleForReading.readDataToEndOfFile()
    guard process.terminationStatus == 0 else {
      throw HermesBridgeServiceManagerError.unsupportedArchitecture("file_failed")
    }
    #if arch(arm64)
      guard output.contains("arm64") || output.contains("universal") else {
        throw HermesBridgeServiceManagerError.unsupportedArchitecture("missing_arm64")
      }
    #elseif arch(x86_64)
      guard output.contains("x86_64") || output.contains("universal") else {
        throw HermesBridgeServiceManagerError.unsupportedArchitecture("missing_x86_64")
      }
    #endif
  }
}

public struct PermissiveTestArchitectureValidator: HermesBridgeArchitectureValidating {
  public init() {}
  public func validate(binary _: URL) throws {}
}

public struct ConstantHermesBridgeServiceHealthChecker: HermesBridgeServiceHealthChecking {
  private let result: HermesBridgeHealthCheckResult

  public init(result: HermesBridgeHealthCheckResult = .healthy()) {
    self.result = result
  }

  public func check(
    layout _: HermesBridgeInstallationLayout,
    launchctl _: HermesBridgeLaunchctlAdapter
  ) async -> HermesBridgeHealthCheckResult {
    result
  }
}

public struct PlutilPlistValidator: HermesBridgePlistValidating {
  public init() {}

  public func validate(plist: URL) throws {
    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
    process.arguments = ["-lint", plist.path]
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    _ = stdout.fileHandleForReading.readDataToEndOfFile()
    let error =
      String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    guard process.terminationStatus == 0 else {
      throw HermesBridgeServiceManagerError.invalidPlist(redacted(error))
    }
  }
}

public struct DefaultHermesBridgeServiceHealthChecker: HermesBridgeServiceHealthChecking {
  public init() {}

  public func check(layout: HermesBridgeInstallationLayout, launchctl: HermesBridgeLaunchctlAdapter)
    async -> HermesBridgeHealthCheckResult
  {
    guard (try? launchctl.printService(layout: layout)) != nil else {
      return .unhealthy("launchd_not_visible")
    }
    do {
      let client = HermesBridgeXPCClient(
        machServiceName: try HermesBridgeMachServiceName(layout.machService),
        timeout: 3
      )
      let capabilities = try await client.connect()
      let version = try await client.protocolVersion()
      await client.close()
      return HermesBridgeHealthCheckResult(
        filesValid: true,
        plistValid: true,
        launchdVisible: true,
        processPresent: true,
        xpcHandshakeSucceeded: version.version.major == HermesBridgeProtocolVersion.current.major,
        capabilitiesSucceeded: capabilities.capabilities.contains(.protocolVersion),
        failureCode: nil
      )
    } catch {
      return HermesBridgeHealthCheckResult(
        filesValid: true,
        plistValid: true,
        launchdVisible: true,
        processPresent: true,
        xpcHandshakeSucceeded: false,
        capabilitiesSucceeded: false,
        failureCode: "xpc_unavailable"
      )
    }
  }
}

private func redacted(_ value: String) -> String {
  String(
    value
      .filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "." || $0 == "-") }
      .prefix(96)
  )
}
