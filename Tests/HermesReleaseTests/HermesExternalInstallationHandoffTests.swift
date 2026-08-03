import Foundation
import XCTest

final class HermesExternalInstallationHandoffTests: XCTestCase {
  func testChecklistCoversSecondMachineCleanUserPlan() throws {
    let checklist = try read("Docs/Release/M14_011ExternalInstallationChecklist.md")
    for marker in [
      "Apple Silicon Mac",
      "clean standard user account",
      "no existing Hermes Bridge installation",
      "Hermes Agent 0.18.2",
      "documented `PATH`",
      "shasum -a 256 -c SHA256SUMS",
      "Gatekeeper behavior",
      "operator acknowledges",
      "Copy/install the app",
      "LaunchAgent asset",
      "first time",
      "XPC connection",
      "Hermes executable discovery",
      "version discovery",
      "Start the isolated Hermes Agent",
      "`/api/status`",
      "Quit and relaunch",
      "Restart the service",
      "Stop the exact isolated Agent",
      "uninstall script",
      "residue",
      "real `~/.hermes` isolation",
      "sanitized evidence",
    ] {
      XCTAssertTrue(checklist.contains(marker), marker)
    }
  }

  func testChecklistDistinguishesFailureCategories() throws {
    let checklist = try read("Docs/Release/M14_011ExternalInstallationChecklist.md")
    for marker in [
      "Expected unsigned Gatekeeper warning",
      "Functional failure",
      "Security boundary failure",
      "Environmental incompatibility",
    ] {
      XCTAssertTrue(checklist.contains(marker), marker)
    }
  }

  func testChecklistDoesNotRequirePrivilegedOrUnsafeBypassWorkflow() throws {
    let checklist = try read("Docs/Release/M14_011ExternalInstallationChecklist.md")
    XCTAssertTrue(checklist.contains("without using `sudo`"))
    XCTAssertTrue(checklist.contains("Do not use `xattr -dr com.apple.quarantine` as the normal installation workflow."))
    XCTAssertFalse(checklist.contains("sudo "))
    XCTAssertFalse(checklist.contains("sudo\t"))
    XCTAssertFalse(checklist.contains("create permanent macOS users"))
    XCTAssertFalse(checklist.contains("weaken Gatekeeper globally"))
  }

  func testChecklistProtectsSecretsProfilesAndIdentityData() throws {
    let checklist = try read("Docs/Release/M14_011ExternalInstallationChecklist.md")
    for marker in [
      "Do not collect credentials",
      "tokens",
      "usernames",
      "identity names",
      "certificate hashes",
      "absolute paths",
      "Keychain items",
      "real Hermes profiles",
      "runtime acceptance state",
    ] {
      XCTAssertTrue(checklist.contains(marker), marker)
    }
  }

  func testRollbackDocumentIsGeneratedFromScriptAndMentionsUserScopedTargets() throws {
    let script = try read("Scripts/m14_011_rc1_publication.sh")
    let rollbackFunction = try extractFunction("write_rollback", from: script)
    for marker in [
      "uninstall-hermes-bridge-app.zsh",
      "~/Applications/Hermes macOS Native Bridge.app",
      "~/Library/LaunchAgents/com.hermes.bridge.plist",
      "~/Library/Application Support/HermesBridge",
      "~/Library/Logs/HermesBridge",
      "Do not delete or inspect real `~/.hermes` profiles",
    ] {
      XCTAssertTrue(rollbackFunction.contains(marker), marker)
    }
  }

  func testKnownLimitationsGeneratedByScriptAreHonestAboutStatusOnlyIntegration() throws {
    let script = try read("Scripts/m14_011_rc1_publication.sh")
    let function = try extractFunction("write_known_limitations", from: script)
    XCTAssertTrue(function.contains("unsigned and not notarized"))
    XCTAssertTrue(function.contains("controlled internal validation"))
    XCTAssertTrue(function.contains("status-only through `/api/status`"))
    XCTAssertTrue(function.contains("transport.route-unsupported"))
    XCTAssertFalse(function.contains("production-ready"))
    XCTAssertFalse(function.contains("safe for general public installation"))
  }

  func testGitHubDescriptorContainsPublicationReadinessMetadata() throws {
    let script = try read("Scripts/m14_011_rc1_publication.sh")
    let function = try extractFunction("write_github_descriptor", from: script)
    for marker in [
      "proposedTag",
      "proposedPrereleaseTitle",
      "artifactNames",
      "checksums",
      "releaseNotesPathCategory",
      "signingStatus",
      "notarizationStatus",
      "supportedCapabilitySummary",
      "unsupportedCapabilitySummary",
      "testedPlatformCategory",
      "testedHermesVersion",
      "xpcProtocolVersion",
      "publicDistributionAllowed",
      "blockingReasons",
      "githubReleaseCreated\": false",
      "tagCreated\": false",
    ] {
      XCTAssertTrue(function.contains(marker), marker)
    }
  }

  func testReadmeLinksTrackedRc1HandoffDocs() throws {
    let readme = try read("README.md")
    XCTAssertTrue(readme.contains("RC1 engineering validation complete"))
    XCTAssertTrue(readme.contains("unsigned internal artifact"))
    XCTAssertTrue(readme.contains("public signed release still blocked"))
    XCTAssertTrue(readme.contains("Docs/Release/v0.1.0-rc.1.md"))
    XCTAssertTrue(readme.contains("Docs/Release/M14_011ExternalInstallationChecklist.md"))
  }

  func testStandaloneInstallerContainsNoSourceBuildDependency() throws {
    let install = try read("Scripts/native/install-hermes-bridge-app.zsh")
    let uninstall = try read("Scripts/native/uninstall-hermes-bridge-app.zsh")
    for forbidden in [
      "xcodebuild",
      "swift build",
      "swift run",
      "Package.swift",
      "repo_root",
      "DerivedData",
      "Packaging/HermesBridgeApp",
      "Sources/",
      "sudo ",
    ] {
      XCTAssertFalse(install.contains(forbidden), forbidden)
      XCTAssertFalse(uninstall.contains(forbidden), forbidden)
    }
    XCTAssertTrue(install.contains("SCRIPT_DIR=\"${0:A:h}\""))
    XCTAssertTrue(install.contains("STAGING_ROOT=\"$(cd \"$SCRIPT_DIR/..\" && pwd -P)\""))
    XCTAssertTrue(install.contains("/usr/bin/ditto \"$src\" \"$tmp\""))
  }

  func testStandaloneInstallerFixtureInstallAndUninstallAreIdempotent() throws {
    let fixture = try makeStandaloneInstallerFixture()
    let unrelated = try temporaryDirectory().appendingPathComponent("unrelated", isDirectory: true)
    try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
    let fakeBin = try temporaryDirectory().appendingPathComponent("fake-bin", isDirectory: true)
    try FileManager.default.createDirectory(at: fakeBin, withIntermediateDirectories: true)
    let buildLog = fixture.home.appendingPathComponent("build-tools.log")
    for name in ["xcodebuild", "swift"] {
      let tool = fakeBin.appendingPathComponent(name)
      try "#!/bin/zsh\nprint -r -- invoked-\(name) >> '\(buildLog.path)'\nexit 99\n".write(to: tool, atomically: true, encoding: .utf8)
      try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
    }

    let environment = [
      "HOME": fixture.home.path,
      "HERMES_INSTALLER_FIXTURE_MODE": "YES",
      "PATH": "\(fakeBin.path):\(ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")",
    ]
    let installScript = fixture.staging.appendingPathComponent("Scripts/install-hermes-bridge-app.zsh")
    let uninstallScript = fixture.staging.appendingPathComponent("Scripts/uninstall-hermes-bridge-app.zsh")

    let firstInstall = try runProcess("/bin/zsh", arguments: [installScript.path, "--install-user-app"], environment: environment, currentDirectory: unrelated)
    XCTAssertEqual(firstInstall.status, 0, firstInstall.combinedOutput)
    let secondInstall = try runProcess("/bin/zsh", arguments: [installScript.path, "--install-user-app"], environment: environment, currentDirectory: unrelated)
    XCTAssertEqual(secondInstall.status, 0, secondInstall.combinedOutput)

    let installedApp = fixture.home.appendingPathComponent("Applications/Hermes macOS Native Bridge.app")
    let installedExecutable = installedApp.appendingPathComponent("Contents/MacOS/HermesBridgeApp")
    let installedPlist = fixture.home.appendingPathComponent("Library/LaunchAgents/com.hermes.bridge.plist")
    let support = fixture.home.appendingPathComponent("Library/Application Support/HermesBridge")
    XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.home.appendingPathComponent("Applications").path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.home.appendingPathComponent("Library/LaunchAgents").path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: installedExecutable.path))
    XCTAssertTrue(FileManager.default.isExecutableFile(atPath: installedExecutable.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: support.appendingPathComponent("HermesBridgeControl").path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: support.appendingPathComponent("HermesBridgeServiceLifecycle").path))
    XCTAssertEqual(try plistValue(installedPlist, keyPath: "ProgramArguments:0"), support.appendingPathComponent("HermesBridgeService").path)
    let installedPlistText = try String(contentsOf: installedPlist, encoding: .utf8)
    XCTAssertFalse(installedPlistText.contains(fixture.staging.path))
    XCTAssertFalse(installedPlistText.contains("<key>PATH</key>"))
    XCTAssertFalse(installedPlistText.contains(".local/bin"))
    XCTAssertFalse(installedPlistText.contains(fakeBin.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: buildLog.path))

    let firstUninstall = try runProcess("/bin/zsh", arguments: [uninstallScript.path, "--uninstall-user-app"], environment: environment, currentDirectory: unrelated)
    XCTAssertEqual(firstUninstall.status, 0, firstUninstall.combinedOutput)
    let secondUninstall = try runProcess("/bin/zsh", arguments: [uninstallScript.path, "--uninstall-user-app"], environment: environment, currentDirectory: unrelated)
    XCTAssertEqual(secondUninstall.status, 0, secondUninstall.combinedOutput)
    XCTAssertFalse(FileManager.default.fileExists(atPath: installedApp.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: installedPlist.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: support.appendingPathComponent("HermesBridgeService").path))
  }

  func testStandaloneInstallerMissingStagedAppReturnsPreciseNonzeroError() throws {
    let fixture = try makeStandaloneInstallerFixture()
    try FileManager.default.removeItem(at: fixture.staging.appendingPathComponent("Hermes macOS Native Bridge.app"))
    let result = try runProcess(
      "/bin/zsh",
      arguments: [fixture.staging.appendingPathComponent("Scripts/install-hermes-bridge-app.zsh").path, "--install-user-app"],
      environment: ["HOME": fixture.home.path, "HERMES_INSTALLER_FIXTURE_MODE": "YES"],
      currentDirectory: try temporaryDirectory()
    )
    XCTAssertEqual(result.status, 66, result.combinedOutput)
    XCTAssertTrue(result.stderr.contains("missing staged app:"), result.combinedOutput)
  }

  private func read(_ relativePath: String) throws -> String {
    try String(contentsOf: repoRoot().appendingPathComponent(relativePath), encoding: .utf8)
  }

  private struct StandaloneInstallerFixture {
    let staging: URL
    let home: URL
  }

  private struct CommandResult {
    let status: Int32
    let stdout: String
    let stderr: String
    var combinedOutput: String { stdout + stderr }
  }

  private func makeStandaloneInstallerFixture() throws -> StandaloneInstallerFixture {
    let root = try temporaryDirectory()
    let staging = root.appendingPathComponent("staging", isDirectory: true)
    let home = root.appendingPathComponent("home", isDirectory: true)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

    let app = staging.appendingPathComponent("Hermes macOS Native Bridge.app", isDirectory: true)
    let appExecutable = app.appendingPathComponent("Contents/MacOS/HermesBridgeApp")
    let service = app.appendingPathComponent("Contents/Library/XPCServices/HermesBridgeService.xpc/Contents/MacOS/HermesBridgeService")
    for executable in [
      appExecutable,
      service,
      staging.appendingPathComponent("bin/HermesBridgeControl"),
      staging.appendingPathComponent("bin/HermesBridgeServiceLifecycle"),
    ] {
      try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
      try "#!/bin/zsh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
      try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }

    try appInfoPlist().write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true, encoding: .utf8)
    let launchAgent = staging.appendingPathComponent("Library/LaunchAgents/com.hermes.bridge.plist")
    try FileManager.default.createDirectory(at: launchAgent.deletingLastPathComponent(), withIntermediateDirectories: true)
    try launchAgentPlist().write(to: launchAgent, atomically: true, encoding: .utf8)
    let scripts = staging.appendingPathComponent("Scripts", isDirectory: true)
    try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
    for name in ["install-hermes-bridge-app.zsh", "uninstall-hermes-bridge-app.zsh"] {
      let source = repoRoot().appendingPathComponent("Scripts/native/\(name)")
      let target = scripts.appendingPathComponent(name)
      if FileManager.default.fileExists(atPath: target.path) {
        try FileManager.default.removeItem(at: target)
      }
      try FileManager.default.copyItem(at: source, to: target)
      try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
    }
    return StandaloneInstallerFixture(staging: staging, home: home)
  }

  private func appInfoPlist() -> String {
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleExecutable</key>
      <string>HermesBridgeApp</string>
      <key>CFBundleIdentifier</key>
      <string>com.hermes.bridge.app</string>
      <key>CFBundleName</key>
      <string>Hermes macOS Native Bridge</string>
      <key>CFBundleShortVersionString</key>
      <string>0.1.0-rc.1</string>
      <key>CFBundleVersion</key>
      <string>0.1.0-rc.1</string>
    </dict>
    </plist>
    """
  }

  private func launchAgentPlist() -> String {
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>Label</key>
      <string>com.hermes.bridge</string>
      <key>MachServices</key>
      <dict>
        <key>com.hermes.bridge.xpc</key>
        <true/>
      </dict>
      <key>ProgramArguments</key>
      <array>
        <string>staged-placeholder</string>
      </array>
      <key>RunAtLoad</key>
      <true/>
      <key>StandardOutPath</key>
      <string>staged-stdout</string>
      <key>StandardErrorPath</key>
      <string>staged-stderr</string>
    </dict>
    </plist>
    """
  }

  private func plistValue(_ url: URL, keyPath: String) throws -> String {
    let result = try runProcess("/usr/libexec/PlistBuddy", arguments: ["-c", "Print :\(keyPath)", url.path])
    XCTAssertEqual(result.status, 0, result.combinedOutput)
    return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  @discardableResult
  private func runProcess(
    _ executable: String,
    arguments: [String],
    environment: [String: String] = [:],
    currentDirectory: URL? = nil
  ) throws -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = currentDirectory
    var processEnvironment = ProcessInfo.processInfo.environment
    for (key, value) in environment {
      processEnvironment[key] = value
    }
    process.environment = processEnvironment
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    return CommandResult(
      status: process.terminationStatus,
      stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
      stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    )
  }

  private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("HermesStandaloneInstallerTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func extractFunction(_ name: String, from script: String) throws -> String {
    let start = try XCTUnwrap(script.range(of: "\(name)() {"))
    let remainder = script[start.lowerBound...]
    let end = try XCTUnwrap(remainder.range(of: "\n}\n"))
    return String(remainder[..<end.upperBound])
  }

  private func repoRoot() -> URL {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<3 {
      url.deleteLastPathComponent()
    }
    return url
  }
}
