import Foundation
import XCTest

@testable import HermesRuntimeFoundation

final class HermesRuntimeCommandAPITests: XCTestCase {
  func testCreateSessionReturnsTypedStatusWithoutRawProcessDetails() throws {
    let sessionID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
    let api = api(sessionIDs: [sessionID])

    let status = api.createSession()

    XCTAssertEqual(status.sessionID, sessionID)
    XCTAssertEqual(status.currentStatus, .created)
    XCTAssertNil(status.backendVersion)
    XCTAssertNil(status.capabilities)
    XCTAssertFalse(status.description.contains("/allowed/hermes"))
    XCTAssertFalse(status.description.contains("4242"))
  }

  func testStartSessionDelegatesToManagerAndReturnsTypedStatus() async throws {
    let sessionID = UUID(uuidString: "30000000-0000-0000-0000-000000000002")!
    let startTime = Date(timeIntervalSince1970: 1_800_000_000)
    let backend = CommandAPIFakeBackend(startResult: .success(Self.startResult()))
    let api = api(sessionIDs: [sessionID], backends: [backend], dates: [startTime])
    _ = api.createSession()

    let status = try await api.startSession(sessionID)

    XCTAssertEqual(status.currentStatus, .running)
    XCTAssertEqual(status.backendVersion, "0.18.2")
    XCTAssertEqual(status.startTime, startTime)
    XCTAssertEqual(status.capabilities?.desktopContract, 3)
    XCTAssertEqual(backend.startCallCount, 1)
    XCTAssertFalse(status.description.contains("/allowed/hermes"))
    XCTAssertFalse(status.description.contains("4242"))
  }

  func testStopSessionDelegatesToManagerAndReturnsTypedStatus() async throws {
    let sessionID = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
    let backend = CommandAPIFakeBackend(startResult: .success(Self.startResult()))
    let api = api(sessionIDs: [sessionID], backends: [backend])
    _ = api.createSession()
    _ = try await api.startSession(sessionID)

    let status = try await api.stopSession(sessionID)

    XCTAssertEqual(status.currentStatus, .stopped)
    XCTAssertEqual(status.shutdownReason, .requested)
    XCTAssertEqual(backend.stopCallCount, 1)
  }

  func testGetSessionStatusReturnsCurrentManagerSnapshot() async throws {
    let sessionID = UUID(uuidString: "30000000-0000-0000-0000-000000000004")!
    let api = api(sessionIDs: [sessionID])
    _ = api.createSession()

    let status = try api.getSessionStatus(sessionID)

    XCTAssertEqual(status.sessionID, sessionID)
    XCTAssertEqual(status.currentStatus, .created)
  }

  func testInvalidSessionReturnsTypedCommandError() async throws {
    let sessionID = UUID(uuidString: "30000000-0000-0000-0000-000000000005")!
    let api = api(sessionIDs: [])

    await XCTAssertThrowsAsyncError(try await api.startSession(sessionID)) {
      XCTAssertEqual(
        $0 as? HermesRuntimeCommandAPIError,
        .sessionManager(.sessionNotFound(sessionID))
      )
    }
  }

  func testBackendErrorIsPropagatedAsTypedCommandErrorAndRedactedInStatus() async throws {
    let sessionID = UUID(uuidString: "30000000-0000-0000-0000-000000000006")!
    let backendError = HermesBackendAdapterError.startupFailed("token=start-secret failed")
    let backend = CommandAPIFakeBackend(startResult: .failure(backendError))
    let api = api(sessionIDs: [sessionID], backends: [backend])
    _ = api.createSession()

    await XCTAssertThrowsAsyncError(try await api.startSession(sessionID)) {
      XCTAssertEqual($0 as? HermesRuntimeCommandAPIError, .backendAdapter(backendError))
    }

    let status = try api.getSessionStatus(sessionID)
    XCTAssertEqual(status.currentStatus, .failed)
    XCTAssertFalse(status.lastErrorMessage?.contains("start-secret") ?? true)
    XCTAssertTrue(status.lastErrorMessage?.contains("token=<redacted>") ?? false)
  }

  func testEventSubscriptionReturnsCommandEventsWithoutRawProcessDetails() async throws {
    let sessionID = UUID(uuidString: "30000000-0000-0000-0000-000000000007")!
    let eventBus = HermesRuntimeEventBus(
      subscriptionIDFactory: {
        UUID(uuidString: "30000000-0000-0000-0000-000000000107")!
      }
    )
    let api = api(sessionIDs: [sessionID], eventBus: eventBus)
    let subscription = api.subscribeEvents()
    var iterator = subscription.events.makeAsyncIterator()

    _ = api.createSession()

    let event = try await nextEvent(from: &iterator)
    XCTAssertEqual(subscription.id, UUID(uuidString: "30000000-0000-0000-0000-000000000107")!)
    XCTAssertEqual(event.kind, .sessionCreated)
    XCTAssertEqual(event.session.sessionID, sessionID)
    XCTAssertEqual(event.session.currentStatus, .created)
    XCTAssertFalse(event.description.contains("/allowed/hermes"))
    XCTAssertFalse(event.description.contains("4242"))
  }

  func testExecuteRoutesTypedCommands() async throws {
    let sessionID = UUID(uuidString: "30000000-0000-0000-0000-000000000008")!
    let api = api(sessionIDs: [sessionID])

    let createResult = try await api.execute(.createSession)
    guard case .sessionStatus(let createStatus) = createResult else {
      return XCTFail("expected session status")
    }
    XCTAssertEqual(createStatus.currentStatus, .created)

    let statusResult = try await api.execute(.getSessionStatus(sessionID))
    guard case .sessionStatus(let queryStatus) = statusResult else {
      return XCTFail("expected session status")
    }
    XCTAssertEqual(queryStatus.sessionID, sessionID)
  }

  private func api(
    sessionIDs: [UUID],
    backends: [CommandAPIFakeBackend] = [
      CommandAPIFakeBackend(startResult: .success(startResult()))
    ],
    dates: [Date] = [Date(timeIntervalSince1970: 1_800_000_001)],
    eventBus: HermesRuntimeEventBus = HermesRuntimeEventBus()
  ) -> HermesRuntimeCommandAPI {
    let backendBox = CommandAPILockedValues(backends)
    let sessionIDBox = CommandAPILockedValues(sessionIDs)
    let dateBox = CommandAPILockedValues(dates)
    let manager = HermesRuntimeSessionManager(
      backendFactory: { backendBox.next() },
      sessionIDFactory: { sessionIDBox.next() },
      clock: { dateBox.next() },
      eventBus: eventBus
    )
    return HermesRuntimeCommandAPI(sessionManager: manager)
  }

  private static func startResult(pid: Int32 = 4242) -> HermesBackendStartResult {
    let discovery = HermesDiscoveryResult(
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
    let identity = HermesProcessIdentity(
      pid: pid,
      pgid: pid,
      processStartIdentity: "fixture-start-\(pid)",
      resolvedExecutablePath: "/allowed/hermes",
      launchNonce: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
      expectedCommandShape: ["/allowed/hermes", "--safe-mode", "serve"]
    )
    return HermesBackendStartResult(
      discovery: discovery,
      launch: HermesProcessLaunchResult(
        identity: identity,
        runtimeDirectory: URL(fileURLWithPath: "/tmp/hermes-runtime/session"),
        launchContext: HermesBackendLaunchContext(
          identity: identity,
          endpoint: try! HermesBackendEndpoint(port: 19123),
          sessionToken: HermesBackendSessionToken(rawValue: "fixture-token")
        ),
        output: emptyCommandAPIOutputSnapshot()
      ),
      initialStatus: status()
    )
  }

  fileprivate static func healthSnapshot(status: HermesBackendStatus = status()) -> HermesBackendHealthSnapshot {
    HermesBackendHealthSnapshot(
      processState: .ready(
        HermesProcessIdentity(
          pid: 4242,
          pgid: 4242,
          processStartIdentity: "fixture-start-4242",
          resolvedExecutablePath: "/allowed/hermes",
          launchNonce: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
          expectedCommandShape: ["/allowed/hermes", "--safe-mode", "serve"]
        )
      ),
      protocolState: .ready,
      status: status
    )
  }

  private static func status() -> HermesBackendStatus {
    HermesBackendStatus(
      version: "0.18.2",
      releaseDate: "2026-07-01",
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

private final class CommandAPIFakeBackend: HermesBackendAdapting, @unchecked Sendable {
  private let lock = NSLock()
  private let startResult: Result<HermesBackendStartResult, Error>
  private let stopResult: Result<HermesBackendStopResult, Error>
  private(set) var startCallCount = 0
  private(set) var stopCallCount = 0

  init(
    startResult: Result<HermesBackendStartResult, Error>,
    stopResult: Result<HermesBackendStopResult, Error> = .success(
      HermesBackendStopResult(
        processStop: HermesProcessStopResult(
          exitStatus: 0,
          output: emptyCommandAPIOutputSnapshot(),
          escapedDescendants: []
        ),
        protocolState: .closed
      )
    )
  ) {
    self.startResult = startResult
    self.stopResult = stopResult
  }

  func discover() throws -> HermesDiscoveryResult {
    try startResult.get().discovery
  }

  func start() async throws -> HermesBackendStartResult {
    try lock.withLock {
      startCallCount += 1
      return try startResult.get()
    }
  }

  func stop() async throws -> HermesBackendStopResult {
    try lock.withLock {
      stopCallCount += 1
      return try stopResult.get()
    }
  }

  func health() async throws -> HermesBackendHealthSnapshot {
    HermesRuntimeCommandAPITests.healthSnapshot()
  }
}

private final class CommandAPILockedValues<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [Value]

  init(_ values: [Value]) {
    self.values = values
  }

  func next() -> Value {
    lock.withLock {
      precondition(!values.isEmpty)
      return values.removeFirst()
    }
  }
}

private func emptyCommandAPIOutputSnapshot() -> HermesProcessOutputSnapshot {
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

private func nextEvent(
  from iterator: inout AsyncStream<HermesRuntimeCommandEvent>.Iterator,
  file: StaticString = #filePath,
  line: UInt = #line
) async throws -> HermesRuntimeCommandEvent {
  guard let event = await iterator.next() else {
    XCTFail("expected event", file: file, line: line)
    throw CommandAPIEventTestError.streamFinished
  }
  return event
}

private enum CommandAPIEventTestError: Error {
  case streamFinished
}
