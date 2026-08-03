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

  func testVersionOutputWithInlineUpstreamSuffix() throws {
    let executable = try fixtureExecutable(
      named: "version-hermes-inline-suffix",
      body: """
        printf 'Hermes Agent v0.18.2 (2026.7.7.2) · upstream 8e1debd5\\n'
        printf 'Install method: git\\n'
        printf 'Python: 3.11.15\\n'
        printf 'OpenAI SDK: 2.24.0\\n'
        """
    )

    let versionInfo = try HermesDiscovery(
      allowlistedExecutableCandidates: [executable]
    ).discover(at: executable).versionInfo

    XCTAssertEqual(versionInfo.semanticVersion, "0.18.2")
    XCTAssertEqual(
      versionInfo.displayVersion,
      "Hermes Agent v0.18.2 (2026.7.7.2) · upstream 8e1debd5"
    )
    XCTAssertEqual(versionInfo.buildDateText, "2026.7.7.2")
    XCTAssertEqual(versionInfo.installationMethod, "git")
    XCTAssertEqual(versionInfo.pythonVersion, "3.11.15")
    XCTAssertEqual(versionInfo.openAISDKVersion, "2.24.0")
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

  func testCurrentUserLocalBinSymlinkToHermesVenvExecutableIsAccepted() throws {
    let home = try fixtureHome()
    let localBin = home.appendingPathComponent(".local/bin", isDirectory: true)
    let venvBin = home.appendingPathComponent(".hermes/hermes-agent/venv/bin", isDirectory: true)
    try FileManager.default.createDirectory(at: localBin, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: venvBin, withIntermediateDirectories: true)
    let target = try fixtureExecutable(
      at: venvBin.appendingPathComponent("hermes"),
      body: "printf 'Hermes Agent v0.18.2 (2026.7.7.2)\\n'"
    )
    let symlink = localBin.appendingPathComponent("hermes")
    try FileManager.default.createSymbolicLink(atPath: symlink.path, withDestinationPath: target.path)

    let result = try productionStyleDiscovery(
      candidates: [symlink],
      sources: [symlink.path: "user-local-bin"],
      home: home
    ).discoverFirstAvailable(candidates: [symlink])

    XCTAssertEqual(result.candidate.sourceCategory, "user-local-bin")
    XCTAssertEqual(result.candidate.symlinkStatus, .symlink(resolved: true))
    XCTAssertEqual(result.versionInfo.semanticVersion, "0.18.2")
  }

  func testBrokenSymlinkRejected() throws {
    let home = try fixtureHome()
    let localBin = home.appendingPathComponent(".local/bin", isDirectory: true)
    try FileManager.default.createDirectory(at: localBin, withIntermediateDirectories: true)
    let symlink = localBin.appendingPathComponent("hermes")
    try FileManager.default.createSymbolicLink(
      atPath: symlink.path,
      withDestinationPath: home.appendingPathComponent(".hermes/missing/hermes").path
    )

    XCTAssertThrowsError(
      try productionStyleDiscovery(candidates: [symlink], home: home)
        .discoverFirstAvailable(candidates: [symlink])
    ) { error in
      guard case .executableNotFound = error as? HermesDiscoveryError else {
        return XCTFail("expected executableNotFound, got \(error)")
      }
    }
  }

  func testAnotherUsersHomeRejectedByCurrentUserInvariant() throws {
    let home = try fixtureHome()
    let otherHome = temporaryDirectory.appendingPathComponent("other-home", isDirectory: true)
    let otherBin = otherHome.appendingPathComponent(".local/bin", isDirectory: true)
    try FileManager.default.createDirectory(at: otherBin, withIntermediateDirectories: true)
    let candidate = try fixtureExecutable(
      at: otherBin.appendingPathComponent("hermes"),
      body: "printf 'Hermes Agent v0.18.2 (2026.7.7.2)\\n'"
    )

    XCTAssertThrowsError(
      try productionStyleDiscovery(candidates: [candidate], home: home)
        .discoverFirstAvailable(candidates: [candidate])
    ) { error in
      XCTAssertEqual(error as? HermesDiscoveryError, .unsafeExecutablePath(path: candidate.path))
    }
  }

  func testWorldWritableParentRejected() throws {
    let home = try fixtureHome()
    let localBin = home.appendingPathComponent(".local/bin", isDirectory: true)
    try FileManager.default.createDirectory(at: localBin, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: localBin.path)
    let candidate = try fixtureExecutable(
      at: localBin.appendingPathComponent("hermes"),
      body: "printf 'Hermes Agent v0.18.2 (2026.7.7.2)\\n'"
    )

    XCTAssertThrowsError(
      try productionStyleDiscovery(candidates: [candidate], home: home)
        .discoverFirstAvailable(candidates: [candidate])
    ) { error in
      XCTAssertEqual(error as? HermesDiscoveryError, .unsafeExecutablePath(path: candidate.path))
    }
  }

  func testNonExecutableProductionCandidateRejected() throws {
    let home = try fixtureHome()
    let localBin = home.appendingPathComponent(".local/bin", isDirectory: true)
    try FileManager.default.createDirectory(at: localBin, withIntermediateDirectories: true)
    let candidate = localBin.appendingPathComponent("hermes")
    try "Hermes Agent v0.18.2\n".write(to: candidate, atomically: true, encoding: .utf8)

    XCTAssertThrowsError(
      try productionStyleDiscovery(candidates: [candidate], home: home)
        .discoverFirstAvailable(candidates: [candidate])
    ) { error in
      XCTAssertEqual(error as? HermesDiscoveryError, .executableNotRunnable(path: candidate.path))
    }
  }

  func testDirectoryProductionCandidateRejected() throws {
    let home = try fixtureHome()
    let candidate = home.appendingPathComponent(".local/bin/hermes", isDirectory: true)
    try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)

    XCTAssertThrowsError(
      try productionStyleDiscovery(candidates: [candidate], home: home)
        .discoverFirstAvailable(candidates: [candidate])
    ) { error in
      XCTAssertEqual(error as? HermesDiscoveryError, .executableNotFound(path: candidate.path))
    }
  }

  func testExplicitCandidateWinsBeforePathCandidate() throws {
    let explicit = try fixtureExecutable(
      named: "explicit-hermes",
      body: "printf 'Hermes Agent v0.18.2 (2026.7.7.2)\\n'"
    )
    let path = try fixtureExecutable(
      named: "path-hermes",
      body: "printf 'Hermes Agent v0.19.0 (2026.7.7.2)\\n'"
    )

    let result = try HermesDiscovery(
      allowlistedExecutableCandidates: [explicit, path],
      sourceCategoriesByCandidatePath: [explicit.path: "explicit", path.path: "path"]
    ).discoverFirstAvailable(candidates: [explicit, path])

    XCTAssertEqual(result.candidate.sourceCategory, "explicit")
    XCTAssertEqual(result.versionInfo.semanticVersion, "0.18.2")
  }

  func testPathCandidateWorksBeforeFallbacks() throws {
    let path = try fixtureExecutable(
      named: "path-hermes",
      body: "printf 'Hermes Agent v0.18.2 (2026.7.7.2)\\n'"
    )
    let fallback = try fixtureExecutable(
      named: "fallback-hermes",
      body: "printf 'Hermes Agent v0.19.0 (2026.7.7.2)\\n'"
    )

    let result = try HermesDiscovery(
      allowlistedExecutableCandidates: [path, fallback],
      sourceCategoriesByCandidatePath: [path.path: "path", fallback.path: "homebrew"]
    ).discoverFirstAvailable(candidates: [path, fallback])

    XCTAssertEqual(result.candidate.sourceCategory, "path")
    XCTAssertEqual(result.versionInfo.semanticVersion, "0.18.2")
  }

  func testHomebrewAndUsrLocalFallbackSourcesWork() throws {
    let missingPath = temporaryDirectory.appendingPathComponent("missing-path-hermes")
    let homebrew = try fixtureExecutable(
      named: "homebrew-hermes",
      body: "printf 'Hermes Agent v0.18.2 (2026.7.7.2)\\n'"
    )
    let usrLocal = try fixtureExecutable(
      named: "usr-local-hermes",
      body: "printf 'Hermes Agent v0.19.0 (2026.7.7.2)\\n'"
    )

    let discovery = HermesDiscovery(
      allowlistedExecutableCandidates: [missingPath, homebrew, usrLocal],
      sourceCategoriesByCandidatePath: [
        missingPath.path: "path",
        homebrew.path: "homebrew",
        usrLocal.path: "usr-local",
      ]
    )
    let result = try discovery.discoverFirstAvailable(candidates: [missingPath, homebrew, usrLocal])

    XCTAssertEqual(result.candidate.sourceCategory, "homebrew")
    XCTAssertEqual(result.versionInfo.semanticVersion, "0.18.2")
  }

  func testAbsolutePathNotExposedInVersionDescriptor() throws {
    let executable = try fixtureExecutable(
      named: "descriptor-hermes",
      body: "printf 'Hermes Agent v0.18.2 (2026.7.7.2)\\n'"
    )
    let result = try HermesDiscovery(
      allowlistedExecutableCandidates: [executable],
      sourceCategoriesByCandidatePath: [executable.path: "path"]
    ).discover(at: executable)
    let descriptor = HermesAgentVersionDescriptor(
      result: result,
      sourceCategory: result.candidate.sourceCategory
    )
    let encoded = String(data: try JSONEncoder().encode(descriptor), encoding: .utf8)!

    XCTAssertFalse(encoded.contains(temporaryDirectory.path))
    XCTAssertEqual(descriptor.semanticVersion, "0.18.2")
    XCTAssertEqual(descriptor.executableBasename, "descriptor-hermes")
  }

  private func fixtureExecutable(named name: String, body: String) throws -> URL {
    let url = temporaryDirectory.appendingPathComponent(name)
    return try fixtureExecutable(at: url, body: body)
  }

  private func fixtureExecutable(at url: URL, body: String) throws -> URL {
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

  private func fixtureHome() throws -> URL {
    let home = temporaryDirectory.appendingPathComponent("home", isDirectory: true)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return home
  }

  private func productionStyleDiscovery(
    candidates: [URL],
    sources: [String: String] = [:],
    home: URL
  ) -> HermesDiscovery {
    HermesDiscovery(
      allowlistedExecutableCandidates: candidates,
      sourceCategoriesByCandidatePath: sources,
      approvedResolvedPathPrefixes: [
        home.appendingPathComponent(".local/bin", isDirectory: true),
        home.appendingPathComponent(".hermes", isDirectory: true),
      ],
      currentUserHomeURL: home,
      enforceCurrentUserSafety: true
    )
  }
}
