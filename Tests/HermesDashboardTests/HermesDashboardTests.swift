import Foundation
@testable import HermesDashboard
@testable import HermesRuntimeFoundation
import XCTest

final class HermesDashboardTests: XCTestCase {
  func testInitialLoadingCreatesDashboardSessionState() async {
    let recording = RecordingDashboardCommandAPI()
    let controller = HermesDashboardController(commandAPI: recording)

    let state = await controller.load()

    XCTAssertEqual(state.runtimeStatus, .created)
    XCTAssertEqual(state.sessionSummary?.status, .created)
    XCTAssertEqual(state.backendHealthSummary?.healthState, .stopped)
    XCTAssertFalse(state.isLoading)
    XCTAssertTrue(recording.commands.contains(.createSession))
  }

  func testStatusRefreshUsesRuntimeCommandAPI() async {
    let recording = RecordingDashboardCommandAPI()
    let controller = HermesDashboardController(commandAPI: recording)

    _ = await controller.refreshStatus()
    let state = await controller.refreshStatus()

    XCTAssertEqual(state.runtimeStatus, .created)
    XCTAssertTrue(recording.commands.contains(.createSession))
    XCTAssertTrue(recording.commands.contains { command in
      if case .getSessionStatus = command { return true }
      return false
    })
  }

  func testEventUpdatesDashboardState() async throws {
    let recording = RecordingDashboardCommandAPI()
    let controller = HermesDashboardController(commandAPI: recording)

    await controller.startEventSubscription()
    let sessionID = recording.primarySessionID
    recording.publish(
      event: .sessionRunning,
      status: .running,
      sessionID: sessionID,
      errorMessage: "token=event-secret failed at /Users/example/.hermes/runtime"
    )

    let state = try await waitForState(controller) { !$0.recentEvents.isEmpty }

    XCTAssertEqual(state.runtimeStatus, .running)
    XCTAssertEqual(state.backendHealthSummary?.healthState, .healthy)
    XCTAssertEqual(state.recentEvents.first?.kind, .sessionRunning)
    XCTAssertTrue(state.recentEvents.first?.lastErrorMessage?.contains("token=<redacted>") ?? false)
    XCTAssertFalse(String(describing: state).contains("event-secret"))
    XCTAssertFalse(String(describing: state).contains("/Users/"))
  }

  func testCommandForwardingForStartStopRestartAndRefresh() async {
    let recording = RecordingDashboardCommandAPI()
    let controller = HermesDashboardController(commandAPI: recording)

    _ = await controller.startHermes()
    _ = await controller.stopHermes()
    _ = await controller.restartHermes()
    _ = await controller.refreshStatus()

    XCTAssertTrue(recording.commands.contains(.createSession))
    XCTAssertTrue(recording.commands.contains { command in
      if case .startSession = command { return true }
      return false
    })
    XCTAssertTrue(recording.commands.contains { command in
      if case .stopSession(_, reason: .requested) = command { return true }
      return false
    })
    XCTAssertTrue(recording.commands.contains { command in
      if case .getSessionStatus = command { return true }
      return false
    })
  }

  func testErrorHandlingRedactsSensitiveFields() async {
    let recording = RecordingDashboardCommandAPI(
      startError: HermesRuntimeCommandAPIError.operationFailed(
        "token=start-secret failed at /Users/example/.hermes/backend"
      )
    )
    let controller = HermesDashboardController(commandAPI: recording)

    let state = await controller.startHermes()

    XCTAssertEqual(state.runtimeStatus, .created)
    XCTAssertEqual(state.backendHealthSummary?.healthState, .failed)
    XCTAssertTrue(state.lastErrorMessage?.contains("token=<redacted>") ?? false)
    XCTAssertFalse(state.lastErrorMessage?.contains("start-secret") ?? true)
    XCTAssertFalse(state.lastErrorMessage?.contains("/Users/") ?? true)
  }

  private func waitForState(
    _ controller: HermesDashboardController,
    matching predicate: (HermesDashboardState) -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async throws -> HermesDashboardState {
    for _ in 0..<50 {
      let state = await controller.currentState()
      if predicate(state) {
        return state
      }
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTFail("Timed out waiting for dashboard state", file: file, line: line)
    return await controller.currentState()
  }
}

private final class RecordingDashboardCommandAPI: HermesDashboardRuntimeCommandExecuting,
  @unchecked Sendable
{
  let primarySessionID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!

  private let startError: Error?
  private let lock = NSLock()
  private var commandStorage: [HermesRuntimeCommand] = []
  private var sessionStatus: HermesRuntimeSessionStatus = .created
  private var activeSessionID: UUID?
  private var nextSessionIndex = 1
  private var eventContinuation: AsyncStream<HermesRuntimeCommandEvent>.Continuation?
  private var nextEventSequence: UInt64 = 0

  init(startError: Error? = nil) {
    self.startError = startError
  }

  var commands: [HermesRuntimeCommand] {
    lock.withLock { commandStorage }
  }

  func execute(_ command: HermesRuntimeCommand) async throws -> HermesRuntimeCommandResult {
    lock.withLock {
      commandStorage.append(command)
    }

    switch command {
    case .createSession:
      let sessionID = lock.withLock {
        let id: UUID
        if nextSessionIndex == 1 {
          id = primarySessionID
        } else {
          id = UUID(uuidString: "10000000-0000-0000-0000-\(String(format: "%012d", nextSessionIndex))")!
        }
        nextSessionIndex += 1
        activeSessionID = id
        sessionStatus = .created
        return id
      }
      return .sessionStatus(makeStatus(sessionID: sessionID, status: .created))

    case .startSession(let sessionID):
      if let startError {
        throw startError
      }
      lock.withLock {
        activeSessionID = sessionID
        sessionStatus = .running
      }
      return .sessionStatus(makeStatus(sessionID: sessionID, status: .running))

    case .stopSession(let sessionID, _):
      lock.withLock {
        activeSessionID = sessionID
        sessionStatus = .stopped
      }
      return .sessionStatus(makeStatus(sessionID: sessionID, status: .stopped))

    case .getSessionStatus(let sessionID):
      let status = lock.withLock { sessionStatus }
      return .sessionStatus(makeStatus(sessionID: sessionID, status: status))

    case .subscribeEvents:
      let stream = AsyncStream<HermesRuntimeCommandEvent> { continuation in
        self.lock.withLock {
          self.eventContinuation = continuation
        }
      }
      return .eventSubscription(
        HermesRuntimeCommandEventSubscription(
          id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
          events: stream
        )
      )
    }
  }

  func publish(
    event kind: HermesRuntimeEventKind,
    status: HermesRuntimeSessionStatus,
    sessionID: UUID,
    errorMessage: String? = nil
  ) {
    let event = lock.withLock {
      nextEventSequence += 1
      return HermesRuntimeCommandEvent(
        event: HermesRuntimeEvent(
          sequenceNumber: nextEventSequence,
          kind: kind,
          session: HermesRuntimeEventSessionSummary(
            snapshot: makeSnapshot(
              sessionID: sessionID,
              status: status,
              errorMessage: errorMessage
            )
          ),
          occurredAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
      )
    }
    eventContinuation?.yield(event)
  }

  private func makeStatus(
    sessionID: UUID,
    status: HermesRuntimeSessionStatus
  ) -> HermesRuntimeCommandSessionStatus {
    HermesRuntimeCommandSessionStatus(
      snapshot: makeSnapshot(sessionID: sessionID, status: status)
    )
  }

  private func makeSnapshot(
    sessionID: UUID,
    status: HermesRuntimeSessionStatus,
    errorMessage: String? = nil
  ) -> HermesRuntimeSessionSnapshot {
    HermesRuntimeSessionSnapshot(
      sessionID: sessionID,
      backendIdentity: status == .created ? nil : HermesRuntimeBackendIdentity(
        executablePath: "/allowed/hermes",
        semanticVersion: "0.18.2",
        displayVersion: "Hermes 0.18.2",
        installationMethod: "fixture",
        releaseDate: "2026-07-01",
        desktopContract: 3
      ),
      processIdentity: nil,
      startTime: status == .created ? nil : Date(timeIntervalSince1970: 1_800_000_000),
      currentStatus: status,
      capabilities: status == .created ? nil : HermesRuntimeCapabilities(
        authMode: .loopbackToken,
        desktopContract: 3,
        gatewayRunning: status == .running,
        gatewayState: "ready",
        gatewayBusy: false,
        gatewayDrainable: true,
        activeAgents: 0
      ),
      lastError: errorMessage.map(HermesRuntimeSessionError.init(message:)),
      shutdownReason: status == .stopped ? .requested : nil
    )
  }
}
