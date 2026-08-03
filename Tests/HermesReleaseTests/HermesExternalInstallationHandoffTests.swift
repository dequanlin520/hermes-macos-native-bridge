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

  private func read(_ relativePath: String) throws -> String {
    try String(contentsOf: repoRoot().appendingPathComponent(relativePath), encoding: .utf8)
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
