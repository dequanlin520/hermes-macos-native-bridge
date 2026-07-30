import Foundation
import XCTest

final class HermesReleaseFreezePreflightTests: XCTestCase {
  private var root: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private func read(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }

  private func json(_ path: String) throws -> [String: Any] {
    let data = try Data(contentsOf: root.appendingPathComponent(path))
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  func testFreezeManifestSchema() throws {
    let manifest = try json("Docs/Release/V0_1ReleaseFreezeManifest.json")

    XCTAssertEqual(manifest["schemaVersion"] as? Int, 1)
    XCTAssertEqual(manifest["productName"] as? String, "Hermes Bridge")
    XCTAssertEqual(manifest["targetVersion"] as? String, "0.1.0")
    XCTAssertEqual(manifest["supportedArchitecture"] as? String, "arm64")
    XCTAssertEqual(manifest["minimumMacOSVersion"] as? String, "13.0")
    XCTAssertEqual(manifest["xpcProtocolVersion"] as? String, "1.8")
    XCTAssertNotNil(manifest["sourceCommit"])
    XCTAssertEqual(manifest["signingState"] as? String, "not-claimed-by-freeze-manifest")
    XCTAssertEqual(manifest["notarizationState"] as? String, "not-claimed-by-freeze-manifest")
  }

  func testProductionTargetInventory() throws {
    let manifest = try json("Docs/Release/V0_1ReleaseFreezeManifest.json")
    let productionTargets = try XCTUnwrap(manifest["productionTargets"] as? [String])

    XCTAssertTrue(productionTargets.contains("HermesBridgeApp"))
    XCTAssertTrue(productionTargets.contains("HermesBridgeService"))
    XCTAssertTrue(productionTargets.contains("HermesBridgeControl"))
    XCTAssertTrue(productionTargets.contains("HermesBridgeServiceLifecycle"))
    XCTAssertFalse(productionTargets.contains("HermesBridgeAppAcceptanceHarness"))
  }

  func testTestAndAcceptanceExclusionIsExplicit() throws {
    let manifest = try json("Docs/Release/V0_1ReleaseFreezeManifest.json")
    let excluded = try XCTUnwrap(manifest["excludedAcceptanceTestTargets"] as? [String])
    let script = try read("Scripts/m14_001_release_freeze_preflight.sh")

    XCTAssertTrue(excluded.contains("HermesBridgeAppAcceptanceHarness"))
    XCTAssertTrue(excluded.contains("HermesBridgeAppAcceptanceSupport"))
    XCTAssertTrue(excluded.contains("M8001ReleaseCandidateAcceptance"))
    XCTAssertTrue(excluded.contains("Tests"))
    XCTAssertTrue(script.contains("ACCEPTANCE_SUPPORT_INCLUDED"))
    XCTAssertTrue(script.contains("TEST_EXECUTABLE_INCLUDED"))
    XCTAssertTrue(script.contains("ARTIFACT_RESULT_INCLUDED"))
    XCTAssertTrue(script.contains("PRODUCTION_TARGETS_ONLY"))
  }

  func testXPCProtocol18IsRequired() throws {
    let script = try read("Scripts/m14_001_release_freeze_preflight.sh")
    let xpcModels = try read("Sources/HermesBridgeXPC/HermesBridgeXPCModels.swift")

    XCTAssertTrue(xpcModels.contains("HermesBridgeProtocolVersion(major: 1, minor: 8)"))
    XCTAssertTrue(script.contains("XPC_PROTOCOL_1_8"))
    XCTAssertTrue(script.contains("case agentDiscovery|case discoverAgent"))
  }

  func testEntitlementPolicy() throws {
    let script = try read("Scripts/m14_001_release_freeze_preflight.sh")
    let appEntitlements = try read("Packaging/Entitlements/HermesBridgeApp.entitlements")
    let serviceEntitlements = try read("Packaging/Entitlements/HermesBridgeService.entitlements")

    XCTAssertTrue(script.contains("com.apple.security.get-task-allow"))
    XCTAssertTrue(script.contains("com.apple.security.cs.disable-library-validation"))
    XCTAssertTrue(script.contains("com.apple.security.temporary-exception"))
    XCTAssertTrue(script.contains("HARDENED_RUNTIME_READY"))
    XCTAssertFalse(appEntitlements.contains("com.apple.security.get-task-allow"))
    XCTAssertFalse(serviceEntitlements.contains("com.apple.security.get-task-allow"))
  }

  func testSafeAgentDiscoveryStatus() throws {
    let script = try read("Scripts/m14_001_release_freeze_preflight.sh")
    let helper = try read("Sources/HermesReleaseAgentPreflight/HermesReleaseAgentPreflight.swift")

    XCTAssertTrue(script.contains("HermesReleaseAgentPreflight"))
    XCTAssertTrue(script.contains("available|unavailable|incompatible|unknown"))
    XCTAssertTrue(helper.contains("HermesBridgeServiceConfiguration.productionDefault()"))
    XCTAssertTrue(helper.contains("HermesDiscovery"))
    XCTAssertTrue(helper.contains("CommandLine.arguments.dropFirst().first == \"m14-005-inspect\""))
    XCTAssertTrue(helper.contains("process.processIdentifier > 1"))
    XCTAssertFalse(helper.contains("[\"stop\", \"--help\"]"))
    XCTAssertFalse(helper.contains("\"serve\", \"--stop\""))
  }

  func testPathAndSecretRedactionChecks() throws {
    let script = try read("Scripts/m14_001_release_freeze_preflight.sh")

    XCTAssertTrue(script.contains("AGENT_PATH_EXPOSED"))
    XCTAssertTrue(script.contains("DEVELOPER_PATH_EXPOSED"))
    XCTAssertTrue(script.contains("TOKEN_EXPOSED"))
    XCTAssertTrue(script.contains("PRIVATE_KEY_EXPOSED"))
    XCTAssertTrue(script.contains("BEGIN (RSA |OPENSSH |EC |DSA |)?PRIVATE KEY"))
    XCTAssertFalse(script.contains("print \"$SIGNING_IDENTITY\""))
    XCTAssertFalse(script.contains("print \"$NOTARY_PROFILE\""))
  }

  func testResultKeyCatalogIsCompleteAndUnique() throws {
    let script = try read("Scripts/m14_001_release_freeze_preflight.sh")
    let keys = try extractOrderedKeys(from: script)
    let required = [
      "V0_1_SCOPE_FROZEN", "FREEZE_MANIFEST_CREATED", "SOURCE_COMMIT_RECORDED",
      "APPLE_SILICON_CONFIRMED", "MACOS_VERSION_SUPPORTED", "SWIFT_TOOLCHAIN_AVAILABLE",
      "XCODE_AVAILABLE", "RELEASE_APP_BUILT", "APP_EXECUTABLE_PRESENT",
      "SERVICE_EXECUTABLE_PRESENT", "CONTROL_EXECUTABLE_PRESENT",
      "LIFECYCLE_EXECUTABLE_PRESENT", "INFO_PLIST_VALID", "BUNDLE_IDENTIFIERS_VALID",
      "XPC_PROTOCOL_1_8", "LAUNCH_TEMPLATE_VALID", "PRODUCTION_TARGETS_ONLY",
      "ACCEPTANCE_SUPPORT_INCLUDED", "TEST_EXECUTABLE_INCLUDED",
      "ARTIFACT_RESULT_INCLUDED", "HARDENED_RUNTIME_READY", "GET_TASK_ALLOW_PRESENT",
      "DANGEROUS_ENTITLEMENT_PRESENT", "SIGNING_IDENTITY_AVAILABLE",
      "NOTARY_PROFILE_AVAILABLE", "HERMES_AGENT_STATUS", "AGENT_PATH_EXPOSED",
      "DEVELOPER_PATH_EXPOSED", "TOKEN_EXPOSED", "PRIVATE_KEY_EXPOSED",
      "APPLICATIONS_MODIFIED", "USER_LAUNCH_AGENTS_MODIFIED",
      "REAL_HERMES_HOME_MODIFIED", "GENERATED_ARTIFACT_TRACKED_BY_GIT",
      "RELEASE_READINESS", "M14_001_RESULT",
    ]

    XCTAssertEqual(keys, required)
    XCTAssertEqual(Set(keys).count, keys.count)
    XCTAssertTrue(script.contains("Duplicate result key"))
    XCTAssertTrue(script.contains("Missing result key"))
  }

  func testNoPermanentSystemMutationCommands() throws {
    let script = try read("Scripts/m14_001_release_freeze_preflight.sh")

    XCTAssertFalse(script.contains("sudo"))
    XCTAssertFalse(script.contains("killall"))
    XCTAssertFalse(script.contains("pkill"))
    XCTAssertFalse(script.contains("launchctl bootstrap"))
    XCTAssertFalse(script.contains("launchctl bootout"))
    XCTAssertFalse(script.contains("notarytool submit"))
    XCTAssertFalse(script.contains("curl "))
    XCTAssertFalse(script.contains("ditto "))
  }

  func testReleaseStateDecisionRules() throws {
    let script = try read("Scripts/m14_001_release_freeze_preflight.sh")

    XCTAssertTrue(script.contains("ready-for-local-beta"))
    XCTAssertTrue(script.contains("ready-for-signing"))
    XCTAssertTrue(script.contains("blocked"))
    XCTAssertTrue(script.contains("SIGNING_IDENTITY_AVAILABLE") && script.contains("NOTARY_PROFILE_AVAILABLE"))
    XCTAssertTrue(script.contains("M14_001_RESULT]=PASS"))
    XCTAssertTrue(script.contains("M14_001_RESULT]=FAIL"))
  }

  func testDocumentationExistsAndCapturesBoundaries() throws {
    let doc = try read("Docs/Release/V0_1ReleaseFreezeAndPreflight.md")

    XCTAssertTrue(doc.contains("Frozen V0.1 Scope"))
    XCTAssertTrue(doc.contains("Deferred Scope"))
    XCTAssertTrue(doc.contains("Preflight Checks"))
    XCTAssertTrue(doc.contains("Real-System Boundaries"))
    XCTAssertTrue(doc.contains("Local Beta Criteria"))
    XCTAssertTrue(doc.contains("Production Release Criteria"))
    XCTAssertTrue(doc.contains("Known Blockers"))
  }

  private func extractOrderedKeys(from script: String) throws -> [String] {
    let pattern = #"ORDERED_KEYS=\(\n(?<body>.*?)\n\)"#
    let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
    let range = NSRange(script.startIndex..., in: script)
    let match = try XCTUnwrap(regex.firstMatch(in: script, range: range))
    let bodyRange = try XCTUnwrap(Range(match.range(withName: "body"), in: script))
    return script[bodyRange]
      .split { $0 == " " || $0 == "\n" || $0 == "\t" }
      .map(String.init)
  }
}
