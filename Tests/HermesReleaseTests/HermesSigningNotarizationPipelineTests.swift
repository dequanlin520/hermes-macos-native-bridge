import Foundation
import XCTest

final class HermesSigningNotarizationPipelineTests: XCTestCase {
  private var root: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private func read(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }

  func testM12003ScriptAndDocumentationExist() throws {
    let script = try read("Scripts/m12_003_signing_notarization_pipeline.sh")
    let doc = try read("Docs/Release/SigningAndNotarizationPipeline.md")

    XCTAssertTrue(script.contains("artifacts/m12-003"))
    XCTAssertTrue(script.contains("HERMES_RELEASE_VERSION"))
    XCTAssertTrue(script.contains("HERMES_SIGNING_IDENTITY"))
    XCTAssertTrue(script.contains("HERMES_TEAM_ID"))
    XCTAssertTrue(script.contains("HERMES_NOTARY_PROFILE"))
    XCTAssertTrue(doc.contains("M12-003"))
    XCTAssertTrue(doc.contains("readiness-only"))
    XCTAssertTrue(doc.contains("production-notarized"))
  }

  func testM12003ResultFileKeyCatalogIsComplete() throws {
    let script = try read("Scripts/m12_003_signing_notarization_pipeline.sh")
    let required = [
      "UNSIGNED_RC_VERIFIED", "PROVENANCE_VERIFIED",
      "SIGNING_IDENTITY_REQUESTED", "SIGNING_IDENTITY_AVAILABLE",
      "TEAM_ID_AVAILABLE", "NOTARY_PROFILE_REQUESTED",
      "NOTARY_PROFILE_AVAILABLE", "CREDENTIALS_AVAILABLE",
      "SIGNING_PIPELINE_READY", "PRODUCTION_COMPONENTS_ONLY",
      "ENTITLEMENTS_INVENTORY_CREATED", "HARDENED_RUNTIME_CONFIGURED",
      "GET_TASK_ALLOW_PRESENT", "DANGEROUS_ENTITLEMENT_PRESENT",
      "ACCEPTANCE_SUPPORT_INCLUDED", "NESTED_COMPONENTS_SIGNED",
      "APP_SIGNED", "SIGNATURES_VERIFIED", "TEAM_ID_CONSISTENT",
      "POST_SIGN_CHECKSUM_CREATED", "POST_SIGN_PROVENANCE_CREATED",
      "NOTARIZATION_SUBMITTED", "NOTARIZATION_ACCEPTED",
      "NOTARIZATION_LOG_RECORDED", "TICKET_STAPLED", "STAPLE_VALID",
      "GATEKEEPER_ACCEPTED", "DEVELOPER_PATH_EXPOSED", "TOKEN_EXPOSED",
      "PRIVATE_KEY_EXPOSED", "APPLICATIONS_MODIFIED",
      "USER_LAUNCH_AGENTS_MODIFIED", "REAL_HERMES_HOME_MODIFIED",
      "RESIDUAL_PROCESS", "RELEASE_STATE", "M12_003_RESULT",
    ]

    XCTAssertEqual(required.count, 36)
    XCTAssertEqual(Set(required).count, required.count)
    for key in required {
      XCTAssertTrue(script.contains(key), key)
    }
  }

  func testMissingCredentialsReadinessPathCannotClaimProductionSuccess() throws {
    let script = try read("Scripts/m12_003_signing_notarization_pipeline.sh")

    XCTAssertTrue(script.contains("CREDENTIALS_AVAILABLE no"))
    XCTAssertTrue(script.contains("RELEASE_STATE]=readiness-only"))
    XCTAssertTrue(script.contains("NOTARIZATION_SUBMITTED=no"))
    XCTAssertTrue(script.contains("readiness-missing-prerequisites.txt"))
    XCTAssertTrue(script.contains("NESTED_COMPONENTS_SIGNED not-run"))
    XCTAssertTrue(script.contains("APP_SIGNED not-run"))
    XCTAssertTrue(script.contains("SIGNATURES_VERIFIED not-run"))
    XCTAssertTrue(script.contains("Never fabricates") == false)
    XCTAssertTrue(script.contains("production-notarized"))
    XCTAssertTrue(script.contains("NOTARIZATION_ACCEPTED") && script.contains("GATEKEEPER_ACCEPTED"))
  }

  func testCredentialDiscoveryIsExplicitAndDoesNotEnumerateKeychain() throws {
    let script = try read("Scripts/m12_003_signing_notarization_pipeline.sh")

    XCTAssertTrue(script.contains("security find-certificate -c \"$SIGNING_IDENTITY\""))
    XCTAssertTrue(script.contains("notarytool history --keychain-profile \"$NOTARY_PROFILE\" --team-id \"$TEAM_ID\""))
    XCTAssertFalse(script.contains("/usr/bin/security find-identity"))
    XCTAssertFalse(script.contains("security dump-keychain"))
    XCTAssertFalse(script.contains("security unlock-keychain"))
    XCTAssertFalse(script.contains("notarytool store-credentials"))
    XCTAssertFalse(script.contains("APPLE_ID_PASSWORD"))
    XCTAssertFalse(script.contains("--password"))
  }

  func testSigningOrderAndNestedExecutableDiscoveryAreExplicit() throws {
    let script = try read("Scripts/m12_003_signing_notarization_pipeline.sh")

    XCTAssertTrue(script.contains("sorted(payload.rglob(\"*\"))"))
    XCTAssertTrue(script.contains("Payload/bin/HermesBridgeService"))
    XCTAssertTrue(script.contains("Payload/bin/HermesBridgeControl"))
    XCTAssertTrue(script.contains("Payload/bin/HermesBridgeServiceLifecycle"))
    XCTAssertTrue(script.contains("Payload/Hermes Bridge.app/Contents/MacOS/HermesBridgeApp"))
    XCTAssertTrue(script.contains("sign_order.append(\"Payload/Hermes Bridge.app\")"))
    XCTAssertTrue(script.contains("while IFS= read -r rel"))
    XCTAssertTrue(script.contains("continue"))
    XCTAssertTrue(script.contains("sign_component \"$staging/Payload/Hermes Bridge.app\""))
  }

  func testEntitlementPolicyRejectsUnsafeProductionEntitlements() throws {
    let script = try read("Scripts/m12_003_signing_notarization_pipeline.sh")

    XCTAssertTrue(script.contains("com.apple.security.get-task-allow"))
    XCTAssertTrue(script.contains("com.apple.security.cs.disable-library-validation"))
    XCTAssertTrue(script.contains("com.apple.security.temporary-exception"))
    XCTAssertTrue(script.contains("getTaskAllowPresent"))
    XCTAssertTrue(script.contains("dangerousEntitlementPresent"))
    XCTAssertTrue(script.contains("--options runtime"))
    XCTAssertTrue(script.contains("--entitlements \"$entitlements\""))
    XCTAssertTrue(script.contains("Packaging/Entitlements/HermesBridgeApp.entitlements"))
    XCTAssertTrue(script.contains("Packaging/Entitlements/HermesBridgeService.entitlements"))
  }

  func testProductionIsolationAndSensitiveContentScansAreExplicit() throws {
    let script = try read("Scripts/m12_003_signing_notarization_pipeline.sh")

    for marker in [
      "AcceptanceHarness",
      "AcceptanceSupport",
      "HermesM11003AcceptanceController",
      "M8001ReleaseCandidateAcceptance",
      "fixture_backend",
      "--hermes-m11-003-acceptance",
      "m11-003-token-sentinel",
      "HERMES_DASHBOARD_SESSION_TOKEN",
      "BEGIN (RSA |OPENSSH |EC |DSA |)?PRIVATE KEY",
      "DEVELOPER_PATH_EXPOSED",
      "TOKEN_EXPOSED",
      "PRIVATE_KEY_EXPOSED",
    ] {
      XCTAssertTrue(script.contains(marker), marker)
    }
  }

  func testUnsignedToSignedProvenanceAndChecksumsAreRecorded() throws {
    let script = try read("Scripts/m12_003_signing_notarization_pipeline.sh")

    XCTAssertTrue(script.contains("POST_SIGN_PROVENANCE"))
    XCTAssertTrue(script.contains("unsignedRC"))
    XCTAssertTrue(script.contains("signedRC"))
    XCTAssertTrue(script.contains("sourceCommit"))
    XCTAssertTrue(script.contains("signingIdentityDesignation"))
    XCTAssertTrue(script.contains("notarizationSubmissionID"))
    XCTAssertTrue(script.contains("post-sign-checksums.sha256"))
    XCTAssertTrue(script.contains("shasum -a 256"))
  }

  func testNotarizationParsingFailureAndGatekeeperEvidenceAreExplicit() throws {
    let script = try read("Scripts/m12_003_signing_notarization_pipeline.sh")

    XCTAssertTrue(script.contains("parse_notary_status"))
    XCTAssertTrue(script.contains("status.lower()"))
    XCTAssertTrue(script.contains("notarytool submit"))
    XCTAssertTrue(script.contains("--wait --output-format json"))
    XCTAssertTrue(script.contains("notarytool log"))
    XCTAssertTrue(script.contains("stapler staple"))
    XCTAssertTrue(script.contains("stapler validate"))
    XCTAssertTrue(script.contains("spctl --assess"))
    XCTAssertTrue(script.contains("[[ \"$status\" == \"accepted\" ]] || return 1"))
  }

  func testFailureCleanupAndCommandOutputRedactionAreScoped() throws {
    let script = try read("Scripts/m12_003_signing_notarization_pipeline.sh")

    XCTAssertTrue(script.contains("trap cleanup EXIT"))
    XCTAssertTrue(script.contains("redact_file"))
    XCTAssertTrue(script.contains("<redacted>"))
    XCTAssertTrue(script.contains("APPLICATIONS_MODIFIED]=no"))
    XCTAssertTrue(script.contains("USER_LAUNCH_AGENTS_MODIFIED]=no"))
    XCTAssertTrue(script.contains("REAL_HERMES_HOME_MODIFIED]=no"))
    XCTAssertFalse(script.contains("sudo "))
    XCTAssertFalse(script.contains("killall"))
    XCTAssertFalse(script.contains("pkill"))
    XCTAssertFalse(script.contains("/Applications/Hermes Bridge.app"))
    XCTAssertFalse(script.contains("launchctl bootstrap"))
    XCTAssertFalse(script.contains("launchctl bootout"))
  }
}
