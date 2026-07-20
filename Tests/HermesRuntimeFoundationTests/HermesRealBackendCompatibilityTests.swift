import Darwin
import Foundation
import XCTest

@testable import HermesRuntimeFoundation

final class HermesRealBackendCompatibilityTests: XCTestCase {
  private var temporaryDirectory: URL!

  override func setUpWithError() throws {
    temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("HermesRealBackendCompatibilityTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: temporaryDirectory)
  }

  func testExecutableCandidateValidationAndExplicitPathDiscovery() throws {
    let executable = try fixtureExecutable(name: "hermes", version: "Hermes Agent v0.18.2")
    let discovery = HermesBackendDiscovery(
      explicitExecutablePath: executable,
      pathEnvironment: "",
      knownExecutableLocations: [],
      allowedExecutableRoots: [temporaryDirectory]
    )

    let result = try discovery.discover()

    XCTAssertEqual(result.candidate.originalPath, executable.path)
    XCTAssertEqual(result.candidate.resolvedPath, executable.path)
    XCTAssertTrue(result.identity.executableAvailable)
    XCTAssertEqual(result.identity.checksumSHA256?.count, 64)
    XCTAssertEqual(result.backendVersion?.rawValue, "0.18.2")
  }

  func testPATHDiscovery() throws {
    let bin = temporaryDirectory.appendingPathComponent("bin", isDirectory: true)
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    _ = try fixtureExecutable(name: "bin/hermes", version: "Hermes Agent v0.18.3")

    let result = try HermesBackendDiscovery(
      pathEnvironment: bin.path,
      knownExecutableLocations: [],
      allowedExecutableRoots: [temporaryDirectory]
    ).discover()

    XCTAssertEqual(result.backendVersion?.rawValue, "0.18.3")
  }

  func testMissingExecutableDirectoryAndNonExecutableRejections() throws {
    let directory = temporaryDirectory.appendingPathComponent("directory", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = temporaryDirectory.appendingPathComponent("not-executable")
    try "Hermes Agent v0.18.2\n".write(to: file, atomically: true, encoding: .utf8)

    let discovery = HermesBackendDiscovery(
      pathEnvironment: "",
      knownExecutableLocations: [],
      allowedExecutableRoots: [temporaryDirectory]
    )
    XCTAssertThrowsError(try discovery.validate(url: temporaryDirectory.appendingPathComponent("missing"))) {
      XCTAssertEqual($0 as? HermesBackendDiscoveryError, .executableUnavailable)
    }
    XCTAssertThrowsError(try discovery.validate(url: directory)) {
      XCTAssertEqual($0 as? HermesBackendDiscoveryError, .directoryRejected)
    }
    XCTAssertThrowsError(try discovery.validate(url: file)) {
      XCTAssertEqual($0 as? HermesBackendDiscoveryError, .nonExecutableRejected)
    }
  }

  func testUnsafeSymlinkRejection() throws {
    let outside = FileManager.default.temporaryDirectory
      .appendingPathComponent("hermes-outside-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: outside) }
    try "#!/bin/sh\nprintf 'Hermes Agent v0.18.2\\n'\n".write(to: outside, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o700))], ofItemAtPath: outside.path)
    let link = temporaryDirectory.appendingPathComponent("hermes-link")
    try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: outside.path)

    XCTAssertThrowsError(
      try HermesBackendDiscovery(
        explicitExecutablePath: link,
        pathEnvironment: "",
        knownExecutableLocations: [],
        allowedExecutableRoots: [temporaryDirectory]
      ).discover()
    ) {
      XCTAssertEqual($0 as? HermesBackendDiscoveryError, .unsafeSymlinkRejected)
    }
    XCTAssertThrowsError(
      try HermesBackendDiscovery(
        pathEnvironment: "",
        knownExecutableLocations: [],
        allowedExecutableRoots: [temporaryDirectory]
      ).validate(url: link)
    ) {
      XCTAssertEqual($0 as? HermesBackendDiscoveryError, .unsafeSymlinkRejected)
    }
  }

  func testVersionParsingAndPolicyStates() throws {
    XCTAssertEqual(HermesBackendVersion.parse("Hermes Agent v0.18.2")?.rawValue, "0.18.2")
    XCTAssertEqual(HermesBackendVersion.parse("hermes 1.2")?.rawValue, "1.2.0")
    XCTAssertNil(HermesBackendVersion.parse("not a version"))

    let policy = HermesBackendCompatibilityPolicy(
      minimumSupported: HermesBackendVersion(rawValue: "0.18.0", major: 0, minor: 18, patch: 0),
      maximumTested: HermesBackendVersion(rawValue: "0.19.0", major: 0, minor: 19, patch: 0),
      requiredCapabilities: [HermesBackendCapability("protocol_handshake")]
    )
    XCTAssertEqual(policy.classify(executableAvailable: false, version: nil, capabilities: []), .executableUnavailable)
    XCTAssertEqual(policy.classify(executableAvailable: true, version: nil, capabilities: []), .versionUnknown)
    XCTAssertEqual(policy.classify(executableAvailable: true, version: HermesBackendVersion(rawValue: "0.17.9", major: 0, minor: 17, patch: 9), capabilities: []), .unsupportedTooOld)
    XCTAssertEqual(policy.classify(executableAvailable: true, version: HermesBackendVersion(rawValue: "0.20.0", major: 0, minor: 20, patch: 0), capabilities: []), .unsupportedTooNew)
    XCTAssertEqual(policy.classify(executableAvailable: true, version: HermesBackendVersion(rawValue: "0.18.2", major: 0, minor: 18, patch: 2), capabilities: []), .incompatibleProtocol)
    XCTAssertEqual(policy.classify(executableAvailable: true, version: HermesBackendVersion(rawValue: "0.18.2", major: 0, minor: 18, patch: 2), capabilities: [HermesBackendCapability("protocol handshake")]), .supported)
  }

  func testSupportedWithWarningsAndCapabilityNormalization() throws {
    let policy = HermesBackendCompatibilityPolicy(requiredCapabilities: [])
    let capability = HermesBackendCapability("Health Probe!")
    XCTAssertEqual(capability.rawValue, "health_probe")
    XCTAssertEqual(
      policy.classify(
        executableAvailable: true,
        version: HermesBackendVersion(rawValue: "0.18.2", major: 0, minor: 18, patch: 2),
        capabilities: []
      ),
      .supportedWithWarnings
    )
  }

  func testVersionOutputByteBoundAndTimeout() throws {
    let large = try fixtureExecutable(
      name: "large-hermes",
      body: "printf 'Hermes Agent v0.18.2\\n'; yes A | head -c 10000\n"
    )
    let output = try HermesBackendDiscovery(
      explicitExecutablePath: large,
      pathEnvironment: "",
      knownExecutableLocations: [],
      allowedExecutableRoots: [temporaryDirectory],
      outputLimitBytes: 64
    ).discover().versionOutput
    XCTAssertLessThanOrEqual(Data(output.utf8).count, 128)

    let slow = try fixtureExecutable(name: "slow-hermes", body: "sleep 5\n")
    XCTAssertThrowsError(
      try HermesBackendDiscovery(
        explicitExecutablePath: slow,
        pathEnvironment: "",
        knownExecutableLocations: [],
        allowedExecutableRoots: [temporaryDirectory],
        timeoutSeconds: 0.1
      ).discover()
    ) {
      XCTAssertEqual($0 as? HermesBackendDiscoveryError, .versionTimedOut)
    }
    XCTAssertThrowsError(
      try HermesBackendDiscovery(
        pathEnvironment: "",
        knownExecutableLocations: [],
        allowedExecutableRoots: [temporaryDirectory],
        timeoutSeconds: 0.1
      ).validate(url: slow)
    ) {
      XCTAssertEqual($0 as? HermesBackendDiscoveryError, .versionTimedOut)
    }
  }

  func testIsolatedEnvironmentRootsAndRealProfileExclusion() throws {
    let environment = try HermesIsolatedBackendEnvironment(
      artifactRoot: temporaryDirectory.appendingPathComponent("artifacts/m9-001", isDirectory: true),
      realHome: URL(fileURLWithPath: "/Users/tester", isDirectory: true)
    )

    XCTAssertTrue(environment.home.hasSuffix("runtime/home"))
    XCTAssertTrue(environment.xdgConfigHome.hasSuffix("runtime/xdg-config"))
    XCTAssertTrue(environment.xdgCacheHome.hasSuffix("runtime/xdg-cache"))
    XCTAssertTrue(environment.xdgStateHome.hasSuffix("runtime/xdg-state"))
    XCTAssertTrue(environment.tmpdir.hasSuffix("runtime/tmp"))
    XCTAssertTrue(environment.realHermesProfileExcluded)
    XCTAssertFalse(environment.keychainAccessed)
    XCTAssertFalse(environment.shellStartupFilesLoaded)
    XCTAssertNil(environment.processEnvironment["HERMES_TOKEN"])
  }

  func testFixedArgumentCatalogAndArbitraryArgumentRejection() throws {
    let candidate = HermesExecutableCandidate(
      allowlistedCandidatePath: "/tmp/hermes",
      originalPath: "/tmp/hermes",
      resolvedPath: "/tmp/hermes",
      symlinkStatus: .notSymlink
    )
    let config = try HermesProcessConfiguration(
      executable: candidate,
      port: 19000,
      runtimeRoot: temporaryDirectory
    )
    XCTAssertEqual(config.fixedArguments, ["--safe-mode", "serve", "--host", "127.0.0.1", "--port", "19000", "--skip-build", "--isolated"])
    XCTAssertFalse(config.fixedArguments.contains("--prompt"))
    XCTAssertFalse(config.fixedArguments.contains(";"))
  }

  func testProcessSupervisionSecurityInSource() throws {
    let source = try String(contentsOf: URL(fileURLWithPath: "Sources/HermesRuntimeFoundation/HermesProcessSupervisor.swift"))
    XCTAssertTrue(source.contains("POSIX_SPAWN_SETPGROUP"))
    XCTAssertTrue(source.contains("pid:"))
    XCTAssertTrue(source.contains("pgid:"))
    XCTAssertTrue(source.contains("startupTimedOut"))
    XCTAssertTrue(source.contains("SIGTERM"))
    XCTAssertTrue(source.contains("SIGKILL"))
    XCTAssertFalse(source.contains("killall"))
    XCTAssertFalse(source.contains("pkill"))
  }

  func testSmokeRunnerReportRedactionAndHarmlessProbeSummary() throws {
    let executable = try fixtureExecutable(name: "hermes", version: "Hermes Agent v0.18.2")
    let report = try HermesRealBackendSmokeTestRunner(
      discovery: HermesBackendDiscovery(
        explicitExecutablePath: executable,
        pathEnvironment: "",
        knownExecutableLocations: [],
        allowedExecutableRoots: [temporaryDirectory]
      ),
      artifactRoot: temporaryDirectory.appendingPathComponent("artifacts/m9-001", isDirectory: true)
    ).run(now: Date(timeIntervalSince1970: 0))

    XCTAssertTrue(report.executableAvailable)
    XCTAssertEqual(report.compatibilityState, .supported)
    XCTAssertEqual(report.version, "0.18.2")
    XCTAssertTrue(report.capabilities.contains("version_output"))
    XCTAssertFalse(report.absolutePathExposed)
    let encoded = String(data: try JSONEncoder().encode(report), encoding: .utf8)!
    XCTAssertFalse(encoded.contains(temporaryDirectory.path))
    XCTAssertFalse(encoded.localizedCaseInsensitiveContains("prompt"))
    XCTAssertFalse(encoded.localizedCaseInsensitiveContains("token"))
  }

  func testTypedProbeResultsRepresentUnsupportedOperationsSafely() throws {
    let cleanup = HermesRealBackendCleanupReport(
      exactPIDTracked: true,
      exactPGIDTracked: true,
      gracefulShutdownPassed: true,
      controlledEscalationUsed: false,
      broadProcessTerminationUsed: false,
      residualProcess: false
    )
    XCTAssertTrue(cleanup.exactPIDTracked)
    XCTAssertTrue(cleanup.exactPGIDTracked)
    XCTAssertTrue(cleanup.gracefulShutdownPassed)
    XCTAssertFalse(cleanup.controlledEscalationUsed)
    XCTAssertFalse(cleanup.broadProcessTerminationUsed)
    XCTAssertFalse(cleanup.residualProcess)
  }

  private func fixtureExecutable(name: String, version: String) throws -> URL {
    try fixtureExecutable(name: name, body: "printf '\(version)\\n'\n")
  }

  private func fixtureExecutable(name: String, body: String) throws -> URL {
    let url = temporaryDirectory.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try ("#!/bin/sh\n" + body).write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o700))], ofItemAtPath: url.path)
    return url
  }
}
