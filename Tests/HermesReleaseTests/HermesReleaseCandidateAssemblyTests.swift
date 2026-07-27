import Foundation
import XCTest

final class HermesReleaseCandidateAssemblyTests: XCTestCase {
  private var root: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private func read(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }

  func testM12001AssemblyScriptExistsAndUsesExistingReleaseFoundation() throws {
    let script = try read("Scripts/m12_001_release_candidate_assembly.sh")

    XCTAssertTrue(script.contains("Scripts/release/build-release-candidate.zsh"))
    XCTAssertTrue(script.contains("Scripts/release/sign-release.zsh"))
    XCTAssertTrue(script.contains("HermesBridgeServiceLifecycle"))
    XCTAssertTrue(script.contains("artifacts/m12-001"))
    XCTAssertTrue(script.contains("RC_DIR=\"$ARTIFACT_DIR/rc\""))
    XCTAssertTrue(script.contains("HERMES_RC_VERSION:-0.1.0-rc.1"))
    XCTAssertFalse(script.contains("/Applications/Hermes Bridge.app"))
    XCTAssertFalse(script.contains("HOME}/.hermes"))
  }

  func testM12001ResultFileKeyCatalogIsComplete() throws {
    let script = try read("Scripts/m12_001_release_candidate_assembly.sh")
    let required = [
      "RC_APP_BUILT", "RC_SERVICE_BUILT", "RC_PACKAGE_CREATED", "RC_VERSION_CONSISTENT",
      "PRODUCTION_COMPONENTS_ONLY", "ACCEPTANCE_SUPPORT_INCLUDED",
      "TEST_EXECUTABLE_INCLUDED", "INFO_PLIST_VALID", "BUNDLE_IDENTIFIERS_VALID",
      "XPC_PROTOCOL_1_7", "APP_SERVICE_COMPATIBLE", "DUPLICATE_APP_INCLUDED",
      "DUPLICATE_SERVICE_INCLUDED", "CHECKSUM_MANIFEST_CREATED",
      "CHECKSUM_MANIFEST_VERIFIED", "SBOM_CREATED", "RELEASE_MANIFEST_CREATED",
      "SOURCE_COMMIT_RECORDED", "SIGNING_STATE", "INSTALL_SMOKE_PASSED",
      "XPC_SMOKE_PASSED", "RUNTIME_SMOKE_PASSED", "UNINSTALL_SMOKE_PASSED",
      "DEVELOPER_PATH_EXPOSED", "TOKEN_EXPOSED", "PRIVATE_KEY_EXPOSED",
      "ACCEPTANCE_SYMBOL_EXPOSED", "APPLICATIONS_MODIFIED",
      "USER_LAUNCH_AGENTS_MODIFIED", "REAL_HERMES_HOME_MODIFIED",
      "RESIDUAL_PROCESS", "M12_001_RESULT",
    ]

    XCTAssertEqual(required.count, 32)
    XCTAssertEqual(Set(required).count, required.count)
    for key in required {
      XCTAssertTrue(script.contains(key), key)
    }
  }

  func testM12001ProductionOnlyAndSecurityScansAreExplicit() throws {
    let script = try read("Scripts/m12_001_release_candidate_assembly.sh")

    for marker in [
      "HermesBridgeAppAcceptanceHarness",
      "HermesBridgeAppAcceptanceSupport",
      "HermesM11003AcceptanceController",
      "--hermes-m11-003-acceptance",
      "m11-003-token-sentinel",
    ] {
      XCTAssertTrue(script.contains(marker), marker)
    }

    XCTAssertTrue(script.contains("BEGIN (RSA |OPENSSH |EC |DSA |)PRIVATE KEY"))
    XCTAssertTrue(script.contains("DEVELOPER_PATH_EXPOSED"))
    XCTAssertTrue(script.contains("TOKEN_EXPOSED"))
    XCTAssertTrue(script.contains("PRIVATE_KEY_EXPOSED"))
  }

  func testM12001MetadataSBOMAndChecksumGeneration() throws {
    let script = try read("Scripts/m12_001_release_candidate_assembly.sh")

    XCTAssertTrue(script.contains("version-manifest.json"))
    XCTAssertTrue(script.contains("upgrade-rollback-metadata.json"))
    XCTAssertTrue(script.contains("release-manifest.json"))
    XCTAssertTrue(script.contains("sbom.spdx.json"))
    XCTAssertTrue(script.contains("\"spdxVersion\": \"SPDX-2.3\""))
    XCTAssertTrue(script.contains("swift package show-dependencies --format json"))
    XCTAssertTrue(script.contains("LC_ALL=C sort"))
    XCTAssertTrue(script.contains("shasum -a 256 -c"))
    XCTAssertTrue(script.contains("COPYFILE_DISABLE=1"))
    XCTAssertTrue(script.contains("touch -h -t 198001010000"))
  }

  func testM12001DocumentationExists() throws {
    let doc = try read("Docs/Release/ReleaseCandidateAssembly.md")

    XCTAssertTrue(doc.contains("M12-001"))
    XCTAssertTrue(doc.contains("0.1.0-rc.1"))
    XCTAssertTrue(doc.contains("artifacts/m12-001/rc"))
    XCTAssertTrue(doc.contains("Signing state"))
    XCTAssertTrue(doc.contains("No generated RC artifacts are committed"))
  }
}
