import XCTest
@testable import HermesBridgeXPC
@testable import HermesReleaseVersion

final class HermesReleaseVersionTests: XCTestCase {
  func testAuthoritativeRC1VersionValues() {
    XCTAssertEqual(HermesReleaseVersion.productVersion, "0.1.0-rc.1")
    XCTAssertEqual(HermesReleaseVersion.tagTarget, "v0.1.0-rc.1")
    XCTAssertEqual(HermesReleaseVersion.xpcProtocolVersion, "1.8")
    XCTAssertEqual(HermesReleaseVersion.testedHermesVersion, "0.18.2")
    XCTAssertEqual(HermesReleaseVersion.minimumMacOS, "13.0")
    XCTAssertEqual(HermesReleaseVersion.packageType, "app-distribution-bundle")
  }

  func testXPCProtocolConstantIsPreserved() {
    XCTAssertEqual(HermesBridgeProtocolVersion.current.description, HermesReleaseVersion.xpcProtocolVersion)
  }

  func testRCCapabilitySummaryPreservesUnsupportedBoundary() {
    XCTAssertTrue(HermesReleaseVersion.supportedCapabilities.contains("status-only-hermes-agent-integration"))
    XCTAssertTrue(
      HermesReleaseVersion.unsupportedCapabilities.contains(
        "request-submission:transport.route-unsupported"
      )
    )
    XCTAssertTrue(
      HermesReleaseVersion.unsupportedCapabilities.contains(
        "request-cancellation:transport.route-unsupported"
      )
    )
    XCTAssertTrue(
      HermesReleaseVersion.unsupportedCapabilities.contains(
        "approval-response:transport.route-unsupported"
      )
    )
    XCTAssertTrue(HermesReleaseVersion.unsupportedCapabilities.contains("private-api-ws:not-claimed"))
  }

  func testDiagnosticsExposeAuthoritativeVersion() throws {
    let preflight = try read("Sources/HermesReleaseAgentPreflight/HermesReleaseAgentPreflight.swift")
    XCTAssertTrue(preflight.contains("HermesReleaseVersion.productVersion"))
    XCTAssertTrue(preflight.contains("m14-010-version"))
  }

  func testPackagingScriptDoesNotDuplicateReleaseLiteralAsDefaultInput() throws {
    let script = try read("Scripts/m14_010_rc1_release.sh")
    XCTAssertTrue(script.contains("VERSION_SOURCE=\"$ROOT_DIR/Sources/HermesReleaseVersion/HermesReleaseVersion.swift\""))
    XCTAssertTrue(script.contains("version_value productVersion"))
    XCTAssertFalse(script.contains("HERMES_RC_VERSION:-0.1.0-rc.1"))
    XCTAssertFalse(script.contains("HERMES_RELEASE_VERSION:-0.1.0-rc.1"))
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
