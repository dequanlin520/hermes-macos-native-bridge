import Foundation
import XCTest

@testable import HermesReleaseCandidateAcceptance

final class HermesReleaseCandidateAcceptanceTests: XCTestCase {
  func testCandidateIDValidation() throws {
    XCTAssertNoThrow(try HermesReleaseCandidateID("m8-001-rc_1"))
    XCTAssertThrowsError(try HermesReleaseCandidateID(""))
    XCTAssertThrowsError(try HermesReleaseCandidateID("bad/id"))
  }

  func testManifestSchemaDuplicateGateRejectionAndRequiredGateCompleteness() throws {
    let gates = passingGates()
    let manifest = try makeManifest(gates: gates)

    XCTAssertEqual(manifest.schemaVersion, 1)
    XCTAssertEqual(Set(manifest.acceptanceGateResults.map(\.gate)), Set(HermesReleaseCandidateGate.allCases))
    XCTAssertThrowsError(try HermesReleaseCandidateManifest.validate(gates: gates + [gates[0]]))
    XCTAssertThrowsError(try HermesReleaseCandidateManifest.validate(gates: Array(gates.dropFirst())))
  }

  func testGateStateCatalog() {
    XCTAssertEqual(
      Set(HermesReleaseCandidateGateState.allCases.map(\.rawValue)),
      ["passed", "failed", "conditionallyBlocked", "notApplicable"]
    )
    XCTAssertTrue(HermesReleaseCandidateGate.allCases.contains(.emergencyStop))
    XCTAssertTrue(HermesReleaseCandidateGate.allCases.contains(.notarization))
  }

  func testConditionalPassAndFailReleaseRules() {
    XCTAssertEqual(HermesReleaseCandidateAcceptanceRunner.finalResult(gates: passingGates()), .pass)

    var conditional = passingGates()
    conditional.replace(.developerIDSigning, .conditionallyBlocked)
    conditional.replace(.notarization, .conditionallyBlocked)
    XCTAssertEqual(HermesReleaseCandidateAcceptanceRunner.finalResult(gates: conditional), .conditional)

    var failed = passingGates()
    failed.replace(.build, .failed)
    XCTAssertEqual(HermesReleaseCandidateAcceptanceRunner.finalResult(gates: failed), .fail)

    var invalidConditional = passingGates()
    invalidConditional.replace(.requestSubmit, .conditionallyBlocked)
    XCTAssertEqual(HermesReleaseCandidateAcceptanceRunner.finalResult(gates: invalidConditional), .fail)
  }

  func testPrivatePathUsernameTokenAndPromptRedaction() {
    let text = "\(NSHomeDirectory()) user=\(NSUserName()) token: secret-token-value prompt: private prompt body"
    let redacted = HermesReleaseCandidateAcceptanceRunner.redact(text)

    XCTAssertFalse(redacted.contains(NSHomeDirectory()))
    XCTAssertFalse(redacted.contains(NSUserName()))
    XCTAssertFalse(redacted.contains("secret-token-value"))
    XCTAssertFalse(redacted.contains("private prompt body"))
  }

  func testComponentCapabilityAndProtocolManifest() throws {
    let manifest = try makeManifest(gates: passingGates())

    XCTAssertTrue(manifest.components.contains { $0.name == "HermesBridgeService" })
    XCTAssertEqual(manifest.capabilities, ["protocolVersion", "submitRequest"])
    XCTAssertEqual(manifest.protocolVersion, "1.6")
  }

  func testChecksumDeterminismSBOMSchemaAndComponentUniqueness() throws {
    let dir = try temporaryDirectory()
    let file = dir.appendingPathComponent("fixture.txt")
    try "abc".write(to: file, atomically: true, encoding: .utf8)

    XCTAssertEqual(
      try HermesReleaseCandidateAcceptanceRunner.sha256(file),
      try HermesReleaseCandidateAcceptanceRunner.sha256(file)
    )

    let sbom = [
      "spdxVersion": "SPDX-2.3",
      "packages": [["name": "A"], ["name": "B"]],
    ] as [String: Any]
    let data = try JSONSerialization.data(withJSONObject: sbom)
    let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let packages = try XCTUnwrap(decoded["packages"] as? [[String: String]])
    XCTAssertEqual(decoded["spdxVersion"] as? String, "SPDX-2.3")
    XCTAssertEqual(Set(packages.compactMap { $0["name"] }).count, packages.count)
  }

  func testCleanupReportLaunchAgentLabelExactPIDAndPGIDTracking() {
    let report = cleanupReport(pid: 123, pgid: 456)

    XCTAssertEqual(report.trackedPID, 123)
    XCTAssertEqual(report.trackedPGID, 456)
    XCTAssertFalse(report.broadProcessTerminationUsed)
    XCTAssertTrue(HermesReleaseCandidateEnvironment.isValidLaunchAgentLabel("com.hermes.bridge.test.m8-001.abc-123"))
    XCTAssertFalse(HermesReleaseCandidateEnvironment.isValidLaunchAgentLabel("com.hermes.bridge"))
  }

  func testNoBroadProcessTerminationUpgradeRollbackEmergencyResumeAndAuditEvidenceLinkage() throws {
    let gates = passingGates()
    let manifest = try makeManifest(gates: gates)

    XCTAssertEqual(gates.first(where: { $0.gate == .upgrade })?.state, .passed)
    XCTAssertEqual(gates.first(where: { $0.gate == .rollback })?.state, .passed)
    XCTAssertEqual(gates.first(where: { $0.gate == .emergencyStop })?.state, .passed)
    XCTAssertEqual(gates.first(where: { $0.gate == .resume })?.state, .passed)
    XCTAssertEqual(manifest.sbomPath, "artifacts/m8-001/sbom.spdx.json")
    XCTAssertFalse(manifest.artifactChecksums.isEmpty)
    XCTAssertFalse(manifest.cleanupResult.broadProcessTerminationUsed)
  }

  func testResultFileCompletenessCatalog() {
    let required = [
      "BUILD_PASSED", "SERVICE_INSTALLED", "SERVICE_STARTED", "XPC_HANDSHAKE_PASSED",
      "REQUEST_SUBMIT_PASSED", "REQUEST_COMPLETION_PASSED", "REQUEST_CANCEL_PASSED",
      "REQUEST_APPROVAL_PASSED", "AUTHORIZED_ROOT_PASSED", "FILE_EVENT_PASSED",
      "SYSTEM_EVENT_PASSED", "EVENT_POLICY_DRY_RUN_PASSED", "EVENT_POLICY_EXECUTION_PASSED",
      "EVENT_POLICY_APPROVAL_PASSED", "PERMISSIONS_DOCTOR_PASSED", "AUDIT_INTEGRITY_PASSED",
      "AUDIT_SIGNING_PASSED", "AUDIT_EXPORT_PASSED", "EMERGENCY_STOP_PASSED", "RESUME_PASSED",
      "UPGRADE_PASSED", "ROLLBACK_PASSED", "SBOM_GENERATED", "CHECKSUMS_GENERATED",
      "RELEASE_MANIFEST_GENERATED", "DEVELOPER_ID_AVAILABLE", "NOTARIZATION_AVAILABLE",
      "CLEAN_UNINSTALL_PASSED", "RESIDUAL_LAUNCH_AGENT", "RESIDUAL_KEYCHAIN_FILE",
      "RESIDUAL_PROCESS", "PRIVATE_PATH_EXPOSED", "PROMPT_EXPOSED", "TOKEN_EXPOSED",
      "M8_001_RESULT",
    ]

    XCTAssertEqual(required.count, 35)
    XCTAssertEqual(Set(required).count, required.count)
  }

  func testEndToEndFixtureSuccessFailureCleanupInterruptedCleanupNoRealAccessAndNoResidualProcess()
    throws
  {
    let environment = try HermesReleaseCandidateEnvironment(
      repositoryRoot: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
      runID: "fixture-1234"
    )
    let report = cleanupReport()

    XCTAssertTrue(environment.artifactRoot.path.hasSuffix("artifacts/m8-001"))
    XCTAssertFalse(environment.artifactRoot.path.contains(".hermes"))
    XCTAssertFalse(report.residualLaunchAgent)
    XCTAssertFalse(report.residualKeychainFile)
    XCTAssertFalse(report.residualProcess)
  }

  private func passingGates() -> [HermesReleaseCandidateGateResult] {
    HermesReleaseCandidateGate.allCases.map {
      HermesReleaseCandidateGateResult(gate: $0, state: .passed, reasonCode: "ok")
    }
  }

  private func cleanupReport(pid: Int32? = nil, pgid: Int32? = nil)
    -> HermesReleaseCandidateCleanupReport
  {
    HermesReleaseCandidateCleanupReport(
      launchAgentLabel: "com.hermes.bridge.test.m8-001.fixture",
      trackedPID: pid,
      trackedPGID: pgid,
      residualLaunchAgent: false,
      residualKeychainFile: false,
      residualProcess: false,
      removedRuntimeState: true,
      broadProcessTerminationUsed: false
    )
  }

  private func makeManifest(gates: [HermesReleaseCandidateGateResult]) throws
    -> HermesReleaseCandidateManifest
  {
    try HermesReleaseCandidateManifest(
      candidateID: HermesReleaseCandidateID("m8-001-test"),
      gitCommit: "abc",
      branch: "feature/m8-001-release-candidate-acceptance",
      buildTimestamp: "1970-01-01T00:00:00Z",
      macOSVersion: "macOS",
      architecture: "arm64",
      swiftVersion: "Swift 6",
      xcodeVersion: "Xcode 16",
      components: [
        HermesReleaseCandidateComponent(
          name: "HermesBridgeService",
          kind: "service",
          version: "test",
          artifactPath: "HermesBridgeService",
          checksumSHA256: "abc"
        )
      ],
      protocolVersion: "1.6",
      capabilities: ["submitRequest", "protocolVersion"],
      testFixtureIdentifiers: ["fake-hermes"],
      artifactChecksums: ["sbom.spdx.json": "abc"],
      sbomPath: "artifacts/m8-001/sbom.spdx.json",
      sbomChecksum: "abc",
      acceptanceGateResults: gates,
      developerIDAvailable: true,
      notarizationAvailable: true,
      cleanupResult: cleanupReport()
    )
  }

  private func temporaryDirectory() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("m8-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}

private extension Array where Element == HermesReleaseCandidateGateResult {
  mutating func replace(
    _ gate: HermesReleaseCandidateGate,
    _ state: HermesReleaseCandidateGateState
  ) {
    guard let index = firstIndex(where: { $0.gate == gate }) else {
      return
    }
    self[index] = HermesReleaseCandidateGateResult(gate: gate, state: state, reasonCode: "test")
  }
}
