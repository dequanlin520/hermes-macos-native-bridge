import XCTest

final class HermesRC1PackagingTests: XCTestCase {
  private let resultKeys = [
    "EXPLICIT_OPT_IN_CONFIRMED",
    "PRODUCT_VERSION",
    "TAG_TARGET",
    "RELEASE_CONFIGURATION",
    "RELEASE_APP_BUILT",
    "APP_BUNDLE_VALID",
    "SERVICE_BUNDLE_VALID",
    "XPC_PROTOCOL_VERSION",
    "APPLE_SILICON_BINARY",
    "MINIMUM_MACOS_VALID",
    "VERSION_CONSISTENT",
    "LAUNCH_AGENT_VALID",
    "ENTITLEMENTS_MINIMAL",
    "GET_TASK_ALLOW_ABSENT",
    "HARDENED_RUNTIME_STATUS",
    "SIGNING_IDENTITY_STATUS",
    "APP_SIGNING_STATUS",
    "SERVICE_SIGNING_STATUS",
    "INSTALLER_SIGNING_STATUS",
    "PACKAGE_TYPE",
    "PACKAGE_BUILT",
    "PACKAGE_CONTENT_VALID",
    "UNINSTALL_VALIDATED",
    "NOTARIZATION_CONFIGURED",
    "NOTARIZATION_STATUS",
    "STAPLING_STATUS",
    "SPCTL_ASSESSMENT",
    "SHA256_MANIFEST_CREATED",
    "RELEASE_MANIFEST_CREATED",
    "NO_SECRET_LEAKAGE",
    "NO_ABSOLUTE_PATH_LEAKAGE",
    "NO_ACCEPTANCE_CODE_ENABLED",
    "GENERATED_ARTIFACT_TRACKED_BY_GIT",
    "ENVIRONMENT_RESTORED",
    "M14_010_REASON_CODE",
    "M14_010_RESULT",
  ]

  func testScriptDefinesRequiredCommandsAndOptInGuards() throws {
    let script = try read("Scripts/m14_010_rc1_release.sh")
    for command in ["inspect", "build-unsigned", "inspect-package", "build-signed", "notarize", "verify", "cleanup"] {
      XCTAssertTrue(script.contains(command), command)
    }
    XCTAssertTrue(script.contains("HERMES_M14_010_ACCEPTANCE"))
    XCTAssertTrue(script.contains("HERMES_M14_010_NOTARIZE"))
    XCTAssertTrue(script.contains("HERMES_RELEASE_APPLICATION_IDENTITY"))
    XCTAssertTrue(script.contains("HERMES_RELEASE_INSTALLER_IDENTITY"))
    XCTAssertTrue(script.contains("blocked.signing-identity-missing"))
    XCTAssertTrue(script.contains("blocked.notarization-credentials-missing"))
  }

  func testDeterministicResultKeysAreCompleteAndOrdered() throws {
    let script = try read("Scripts/m14_010_rc1_release.sh")
    for key in resultKeys {
      XCTAssertTrue(script.contains(key), "missing \(key)")
    }
    XCTAssertEqual(resultKeys.count, 36)
    XCTAssertEqual(Set(resultKeys).count, resultKeys.count)
  }

  func testPackageAllowlistAndDenylistAreExplicit() throws {
    let script = try read("Scripts/m14_010_rc1_release.sh")
    for marker in [
      "Hermes macOS Native Bridge.app/Contents/Info.plist",
      "HermesBridgeService.xpc/Contents/MacOS/HermesBridgeService",
      "Library/LaunchAgents/com.hermes.bridge.plist",
      "Scripts/install-hermes-bridge-app.zsh",
      "Scripts/uninstall-hermes-bridge-app.zsh",
      "Sources/",
      "Tests/",
      ".pem",
      ".p12",
    ] {
      XCTAssertTrue(script.contains(marker), marker)
    }
  }

  func testEntitlementPolicyRejectsDebugAndBroadRuntimeExceptions() throws {
    let script = try read("Scripts/m14_010_rc1_release.sh")
    for marker in [
      "com.apple.security.get-task-allow",
      "com.apple.security.cs.disable-library-validation",
      "com.apple.security.cs.allow-unsigned-executable-memory",
      "com.apple.security.temporary-exception.files.absolute-path.read-write",
      "--options runtime",
      "HARDENED_RUNTIME_STATUS]=enabled",
    ] {
      XCTAssertTrue(script.contains(marker), marker)
    }

    let appEntitlements = try read("Packaging/Entitlements/HermesBridgeApp.entitlements")
    let serviceEntitlements = try read("Packaging/Entitlements/HermesBridgeService.entitlements")
    XCTAssertFalse(appEntitlements.contains("get-task-allow"))
    XCTAssertFalse(serviceEntitlements.contains("get-task-allow"))
    XCTAssertFalse(appEntitlements.contains("disable-library-validation"))
    XCTAssertFalse(serviceEntitlements.contains("disable-library-validation"))
  }

  func testSigningIdentityAndNotarizationRedactionPolicy() throws {
    let script = try read("Scripts/m14_010_rc1_release.sh")
    XCTAssertTrue(script.contains("security find-identity -v -p codesigning"))
    XCTAssertTrue(script.contains("developer-id-application-count"))
    XCTAssertTrue(script.contains("developer-id-installer-count"))
    XCTAssertTrue(script.contains("rm -f \"$EVIDENCE_DIR/signing-identities.raw\""))
    XCTAssertFalse(script.contains("security dump-keychain"))
    XCTAssertFalse(script.contains("security unlock-keychain"))
    XCTAssertFalse(script.contains("notarytool store-credentials"))
    XCTAssertFalse(script.contains("APPLE_ID_PASSWORD"))
    XCTAssertTrue(script.contains("notarytool submit"))
    XCTAssertTrue(script.contains("stapler staple"))
    XCTAssertTrue(script.contains("stapler validate"))
    XCTAssertTrue(script.contains("spctl --assess"))
  }

  func testPrivacyScansCoverSecretsPathsAcceptanceAndPrivateRoutes() throws {
    let script = try read("Scripts/m14_010_rc1_release.sh")
    for marker in [
      "BEGIN (RSA |OPENSSH |EC |DSA |)?PRIVATE KEY",
      "bearer",
      "/Users/",
      "AcceptanceHarness",
      "AcceptanceSupport",
      "M8001ReleaseCandidateAcceptance",
      "/api/ws",
      "NO_SECRET_LEAKAGE",
      "NO_ABSOLUTE_PATH_LEAKAGE",
      "NO_ACCEPTANCE_CODE_ENABLED",
    ] {
      XCTAssertTrue(script.contains(marker), marker)
    }
  }

  func testChecksumManifestUninstallPairingAndGeneratedArtifactsIgnored() throws {
    let script = try read("Scripts/m14_010_rc1_release.sh")
    let gitignore = try read(".gitignore")
    XCTAssertTrue(script.contains("shasum -a 256"))
    XCTAssertTrue(script.contains("checksums.sha256"))
    XCTAssertTrue(script.contains("validate_uninstall_pairing"))
    XCTAssertTrue(script.contains("git -C \"$ROOT_DIR\" check-ignore -q \"artifacts/m14-010/release-manifest.json\""))
    XCTAssertTrue(gitignore.contains("artifacts/"))
  }

  func testDocumentationCoversReleaseDebtAndManualPublication() throws {
    let doc = try read("Docs/Release/M14_010RC1ReleasePackaging.md")
    let checklist = try read("Docs/Release/RC1ReleaseChecklist.md")
    XCTAssertTrue(doc.contains("unsigned-local-validation"))
    XCTAssertTrue(doc.contains("signed-notarized-release"))
    XCTAssertTrue(doc.contains("Security API Compatibility Debt"))
    XCTAssertTrue(doc.contains("SecTrustedApplicationCreateFromPath"))
    XCTAssertTrue(doc.contains("warnings do not by themselves block unsigned packaging readiness"))
    XCTAssertTrue(checklist.contains("Manual GitHub Release Publication"))
    XCTAssertTrue(checklist.contains("Do not claim production readiness"))
  }

  private func read(_ relativePath: String) throws -> String {
    try String(contentsOf: repoRoot().appendingPathComponent(relativePath), encoding: .utf8)
  }

  private func repoRoot() -> URL {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<3 {
      url.deleteLastPathComponent()
    }
    return url
  }
}
