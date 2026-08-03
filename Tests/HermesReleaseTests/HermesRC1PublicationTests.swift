import XCTest

final class HermesRC1PublicationTests: XCTestCase {
  private let resultKeys = [
    "EXPLICIT_OPT_IN_CONFIRMED",
    "PRODUCT_VERSION",
    "TAG_TARGET",
    "PACKAGE_TYPE",
    "DISTRIBUTION_CLASSIFICATION",
    "PUBLIC_DISTRIBUTION_ALLOWED",
    "SIGNED_RELEASE_BLOCKING_REASON",
    "RC_ARTIFACT_ASSEMBLED",
    "RC_ARTIFACT_FILENAME_VALID",
    "ZIP_CONTENT_VALID",
    "SHA256SUMS_CREATED",
    "SHA256_VERIFIED",
    "RELEASE_MANIFEST_VALID",
    "RELEASE_NOTES_CREATED",
    "EXTERNAL_INSTALL_CHECKLIST_CREATED",
    "ROLLBACK_DOCUMENT_CREATED",
    "GITHUB_DRAFT_DESCRIPTOR_CREATED",
    "GITHUB_RELEASE_CREATED",
    "TAG_CREATED",
    "APPLICATION_SIGNING_STATUS",
    "NOTARIZATION_STATUS",
    "STAPLING_STATUS",
    "CLEAN_USER_ACCEPTANCE_CAPABILITY",
    "CLEAN_USER_ACCEPTANCE_ATTEMPTED",
    "CLEAN_USER_ACCEPTANCE_RESULT",
    "NO_SECRET_LEAKAGE",
    "NO_ABSOLUTE_PATH_LEAKAGE",
    "NO_SOURCE_CODE_INCLUDED",
    "GENERATED_ARTIFACT_TRACKED_BY_GIT",
    "ENVIRONMENT_RESTORED",
    "M14_011_REASON_CODE",
    "M14_011_RESULT",
  ]

  func testScriptDefinesPublicationCommandsAndConsumesM14010Pipeline() throws {
    let script = try read("Scripts/m14_011_rc1_publication.sh")
    for command in [
      "inspect",
      "assemble",
      "verify",
      "external-test-plan",
      "print-gh-draft-command",
      "cleanup",
    ] {
      XCTAssertTrue(script.contains(command), command)
    }
    XCTAssertTrue(script.contains("HERMES_M14_011_ACCEPTANCE"))
    XCTAssertTrue(script.contains("HERMES_M14_010_ACCEPTANCE=YES \"$M14_010_SCRIPT\" build-unsigned"))
    XCTAssertTrue(script.contains("\"$M14_010_SCRIPT\" verify"))
    XCTAssertTrue(script.contains("HERMES_M14_011_CLEAN_USER_ACCEPTANCE"))
  }

  func testDistributionClassificationIsUnsignedAndPublicDistributionFalse() throws {
    let script = try read("Scripts/m14_011_rc1_publication.sh")
    XCTAssertTrue(script.contains("DISTRIBUTION_CLASSIFICATION=\"unsigned-internal-validation\""))
    XCTAssertTrue(script.contains("PUBLIC_DISTRIBUTION_ALLOWED=\"no\""))
    XCTAssertTrue(script.contains("SIGNED_RELEASE_BLOCKING_REASON=\"signing.application-identity-unavailable\""))
    XCTAssertTrue(script.contains("APPLICATION_SIGNING_STATUS=\"unavailable\""))
    XCTAssertTrue(script.contains("NOTARIZATION_STATUS=\"not-attempted\""))
    XCTAssertTrue(script.contains("STAPLING_STATUS=\"not-attempted\""))
    XCTAssertFalse(script.contains("PUBLIC_DISTRIBUTION_ALLOWED=\"yes\""))
  }

  func testUnsignedArtifactNamingAndRequiredOutputs() throws {
    let script = try read("Scripts/m14_011_rc1_publication.sh")
    XCTAssertTrue(script.contains("Hermes-macOS-Native-Bridge-${PRODUCT_VERSION}-unsigned.zip"))
    XCTAssertTrue(script.contains("RC_ARCHIVE_NAME") && script.contains("-unsigned.zip"))
    for output in [
      "SHA256SUMS",
      "release-manifest.json",
      "release-notes.md",
      "external-install-checklist.md",
      "known-limitations.md",
      "rollback-and-uninstall.md",
    ] {
      XCTAssertTrue(script.contains(output), output)
    }
    XCTAssertFalse(script.contains("-signed.zip"))
    XCTAssertFalse(script.contains("-notarized.zip"))
  }

  func testGitHubDraftCommandIsPrintedButNeverExecuted() throws {
    let script = try read("Scripts/m14_011_rc1_publication.sh")
    let function = try extractFunction("print_gh_draft_command", from: script)
    XCTAssertTrue(function.contains("WARNING: unsigned internal validation artifact"))
    XCTAssertTrue(function.contains("gh release create $TAG_TARGET"))
    XCTAssertTrue(function.contains("--prerelease"))
    XCTAssertTrue(function.contains("not executed by this script"))
    XCTAssertFalse(function.contains("\ngh release create"))
    XCTAssertFalse(script.contains("git tag "))
    XCTAssertFalse(script.contains("git push --tags"))
  }

  func testZipAllowlistAndDenylistAreExplicit() throws {
    let script = try read("Scripts/m14_011_rc1_publication.sh")
    for marker in [
      "Hermes macOS Native Bridge.app/Contents/Info.plist",
      "HermesBridgeService.xpc/Contents/MacOS/HermesBridgeService",
      "Library/LaunchAgents/com.hermes.bridge.plist",
      "Scripts/install-hermes-bridge-app.zsh",
      "Scripts/uninstall-hermes-bridge-app.zsh",
      "bin/HermesBridgeControl",
      "bin/HermesBridgeServiceLifecycle",
      "Sources/",
      "Tests/",
      ".swift",
      ".pem",
      ".p12",
    ] {
      XCTAssertTrue(script.contains(marker), marker)
    }
  }

  func testChecksumManifestParityAndPrivacyScansArePresent() throws {
    let script = try read("Scripts/m14_011_rc1_publication.sh")
    XCTAssertTrue(script.contains("shasum -a 256 \"$RC_ARCHIVE_NAME\" > SHA256SUMS"))
    XCTAssertTrue(script.contains("data[\"artifactSHA256\"][sys.argv[2]]"))
    XCTAssertTrue(script.contains("BEGIN (RSA |OPENSSH |EC |DSA |)?PRIVATE KEY"))
    XCTAssertTrue(script.contains("/Users/[^"))
    XCTAssertTrue(script.contains("getpass.getuser()"))
    XCTAssertTrue(script.contains("NO_SECRET_LEAKAGE"))
    XCTAssertTrue(script.contains("NO_ABSOLUTE_PATH_LEAKAGE"))
    XCTAssertTrue(script.contains("NO_SOURCE_CODE_INCLUDED"))
  }

  func testReleaseNotesContainUnsignedWarningAndCapabilityParity() throws {
    let notes = try read("Docs/Release/v0.1.0-rc.1.md")
    XCTAssertTrue(notes.contains("unsigned and not notarized"))
    XCTAssertTrue(notes.contains("Public distribution is blocked"))
    for supported in [
      "native menu-bar application",
      "XPC 1.8 Bridge service",
      "Hermes executable/version discovery",
      "isolated Hermes Agent lifecycle",
      "dynamic endpoint ownership",
      "`/api/status` readiness",
      "emergency stop",
      "user-scoped install/uninstall",
    ] {
      XCTAssertTrue(notes.localizedCaseInsensitiveContains(supported), supported)
    }
    for unsupported in [
      "Hermes request submission",
      "Request status/cancel",
      "Approval response",
      "Private `/api/ws`",
      "Arbitrary shell",
      "GUI computer use",
      "Browser automation",
      "Arbitrary AppleScript/JXA",
      "Broad process control",
    ] {
      XCTAssertTrue(notes.localizedCaseInsensitiveContains(unsupported), unsupported)
    }
  }

  func testGeneratedArtifactsIgnoredAndResultKeysDeterministic() throws {
    let script = try read("Scripts/m14_011_rc1_publication.sh")
    let gitignore = try read(".gitignore")
    XCTAssertTrue(script.contains("git -C \"$ROOT_DIR\" check-ignore -q \"artifacts/m14-011/output/release-manifest.json\""))
    XCTAssertTrue(gitignore.contains("artifacts/"))
    for key in resultKeys {
      XCTAssertTrue(script.contains(key), "missing \(key)")
    }
    XCTAssertEqual(resultKeys.count, 32)
    XCTAssertEqual(Set(resultKeys).count, resultKeys.count)
  }

  func testCleanupIsScopedAndIdempotent() throws {
    let script = try read("Scripts/m14_011_rc1_publication.sh")
    let cleanup = try extractFunction("cleanup", from: script)
    XCTAssertTrue(cleanup.contains("rm -rf \"$ARTIFACT_DIR\""))
    XCTAssertTrue(cleanup.contains("mkdir -p \"$ARTIFACT_DIR\""))
    XCTAssertFalse(cleanup.contains("artifacts/m14-010"))
    XCTAssertFalse(cleanup.contains("~/.hermes"))
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
