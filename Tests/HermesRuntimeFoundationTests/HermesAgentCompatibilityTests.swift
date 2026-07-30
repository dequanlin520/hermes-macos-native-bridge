import Foundation
import XCTest

@testable import HermesRuntimeFoundation

final class HermesAgentCompatibilityTests: XCTestCase {
  private var temporaryDirectory: URL!

  override func setUpWithError() throws {
    temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("HermesAgentCompatibilityTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: temporaryDirectory)
  }

  func testSemanticVersionCompatibleForCurrentZeroMajorContract() throws {
    XCTAssertEqual(
      HermesAgentCompatibilityReport.compatibilityLevel(forSemanticVersion: "0.18.2"),
      .compatible
    )
    XCTAssertEqual(
      HermesAgentCompatibilityReport.compatibilityLevel(forSemanticVersion: "1.0.0"),
      .incompatible
    )
  }

  func testUnknownVersionIsUnverified() throws {
    XCTAssertEqual(
      HermesAgentCompatibilityReport.compatibilityLevel(forSemanticVersion: nil),
      .unverified
    )
    XCTAssertEqual(
      HermesAgentCompatibilityReport.compatibilityLevel(forSemanticVersion: "not-a-version"),
      .unverified
    )
  }

  func testMissingExecutableBecomesBlockedReport() throws {
    let report = HermesAgentCompatibilityReport.blocked(reasonCode: "discovery.executable_not_found")

    XCTAssertEqual(report.overallCompatibilityLevel, .blocked)
    XCTAssertEqual(report.versionDescriptor.discoveryStatus, "unavailable")
    XCTAssertEqual(report.capabilities.first?.capabilityIdentifier, .executableDiscovery)
    XCTAssertEqual(report.capabilities.first?.compatibilityLevel, .blocked)
    XCTAssertTrue(report.capabilities.contains { $0.capabilityIdentifier == .realHomeIsolation })
  }

  func testDiscoveredExecutableProducesPartialMatrixUntilLifecycleIsExercised() throws {
    let executable = try fixtureExecutable(
      named: "hermes",
      body: "printf 'Hermes Agent v0.18.2 (2026.7.7.2)\\n'"
    )
    let result = try HermesDiscovery(allowlistedExecutableCandidates: [executable])
      .discover(at: executable)

    let report = HermesAgentCompatibilityReport.discovered(result)

    XCTAssertEqual(report.overallCompatibilityLevel, .partiallyCompatible)
    XCTAssertEqual(report.versionDescriptor.executableFamily, "hermes-agent")
    XCTAssertEqual(report.versionDescriptor.executableBasename, "hermes")
    XCTAssertEqual(report.versionDescriptor.semanticVersion, "0.18.2")
    XCTAssertEqual(
      report.capabilities.first(where: { $0.capabilityIdentifier == .boundedAgentStartup })?
        .compatibilityLevel,
      .blocked
    )
  }

  func testDeterministicMatrixOrdering() throws {
    let report = HermesAgentCompatibilityReport.blocked(reasonCode: "discovery.executable_not_found")

    XCTAssertEqual(report.capabilities.map(\.capabilityIdentifier), HermesAgentCapabilityID.allCases)
  }

  func testPrivacySafeDescriptorRedactsPathLikeValues() throws {
    let descriptor = HermesAgentVersionDescriptor(
      discoveryStatus: "available",
      executableFamily: "hermes-agent",
      executableBasename: "/Users/example/.local/bin/hermes",
      semanticVersion: "0.18.2-private",
      versionCommandExitStatus: "0",
      supportedInvocationStyle: "direct-executable",
      sourceCategory: "PATH"
    )
    let encoded = String(data: try JSONEncoder().encode(descriptor), encoding: .utf8) ?? ""

    XCTAssertEqual(descriptor.executableBasename, "hermes")
    XCTAssertEqual(descriptor.semanticVersion, "0.18.2")
    XCTAssertFalse(encoded.contains("/Users"))
    XCTAssertFalse(encoded.contains("/.local/"))
  }

  private func fixtureExecutable(named name: String, body: String) throws -> URL {
    let url = temporaryDirectory.appendingPathComponent(name)
    let script = """
      #!/bin/sh
      \(body)
      """
    try script.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
  }
}
