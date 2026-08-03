import Foundation
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
      "inspect-existing",
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
    XCTAssertTrue(script.contains("SHA256SUMS=\"$OUTPUT_DIR/SHA256SUMS\""))
    XCTAssertTrue(script.contains("print -r -- \"$(sha256 \"$RC_ARCHIVE\")  $RC_ARCHIVE_NAME\" > \"$SHA256SUMS\""))
    XCTAssertTrue(script.contains("expected_checksum_from_sha256sums()"))
    XCTAssertTrue(script.contains("validate_release_manifest()"))
    XCTAssertTrue(script.contains("BEGIN (RSA |OPENSSH |EC |DSA |)?PRIVATE KEY"))
    XCTAssertTrue(script.contains("/Users/[^"))
    XCTAssertTrue(script.contains("getpass.getuser()"))
    XCTAssertTrue(script.contains("NO_SECRET_LEAKAGE"))
    XCTAssertTrue(script.contains("NO_ABSOLUTE_PATH_LEAKAGE"))
    XCTAssertTrue(script.contains("NO_SOURCE_CODE_INCLUDED"))
  }

  func testSHA256SUMSFileIsCreatedAtExpectedPathWithExpectedZipEntry() throws {
    let script = try read("Scripts/m14_011_rc1_publication.sh")
    XCTAssertTrue(script.contains("SHA256SUMS=\"$OUTPUT_DIR/SHA256SUMS\""))
    XCTAssertTrue(script.contains("print -r -- \"$(sha256 \"$RC_ARCHIVE\")  $RC_ARCHIVE_NAME\" > \"$SHA256SUMS\""))
    XCTAssertTrue(script.contains("$2 == name"))
    XCTAssertFalse(script.contains("checksums.sha256"))
  }

  func testVerifyPassesWithCorrectChecksumAndReturnsZero() throws {
    let fixture = try makePublicationFixture()
    let result = try runPublication(["verify"], artifactDir: fixture.artifactDir)
    XCTAssertEqual(result.status, 0, result.combinedOutput)
    let fields = try resultFields(in: fixture.artifactDir)
    XCTAssertEqual(fields["SHA256SUMS_CREATED"], "yes")
    XCTAssertEqual(fields["SHA256_VERIFIED"], "yes")
    XCTAssertEqual(fields["M14_011_REASON_CODE"], "ok")
    XCTAssertEqual(fields["M14_011_RESULT"], "PASS")
  }

  func testVerifyMissingSHA256SUMSFailsWithSpecificReasonAndExitOne() throws {
    let fixture = try makePublicationFixture()
    try FileManager.default.removeItem(at: fixture.sha256sums)
    let result = try runPublication(["verify"], artifactDir: fixture.artifactDir)
    XCTAssertEqual(result.status, 1, result.combinedOutput)
    let fields = try resultFields(in: fixture.artifactDir)
    XCTAssertEqual(fields["SHA256SUMS_CREATED"], "no")
    XCTAssertEqual(fields["SHA256_VERIFIED"], "no")
    XCTAssertEqual(fields["M14_011_REASON_CODE"], "checksum.file-missing")
    XCTAssertEqual(fields["M14_011_RESULT"], "FAIL")
  }

  func testVerifyEmptySHA256SUMSFailsWithSpecificReason() throws {
    let fixture = try makePublicationFixture()
    try "".write(to: fixture.sha256sums, atomically: true, encoding: .utf8)
    let result = try runPublication(["verify"], artifactDir: fixture.artifactDir)
    XCTAssertEqual(result.status, 1, result.combinedOutput)
    let fields = try resultFields(in: fixture.artifactDir)
    XCTAssertEqual(fields["SHA256SUMS_CREATED"], "no")
    XCTAssertEqual(fields["SHA256_VERIFIED"], "no")
    XCTAssertEqual(fields["M14_011_REASON_CODE"], "checksum.file-empty")
  }

  func testVerifyMissingArtifactChecksumEntryFailsWithSpecificReason() throws {
    let fixture = try makePublicationFixture()
    try "\(fixture.archiveSHA256)  other.zip\n".write(to: fixture.sha256sums, atomically: true, encoding: .utf8)
    let result = try runPublication(["verify"], artifactDir: fixture.artifactDir)
    XCTAssertEqual(result.status, 1, result.combinedOutput)
    let fields = try resultFields(in: fixture.artifactDir)
    XCTAssertEqual(fields["SHA256SUMS_CREATED"], "no")
    XCTAssertEqual(fields["SHA256_VERIFIED"], "no")
    XCTAssertEqual(fields["M14_011_REASON_CODE"], "checksum.entry-missing")
  }

  func testVerifyIncorrectChecksumFailsWithSpecificReason() throws {
    let fixture = try makePublicationFixture()
    let incorrect = String(repeating: "0", count: 64)
    try "\(incorrect)  \(Self.archiveName)\n".write(to: fixture.sha256sums, atomically: true, encoding: .utf8)
    let result = try runPublication(["verify"], artifactDir: fixture.artifactDir)
    XCTAssertEqual(result.status, 1, result.combinedOutput)
    let fields = try resultFields(in: fixture.artifactDir)
    XCTAssertEqual(fields["SHA256SUMS_CREATED"], "yes")
    XCTAssertEqual(fields["SHA256_VERIFIED"], "no")
    XCTAssertEqual(fields["M14_011_REASON_CODE"], "checksum.mismatch")
  }

  func testVerifyRecalculatesStateInsteadOfPreservingContradictoryResultFile() throws {
    let fixture = try makePublicationFixture()
    try """
    SHA256SUMS_CREATED=no
    SHA256_VERIFIED=yes
    M14_011_REASON_CODE=validation.failed
    M14_011_RESULT=FAIL
    """.write(to: fixture.artifactDir.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)

    let result = try runPublication(["verify"], artifactDir: fixture.artifactDir)
    XCTAssertEqual(result.status, 0, result.combinedOutput)
    let fields = try resultFields(in: fixture.artifactDir)
    XCTAssertEqual(fields["SHA256SUMS_CREATED"], "yes")
    XCTAssertEqual(fields["SHA256_VERIFIED"], "yes")
    XCTAssertEqual(fields["M14_011_RESULT"], "PASS")
  }

  func testSHA256VerifiedCannotRemainYesWhenSHA256SUMSCreatedIsNo() throws {
    let fixture = try makePublicationFixture()
    try FileManager.default.removeItem(at: fixture.sha256sums)
    try """
    SHA256SUMS_CREATED=no
    SHA256_VERIFIED=yes
    M14_011_REASON_CODE=validation.failed
    M14_011_RESULT=FAIL
    """.write(to: fixture.artifactDir.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)

    let result = try runPublication(["verify"], artifactDir: fixture.artifactDir)
    XCTAssertEqual(result.status, 1, result.combinedOutput)
    let fields = try resultFields(in: fixture.artifactDir)
    XCTAssertEqual(fields["SHA256SUMS_CREATED"], "no")
    XCTAssertEqual(fields["SHA256_VERIFIED"], "no")
    XCTAssertEqual(fields["M14_011_REASON_CODE"], "checksum.file-missing")
    XCTAssertEqual(fields["M14_011_RESULT"], "FAIL")
  }

  func testMissingOptInAssembleReturnsTwoWithoutRunningAssembly() throws {
    let temp = try temporaryDirectory().appendingPathComponent("artifact")
    let result = try runPublication(["assemble"], artifactDir: temp)
    XCTAssertEqual(result.status, 2, result.combinedOutput)
    let fields = try resultFields(in: temp)
    XCTAssertEqual(fields["M14_011_REASON_CODE"], "blocked.acceptance-opt-in-required")
    XCTAssertEqual(fields["M14_011_RESULT"], "BLOCKED")
  }

  func testResultExitCodeMappingsAreSharedAndComplete() throws {
    let script = try read("Scripts/m14_011_rc1_publication.sh")
    let mapper = try extractFunction("result_exit_code", from: script)
    XCTAssertTrue(script.contains("return \"$(result_exit_code)\""))
    XCTAssertTrue(mapper.contains("PASS) print -r -- 0"))
    XCTAssertTrue(mapper.contains("FAIL) print -r -- 1"))
    XCTAssertTrue(mapper.contains("blocked.acceptance-opt-in-required"))
    XCTAssertTrue(mapper.contains("print -r -- 2"))
    XCTAssertTrue(mapper.contains("print -r -- 3"))
    XCTAssertTrue(mapper.contains("PARTIAL) print -r -- 5"))
    XCTAssertTrue(mapper.contains("UNSUPPORTED) print -r -- 6"))
  }

  func testSpecificReasonsReplaceGenericChecksumValidationReason() throws {
    let script = try read("Scripts/m14_011_rc1_publication.sh")
    for reason in [
      "checksum.file-missing",
      "checksum.file-empty",
      "checksum.entry-missing",
      "checksum.mismatch",
      "checksum.state-inconsistent",
      "manifest.checksum-mismatch",
      "result.exit-code-inconsistent",
    ] {
      XCTAssertTrue(script.contains(reason), reason)
    }
    XCTAssertFalse(script.contains("checksum.invalid"))
    XCTAssertFalse(script.contains("verify.artifacts-missing"))
    XCTAssertFalse(script.contains("manifest.invalid"))
  }

  func testInspectExistingIsReadOnlyAndReportsCurrentArtifactState() throws {
    let fixture = try makePublicationFixture()
    let before = try fileSnapshot(under: fixture.artifactDir)
    let result = try runPublication(["inspect-existing"], artifactDir: fixture.artifactDir)
    let after = try fileSnapshot(under: fixture.artifactDir)

    XCTAssertEqual(result.status, 0, result.combinedOutput)
    XCTAssertEqual(before, after)
    XCTAssertTrue(result.stdout.contains("ARTIFACT_PRESENT=yes"))
    XCTAssertTrue(result.stdout.contains("EXPECTED_ARTIFACT_FILENAME=yes"))
    XCTAssertTrue(result.stdout.contains("SHA256SUMS_PRESENT=yes"))
    XCTAssertTrue(result.stdout.contains("SHA256SUMS_NONEMPTY=yes"))
    XCTAssertTrue(result.stdout.contains("SHA256_ENTRY_PRESENT=yes"))
    XCTAssertTrue(result.stdout.contains("SHA256_MATCH=yes"))
    XCTAssertTrue(result.stdout.contains("MANIFEST_PRESENT=yes"))
    XCTAssertTrue(result.stdout.contains("MANIFEST_CHECKSUM_MATCH=yes"))
    XCTAssertTrue(result.stdout.contains("CURRENT_RESULT=unknown"))
    XCTAssertTrue(result.stdout.contains("EXPECTED_VERIFY_EXIT_CODE=0"))
  }

  func testGitHubReleaseAndTagOperationsRemainForbidden() throws {
    let script = try read("Scripts/m14_011_rc1_publication.sh")
    XCTAssertFalse(script.contains("\ngh release create"))
    XCTAssertFalse(script.contains("\ngit tag "))
    XCTAssertFalse(script.contains("\ngit push"))
    XCTAssertTrue(script.contains("GITHUB_RELEASE_CREATED no"))
    XCTAssertTrue(script.contains("TAG_CREATED no"))
  }

  func testResultInvariantsAreEnforcedBeforeWritingFinalResult() throws {
    let script = try read("Scripts/m14_011_rc1_publication.sh")
    let invariants = try extractFunction("enforce_result_invariants", from: script)
    for marker in [
      "SHA256_VERIFIED",
      "SHA256SUMS_CREATED",
      "M14_011_RESULT",
      "PASS",
      "GITHUB_RELEASE_CREATED",
      "TAG_CREATED",
      "PUBLIC_DISTRIBUTION_ALLOWED",
      "APPLICATION_SIGNING_STATUS",
      "NOTARIZATION_STATUS",
      "STAPLING_STATUS",
      "checksum.state-inconsistent",
      "result.exit-code-inconsistent",
    ] {
      XCTAssertTrue(invariants.contains(marker), marker)
    }
    XCTAssertTrue(script.contains("enforce_result_invariants"))
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

  private static let archiveName = "Hermes-macOS-Native-Bridge-0.1.0-rc.1-unsigned.zip"

  private struct PublicationFixture {
    let artifactDir: URL
    let outputDir: URL
    let evidenceDir: URL
    let archive: URL
    let sha256sums: URL
    let archiveSHA256: String
  }

  private struct CommandResult {
    let status: Int32
    let stdout: String
    let stderr: String

    var combinedOutput: String {
      stdout + stderr
    }
  }

  private func makePublicationFixture() throws -> PublicationFixture {
    let artifactDir = try temporaryDirectory().appendingPathComponent("m14-011")
    let outputDir = artifactDir.appendingPathComponent("output")
    let evidenceDir = artifactDir.appendingPathComponent("evidence")
    try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: evidenceDir, withIntermediateDirectories: true)

    let staging = try temporaryDirectory().appendingPathComponent("zip-staging")
    for relative in [
      "Fixture/Hermes macOS Native Bridge.app/Contents/Info.plist",
      "Fixture/Hermes macOS Native Bridge.app/Contents/MacOS/HermesBridgeApp",
      "Fixture/Hermes macOS Native Bridge.app/Contents/Library/XPCServices/HermesBridgeService.xpc/Contents/Info.plist",
      "Fixture/Hermes macOS Native Bridge.app/Contents/Library/XPCServices/HermesBridgeService.xpc/Contents/MacOS/HermesBridgeService",
      "Fixture/Library/LaunchAgents/com.hermes.bridge.plist",
      "Fixture/Scripts/install-hermes-bridge-app.zsh",
      "Fixture/Scripts/uninstall-hermes-bridge-app.zsh",
      "Fixture/bin/HermesBridgeControl",
      "Fixture/bin/HermesBridgeServiceLifecycle",
    ] {
      let url = staging.appendingPathComponent(relative)
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try "fixture\n".write(to: url, atomically: true, encoding: .utf8)
    }

    let archive = outputDir.appendingPathComponent(Self.archiveName)
    try runProcess("/usr/bin/zip", arguments: ["-qr", archive.path, "Fixture"], currentDirectory: staging)
    let archiveSHA256 = try sha256(of: archive)
    let sha256sums = outputDir.appendingPathComponent("SHA256SUMS")
    try "\(archiveSHA256)  \(Self.archiveName)\n".write(to: sha256sums, atomically: true, encoding: .utf8)
    try releaseManifest(checksum: archiveSHA256).write(
      to: outputDir.appendingPathComponent("release-manifest.json"),
      atomically: true,
      encoding: .utf8
    )
    for name in [
      "release-notes.md",
      "external-install-checklist.md",
      "known-limitations.md",
      "rollback-and-uninstall.md",
    ] {
      try "fixture\n".write(to: outputDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
    try "{}\n".write(
      to: evidenceDir.appendingPathComponent("github-publication-draft.json"),
      atomically: true,
      encoding: .utf8
    )

    return PublicationFixture(
      artifactDir: artifactDir,
      outputDir: outputDir,
      evidenceDir: evidenceDir,
      archive: archive,
      sha256sums: sha256sums,
      archiveSHA256: archiveSHA256
    )
  }

  private func releaseManifest(checksum: String) -> String {
    """
    {
      "artifactSHA256": {
        "\(Self.archiveName)": "\(checksum)"
      },
      "distributionClassification": "unsigned-internal-validation",
      "publicDistributionAllowed": "no",
      "signedReleaseBlockingReason": "signing.application-identity-unavailable",
      "signingStatus": {
        "application": "unavailable"
      },
      "notarizationStatus": "not-attempted",
      "staplingStatus": "not-attempted"
    }
    """
  }

  private func runPublication(_ arguments: [String], artifactDir: URL) throws -> CommandResult {
    try runProcess(
      "/bin/zsh",
      arguments: [repoRoot().appendingPathComponent("Scripts/m14_011_rc1_publication.sh").path] + arguments,
      environment: ["HERMES_M14_011_ARTIFACT_DIR": artifactDir.path],
      currentDirectory: repoRoot()
    )
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
    if let currentDirectory {
      process.currentDirectoryURL = currentDirectory
    }
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

  private func sha256(of url: URL) throws -> String {
    let result = try runProcess("/usr/bin/shasum", arguments: ["-a", "256", url.path])
    XCTAssertEqual(result.status, 0, result.combinedOutput)
    return try XCTUnwrap(result.stdout.split(separator: " ").first).description
  }

  private func resultFields(in artifactDir: URL) throws -> [String: String] {
    let result = try String(contentsOf: artifactDir.appendingPathComponent("result.txt"), encoding: .utf8)
    return Dictionary(uniqueKeysWithValues: result.split(separator: "\n").compactMap { line in
      guard let equals = line.firstIndex(of: "=") else { return nil }
      return (String(line[..<equals]), String(line[line.index(after: equals)...]))
    })
  }

  private func fileSnapshot(under root: URL) throws -> [String: String] {
    let files = try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted()
    var snapshot: [String: String] = [:]
    for file in files {
      let url = root.appendingPathComponent(file)
      var isDirectory: ObjCBool = false
      guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
        continue
      }
      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
      let size = attributes[.size] as? NSNumber
      let modified = attributes[.modificationDate] as? Date
      let content = try Data(contentsOf: url).base64EncodedString()
      snapshot[file] = "\(size?.intValue ?? -1):\(modified?.timeIntervalSince1970 ?? -1):\(content)"
    }
    return snapshot
  }

  private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("HermesRC1PublicationTests-\(UUID().uuidString)", isDirectory: true)
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
