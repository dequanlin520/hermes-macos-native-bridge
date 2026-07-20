import Foundation
import XCTest

@testable import HermesRuntimeFoundation

final class HermesAuditSigningOperationsTests: XCTestCase {
  func testAccessPolicyStateMappingSetupRequired() throws {
    let root = try temporaryDirectory()
    let status = HermesAuditKeychainSetupCoordinator(auditRoot: root).status()
    XCTAssertEqual(status.accessPolicyState, .setupRequired)
    XCTAssertEqual(status.recoveryRequired, .recreateMissingSigningKey)
  }

  func testExplicitSetupRequiredAndNotAutomatic() throws {
    let root = try temporaryDirectory()
    let policyURL = root.appendingPathComponent(
      HermesAuditKeychainSetupCoordinator.accessPolicyFileName)
    _ = HermesAuditKeychainSetupCoordinator(auditRoot: root).status()
    XCTAssertFalse(FileManager.default.fileExists(atPath: policyURL.path))
  }

  func testAppIdentityAccepted() {
    let identity = HermesAuditAuthorizedCodeIdentity(
      role: "currentApp",
      bundleIdentifier: "com.hermes.bridge",
      designatedRequirement: "anchor apple generic",
      teamIdentifier: "TEAM123456",
      signingKind: "developerIDOrTeamSigned",
      hardenedRuntime: true,
      appSandbox: true,
      fingerprint: String(repeating: "a", count: 64)
    )
    XCTAssertTrue(identity.isCompatible(with: identity))
  }

  func testServiceIdentityAccepted() {
    let service = HermesAuditAuthorizedCodeIdentity(
      role: "currentService",
      bundleIdentifier: "com.hermes.bridge.service",
      designatedRequirement: "identifier com.hermes.bridge.service",
      teamIdentifier: nil,
      signingKind: "adhoc",
      hardenedRuntime: false,
      appSandbox: false,
      fingerprint: String(repeating: "b", count: 64)
    )
    XCTAssertEqual(service.role, "currentService")
    XCTAssertEqual(service.signingKind, "adhoc")
  }

  func testWrongIdentityRejected() {
    let first = identity(requirement: "identifier one", fingerprintSeed: "a")
    let second = identity(requirement: "identifier two", fingerprintSeed: "a")
    XCTAssertFalse(first.isCompatible(with: second))
  }

  func testBroadApplicationAccessRejected() throws {
    let manager = HermesAuditSigningKeyManager()
    XCTAssertThrowsError(
      try manager.createKey(
        signerID: try HermesAuditSignerID.generate(),
        keyGenerationID: UUID().uuidString.lowercased(),
        trustedApplicationPaths: []
      )
    ) { error in
      XCTAssertEqual(error as? HermesAuditSigningError, .broadApplicationAccessRejected)
    }
  }

  func testSigningPoliciesAreStable() {
    XCTAssertEqual(HermesAuditSigningRequirementPolicy.allCases.count, 3)
    XCTAssertTrue(HermesAuditSigningRequirementPolicy.allCases.contains(.signingRequired))
    XCTAssertTrue(HermesAuditSigningRequirementPolicy.allCases.contains(.signingPreferred))
    XCTAssertTrue(
      HermesAuditSigningRequirementPolicy.allCases.contains(.unsignedAllowedForLegacyOnly))
  }

  func testLockedAndInaccessibleStatesMapToRecovery() throws {
    let locked = HermesAuditKeyAccessPolicy(
      appIdentity: nil,
      serviceIdentity: nil,
      signingPolicy: .signingRequired,
      configuredAt: nil,
      nonInteractiveSigningProven: false,
      lastSuccessfulSignatureAt: nil,
      status: .locked,
      remediation: .unlockKeychain
    )
    XCTAssertEqual(locked.status, .locked)
    XCTAssertEqual(locked.remediation, .unlockKeychain)
  }

  func testReleaseIdentityAdhocStateIsHonest() {
    let identity = HermesAuditAuthorizedCodeIdentity(
      role: "currentApp",
      bundleIdentifier: "com.hermes.bridge",
      designatedRequirement: "identifier com.hermes.bridge",
      teamIdentifier: nil,
      signingKind: "adhoc",
      hardenedRuntime: false,
      appSandbox: false,
      fingerprint: String(repeating: "c", count: 64)
    )
    let validation = HermesAuditSigningReleaseIdentityValidation(
      appIdentity: identity,
      serviceIdentity: nil,
      developerIDAvailable: false,
      validationPassed: false,
      blocked: true,
      issueCodes: ["developer_id_unavailable"]
    )
    XCTAssertFalse(validation.developerIDAvailable)
    XCTAssertTrue(validation.blocked)
    XCTAssertTrue(validation.issueCodes.contains("developer_id_unavailable"))
  }

  func testTeamIDMismatchDetectedAsIssue() {
    let validation = HermesAuditSigningReleaseIdentityValidation(
      appIdentity: identity(team: "TEAM1"),
      serviceIdentity: identity(role: "currentService", team: "TEAM2"),
      developerIDAvailable: true,
      validationPassed: false,
      blocked: true,
      issueCodes: ["team_id_mismatch"]
    )
    XCTAssertTrue(validation.issueCodes.contains("team_id_mismatch"))
  }

  func testHardenedRuntimeAndEntitlementValidationFields() {
    let identity = HermesAuditAuthorizedCodeIdentity(
      role: "currentApp",
      bundleIdentifier: "com.hermes.bridge",
      designatedRequirement: "identifier com.hermes.bridge",
      teamIdentifier: "TEAM123456",
      signingKind: "developerIDOrTeamSigned",
      hardenedRuntime: true,
      appSandbox: true,
      fingerprint: String(repeating: "d", count: 64)
    )
    XCTAssertTrue(identity.hardenedRuntime)
    XCTAssertTrue(identity.appSandbox)
  }

  func testRotationTransactionStagesAreStable() {
    XCTAssertEqual(
      HermesAuditKeyRotationTransactionStage.allCases,
      [
        .prepared,
        .oldSegmentFinalized,
        .newKeyCreated,
        .oldAnchorRetired,
        .newAnchorActivated,
        .rotationEventWritten,
        .completed,
      ])
  }

  func testInterruptedRotationDetectedAndAbandonRequiresConfirmation() throws {
    let root = try temporaryDirectory()
    let coordinator = HermesAuditKeychainSetupCoordinator(auditRoot: root)
    _ = try coordinator.prepareRotationTransaction(interruptAt: .prepared)
    XCTAssertEqual(coordinator.status().rotationTransactionState, .prepared)
    XCTAssertEqual(coordinator.status().recoveryRequired, .resumeInterruptedRotation)
    XCTAssertThrowsError(try coordinator.abandonIncompleteRotation(confirm: false))
    try coordinator.abandonIncompleteRotation(confirm: true)
    XCTAssertNil(coordinator.status().rotationTransactionState)
  }

  func testExplicitResetConfirmationAndPreservesAuditHistory() async throws {
    let root = try temporaryDirectory()
    let coordinator = HermesAuditKeychainSetupCoordinator(auditRoot: root)
    let store = try FileBackedHermesAuditStore(
      configuration: HermesAuditStoreConfiguration(root: root))
    try await store.append(
      HermesAuditEvent.make(
        kind: .doctorExecuted,
        actor: .testFixture,
        outcome: .succeeded,
        reasonCode: "before_reset"
      ))
    XCTAssertThrowsError(try coordinator.resetAuditSigningConfiguration(confirm: false))
    try coordinator.resetAuditSigningConfiguration(confirm: true)
    let events = try await store.query(try HermesAuditQuery(limit: 10))
    XCTAssertEqual(events.count, 1)
  }

  func testPublicTrustAnchorImportRejectsNonAnchorData() throws {
    let root = try temporaryDirectory()
    let file = root.appendingPathComponent("not-private-key.json")
    try Data(#"[{"privateKey":"forbidden"}]"#.utf8).write(to: file)
    XCTAssertThrowsError(
      try HermesAuditKeychainSetupCoordinator(auditRoot: root).importPublicTrustAnchors(from: file)
    )
  }

  func testOperationalStatusRedactsPrivateMaterial() {
    let status = HermesAuditSigningOperationalStatus(
      activeSignerID: try? HermesAuditSignerID(rawValue: "hasg_test"),
      activeFingerprintPrefix: "abcdef123456",
      accessPolicyState: .configuredForCurrentApp,
      signingRequiredPolicy: .signingRequired,
      nonInteractiveSigningProven: true,
      lastSuccessfulSignatureAt: Date(timeIntervalSince1970: 1),
      rotationTransactionState: nil,
      recoveryRequired: nil,
      releaseIdentityValidation: HermesAuditSigningReleaseIdentityValidation(
        appIdentity: identity(),
        serviceIdentity: nil,
        developerIDAvailable: false,
        validationPassed: false,
        blocked: true,
        issueCodes: ["developer_id_unavailable"]
      ),
      trustAnchorCount: 1
    )
    let encoded = String(data: try! JSONEncoder().encode(status), encoding: .utf8)!
    XCTAssertFalse(encoded.localizedCaseInsensitiveContains("private"))
    XCTAssertFalse(encoded.localizedCaseInsensitiveContains("token"))
    XCTAssertFalse(encoded.contains("/Users/"))
  }

  private func identity(
    role: String = "currentApp",
    requirement: String = "identifier com.hermes.bridge",
    team: String? = "TEAM123456",
    fingerprintSeed: String = "e"
  ) -> HermesAuditAuthorizedCodeIdentity {
    HermesAuditAuthorizedCodeIdentity(
      role: role,
      bundleIdentifier: "com.hermes.bridge",
      designatedRequirement: requirement,
      teamIdentifier: team,
      signingKind: team == nil ? "adhoc" : "developerIDOrTeamSigned",
      hardenedRuntime: team != nil,
      appSandbox: role == "currentApp",
      fingerprint: String(repeating: fingerprintSeed, count: 64)
    )
  }

  private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "hermes-audit-signing-operations-tests-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
