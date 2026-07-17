import Foundation
import XCTest

@testable import HermesRuntimeFoundation

final class HermesDiscoveryTests: XCTestCase {
  private var temporaryDirectory: URL!

  override func setUpWithError() throws {
    temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("HermesDiscoveryTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory,
      withIntermediateDirectories: true
    )
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: temporaryDirectory)
  }

  func testDirectExecutableSuccess() throws {
    let executable = try fixtureExecutable(
      named: "hermes",
      body: """
        printf 'Hermes Agent v0.18.2 (2026.7.7.2)\\n'
        printf 'Upstream: 56e2ba5e\\n'
        printf 'Install method: git\\n'
        printf 'Python: 3.11.15\\n'
        printf 'OpenAI SDK: 2.24.0\\n'
        """
    )

    let result = try HermesDiscovery(
      allowlistedExecutableCandidates: [executable]
    ).discover(at: executable)

    XCTAssertEqual(result.candidate.allowlistedCandidatePath, executable.path)
    XCTAssertEqual(result.candidate.originalPath, executable.path)
    XCTAssertEqual(result.candidate.resolvedPath, executable.path)
    XCTAssertEqual(result.candidate.symlinkStatus, .notSymlink)
    XCTAssertEqual(result.versionInfo.semanticVersion, "0.18.2")
    XCTAssertEqual(result.versionInfo.buildDateText, "2026.7.7.2")
    XCTAssertEqual(result.versionInfo.upstreamRevision, "56e2ba5e")
    XCTAssertEqual(result.versionInfo.installationMethod, "git")
    XCTAssertEqual(result.versionInfo.pythonVersion, "3.11.15")
    XCTAssertEqual(result.versionInfo.openAISDKVersion, "2.24.0")
    XCTAssertFalse(result.versionInfo.outputWasTruncated)
    XCTAssertEqual(result.versionInfo.rawOutputSHA256Digest.count, 64)
  }

  func testSymlinkExecutableSuccess() throws {
    let target = try fixtureExecutable(
      named: "hermes-real",
      body: "printf 'Hermes Agent v0.18.2 (2026.7.7.2)\\n'"
    )
    let symlink = temporaryDirectory.appendingPathComponent("hermes-link")
    try FileManager.default.createSymbolicLink(
      atPath: symlink.path,
      withDestinationPath: target.path
    )

    let result = try HermesDiscovery(
      allowlistedExecutableCandidates: [symlink]
    ).discover(at: symlink)

    XCTAssertEqual(result.candidate.originalPath, symlink.path)
    XCTAssertEqual(result.candidate.resolvedPath, target.path)
    XCTAssertEqual(result.candidate.symlinkStatus, .symlink(resolved: true))
    XCTAssertEqual(result.versionInfo.semanticVersion, "0.18.2")
  }

  func testMissingExecutable() throws {
    let missing = temporaryDirectory.appendingPathComponent("missing-hermes")

    XCTAssertThrowsError(
      try HermesDiscovery(
        allowlistedExecutableCandidates: [missing]
      ).discover(at: missing)
    ) { error in
      XCTAssertEqual(error as? HermesDiscoveryError, .executableNotFound(path: missing.path))
    }
  }

  func testNonAllowlistedPath() throws {
    let allowed = try fixtureExecutable(
      named: "allowed-hermes",
      body: "printf 'Hermes Agent v0.18.2 (2026.7.7.2)\\n'"
    )
    let rejected = try fixtureExecutable(
      named: "rejected-hermes",
      body: "printf 'Hermes Agent v0.18.2 (2026.7.7.2)\\n'"
    )

    XCTAssertThrowsError(
      try HermesDiscovery(
        allowlistedExecutableCandidates: [allowed]
      ).discover(at: rejected)
    ) { error in
      XCTAssertEqual(error as? HermesDiscoveryError, .pathNotAllowlisted(path: rejected.path))
    }
  }

  func testNonExecutableFile() throws {
    let file = temporaryDirectory.appendingPathComponent("not-executable")
    try "Hermes Agent v0.18.2 (2026.7.7.2)\n".write(to: file, atomically: true, encoding: .utf8)

    XCTAssertThrowsError(
      try HermesDiscovery(
        allowlistedExecutableCandidates: [file]
      ).discover(at: file)
    ) { error in
      XCTAssertEqual(error as? HermesDiscoveryError, .executableNotRunnable(path: file.path))
    }
  }

  func testValidHermesVersionOutput() throws {
    let executable = try fixtureExecutable(
      named: "version-hermes",
      body: """
        printf 'Hermes Agent v1.2.3 (2026.7.7.2)\\n'
        printf 'Upstream revision: abc123\\n'
        printf 'Installation method: archive\\n'
        printf 'Python: 3.12.1\\n'
        printf 'OpenAI SDK: 2.30.0\\n'
        """
    )

    let versionInfo = try HermesDiscovery(
      allowlistedExecutableCandidates: [executable]
    ).discover(at: executable).versionInfo

    XCTAssertEqual(versionInfo.semanticVersion, "1.2.3")
    XCTAssertEqual(versionInfo.displayVersion, "Hermes Agent v1.2.3 (2026.7.7.2)")
    XCTAssertEqual(versionInfo.buildDateText, "2026.7.7.2")
    XCTAssertEqual(versionInfo.upstreamRevision, "abc123")
    XCTAssertEqual(versionInfo.installationMethod, "archive")
    XCTAssertEqual(versionInfo.pythonVersion, "3.12.1")
    XCTAssertEqual(versionInfo.openAISDKVersion, "2.30.0")
  }

  func testMalformedOutput() throws {
    let executable = try fixtureExecutable(
      named: "malformed-hermes",
      body: "printf 'not hermes version output\\n'"
    )

    XCTAssertThrowsError(
      try HermesDiscovery(
        allowlistedExecutableCandidates: [executable]
      ).discover(at: executable)
    ) { error in
      XCTAssertEqual(error as? HermesDiscoveryError, .malformedVersionOutput)
    }
  }

  func testNonzeroExit() throws {
    let executable = try fixtureExecutable(
      named: "failing-hermes",
      body: """
        printf 'Hermes Agent v0.18.2 (2026.7.7.2)\\n'
        exit 42
        """
    )

    XCTAssertThrowsError(
      try HermesDiscovery(
        allowlistedExecutableCandidates: [executable]
      ).discover(at: executable)
    ) { error in
      XCTAssertEqual(error as? HermesDiscoveryError, .versionCommandFailed(exitCode: 42))
    }
  }

  func testTimeout() throws {
    let executable = try fixtureExecutable(
      named: "slow-hermes",
      body: "sleep 5"
    )

    XCTAssertThrowsError(
      try HermesDiscovery(
        allowlistedExecutableCandidates: [executable],
        timeoutSeconds: 0.1
      ).discover(at: executable)
    ) { error in
      XCTAssertEqual(error as? HermesDiscoveryError, .timeout)
    }
  }

  func testOversizedOutputBounding() throws {
    let executable = try fixtureExecutable(
      named: "large-hermes",
      body: """
        printf 'Hermes Agent v0.18.2 (2026.7.7.2)\\n'
        yes A | head -c 10000
        """
    )

    let result = try HermesDiscovery(
      allowlistedExecutableCandidates: [executable],
      outputLimitBytes: 128
    ).discover(at: executable)

    XCTAssertEqual(result.versionInfo.semanticVersion, "0.18.2")
    XCTAssertTrue(result.versionInfo.outputWasTruncated)
    XCTAssertLessThanOrEqual(result.versionInfo.capturedOutputByteCount, 256)
  }

  func testNoShellMetacharacterInterpretation() throws {
    let executable = try fixtureExecutable(
      named: "hermes;touch SHOULD_NOT_EXIST",
      body: """
        if [ "$1" = "--version" ]; then
          printf 'Hermes Agent v0.18.2 (2026.7.7.2)\\n'
        else
          exit 99
        fi
        """
    )
    let marker = temporaryDirectory.appendingPathComponent("SHOULD_NOT_EXIST")

    let result = try HermesDiscovery(
      allowlistedExecutableCandidates: [executable]
    ).discover(at: executable)

    XCTAssertEqual(result.versionInfo.semanticVersion, "0.18.2")
    XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
  }

  private func fixtureExecutable(named name: String, body: String) throws -> URL {
    let url = temporaryDirectory.appendingPathComponent(name)
    let script = """
      #!/bin/sh
      \(body)
      """
    try script.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: NSNumber(value: Int16(0o700))],
      ofItemAtPath: url.path
    )
    return url
  }
}
