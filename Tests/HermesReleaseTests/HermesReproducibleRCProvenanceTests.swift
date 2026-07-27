import Foundation
import XCTest

final class HermesReproducibleRCProvenanceTests: XCTestCase {
  private var root: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private func read(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }

  func testM12002ScriptExistsAndReusesM12001AssemblyFlow() throws {
    let script = try read("Scripts/m12_002_reproducible_rc_provenance.sh")

    XCTAssertTrue(script.contains("Scripts/m12_001_release_candidate_assembly.sh"))
    XCTAssertTrue(script.contains("git clone --quiet"))
    XCTAssertTrue(script.contains("git -C \"$dest\" checkout --quiet --detach \"$SOURCE_COMMIT\""))
    XCTAssertTrue(script.contains("HOME=\"$home\""))
    XCTAssertTrue(script.contains("XDG_CONFIG_HOME=\"$home/.config\""))
    XCTAssertTrue(script.contains("artifacts/m12-002"))
    XCTAssertFalse(script.contains("sudo "))
    XCTAssertFalse(script.contains("killall"))
    XCTAssertFalse(script.contains("pkill"))
    XCTAssertFalse(script.contains("/Applications/Hermes Bridge.app"))
    XCTAssertFalse(script.contains("HOME}/.hermes"))
  }

  func testM12002ResultFileKeyCatalogIsComplete() throws {
    let script = try read("Scripts/m12_002_reproducible_rc_provenance.sh")
    let required = [
      "SOURCE_COMMIT_FIXED", "CLEAN_BUILD_A", "CLEAN_BUILD_B",
      "BUILD_A_RC_CREATED", "BUILD_B_RC_CREATED", "RC_VERSION_MATCH",
      "SOURCE_COMMIT_MATCH", "PAYLOAD_TOPOLOGY_MATCH", "NORMALIZED_PAYLOAD_MATCH",
      "UNEXPLAINED_DIFFERENCES", "INVENTORY_A_CREATED", "INVENTORY_B_CREATED",
      "INVENTORIES_MATCH", "PROVENANCE_CREATED", "PROVENANCE_SOURCE_RECORDED",
      "PROVENANCE_OUTPUT_HASHES_RECORDED", "MANIFEST_CONSISTENT",
      "SBOM_CONSISTENT", "CHECKSUMS_CONSISTENT",
      "APP_SERVICE_VERSION_CONSISTENT", "XPC_PROTOCOL_1_7",
      "PRODUCTION_COMPONENTS_ONLY", "ACCEPTANCE_SUPPORT_INCLUDED",
      "TEST_COMPONENT_INCLUDED", "DEVELOPER_PATH_EXPOSED", "TOKEN_EXPOSED",
      "PRIVATE_KEY_EXPOSED", "ISOLATED_WORKTREES_CLEANED", "RESIDUAL_PROCESS",
      "READY_FOR_SIGNING_PROMOTION", "M12_002_RESULT",
    ]

    XCTAssertEqual(required.count, 31)
    XCTAssertEqual(Set(required).count, required.count)
    for key in required {
      XCTAssertTrue(script.contains(key), key)
    }
  }

  func testM12002DeterministicInventoryAndPayloadEqualityAreExplicit() throws {
    let script = try read("Scripts/m12_002_reproducible_rc_provenance.sh")

    XCTAssertTrue(script.contains("sorted(staging.rglob(\"*\"), key=lambda p: rel(p, staging))"))
    XCTAssertTrue(script.contains("\"relativePath\""))
    XCTAssertTrue(script.contains("\"fileType\""))
    XCTAssertTrue(script.contains("\"executable\""))
    XCTAssertTrue(script.contains("\"size\""))
    XCTAssertTrue(script.contains("\"sha256\""))
    XCTAssertTrue(script.contains("\"bundleRole\""))
    XCTAssertTrue(script.contains("\"classification\""))
    XCTAssertTrue(script.contains("production_topology"))
    XCTAssertTrue(script.contains("PAYLOAD_TOPOLOGY_MATCH"))
    XCTAssertTrue(script.contains("NORMALIZED_PAYLOAD_MATCH"))
    XCTAssertTrue(script.contains("normalized_differences"))
  }

  func testM12002VersionAndSourceCommitConsistencyChecksAreExplicit() throws {
    let script = try read("Scripts/m12_002_reproducible_rc_provenance.sh")

    XCTAssertTrue(script.contains("HermesBridge-{safe_version}-unsigned-rc.tar.gz"))
    XCTAssertTrue(script.contains("manifest_a.get(\"rcVersion\")"))
    XCTAssertTrue(script.contains("versions_a.get(\"version\")"))
    XCTAssertTrue(script.contains("appShortVersion"))
    XCTAssertTrue(script.contains("appBuildVersion"))
    XCTAssertTrue(script.contains("componentVersions"))
    XCTAssertTrue(script.contains("sourceCommit"))
    XCTAssertTrue(script.contains("SOURCE_COMMIT_MATCH"))
    XCTAssertTrue(script.contains("git -C \"$ROOT_DIR\" cat-file -e \"$SOURCE_COMMIT^{commit}\""))
  }

  func testM12002AllowedNondeterminismAndUnexplainedDifferenceRejection() throws {
    let script = try read("Scripts/m12_002_reproducible_rc_provenance.sh")

    for marker in [
      "release-manifest.buildTimestamp",
      "archive gzip/container timestamp",
      "Mach-O LC_UUID",
      "ad-hoc code signature blobs",
      "temporary clean-clone build paths",
      "normalized_file_hash",
      "normalized_macho_hash",
      "CodeSignature",
    ] {
      XCTAssertTrue(script.contains(marker), marker)
    }

    XCTAssertTrue(script.contains("UNEXPLAINED_DIFFERENCES"))
    XCTAssertTrue(script.contains("exactDifferences"))
    XCTAssertTrue(script.contains("normalizedDifferences"))
    XCTAssertTrue(script.contains("READY_FOR_SIGNING_PROMOTION"))
  }

  func testM12002ProvenanceRecordsMaterialsOutputsAndBuilder() throws {
    let script = try read("Scripts/m12_002_reproducible_rc_provenance.sh")

    XCTAssertTrue(script.contains("https://in-toto.io/Statement/v1"))
    XCTAssertTrue(script.contains("https://slsa.dev/provenance/v1-inspired-unofficial"))
    XCTAssertTrue(script.contains("\"resolvedDependencies\""))
    XCTAssertTrue(script.contains("\"subject\": output_artifacts"))
    XCTAssertTrue(script.contains("builder_versions"))
    XCTAssertTrue(script.contains("\"targetArchitecture\""))
    XCTAssertTrue(script.contains("\"minimumMacOSVersion\""))
    XCTAssertTrue(script.contains("\"xpcProtocolVersion\""))
    XCTAssertTrue(script.contains("\"signingState\""))
    XCTAssertTrue(script.contains("PROVENANCE_OUTPUT_HASHES_RECORDED"))
  }

  func testM12002ProductionIsolationSecurityAndDirtySourceRejection() throws {
    let script = try read("Scripts/m12_002_reproducible_rc_provenance.sh")

    for marker in [
      "HermesBridgeAppAcceptanceHarness",
      "HermesBridgeAppAcceptanceSupport",
      "HermesM11003AcceptanceController",
      "M8001ReleaseCandidateAcceptance",
      "fixture_backend",
      "BEGIN (RSA |OPENSSH |EC |DSA |)?PRIVATE KEY",
      "HERMES_DASHBOARD_SESSION_TOKEN",
      "DEVELOPER_PATH_EXPOSED",
      "status --porcelain --untracked-files=all",
      "dirty isolated source",
    ] {
      XCTAssertTrue(script.contains(marker), marker)
    }
  }

  func testM12002CleanupAfterFailureIsScopedToOwnedWorktrees() throws {
    let script = try read("Scripts/m12_002_reproducible_rc_provenance.sh")

    XCTAssertTrue(script.contains("trap cleanup EXIT"))
    XCTAssertTrue(script.contains("rm -rf \"$WORK_ROOT\""))
    XCTAssertTrue(script.contains("ISOLATED_WORKTREES_CLEANED"))
    XCTAssertTrue(script.contains("RESIDUAL_PROCESS"))
    XCTAssertFalse(script.contains("rm -rf \"$ROOT_DIR\""))
    XCTAssertFalse(script.contains("launchctl bootout"))
  }

  func testM12002DocumentationExists() throws {
    let doc = try read("Docs/Release/ReproducibleRCAndProvenance.md")

    XCTAssertTrue(doc.contains("M12-002"))
    XCTAssertTrue(doc.contains("Reproducibility definition"))
    XCTAssertTrue(doc.contains("Allowed nondeterminism"))
    XCTAssertTrue(doc.contains("Provenance format"))
    XCTAssertTrue(doc.contains("Clean-worktree guarantees"))
    XCTAssertTrue(doc.contains("Swift/Xcode reproducibility limitations"))
    XCTAssertTrue(doc.contains("Promotion criteria"))
  }
}
