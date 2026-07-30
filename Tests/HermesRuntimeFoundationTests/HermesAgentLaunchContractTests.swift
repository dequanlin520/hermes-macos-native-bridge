import Darwin
import Foundation
import XCTest

@testable import HermesRuntimeFoundation

final class HermesAgentLaunchContractTests: XCTestCase {
  private var temporaryDirectory: URL!

  override func setUpWithError() throws {
    temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("HermesAgentLaunchContractTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: temporaryDirectory)
  }

  func testSemanticVersionAdapterSelectionForObserved018Family() throws {
    let contract = HermesAgentLaunchContractSelector.select(
      discoveryResult: try discoveryResult(version: "0.18.2"),
      commandSurface: HermesAgentCommandSurface(
        versionOutput: "Hermes Agent v0.18.2",
        rootHelpOutput: "Commands:\n  serve\n  status\n  stop\n",
        subcommandHelp: ["serve": "serve --isolated", "status": "status", "stop": "stop"]
      )
    )

    XCTAssertEqual(contract.status, .supported)
    XCTAssertEqual(contract.observedVersion, "0.18.2")
    XCTAssertEqual(contract.descriptor.requiredArguments, ["serve"])
    XCTAssertEqual(contract.readinessMechanism, .documentedStatusCommand)
  }

  func testUnknownVersionRejected() throws {
    let contract = HermesAgentLaunchContractSelector.unsupported(
      version: nil,
      status: .blocked,
      reason: "version.unknown"
    )

    XCTAssertEqual(contract.status, .blocked)
    XCTAssertEqual(contract.reasonCode, "version.unknown")
    XCTAssertFalse(contract.isStartable)
  }

  func testFutureVersionIsNotAssumedCompatible() throws {
    let contract = HermesAgentLaunchContractSelector.select(
      discoveryResult: try discoveryResult(version: "0.19.0"),
      commandSurface: HermesAgentCommandSurface(
        versionOutput: "Hermes Agent v0.19.0",
        rootHelpOutput: "Commands:\n  serve\n  status\n  stop\n",
        subcommandHelp: ["serve": "serve --isolated"]
      )
    )

    XCTAssertEqual(contract.status, .incompatible)
    XCTAssertEqual(contract.reasonCode, "version.out_of_range")
  }

  func testUnsupportedContractSerializationIsPrivacySafe() throws {
    let contract = HermesAgentLaunchContractSelector.unsupported(
      version: "0.18.2",
      reason: "startup.command.not_advertised"
    )
    let encoded = String(data: try JSONEncoder().encode(contract), encoding: .utf8) ?? ""

    XCTAssertTrue(encoded.contains("\"unsupported\""))
    XCTAssertFalse(encoded.contains("/Users/"))
    XCTAssertFalse(encoded.contains("token"))
    XCTAssertFalse(encoded.contains("UUID"))
  }

  func testServeStopAllSurfaceIsUnsupportedForExactIsolatedLifecycle() throws {
    let contract = HermesAgentLaunchContractSelector.select(
      discoveryResult: try discoveryResult(version: "0.18.2"),
      commandSurface: HermesAgentCommandSurface(
        versionOutput: "Hermes Agent v0.18.2",
        rootHelpOutput: "Commands:\n  serve\n  status\n",
        subcommandHelp: [
          "serve": "serve --isolated --status --stop Stop all running Hermes web server processes",
          "status": "status",
        ]
      )
    )

    XCTAssertEqual(contract.status, .unsupported)
    XCTAssertEqual(contract.reasonCode, "shutdown.command.not_advertised")
  }

  func testNoBareHermesInvocation() throws {
    XCTAssertThrowsError(try HermesAgentCommandSafetyPolicy.validateProbeArguments([])) {
      XCTAssertEqual($0 as? HermesAgentLifecycleError, .forbiddenCommand("bare-hermes"))
    }
    try HermesAgentCommandSafetyPolicy.validateProbeArguments(["--version"])
    try HermesAgentCommandSafetyPolicy.validateProbeArguments(["--help"])
    try HermesAgentCommandSafetyPolicy.validateProbeArguments(["status", "--help"])
    XCTAssertThrowsError(try HermesAgentCommandSafetyPolicy.validateProbeArguments(["login", "--help"]))
  }

  func testIsolatedEnvironmentConstruction() throws {
    let environment = try HermesAgentLaunchEnvironment.construct(
      runtimeRoot: temporaryDirectory.appendingPathComponent("runtime", isDirectory: true),
      inherited: ["HOME": temporaryDirectory.appendingPathComponent("real-home").path]
    )

    XCTAssertEqual(environment.variables["HERMES_HOME"]?.contains("hermes-home"), true)
    XCTAssertEqual(environment.variables["PATH"], "/usr/bin:/bin:/usr/sbin:/sbin")
    XCTAssertFalse(environment.variables.values.contains { $0.contains("/.hermes") })
  }

  func testRealHomeRejection() throws {
    let realHome = temporaryDirectory.appendingPathComponent("real-home", isDirectory: true)
    let realHermes = realHome.appendingPathComponent(".hermes", isDirectory: true)

    XCTAssertThrowsError(
      try HermesAgentLaunchEnvironment.construct(
        runtimeRoot: realHermes,
        inherited: ["HOME": realHome.path]
      )
    )
  }

  func testSymlinkEscapeRejection() throws {
    let outside = temporaryDirectory.appendingPathComponent("outside", isDirectory: true)
    let root = temporaryDirectory.appendingPathComponent("runtime", isDirectory: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let link = root.appendingPathComponent("home")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

    XCTAssertThrowsError(try HermesAgentLaunchEnvironment.construct(runtimeRoot: root))
  }

  func testPathTraversalRejection() throws {
    let root = URL(fileURLWithPath: temporaryDirectory.path + "/runtime/../escape")
    XCTAssertThrowsError(try HermesAgentLaunchEnvironment.construct(runtimeRoot: root))
  }

  private func discoveryResult(version: String) throws -> HermesDiscoveryResult {
    let executable = temporaryDirectory.appendingPathComponent("hermes")
    try "#!/bin/sh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    return HermesDiscoveryResult(
      candidate: HermesExecutableCandidate(
        allowlistedCandidatePath: executable.path,
        originalPath: executable.path,
        resolvedPath: executable.path,
        symlinkStatus: .notSymlink
      ),
      versionInfo: HermesVersionInfo(
        semanticVersion: version,
        displayVersion: "Hermes Agent v\(version)",
        buildDateText: nil,
        upstreamRevision: nil,
        installationMethod: nil,
        pythonVersion: nil,
        openAISDKVersion: nil,
        rawOutputSHA256Digest: "digest",
        capturedOutputByteCount: 1,
        outputWasTruncated: false,
        sanitizedDiagnosticMetadata: [:]
      )
    )
  }
}
