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
    "APPLICATION_IDENTITY_REQUIRED",
    "INSTALLER_IDENTITY_REQUIRED",
    "INSTALLER_IDENTITY_STATUS",
    "APP_SIGNING_STATUS",
    "SERVICE_SIGNING_STATUS",
    "INSTALLER_SIGNING_STATUS",
    "PACKAGE_TYPE",
    "PACKAGE_BUILT",
    "PACKAGE_CONTENT_VALID",
    "UNINSTALL_VALIDATED",
    "NOTARIZATION_CONFIGURED",
    "NOTARIZATION_STATUS",
    "NOTARIZATION_SUBMISSION_TYPE",
    "STAPLING_STATUS",
    "STAPLING_TARGET",
    "FINAL_ARCHIVE_CREATED_AFTER_STAPLING",
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
    XCTAssertEqual(resultKeys.count, 42)
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

  func testArtifactSpecificSigningPolicyModelsZipDmgAndPkg() throws {
    let script = try read("Scripts/m14_010_rc1_release.sh")
    let policy = try extractFunction("signing_policy_field", from: script)
    let fixtures: [(packageType: String, application: String, installer: String, submission: String, staple: String)] = [
      ("app-distribution-bundle", "yes", "no", "zip", "app-bundle"),
      ("disk-image", "yes", "no", "disk-image", "disk-image"),
      ("installer-package", "yes", "yes", "installer-package", "installer-package"),
    ]

    XCTAssertTrue(script.contains("application_identity_required_for_signed_mode()"))
    XCTAssertTrue(script.contains("installer_identity_required_for_signed_mode()"))
    XCTAssertTrue(script.contains("signing_policy_field \"$1\" application_identity_required"))
    XCTAssertTrue(script.contains("signing_policy_field \"$1\" installer_identity_required"))
    for fixture in fixtures {
      XCTAssertTrue(policy.contains("\(fixture.packageType):application_identity_required) print -r -- \(fixture.application)"), fixture.packageType)
      XCTAssertTrue(policy.contains("\(fixture.packageType):installer_identity_required) print -r -- \(fixture.installer)"), fixture.packageType)
      XCTAssertTrue(policy.contains("\(fixture.packageType):notarization_submission_type) print -r -- \(fixture.submission)"), fixture.packageType)
      XCTAssertTrue(policy.contains("\(fixture.packageType):stapling_target) print -r -- \(fixture.staple)"), fixture.packageType)
    }
  }

  func testZipSignedModeRequiresOnlyApplicationIdentity() throws {
    let script = try read("Scripts/m14_010_rc1_release.sh")
    XCTAssertTrue(script.contains("if [[ -z \"${HERMES_RELEASE_APPLICATION_IDENTITY:-}\" ]]; then"))
    XCTAssertTrue(script.contains("if [[ \"${RESULT[INSTALLER_IDENTITY_REQUIRED]}\" == \"yes\" && -z \"${HERMES_RELEASE_INSTALLER_IDENTITY:-}\" ]]; then"))
    XCTAssertTrue(script.contains("warning: HERMES_RELEASE_INSTALLER_IDENTITY is not used for PACKAGE_TYPE=$PACKAGE_TYPE"))
    XCTAssertTrue(script.contains("RESULT[INSTALLER_SIGNING_STATUS]=\"$(if [[ \"${RESULT[INSTALLER_IDENTITY_REQUIRED]}\" == \"yes\" ]]; then print -r -- developer-id-installer; else print -r -- not-applicable; fi)\""))
    XCTAssertFalse(script.contains("-z \"${HERMES_RELEASE_APPLICATION_IDENTITY:-}\" || -z \"${HERMES_RELEASE_INSTALLER_IDENTITY:-}\""))
    XCTAssertFalse(script.contains("productsign"))
  }

  func testPkgFixtureRequiresInstallerIdentityButZipDoesNot() throws {
    let policy = try extractFunction("signing_policy_field", from: try read("Scripts/m14_010_rc1_release.sh"))
    XCTAssertTrue(policy.contains("app-distribution-bundle:installer_identity_required) print -r -- no"))
    XCTAssertTrue(policy.contains("installer-package:installer_identity_required) print -r -- yes"))
    XCTAssertTrue(policy.contains("installer-package:application_identity_required) print -r -- yes"))
  }

  func testZipFlowSignsNestedCodeBeforeOuterAppWithHardenedRuntime() throws {
    let script = try read("Scripts/m14_010_rc1_release.sh")
    let signingFunction = try extractFunction("sign_release_code_inside_out", from: script)
    let serviceSign = try XCTUnwrap(signingFunction.range(of: "$SERVICE_EXEC"))
    let serviceBundleSign = try XCTUnwrap(signingFunction.range(of: "$SERVICE_BUNDLE"))
    let appSign = try XCTUnwrap(signingFunction.range(of: "$APP_BUNDLE"))
    XCTAssertLessThan(serviceSign.lowerBound, appSign.lowerBound)
    XCTAssertLessThan(serviceBundleSign.lowerBound, appSign.lowerBound)
    XCTAssertTrue(signingFunction.contains("--options runtime"))
    XCTAssertTrue(script.contains("RESULT[HARDENED_RUNTIME_STATUS]=enabled"))
    XCTAssertTrue(script.contains("codesign --verify --strict --deep \"$APP_BUNDLE\""))
  }

  func testNotarizationSubmitsZipStaplesAppAndRecreatesArchive() throws {
    let script = try read("Scripts/m14_010_rc1_release.sh")
    XCTAssertTrue(script.contains("notarytool submit \"$PACKAGE_ARCHIVE\""))
    XCTAssertTrue(script.contains("stapler staple \"$APP_BUNDLE\""))
    XCTAssertTrue(script.contains("stapler validate \"$APP_BUNDLE\""))
    XCTAssertFalse(script.contains("stapler staple \"$PACKAGE_ARCHIVE\""))
    XCTAssertTrue(script.contains("RESULT[FINAL_ARCHIVE_CREATED_AFTER_STAPLING]=yes"))
    XCTAssertTrue(script.contains("/usr/bin/ditto -c -k --sequesterRsrc --keepParent"))
  }

  func testResultAndManifestDoNotClaimInstallerSigningForZip() throws {
    let script = try read("Scripts/m14_010_rc1_release.sh")
    XCTAssertTrue(script.contains("APP_SIGNING_STATUS unavailable"))
    XCTAssertTrue(script.contains("SERVICE_SIGNING_STATUS unavailable"))
    XCTAssertTrue(script.contains("print -r -- invalid"))
    XCTAssertTrue(script.contains("print -r -- unavailable"))
    XCTAssertTrue(script.contains("INSTALLER_SIGNING_STATUS \"$(if [[ \"$(installer_identity_required_for_signed_mode \"$PACKAGE_TYPE\")\" == \"yes\" ]]; then print -r -- unsigned; else print -r -- not-applicable; fi)\""))
    XCTAssertTrue(script.contains("\"installer\": $(json_escape \"${RESULT[INSTALLER_IDENTITY_REQUIRED]}\")"))
    XCTAssertTrue(script.contains("\"installer\": $(json_escape \"${RESULT[INSTALLER_SIGNING_STATUS]}\")"))
    XCTAssertTrue(script.contains("\"notarizationSubmissionType\": $(json_escape \"${RESULT[NOTARIZATION_SUBMISSION_TYPE]}\")"))
    XCTAssertTrue(script.contains("\"staplingTarget\": $(json_escape \"${RESULT[STAPLING_TARGET]}\")"))
    XCTAssertTrue(script.contains("INSTALLER_IDENTITY_STATUS]=\"$(if [[ \"${RESULT[INSTALLER_IDENTITY_REQUIRED]}\" == \"yes\" ]]; then print -r -- configured; else print -r -- not-applicable; fi)\""))
    XCTAssertFalse(script.contains("signed ZIP container"))
    XCTAssertFalse(script.contains("productsign"))
  }

  func testInspectReportsRequirementsWithoutIdentityNamesOrHashes() throws {
    let script = try read("Scripts/m14_010_rc1_release.sh")
    XCTAssertTrue(script.contains("APPLICATION_IDENTITY_CATEGORY_AVAILABLE=$(identity_category_available application)"))
    XCTAssertTrue(script.contains("INSTALLER_IDENTITY_CATEGORY_AVAILABLE=$(identity_category_available installer)"))
    XCTAssertTrue(script.contains("APPLICATION_IDENTITY_REQUIRED_FOR_SIGNED_MODE=$(application_identity_required_for_signed_mode \"$PACKAGE_TYPE\")"))
    XCTAssertTrue(script.contains("INSTALLER_IDENTITY_REQUIRED_FOR_SIGNED_MODE=$(installer_identity_required_for_signed_mode \"$PACKAGE_TYPE\")"))
    XCTAssertTrue(script.contains("NOTARIZATION_SUBMISSION_TYPE=$(notarization_submission_type_for_package \"$PACKAGE_TYPE\")"))
    XCTAssertTrue(script.contains("STAPLING_TARGET=$(stapling_target_for_package \"$PACKAGE_TYPE\")"))
    XCTAssertTrue(script.contains("developer-id-application-count"))
    XCTAssertTrue(script.contains("developer-id-installer-count"))
    XCTAssertFalse(script.contains("SHA-1"))
    XCTAssertFalse(script.contains("certificate hash"))
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
    for forbidden in [
      "com.apple.security.automation.apple-events",
      "com.apple.security.device.audio-input",
      "com.apple.security.device.camera",
      "com.apple.security.files.all",
      "com.apple.security.temporary-exception.apple-events",
    ] {
      XCTAssertFalse(appEntitlements.contains(forbidden), forbidden)
      XCTAssertFalse(serviceEntitlements.contains(forbidden), forbidden)
    }
  }

  func testInfoPlistDoesNotDeclareUnusedPrivacyAccess() throws {
    let info = try read("Packaging/HermesBridgeApp/Info.plist")
    for forbidden in [
      "NSInputMonitoringUsageDescription",
      "NSScreenCaptureUsageDescription",
      "NSSystemAdministrationUsageDescription",
      "NSAppleEventsUsageDescription",
      "NSAccessibilityUsageDescription",
      "NSMicrophoneUsageDescription",
      "NSCameraUsageDescription",
    ] {
      XCTAssertFalse(info.contains(forbidden), forbidden)
    }
  }

  func testRC1PackagingScriptAssertsPermissionPolicy() throws {
    let script = try read("Scripts/m14_010_rc1_release.sh")
    XCTAssertTrue(script.contains("NSInputMonitoringUsageDescription"))
    XCTAssertTrue(script.contains("NSAppleEventsUsageDescription"))
    XCTAssertTrue(script.contains("com.apple.security.automation.apple-events"))
    XCTAssertTrue(script.contains("com.apple.security.device.camera"))
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
