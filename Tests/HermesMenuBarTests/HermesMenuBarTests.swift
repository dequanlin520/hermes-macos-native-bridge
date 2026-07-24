import Foundation
@testable import HermesMenuBar
@testable import HermesRuntimeFoundation
import XCTest

final class HermesMenuBarTests: XCTestCase {
  func testInitialState() async {
    let controller = HermesMenuBarController(commandAPI: makeRecordingAPI().api)

    let state = await controller.currentState()

    XCTAssertNil(state.runtimeStatus)
    XCTAssertNil(state.sessionSummary)
    XCTAssertEqual(state.healthState, .unavailable)
    XCTAssertTrue(state.recentEvents.isEmpty)
    XCTAssertNil(state.lastErrorMessage)
  }

  func testStatusUpdate() async {
    let controller = HermesMenuBarController(commandAPI: makeRecordingAPI().api)

    let state = await controller.refreshStatus()

    XCTAssertEqual(state.runtimeStatus, .created)
    XCTAssertEqual(state.sessionSummary?.status, .created)
    XCTAssertEqual(state.healthState, .stopped)
  }

  func testEventReceptionUpdatesStateWithoutPollingSource() async throws {
    let recording = makeRecordingAPI()
    let controller = HermesMenuBarController(commandAPI: recording.api)

    await controller.startEventSubscription()
    _ = await controller.refreshStatus()
    let state = try await waitForState(controller) { !$0.recentEvents.isEmpty }

    XCTAssertEqual(state.recentEvents.first?.kind, .sessionCreated)
    XCTAssertEqual(state.recentEvents.first?.status, .created)
    XCTAssertFalse(String(describing: state.recentEvents).contains("4242"))
    XCTAssertFalse(String(describing: state.recentEvents).contains("/allowed/hermes"))
  }

  func testStartCommandForwarding() async {
    let recording = makeRecordingAPI()
    let controller = HermesMenuBarController(commandAPI: recording.api)

    let state = await controller.startHermes()

    XCTAssertEqual(state.runtimeStatus, .running)
    XCTAssertEqual(state.healthState, .healthy)
    XCTAssertTrue(recording.api.commands.contains(.createSession))
    XCTAssertTrue(recording.api.commands.contains { command in
      if case .startSession = command { return true }
      return false
    })
  }

  func testStopCommandForwarding() async {
    let recording = makeRecordingAPI()
    let controller = HermesMenuBarController(commandAPI: recording.api)

    _ = await controller.startHermes()
    let state = await controller.stopHermes()

    XCTAssertEqual(state.runtimeStatus, .stopped)
    XCTAssertTrue(recording.api.commands.contains { command in
      if case .stopSession(_, reason: .requested) = command { return true }
      return false
    })
  }

  func testErrorDisplayIsRedacted() async {
    let recording = makeRecordingAPI(
      startError: HermesRuntimeCommandAPIError.operationFailed(
        "token=start-secret failed at /Users/example/.hermes/backend"
      )
    )
    let controller = HermesMenuBarController(commandAPI: recording.api)

    let state = await controller.startHermes()

    XCTAssertEqual(state.healthState, .failed)
    XCTAssertEqual(state.runtimeStatus, .created)
    XCTAssertTrue(state.lastErrorMessage?.contains("token=<redacted>") ?? false)
    XCTAssertFalse(state.lastErrorMessage?.contains("start-secret") ?? true)
    XCTAssertFalse(state.lastErrorMessage?.contains("/Users/") ?? true)
  }

  private func makeRecordingAPI(
    startError: Error? = nil
  ) -> (api: RecordingRuntimeCommandAPI, eventBus: HermesRuntimeEventBus) {
    let sessionID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    let eventBus = HermesRuntimeEventBus()
    let manager = HermesRuntimeSessionManager(
      backendFactory: { MenuBarFakeBackend() },
      sessionIDFactory: { sessionID },
      clock: { Date(timeIntervalSince1970: 1_800_000_000) },
      eventBus: eventBus
    )
    let commandAPI = HermesRuntimeCommandAPI(sessionManager: manager)
    return (
      RecordingRuntimeCommandAPI(delegate: commandAPI, startError: startError),
      eventBus
    )
  }

  private func waitForState(
    _ controller: HermesMenuBarController,
    matching predicate: (HermesMenuBarState) -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async throws -> HermesMenuBarState {
    for _ in 0..<50 {
      let state = await controller.currentState()
      if predicate(state) {
        return state
      }
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTFail("Timed out waiting for menu bar state", file: file, line: line)
    return await controller.currentState()
  }
}

private final class RecordingRuntimeCommandAPI: HermesRuntimeCommandExecuting, @unchecked Sendable {
  private let delegate: HermesRuntimeCommandAPI
  private let startError: Error?
  private let lock = NSLock()
  private var storage: [HermesRuntimeCommand] = []

  init(delegate: HermesRuntimeCommandAPI, startError: Error?) {
    self.delegate = delegate
    self.startError = startError
  }

  var commands: [HermesRuntimeCommand] {
    lock.withLock { storage }
  }

  func execute(_ command: HermesRuntimeCommand) async throws -> HermesRuntimeCommandResult {
    lock.withLock {
      storage.append(command)
    }
    if case .startSession = command, let startError {
      throw startError
    }
    return try await delegate.execute(command)
  }
}

private final class MenuBarFakeBackend: HermesBackendAdapting, @unchecked Sendable {
  func discover() throws -> HermesDiscoveryResult {
    HermesDiscoveryResult(
      candidate: HermesExecutableCandidate(
        allowlistedCandidatePath: "/allowed/hermes",
        originalPath: "/allowed/hermes",
        resolvedPath: "/allowed/hermes",
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

  func start() async throws -> HermesBackendStartResult {
    let identity = processIdentity()
    return HermesBackendStartResult(
      discovery: try discover(),
      launch: HermesProcessLaunchResult(
        identity: identity,
        runtimeDirectory: URL(fileURLWithPath: "/tmp/hermes-runtime/session"),
        launchContext: HermesBackendLaunchContext(
          identity: identity,
          endpoint: try HermesBackendEndpoint(port: 19123),
          sessionToken: try HermesBackendSessionToken.generate()
        ),
        output: outputSnapshot()
      ),
      initialStatus: backendStatus()
    )
  }

  func stop() async throws -> HermesBackendStopResult {
    HermesBackendStopResult(
      processStop: HermesProcessStopResult(
        exitStatus: 0,
        output: outputSnapshot(),
        escapedDescendants: []
      ),
      protocolState: .closed
    )
  }

  func health() async throws -> HermesBackendHealthSnapshot {
    HermesBackendHealthSnapshot(
      processState: .ready(processIdentity()),
      protocolState: .ready,
      status: backendStatus()
    )
  }

  private func processIdentity() -> HermesProcessIdentity {
    HermesProcessIdentity(
      pid: 4242,
      pgid: 4242,
      processStartIdentity: "fixture-start-4242",
      resolvedExecutablePath: "/allowed/hermes",
      launchNonce: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
      expectedCommandShape: ["/allowed/hermes", "--safe-mode", "serve"]
    )
  }

  private func outputSnapshot() -> HermesProcessOutputSnapshot {
    HermesProcessOutputSnapshot(
      stdout: Data(),
      stderr: Data(),
      stdoutTruncated: false,
      stderrTruncated: false
    )
  }

  private func backendStatus() -> HermesBackendStatus {
    let json = """
      {
        "version": "0.18.2",
        "release_date": "2026-07-01",
        "auth_required": true,
        "auth_mode": "loopback_token",
        "desktop_contract": 3,
        "gateway_running": true,
        "gateway_state": "ready",
        "active_agents": 0,
        "gateway_busy": false,
        "gateway_drainable": true
      }
      """
    return try! JSONDecoder().decode(HermesBackendStatus.self, from: Data(json.utf8))
  }
}
