import Foundation
import XCTest

@testable import HermesRuntimeFoundation

final class HermesBackendAdapterTests: XCTestCase {
  func testDiscoveryFailureIsTyped() throws {
    let adapter = adapter(discoveryError: HermesDiscoveryError.executableNotFound(path: "/allowed/hermes"))

    XCTAssertThrowsError(try adapter.discover()) {
      XCTAssertEqual(
        $0 as? HermesBackendAdapterError,
        .discoveryFailed(
          "executableNotFound(path: \"/allowed/hermes\")"))
    }
  }

  func testSuccessfulStartupDiscoversLaunchesAndChecksProtocolStatus() async throws {
    let supervisor = FakeSupervisor()
    let client = FakeProtocolClient(statusResults: [
      .success(Self.status(version: "0.18.2"))
    ])
    let adapter = adapter(supervisor: supervisor, client: client)

    let result = try await adapter.start()

    XCTAssertEqual(result.discovery.versionInfo.semanticVersion, "0.18.2")
    XCTAssertEqual(result.launch.launchContext.endpoint, try HermesBackendEndpoint(port: 19123))
    XCTAssertEqual(result.initialStatus.version, "0.18.2")
    XCTAssertEqual(supervisor.startCallCount, 1)
    XCTAssertEqual(client.fetchStatusCallCount, 1)
  }

  func testHealthFailureIsTypedAndRedacted() async throws {
    let secret = "secret-session-token"
    let client = FakeProtocolClient(statusResults: [
      .success(Self.status()),
      .failure(HermesProtocolClientError.transport("ws://127.0.0.1:19123/api/ws?token=\(secret)")),
    ])
    let adapter = adapter(client: client)
    _ = try await adapter.start()

    await XCTAssertThrowsAsyncError(try await adapter.health()) {
      guard case .healthFailed(let message) = $0 as? HermesBackendAdapterError else {
        return XCTFail("expected healthFailed, got \($0)")
      }
      XCTAssertFalse(message.contains(secret))
      XCTAssertTrue(message.contains("token=<redacted>"))
    }
  }

  func testGracefulShutdownClosesProtocolThenStopsSupervisor() async throws {
    let supervisor = FakeSupervisor()
    let client = FakeProtocolClient(statusResults: [.success(Self.status())])
    let adapter = adapter(supervisor: supervisor, client: client)
    _ = try await adapter.start()

    let result = try await adapter.stop()

    XCTAssertEqual(client.closeCallCount, 1)
    XCTAssertEqual(supervisor.stopCallCount, 1)
    XCTAssertEqual(result.processStop.exitStatus, 0)
    XCTAssertEqual(result.protocolState, HermesProtocolClientState.closed)
  }

  func testRepeatedShutdownIsIdempotent() async throws {
    let supervisor = FakeSupervisor()
    let client = FakeProtocolClient(statusResults: [.success(Self.status())])
    let adapter = adapter(supervisor: supervisor, client: client)
    _ = try await adapter.start()

    do {
      _ = try await adapter.stop()
      _ = try await adapter.stop()
    } catch {
      XCTFail("expected repeated shutdown to succeed, got \(error)")
    }

    XCTAssertEqual(client.closeCallCount, 1)
    XCTAssertEqual(supervisor.stopCallCount, 2)
  }

  func testProtocolUnavailableDuringStartupClosesClientAndStopsProcess() async throws {
    let supervisor = FakeSupervisor()
    let client = FakeProtocolClient(statusResults: [
      .failure(HermesProtocolClientError.transport("connection refused token=startup-secret"))
    ])
    let adapter = adapter(supervisor: supervisor, client: client)

    await XCTAssertThrowsAsyncError(try await adapter.start()) {
      guard case .protocolUnavailable(let message) = $0 as? HermesBackendAdapterError else {
        return XCTFail("expected protocolUnavailable, got \($0)")
      }
      XCTAssertFalse(message.contains("startup-secret"))
      XCTAssertTrue(message.contains("token=<redacted>"))
    }
    XCTAssertEqual(client.closeCallCount, 1)
    XCTAssertEqual(supervisor.stopCallCount, 1)
  }

  func testRedactedErrorsCoverTokenCarryingMessages() throws {
    let redacted = HermesBackendAdapter.redactedMessage(
      for: HermesProtocolClientError.transport(
        "GET ws://127.0.0.1:19123/api/ws?token=abc123&next=1 HERMES_DASHBOARD_SESSION_TOKEN=def456"
      )
    )

    XCTAssertFalse(redacted.contains("abc123"))
    XCTAssertFalse(redacted.contains("def456"))
    XCTAssertTrue(redacted.contains("token=<redacted>"))
    XCTAssertTrue(redacted.contains("HERMES_DASHBOARD_SESSION_TOKEN=<redacted>"))
  }

  private func adapter(
    discoveryError: Error? = nil,
    supervisor: FakeSupervisor = FakeSupervisor(),
    client: FakeProtocolClient = FakeProtocolClient(statusResults: [
      .success(HermesBackendAdapterTests.status())
    ])
  ) -> HermesBackendAdapter {
    HermesBackendAdapter(
      configuration: HermesBackendAdapterConfiguration(
        executableURL: URL(fileURLWithPath: "/allowed/hermes"),
        port: 19123,
        runtimeRoot: URL(fileURLWithPath: "/tmp/hermes-runtime")
      ),
      discovery: FakeDiscovery(error: discoveryError),
      supervisor: supervisor,
      protocolClientFactory: { _ in client }
    )
  }

  fileprivate static func status(version: String = "0.18.2") -> HermesBackendStatus {
    HermesBackendStatus(
      version: version,
      releaseDate: nil,
      authRequired: true,
      authMode: .loopbackToken,
      desktopContract: 3,
      gatewayRunning: true,
      gatewayState: "ready",
      activeAgents: 0,
      gatewayBusy: false,
      gatewayDrainable: true
    )
  }
}

private final class FakeDiscovery: HermesBackendDiscovering, @unchecked Sendable {
  private let error: Error?

  init(error: Error?) {
    self.error = error
  }

  func discover(at candidateURL: URL) throws -> HermesDiscoveryResult {
    if let error {
      throw error
    }
    return HermesDiscoveryResult(
      candidate: HermesExecutableCandidate(
        allowlistedCandidatePath: candidateURL.path,
        originalPath: candidateURL.path,
        resolvedPath: candidateURL.path,
        symlinkStatus: .notSymlink
      ),
      versionInfo: HermesVersionInfo(
        semanticVersion: "0.18.2",
        displayVersion: "Hermes 0.18.2",
        buildDateText: nil,
        upstreamRevision: nil,
        installationMethod: "fixture",
        pythonVersion: nil,
        openAISDKVersion: nil,
        rawOutputSHA256Digest: "fixture-digest",
        capturedOutputByteCount: 16,
        outputWasTruncated: false,
        sanitizedDiagnosticMetadata: [:]
      )
    )
  }
}

private final class FakeSupervisor: HermesBackendSupervising, @unchecked Sendable {
  private(set) var state: HermesProcessState = .idle
  private(set) var startCallCount = 0
  private(set) var stopCallCount = 0

  func start(configuration: HermesProcessConfiguration) throws -> HermesProcessLaunchResult {
    startCallCount += 1
    let identity = HermesProcessIdentity(
      pid: 100,
      pgid: 100,
      processStartIdentity: "fixture-start",
      resolvedExecutablePath: configuration.executable.resolvedPath,
      launchNonce: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
      expectedCommandShape: [configuration.executable.resolvedPath] + configuration.fixedArguments
    )
    state = .ready(identity)
    return HermesProcessLaunchResult(
      identity: identity,
      runtimeDirectory: configuration.runtimeRoot.appendingPathComponent("fixture-runtime"),
      launchContext: HermesBackendLaunchContext(
        identity: identity,
        endpoint: try HermesBackendEndpoint(port: configuration.port),
        sessionToken: configuration.sessionToken
      ),
      output: emptyOutputSnapshot()
    )
  }

  func stop() throws -> HermesProcessStopResult {
    stopCallCount += 1
    state = .exited(HermesProcessExit(pid: 100, status: 0))
    return HermesProcessStopResult(
      exitStatus: 0,
      output: emptyOutputSnapshot(),
      escapedDescendants: []
    )
  }
}

private final class FakeProtocolClient: HermesBackendProtocolClienting, @unchecked Sendable {
  private var statusResults: [Result<HermesBackendStatus, Error>]
  private(set) var state: HermesProtocolClientState = .ready
  private(set) var fetchStatusCallCount = 0
  private(set) var closeCallCount = 0

  init(statusResults: [Result<HermesBackendStatus, Error>]) {
    self.statusResults = statusResults
  }

  func fetchStatus() async throws -> HermesBackendStatus {
    fetchStatusCallCount += 1
    guard !statusResults.isEmpty else {
      return HermesBackendAdapterTests.status()
    }
    return try statusResults.removeFirst().get()
  }

  func close() async {
    guard state != .closed else {
      return
    }
    closeCallCount += 1
    state = .closed
  }
}

private func emptyOutputSnapshot() -> HermesProcessOutputSnapshot {
  HermesProcessOutputSnapshot(
    stdout: Data(),
    stderr: Data(),
    stdoutTruncated: false,
    stderrTruncated: false
  )
}

private func XCTAssertThrowsAsyncError<T>(
  _ expression: @autoclosure () async throws -> T,
  _ errorHandler: (Error) -> Void = { _ in },
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  do {
    _ = try await expression()
    XCTFail("expected error", file: file, line: line)
  } catch {
    errorHandler(error)
  }
}
