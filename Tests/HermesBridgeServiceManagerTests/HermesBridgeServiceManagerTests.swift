import Darwin
import Foundation
import XCTest

@testable import HermesBridgeServiceManager

final class HermesBridgeServiceManagerTests: XCTestCase {
  private var root: URL!
  private var layout: HermesBridgeInstallationLayout!
  private var launchctl: FakeLaunchctl!
  private var health: FakeHealthChecker!

  override func setUpWithError() throws {
    root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("artifacts/m3-001/unit-\(UUID().uuidString)", isDirectory: true)
    layout = HermesBridgeInstallationLayout(
      homeRoot: root.appendingPathComponent("fake-home", isDirectory: true),
      label: "com.hermes.bridge.test.unit",
      machService: "com.hermes.bridge.test.unit.xpc"
    )
    launchctl = FakeLaunchctl()
    health = FakeHealthChecker()
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: root)
  }

  func testLayoutGeneration() throws {
    XCTAssertTrue(
      layout.applicationSupportRoot.path.hasSuffix("Library/Application Support/HermesBridge"))
    XCTAssertTrue(layout.versionsRoot.path.hasSuffix("HermesBridge/Versions"))
    XCTAssertTrue(
      layout.launchAgentPlist.path.hasSuffix(
        "Library/LaunchAgents/com.hermes.bridge.test.unit.plist"))
  }

  func testPermissionCreation() async throws {
    _ = try await manager().install(serviceBinary: try binary(version: "one"))
    for url in [
      layout.applicationSupportRoot, layout.versionsRoot, layout.runtimeRoot, layout.stateRoot,
      layout.logsRoot,
    ] {
      XCTAssertEqual(try permissions(url), 0o700)
    }
    XCTAssertEqual(try permissions(layout.launchAgentPlist), 0o600)
  }

  func testSymlinkRootRejection() throws {
    let real = root.appendingPathComponent("real-home", isDirectory: true)
    let link = root.appendingPathComponent("link-home", isDirectory: true)
    try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
    let symlinkLayout = HermesBridgeInstallationLayout(
      homeRoot: link, label: "com.hermes.bridge.test.unit",
      machService: "com.hermes.bridge.test.unit.xpc")
    XCTAssertThrowsError(
      try manager(layout: symlinkLayout).planInstall(serviceBinary: try binary(version: "one")))
  }

  func testBinaryValidation() throws {
    let plan = try manager().planInstall(
      serviceBinary: try binary(version: "one"), options: .init(version: "1.0.0"))
    XCTAssertEqual(plan.version, "1.0.0")
    XCTAssertTrue(plan.stagedBinaryPath.hasSuffix("/Versions/1.0.0/HermesBridgeService"))
  }

  func testRejectsNonExecutableBinary() throws {
    let url = try binary(version: "one", executable: false)
    XCTAssertThrowsError(try manager().planInstall(serviceBinary: url))
  }

  func testRejectsBinarySymlink() throws {
    let real = try binary(version: "one")
    let link = root.appendingPathComponent("HermesBridgeService")
    try? FileManager.default.removeItem(at: link)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
    XCTAssertThrowsError(try manager().planInstall(serviceBinary: link))
  }

  func testArchitectureValidationFailure() throws {
    XCTAssertThrowsError(
      try manager(architecture: FailingArchitectureValidator()).planInstall(
        serviceBinary: try binary(version: "one"))
    ) {
      XCTAssertEqual($0 as? HermesBridgeServiceManagerError, .unsupportedArchitecture("test"))
    }
  }

  func testVersionedStagingAndAtomicActivation() async throws {
    _ = try await manager().install(
      serviceBinary: try binary(version: "one"), options: .init(version: "1.0.0"))
    let active = try FileManager.default.destinationOfSymbolicLink(atPath: layout.currentLink.path)
    XCTAssertEqual(active, "Versions/1.0.0")
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: layout.versionsRoot.appendingPathComponent("1.0.0/HermesBridgeService").path))
  }

  func testPlistGenerationAndValidation() async throws {
    _ = try await manager().install(
      serviceBinary: try binary(version: "one"), options: .init(version: "1.0.0"))
    let data = try Data(contentsOf: layout.launchAgentPlist)
    let plist = try XCTUnwrap(
      PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        as? [String: Any])
    XCTAssertEqual(plist["Label"] as? String, layout.label)
    XCTAssertEqual(
      plist["ProgramArguments"] as? [String],
      [layout.versionsRoot.appendingPathComponent("1.0.0/HermesBridgeService").path])
  }

  func testFixedLabelAndMachService() async throws {
    _ = try await manager().install(serviceBinary: try binary(version: "one"))
    let text = try String(contentsOf: layout.launchAgentPlist, encoding: .utf8)
    XCTAssertTrue(text.contains(layout.label))
    XCTAssertTrue(text.contains(layout.machService))
  }

  func testInstallStateAtomicPersistence() async throws {
    let state = try await manager().install(
      serviceBinary: try binary(version: "one"), options: .init(version: "1"))
    XCTAssertEqual(state.activeVersion, "1")
    let loaded = try manager().loadState()
    XCTAssertEqual(loaded?.activeVersion, "1")
    XCTAssertFalse(try String(contentsOf: layout.installState).contains(root.path + "/source"))
  }

  func testInstallIdempotency() async throws {
    _ = try await manager().install(
      serviceBinary: try binary(version: "one"), options: .init(version: "1"))
    _ = try await manager().install(
      serviceBinary: try binary(version: "one"), options: .init(version: "1"))
    XCTAssertEqual(try manager().loadState()?.installedVersions.count, 1)
  }

  func testBootstrapExactCommand() async throws {
    _ = try await manager().install(
      serviceBinary: try binary(version: "one"), options: .init(version: "1"))
    try manager().bootstrap()
    XCTAssertEqual(
      launchctl.commands.last, "bootstrap gui/\(getuid()) \(layout.launchAgentPlist.path)")
  }

  func testBootoutExactCommand() async throws {
    _ = try await manager().install(
      serviceBinary: try binary(version: "one"), options: .init(version: "1"))
    try manager().stop()
    XCTAssertEqual(
      launchctl.commands.last, "bootout gui/\(getuid()) \(layout.launchAgentPlist.path)")
  }

  func testStatusNotInstalled() async throws {
    let status = await manager().status()
    XCTAssertEqual(status, .notInstalled)
  }

  func testStatusInstalledStopped() async throws {
    _ = try await manager().install(serviceBinary: try binary(version: "one"))
    let status = await manager().status()
    XCTAssertEqual(status, .installedStopped)
  }

  func testStatusHealthy() async throws {
    _ = try await manager().install(
      serviceBinary: try binary(version: "one"), options: .init(bootstrap: true))
    let status = await manager().status()
    XCTAssertEqual(status, .runningHealthy)
  }

  func testStatusUnhealthy() async throws {
    _ = try await manager().install(
      serviceBinary: try binary(version: "one"), options: .init(bootstrap: true))
    health.result = .init(
      filesValid: true, plistValid: true, launchdVisible: true, processPresent: true,
      xpcHandshakeSucceeded: false, capabilitiesSucceeded: false, failureCode: "xpc_timeout")
    let status = await manager().status()
    XCTAssertEqual(status, .runningUnhealthy)
  }

  func testXPCHealthCheckSuccess() async throws {
    let result = await health.check(layout: layout, launchctl: launchctl)
    XCTAssertTrue(result.xpcHandshakeSucceeded)
    XCTAssertTrue(result.capabilitiesSucceeded)
  }

  func testXPCHealthCheckTimeout() async throws {
    health.result = .unhealthy("xpc_timeout")
    let result = await health.check(layout: layout, launchctl: launchctl)
    XCTAssertEqual(result.failureCode, "xpc_timeout")
  }

  func testUpgradeSuccess() async throws {
    _ = try await manager().install(
      serviceBinary: try binary(version: "one"), options: .init(version: "1", bootstrap: true))
    _ = try await manager().upgrade(
      serviceBinary: try binary(version: "two"), options: .init(version: "2", bootstrap: true))
    let state = try XCTUnwrap(try manager().loadState())
    XCTAssertEqual(state.activeVersion, "2")
    XCTAssertEqual(state.previousVersion, "1")
  }

  func testUpgradeHealthFailureRollsBackAutomatically() async throws {
    _ = try await manager().install(
      serviceBinary: try binary(version: "one"), options: .init(version: "1", bootstrap: true))
    health.result = .unhealthy("capabilities_failed")
    await XCTAssertThrowsAsyncError(
      try await manager().upgrade(
        serviceBinary: try binary(version: "two"), options: .init(version: "2", bootstrap: true))
    )
    XCTAssertEqual(try manager().loadState()?.activeVersion, "1")
    XCTAssertEqual(
      try FileManager.default.destinationOfSymbolicLink(atPath: layout.currentLink.path),
      "Versions/1")
  }

  func testExplicitRollback() async throws {
    _ = try await manager().install(
      serviceBinary: try binary(version: "one"), options: .init(version: "1", bootstrap: true))
    _ = try await manager().upgrade(
      serviceBinary: try binary(version: "two"), options: .init(version: "2", bootstrap: true))
    _ = try await manager().rollback()
    XCTAssertEqual(try manager().loadState()?.activeVersion, "1")
  }

  func testBoundedVersionRetention() async throws {
    _ = try await manager().install(
      serviceBinary: try binary(version: "one"), options: .init(version: "1", keepVersions: 2))
    _ = try await manager().upgrade(
      serviceBinary: try binary(version: "two"),
      options: .init(version: "2", bootstrap: true, keepVersions: 2))
    _ = try await manager().upgrade(
      serviceBinary: try binary(version: "three"),
      options: .init(version: "3", bootstrap: true, keepVersions: 2))
    let versions = try FileManager.default.contentsOfDirectory(atPath: layout.versionsRoot.path)
    XCTAssertLessThanOrEqual(versions.filter { !$0.hasPrefix(".") }.count, 2)
  }

  func testUninstallPreservesStateAndLogs() async throws {
    _ = try await manager().install(serviceBinary: try binary(version: "one"))
    try "state".write(
      to: layout.stateRoot.appendingPathComponent("kept"), atomically: true, encoding: .utf8)
    try "log".write(
      to: layout.logsRoot.appendingPathComponent("kept"), atomically: true, encoding: .utf8)
    try manager().uninstall()
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: layout.stateRoot.appendingPathComponent("kept").path))
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: layout.logsRoot.appendingPathComponent("kept").path))
  }

  func testPurgeStateOnlyWhenExplicit() async throws {
    _ = try await manager().install(serviceBinary: try binary(version: "one"))
    try "state".write(
      to: layout.stateRoot.appendingPathComponent("purged"), atomically: true, encoding: .utf8)
    try manager().uninstall(purgeState: true)
    XCTAssertFalse(FileManager.default.fileExists(atPath: layout.stateRoot.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: layout.logsRoot.path))
  }

  func testUninstallIdempotency() async throws {
    _ = try await manager().install(serviceBinary: try binary(version: "one"))
    try manager().uninstall()
    try manager().uninstall()
    XCTAssertFalse(FileManager.default.fileExists(atPath: layout.launchAgentPlist.path))
  }

  func testNoUnrelatedLaunchAgentModification() async throws {
    try FileManager.default.createDirectory(
      at: layout.launchAgentsRoot, withIntermediateDirectories: true)
    let unrelated = layout.launchAgentsRoot.appendingPathComponent("com.example.other.plist")
    try "keep".write(to: unrelated, atomically: true, encoding: .utf8)
    _ = try await manager().install(serviceBinary: try binary(version: "one"))
    try manager().uninstall()
    XCTAssertEqual(try String(contentsOf: unrelated), "keep")
  }

  func testNoArbitraryLaunchctlCommandSurface() async throws {
    _ = try await manager().install(serviceBinary: try binary(version: "one"))
    try manager().bootstrap()
    try manager().stop()
    XCTAssertTrue(
      launchctl.commands.allSatisfy { command in
        command.contains("com.hermes.bridge.test.unit.plist")
          || command.contains("com.hermes.bridge.test.unit")
      })
  }

  func testNoBackendTokenInMetadataPlistOrLogs() async throws {
    _ = try await manager().install(
      serviceBinary: try binary(version: "one"), options: .init(version: "1", bootstrap: true))
    let combined = try [
      String(contentsOf: layout.installState),
      String(contentsOf: layout.launchAgentPlist),
      launchctl.commands.joined(separator: "\n"),
    ].joined(separator: "\n")
    XCTAssertFalse(combined.localizedCaseInsensitiveContains("token"))
    XCTAssertFalse(combined.localizedCaseInsensitiveContains("prompt"))
    XCTAssertFalse(combined.contains("HERMES_DASHBOARD_SESSION_TOKEN"))
  }

  func testTemporaryIntegrationInstallRootShape() async throws {
    _ = try await manager().install(serviceBinary: try binary(version: "one"))
    XCTAssertTrue(layout.applicationSupportRoot.path.contains("/artifacts/m3-001/"))
    XCTAssertNotEqual(
      layout.launchAgentPlist.path,
      NSHomeDirectory() + "/Library/LaunchAgents/com.hermes.bridge.plist"
    )
  }

  func testNoResidualTemporaryServiceProcess() throws {
    let output = try shell(
      "pgrep -fl 'com.hermes.bridge.test.m3-001|com.hermes.bridge.test.unit' || true")
    XCTAssertTrue(output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
  }

  private func manager(
    layout: HermesBridgeInstallationLayout? = nil,
    architecture: HermesBridgeArchitectureValidating = PermissiveTestArchitectureValidator()
  ) -> HermesBridgeServiceManager {
    HermesBridgeServiceManager(
      layout: layout ?? self.layout,
      launchctl: launchctl,
      architectureValidator: architecture,
      healthChecker: health
    )
  }

  private func binary(version: String, executable: Bool = true) throws -> URL {
    let dir = root.appendingPathComponent("source-\(version)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("HermesBridgeService")
    try "#!/bin/zsh\n# \(version)\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: NSNumber(value: Int16(executable ? 0o700 : 0o600))],
      ofItemAtPath: url.path
    )
    return url
  }

  private func permissions(_ url: URL) throws -> Int {
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    return ((attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o777
  }
}

private final class FakeLaunchctl: HermesBridgeLaunchctlAdapter, @unchecked Sendable {
  var commands: [String] = []
  var visible = false

  func bootstrap(plist: URL, layout _: HermesBridgeInstallationLayout) throws {
    visible = true
    commands.append("bootstrap gui/\(getuid()) \(plist.path)")
  }

  func bootout(plist: URL, layout _: HermesBridgeInstallationLayout) throws {
    visible = false
    commands.append("bootout gui/\(getuid()) \(plist.path)")
  }

  func kickstart(layout: HermesBridgeInstallationLayout) throws {
    visible = true
    commands.append("kickstart -k gui/\(getuid())/\(layout.label)")
  }

  func printService(layout: HermesBridgeInstallationLayout) throws -> String {
    guard visible else {
      throw HermesBridgeServiceManagerError.launchctlFailed("not_visible")
    }
    commands.append("print gui/\(getuid())/\(layout.label)")
    return "label=\(layout.label)"
  }
}

private final class FakeHealthChecker: HermesBridgeServiceHealthChecking, @unchecked Sendable {
  var result = HermesBridgeHealthCheckResult.healthy()

  func check(
    layout _: HermesBridgeInstallationLayout,
    launchctl _: HermesBridgeLaunchctlAdapter
  ) async -> HermesBridgeHealthCheckResult {
    result
  }
}

private struct FailingArchitectureValidator: HermesBridgeArchitectureValidating {
  func validate(binary _: URL) throws {
    throw HermesBridgeServiceManagerError.unsupportedArchitecture("test")
  }
}

private func shell(_ command: String) throws -> String {
  let process = Process()
  let stdout = Pipe()
  let stderr = Pipe()
  process.executableURL = URL(fileURLWithPath: "/bin/zsh")
  process.arguments = ["-lc", command]
  process.standardOutput = stdout
  process.standardError = stderr
  try process.run()
  process.waitUntilExit()
  let output =
    String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
  let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
  guard process.terminationStatus == 0 else {
    throw NSError(
      domain: "ShellError", code: Int(process.terminationStatus),
      userInfo: [NSLocalizedDescriptionKey: output + error])
  }
  return output
}

private func XCTAssertThrowsAsyncError<T>(
  _ expression: @autoclosure () async throws -> T,
  file: StaticString = #filePath,
  line: UInt = #line,
  _ errorHandler: (Error) -> Void = { _ in }
) async {
  do {
    _ = try await expression()
    XCTFail("Expected async error", file: file, line: line)
  } catch {
    errorHandler(error)
  }
}
