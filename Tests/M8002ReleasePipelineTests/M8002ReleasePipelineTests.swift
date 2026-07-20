import Foundation
import XCTest

final class M8002ReleasePipelineTests: XCTestCase {
  private var root: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private func read(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }

  private func assertCommandSucceeds(_ launchPath: String, _ arguments: [String], file: StaticString = #filePath, line: UInt = #line) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    process.currentDirectoryURL = root
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0, arguments.joined(separator: " "), file: file, line: line)
  }

  func testWorkflowYAMLParses() throws {
    for workflow in ["ci.yml", "release-candidate.yml", "release.yml"] {
      try assertCommandSucceeds("/usr/bin/ruby", ["-e", "require 'yaml'; YAML.load_file('.github/workflows/\(workflow)' )"])
    }
  }

  func testMinimalWorkflowPermissions() throws {
    let ci = try read(".github/workflows/ci.yml")
    let rc = try read(".github/workflows/release-candidate.yml")
    let release = try read(".github/workflows/release.yml")
    XCTAssertTrue(ci.contains("permissions:\n  contents: read"))
    XCTAssertTrue(rc.contains("permissions:\n  contents: read"))
    XCTAssertTrue(release.contains("permissions:\n  contents: read"))
    XCTAssertTrue(rc.contains("attestations: write"))
    XCTAssertTrue(release.contains("contents: write"))
  }

  func testForkPRHasNoAppleSecrets() throws {
    let ci = try read(".github/workflows/ci.yml")
    XCTAssertTrue(ci.contains("pull_request:"))
    XCTAssertFalse(ci.contains("pull_request_target"))
    XCTAssertFalse(ci.contains("secrets.APPLE_"))
  }

  func testReleaseTagPatternsAndProductionConfirmation() throws {
    let rc = try read(".github/workflows/release-candidate.yml")
    let release = try read(".github/workflows/release.yml")
    XCTAssertTrue(rc.contains("'v*-rc.*'"))
    XCTAssertTrue(release.contains("'v*.*.*'"))
    XCTAssertTrue(release.contains("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))
    XCTAssertTrue(release.contains("confirmation"))
    XCTAssertTrue(release.contains("== \"RELEASE\""))
  }

  func testSecretNamesOnlyAndNoSecretEcho() throws {
    let combined = try [
      ".github/workflows/release.yml",
      "Docs/Release/GitHubSecrets.md",
      "Scripts/release/sign-release.zsh",
      "Scripts/release/notarize-release.zsh",
    ].map(read).joined(separator: "\n")
    XCTAssertTrue(combined.contains("APPLE_DEVELOPER_ID_APPLICATION_P12_BASE64"))
    XCTAssertTrue(combined.contains("APPLE_API_PRIVATE_KEY_BASE64"))
    XCTAssertFalse(combined.contains("echo $APPLE"))
    XCTAssertFalse(combined.contains("echo \"${APPLE"))
    XCTAssertFalse(combined.contains("print \"$APPLE"))
  }

  func testTemporaryKeychainCleanupIsImplemented() throws {
    let sign = try read("Scripts/release/sign-release.zsh")
    XCTAssertTrue(sign.contains("uuidgen"))
    XCTAssertTrue(sign.contains(".keychain-db"))
    XCTAssertTrue(sign.contains("security create-keychain"))
    XCTAssertTrue(sign.contains("security delete-keychain \"$keychain_path\""))
    XCTAssertTrue(sign.contains("trap cleanup EXIT"))
    XCTAssertTrue(sign.contains("security list-keychains -d user -s \"$keychain_path\""))
  }

  func testNoCurlPipeShOrEval() throws {
    for path in [
      ".github/workflows/ci.yml",
      ".github/workflows/release-candidate.yml",
      ".github/workflows/release.yml",
      "Scripts/release/build-release-candidate.zsh",
      "Scripts/release/package-release.zsh",
      "Scripts/release/sign-release.zsh",
      "Scripts/release/notarize-release.zsh",
      "Scripts/release/verify-release.zsh",
      "Scripts/release/generate-release-manifest.zsh",
    ] {
      let source = try read(path)
      XCTAssertFalse(source.range(of: #"curl\s+.*\|\s*(sh|bash|zsh)"#, options: .regularExpression) != nil, path)
      XCTAssertFalse(source.range(of: #"(^|[;&|]\s*)eval\s"#, options: .regularExpression) != nil, path)
    }
  }

  func testDeterministicStagingListAndExclusionRules() throws {
    let package = try read("Scripts/release/package-release.zsh")
    let verify = try read("Scripts/release/verify-release.zsh")
    XCTAssertTrue(package.contains("LC_ALL=C sort"))
    XCTAssertTrue(package.contains("staging-files.txt"))
    XCTAssertTrue(package.contains("touch -h -t 198001010000"))
    XCTAssertTrue(package.contains("COPYFILE_DISABLE=1"))
    XCTAssertTrue(verify.contains("-name .git"))
    XCTAssertTrue(verify.contains("-name .build"))
    XCTAssertTrue(verify.contains("-name DerivedData"))
    XCTAssertTrue(verify.contains("-name '*.keychain-db'"))
    XCTAssertTrue(verify.contains("-name '*.prompt'"))
  }

  func testManifestCompletenessSBOMAndChecksumValidation() throws {
    let manifest = try read("Scripts/release/generate-release-manifest.zsh")
    let verify = try read("Scripts/release/verify-release.zsh")
    for key in [
      "CI_BUILD_PASSED", "CI_TESTS_PASSED", "XCODE_BUILD_PASSED",
      "M8_001_ACCEPTANCE_PASSED", "RC_PACKAGE_CREATED", "SBOM_GENERATED",
      "CHECKSUMS_GENERATED", "MANIFEST_GENERATED", "DEVELOPER_ID_SIGNED",
      "NOTARIZATION_ACCEPTED", "STAPLE_VERIFIED", "GATEKEEPER_VERIFIED",
      "SECRETS_EXPOSED", "PRIVATE_PATH_EXPOSED", "RESIDUAL_KEYCHAIN",
      "M8_002_RESULT",
    ] {
      XCTAssertTrue(manifest.contains(key), key)
      XCTAssertTrue(verify.contains(key), key)
    }
    XCTAssertTrue(verify.contains("spdxVersion"))
    XCTAssertTrue(verify.contains("shasum -a 256 -c"))
  }

  func testUnsignedRCConditionalAndSignedReleasePassRules() throws {
    let manifest = try read("Scripts/release/generate-release-manifest.zsh")
    XCTAssertTrue(manifest.contains("result=\"CONDITIONAL\""))
    XCTAssertTrue(manifest.contains("mode\" == \"rc\""))
    XCTAssertTrue(manifest.contains("developer_id_signed\" == \"no\""))
    XCTAssertTrue(manifest.contains("result=\"PASS\""))
    XCTAssertTrue(manifest.contains("notarization_accepted\" == \"yes\""))
  }

  func testProductionRejectionsAndVerificationGates() throws {
    let verify = try read("Scripts/release/verify-release.zsh")
    XCTAssertTrue(verify.contains("production release must pass"))
    XCTAssertTrue(verify.contains("production unsigned release rejected"))
    XCTAssertTrue(verify.contains("notarization failure rejected"))
    XCTAssertTrue(verify.contains("staple verification required"))
    XCTAssertTrue(verify.contains("Gatekeeper verification required"))
  }

  func testArtifactNamingPrereleaseAndPublicationGuard() throws {
    let package = try read("Scripts/release/package-release.zsh")
    let rc = try read(".github/workflows/release-candidate.yml")
    let release = try read(".github/workflows/release.yml")
    XCTAssertTrue(package.contains("unsigned-rc"))
    XCTAssertTrue(package.contains("developer-id"))
    XCTAssertTrue(rc.contains("--prerelease"))
    XCTAssertTrue(rc.contains("github.repository_owner == 'dequanlin520'"))
    XCTAssertTrue(release.contains("Verify production release gates"))
    XCTAssertTrue(release.contains("gh release create"))
  }

  func testPrivatePathRedactionAndNoResidualTemporaryKeychain() throws {
    let manifest = try read("Scripts/release/generate-release-manifest.zsh")
    let verify = try read("Scripts/release/verify-release.zsh")
    XCTAssertTrue(manifest.contains("/Users/"))
    XCTAssertTrue(manifest.contains("private_path_exposed=\"yes\""))
    XCTAssertTrue(manifest.contains("residual_keychain=\"yes\""))
    XCTAssertTrue(verify.contains("secret or private path marker"))
    XCTAssertTrue(verify.contains("*.keychain-db"))
  }
}
