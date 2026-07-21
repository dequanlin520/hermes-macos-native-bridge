import Foundation
import XCTest

@testable import HermesRuntimeFoundation

final class HermesRuntimeSessionManagerTests: XCTestCase {
  func testEventBusPublishesAndReceivesEvent() async throws {
    let eventBus = HermesRuntimeEventBus(
      subscriptionIDFactory: {
        UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
      }
    )
    let subscription = eventBus.subscribe()
    var iterator = subscription.events.makeAsyncIterator()
    let sessionID = UUID(uuidString: "10000000-0000-0000-0000-000000000101")!

    eventBus.publish(
      HermesRuntimeEvent(
        kind: .sessionCreated,
        session: HermesRuntimeEventSessionSummary(snapshot: Self.createdSnapshot(sessionID: sessionID))
      )
    )

    let event = try await nextEvent(from: &iterator)
    XCTAssertEqual(event.kind, .sessionCreated)
    XCTAssertEqual(event.sequenceNumber, 1)
    XCTAssertEqual(event.session.sessionID, sessionID)
  }

  func testEventBusDeliversToMultipleSubscribers() async throws {
    let eventBus = HermesRuntimeEventBus()
    let first = eventBus.subscribe()
    let second = eventBus.subscribe()
    var firstIterator = first.events.makeAsyncIterator()
    var secondIterator = second.events.makeAsyncIterator()

    eventBus.publish(
      HermesRuntimeEvent(
        kind: .sessionCreated,
        session: HermesRuntimeEventSessionSummary(
          snapshot: Self.createdSnapshot(
            sessionID: UUID(uuidString: "10000000-0000-0000-0000-000000000102")!
          )
        )
      )
    )

    let firstEvent = try await nextEvent(from: &firstIterator)
    let secondEvent = try await nextEvent(from: &secondIterator)
    XCTAssertEqual(firstEvent.kind, .sessionCreated)
    XCTAssertEqual(secondEvent.kind, .sessionCreated)
  }

  func testEventBusUnsubscribeStopsDeliveryAndReleasesSubscription() async throws {
    let eventBus = HermesRuntimeEventBus()
    let subscription = eventBus.subscribe()
    var iterator = subscription.events.makeAsyncIterator()

    eventBus.unsubscribe(subscription.id)

    let event = try await nextOptionalEvent(from: &iterator)
    XCTAssertNil(event)
    XCTAssertEqual(eventBus.subscriberCount(), 0)
  }

  func testSessionLifecyclePublishesOrderedEvents() async throws {
    let sessionID = UUID(uuidString: "10000000-0000-0000-0000-000000000103")!
    let eventBus = HermesRuntimeEventBus()
    let subscription = eventBus.subscribe()
    var iterator = subscription.events.makeAsyncIterator()
    let backend = FakeRuntimeBackend(startResult: .success(Self.startResult()))
    let manager = manager(sessionIDs: [sessionID], backends: [backend], eventBus: eventBus)

    _ = manager.createSession()
    _ = try await manager.startSession(sessionID)
    _ = try await manager.stopSession(sessionID)

    let events = try await nextEvents(count: 5, from: &iterator)
    XCTAssertEqual(
      events.map(\.kind),
      [.sessionCreated, .sessionStarting, .sessionRunning, .sessionStopping, .sessionStopped]
    )
    XCTAssertEqual(events.map(\.sequenceNumber), [1, 2, 3, 4, 5])
    XCTAssertEqual(events.map(\.session.currentStatus), [.created, .starting, .running, .stopping, .stopped])
  }

  func testSessionHealthChangePublishesEvent() async throws {
    let sessionID = UUID(uuidString: "10000000-0000-0000-0000-000000000104")!
    let eventBus = HermesRuntimeEventBus()
    let subscription = eventBus.subscribe()
    var iterator = subscription.events.makeAsyncIterator()
    let backend = FakeRuntimeBackend(
      startResult: .success(Self.startResult()),
      healthResults: [
        .success(Self.healthSnapshot(status: Self.status(gatewayRunning: false)))
      ]
    )
    let manager = manager(sessionIDs: [sessionID], backends: [backend], eventBus: eventBus)
    _ = manager.createSession()
    _ = try await manager.startSession(sessionID)

    _ = try await manager.refreshSessionStatus(sessionID)

    let events = try await nextEvents(count: 4, from: &iterator)
    XCTAssertEqual(events.map(\.kind), [.sessionCreated, .sessionStarting, .sessionRunning, .sessionHealthChanged])
    XCTAssertEqual(events.last?.session.currentStatus, .degraded)
  }

  func testSessionStartFailurePublishesRedactedFailureEvent() async throws {
    let sessionID = UUID(uuidString: "10000000-0000-0000-0000-000000000105")!
    let eventBus = HermesRuntimeEventBus()
    let subscription = eventBus.subscribe()
    var iterator = subscription.events.makeAsyncIterator()
    let backend = FakeRuntimeBackend(
      startResult: .failure(
        HermesBackendAdapterError.startupFailed(
          "token=start-secret failed at /Users/example/private/hermes"
        )
      )
    )
    let manager = manager(sessionIDs: [sessionID], backends: [backend], eventBus: eventBus)
    _ = manager.createSession()

    await XCTAssertThrowsAsyncError(try await manager.startSession(sessionID))

    let events = try await nextEvents(count: 3, from: &iterator)
    XCTAssertEqual(events.map(\.kind), [.sessionCreated, .sessionStarting, .sessionFailed])
    XCTAssertEqual(events.last?.session.currentStatus, .failed)
    XCTAssertEqual(events.last?.session.shutdownReason, .startupFailed)
    XCTAssertFalse(events.last?.description.contains("start-secret") ?? true)
    XCTAssertFalse(events.last?.description.contains("/Users/example/private/hermes") ?? true)
  }

  func testSessionStopFailurePublishesFailureEvent() async throws {
    let sessionID = UUID(uuidString: "10000000-0000-0000-0000-000000000106")!
    let eventBus = HermesRuntimeEventBus()
    let subscription = eventBus.subscribe()
    var iterator = subscription.events.makeAsyncIterator()
    let backend = FakeRuntimeBackend(
      startResult: .success(Self.startResult()),
      stopResult: .failure(HermesBackendAdapterError.shutdownFailed("forced stop failed"))
    )
    let manager = manager(sessionIDs: [sessionID], backends: [backend], eventBus: eventBus)
    _ = manager.createSession()
    _ = try await manager.startSession(sessionID)

    await XCTAssertThrowsAsyncError(try await manager.stopSession(sessionID))

    let events = try await nextEvents(count: 5, from: &iterator)
    XCTAssertEqual(
      events.map(\.kind),
      [.sessionCreated, .sessionStarting, .sessionRunning, .sessionStopping, .sessionFailed]
    )
    XCTAssertEqual(events.last?.session.currentStatus, .failed)
    XCTAssertEqual(events.last?.session.shutdownReason, .shutdownFailed)
  }

  func testCreateSessionStoresTypedCreatedSnapshot() throws {
    let sessionID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    let manager = manager(sessionIDs: [sessionID])

    let snapshot = manager.createSession()

    XCTAssertEqual(snapshot.sessionID, sessionID)
    XCTAssertEqual(snapshot.currentStatus, .created)
    XCTAssertNil(snapshot.backendIdentity)
    XCTAssertNil(snapshot.processIdentity)
    XCTAssertNil(snapshot.startTime)
    XCTAssertNil(snapshot.capabilities)
    XCTAssertNil(snapshot.lastError)
    XCTAssertEqual(try manager.getSession(sessionID), snapshot)
  }

  func testStartSuccessRecordsBackendProcessCapabilitiesAndStartTime() async throws {
    let sessionID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
    let startTime = Date(timeIntervalSince1970: 1_700_000_000)
    let backend = FakeRuntimeBackend(startResult: .success(Self.startResult()))
    let manager = manager(sessionIDs: [sessionID], backends: [backend], dates: [startTime])
    _ = manager.createSession()

    let snapshot = try await manager.startSession(sessionID)

    XCTAssertEqual(snapshot.currentStatus, .running)
    XCTAssertEqual(snapshot.startTime, startTime)
    XCTAssertEqual(snapshot.backendIdentity?.semanticVersion, "0.18.2")
    XCTAssertEqual(snapshot.backendIdentity?.executablePath, "/allowed/hermes")
    XCTAssertEqual(snapshot.processIdentity?.pid, 4242)
    XCTAssertEqual(snapshot.capabilities?.desktopContract, 3)
    XCTAssertEqual(snapshot.capabilities?.gatewayRunning, true)
    XCTAssertEqual(backend.startCallCount, 1)
  }

  func testStartFailureMarksSessionFailedAndPropagatesError() async throws {
    let sessionID = UUID(uuidString: "10000000-0000-0000-0000-000000000003")!
    let error = HermesBackendAdapterError.startupFailed("port busy token=start-secret")
    let backend = FakeRuntimeBackend(startResult: .failure(error))
    let manager = manager(sessionIDs: [sessionID], backends: [backend])
    _ = manager.createSession()

    await XCTAssertThrowsAsyncError(try await manager.startSession(sessionID)) {
      XCTAssertEqual($0 as? HermesBackendAdapterError, error)
    }

    let snapshot = try manager.getSession(sessionID)
    XCTAssertEqual(snapshot.currentStatus, .failed)
    XCTAssertEqual(snapshot.shutdownReason, .startupFailed)
    XCTAssertEqual(snapshot.lastError?.description, "Hermes backend startup failed: port busy token=<redacted>")
    XCTAssertFalse(snapshot.description.contains("start-secret"))
  }

  func testStatusUpdateCanMoveRunningSessionToDegraded() async throws {
    let sessionID = UUID(uuidString: "10000000-0000-0000-0000-000000000004")!
    let backend = FakeRuntimeBackend(
      startResult: .success(Self.startResult()),
      healthResults: [
        .success(Self.healthSnapshot(status: Self.status(gatewayRunning: false)))
      ]
    )
    let manager = manager(sessionIDs: [sessionID], backends: [backend])
    _ = manager.createSession()
    _ = try await manager.startSession(sessionID)

    let snapshot = try await manager.refreshSessionStatus(sessionID)

    XCTAssertEqual(snapshot.currentStatus, .degraded)
    XCTAssertEqual(snapshot.capabilities?.gatewayRunning, false)
    XCTAssertEqual(backend.healthCallCount, 1)
  }

  func testMultipleSessionsAreTrackedIndependently() async throws {
    let firstID = UUID(uuidString: "10000000-0000-0000-0000-000000000005")!
    let secondID = UUID(uuidString: "10000000-0000-0000-0000-000000000006")!
    let firstBackend = FakeRuntimeBackend(startResult: .success(Self.startResult(pid: 5101)))
    let secondBackend = FakeRuntimeBackend(startResult: .success(Self.startResult(pid: 5102)))
    let manager = manager(
      sessionIDs: [firstID, secondID],
      backends: [firstBackend, secondBackend]
    )

    _ = manager.createSession()
    _ = manager.createSession()
    _ = try await manager.startSession(secondID)

    let sessions = manager.listSessions()

    XCTAssertEqual(sessions.map(\.sessionID), [firstID, secondID])
    XCTAssertEqual(sessions[0].currentStatus, .created)
    XCTAssertEqual(sessions[1].currentStatus, .running)
    XCTAssertEqual(sessions[1].processIdentity?.pid, 5102)
  }

  func testStopIsIdempotent() async throws {
    let sessionID = UUID(uuidString: "10000000-0000-0000-0000-000000000007")!
    let backend = FakeRuntimeBackend(startResult: .success(Self.startResult()))
    let manager = manager(sessionIDs: [sessionID], backends: [backend])
    _ = manager.createSession()
    _ = try await manager.startSession(sessionID)

    let firstStop = try await manager.stopSession(sessionID)
    let secondStop = try await manager.stopSession(sessionID)

    XCTAssertEqual(firstStop.currentStatus, .stopped)
    XCTAssertEqual(secondStop.currentStatus, .stopped)
    XCTAssertEqual(firstStop.shutdownReason, .requested)
    XCTAssertEqual(backend.stopCallCount, 1)
  }

  func testRemoveStoppedSession() async throws {
    let sessionID = UUID(uuidString: "10000000-0000-0000-0000-000000000008")!
    let manager = manager(sessionIDs: [sessionID])
    _ = manager.createSession()
    _ = try await manager.stopSession(sessionID)

    let removed = try manager.removeSession(sessionID)

    XCTAssertEqual(removed.currentStatus, .stopped)
    XCTAssertTrue(manager.listSessions().isEmpty)
    XCTAssertThrowsError(try manager.getSession(sessionID)) {
      XCTAssertEqual($0 as? HermesRuntimeSessionManagerError, .sessionNotFound(sessionID))
    }
  }

  func testHealthErrorIsStoredRedactedAndPropagated() async throws {
    let sessionID = UUID(uuidString: "10000000-0000-0000-0000-000000000009")!
    let secret = "health-secret"
    let error = HermesBackendAdapterError.healthFailed("GET /api/status X-Hermes-Session-Token=\(secret)")
    let backend = FakeRuntimeBackend(
      startResult: .success(Self.startResult()),
      healthResults: [.failure(error)]
    )
    let manager = manager(sessionIDs: [sessionID], backends: [backend])
    _ = manager.createSession()
    _ = try await manager.startSession(sessionID)

    await XCTAssertThrowsAsyncError(try await manager.refreshSessionStatus(sessionID)) {
      XCTAssertEqual($0 as? HermesBackendAdapterError, error)
    }

    let snapshot = try manager.getSession(sessionID)
    XCTAssertEqual(snapshot.currentStatus, .degraded)
    XCTAssertFalse(snapshot.lastError?.description.contains(secret) ?? true)
    XCTAssertTrue(snapshot.lastError?.description.contains("X-Hermes-Session-Token=<redacted>") ?? false)
  }

  func testRedactedDescriptionDoesNotExposeCredentialMarkers() async throws {
    let sessionID = UUID(uuidString: "10000000-0000-0000-0000-000000000010")!
    let secret = "debug-secret"
    let backend = FakeRuntimeBackend(
      startResult: .failure(
        HermesBackendAdapterError.protocolUnavailable("ws://127.0.0.1:19123/api/ws?token=\(secret)&next=1")
      )
    )
    let manager = manager(sessionIDs: [sessionID], backends: [backend])
    _ = manager.createSession()

    await XCTAssertThrowsAsyncError(try await manager.startSession(sessionID))

    let snapshot = try manager.getSession(sessionID)
    XCTAssertFalse(snapshot.description.contains(secret))
    XCTAssertFalse(snapshot.debugDescription.contains(secret))
    XCTAssertTrue(snapshot.description.contains("token=<redacted>"))
  }

  private func manager(
    sessionIDs: [UUID],
    backends: [FakeRuntimeBackend] = [FakeRuntimeBackend(startResult: .success(startResult()))],
    dates: [Date] = [Date(timeIntervalSince1970: 1_700_000_001)],
    eventBus: HermesRuntimeEventBus = HermesRuntimeEventBus()
  ) -> HermesRuntimeSessionManager {
    let backendBox = LockedTestValues(backends)
    let sessionIDBox = LockedTestValues(sessionIDs)
    let dateBox = LockedTestValues(dates)
    return HermesRuntimeSessionManager(
      backendFactory: { backendBox.next() },
      sessionIDFactory: { sessionIDBox.next() },
      clock: { dateBox.next() },
      eventBus: eventBus
    )
  }

  private static func createdSnapshot(sessionID: UUID) -> HermesRuntimeSessionSnapshot {
    HermesRuntimeSessionSnapshot(
      sessionID: sessionID,
      backendIdentity: nil,
      processIdentity: nil,
      startTime: nil,
      currentStatus: .created,
      capabilities: nil,
      lastError: nil,
      shutdownReason: nil
    )
  }

  private static func startResult(pid: Int32 = 4242) -> HermesBackendStartResult {
    let discovery = discoveryResult()
    let identity = processIdentity(pid: pid)
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
        output: emptyOutputSnapshot()
      ),
      initialStatus: status()
    )
  }

  fileprivate static func healthSnapshot(status: HermesBackendStatus = status()) -> HermesBackendHealthSnapshot {
    HermesBackendHealthSnapshot(
      processState: .ready(processIdentity()),
      protocolState: .ready,
      status: status
    )
  }

  private static func discoveryResult() -> HermesDiscoveryResult {
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

  private static func processIdentity(pid: Int32 = 4242) -> HermesProcessIdentity {
    HermesProcessIdentity(
      pid: pid,
      pgid: pid,
      processStartIdentity: "fixture-start-\(pid)",
      resolvedExecutablePath: "/allowed/hermes",
      launchNonce: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
      expectedCommandShape: ["/allowed/hermes", "--safe-mode", "serve"]
    )
  }

  private static func status(
    gatewayRunning: Bool = true,
    gatewayState: String = "ready"
  ) -> HermesBackendStatus {
    HermesBackendStatus(
      version: "0.18.2",
      releaseDate: "2026-07-01",
      authRequired: true,
      authMode: .loopbackToken,
      desktopContract: 3,
      gatewayRunning: gatewayRunning,
      gatewayState: gatewayState,
      activeAgents: 0,
      gatewayBusy: false,
      gatewayDrainable: true
    )
  }
}

private final class FakeRuntimeBackend: HermesBackendAdapting, @unchecked Sendable {
  private let lock = NSLock()
  private let startResult: Result<HermesBackendStartResult, Error>
  private let stopResult: Result<HermesBackendStopResult, Error>
  private var healthResults: [Result<HermesBackendHealthSnapshot, Error>]
  private(set) var startCallCount = 0
  private(set) var stopCallCount = 0
  private(set) var healthCallCount = 0

  init(
    startResult: Result<HermesBackendStartResult, Error>,
    stopResult: Result<HermesBackendStopResult, Error> = .success(
      HermesBackendStopResult(
        processStop: HermesProcessStopResult(
          exitStatus: 0,
          output: emptyOutputSnapshot(),
          escapedDescendants: []
        ),
        protocolState: .closed
      )
    ),
    healthResults: [Result<HermesBackendHealthSnapshot, Error>] = []
  ) {
    self.startResult = startResult
    self.stopResult = stopResult
    self.healthResults = healthResults
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
    lock.withLock {
      stopCallCount += 1
    }
    return try stopResult.get()
  }

  func health() async throws -> HermesBackendHealthSnapshot {
    try lock.withLock {
      healthCallCount += 1
      guard !healthResults.isEmpty else {
        return HermesRuntimeSessionManagerTests.healthSnapshot()
      }
      return try healthResults.removeFirst().get()
    }
  }
}

private final class LockedTestValues<Value>: @unchecked Sendable {
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

private func nextEvents(
  count: Int,
  from iterator: inout AsyncStream<HermesRuntimeEvent>.Iterator,
  file: StaticString = #filePath,
  line: UInt = #line
) async throws -> [HermesRuntimeEvent] {
  var events: [HermesRuntimeEvent] = []
  for _ in 0..<count {
    guard let event = try await nextOptionalEvent(from: &iterator, file: file, line: line) else {
      XCTFail("expected event", file: file, line: line)
      break
    }
    events.append(event)
  }
  return events
}

private func nextEvent(
  from iterator: inout AsyncStream<HermesRuntimeEvent>.Iterator,
  file: StaticString = #filePath,
  line: UInt = #line
) async throws -> HermesRuntimeEvent {
  guard let event = try await nextOptionalEvent(from: &iterator, file: file, line: line) else {
    throw EventBusTestError.streamFinished
  }
  return event
}

private func nextOptionalEvent(
  from iterator: inout AsyncStream<HermesRuntimeEvent>.Iterator,
  file: StaticString = #filePath,
  line: UInt = #line
) async throws -> HermesRuntimeEvent? {
  await iterator.next()
}

private enum EventBusTestError: Error {
  case streamFinished
}
