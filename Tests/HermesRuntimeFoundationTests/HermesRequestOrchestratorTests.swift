import Foundation
import XCTest

@testable import HermesRuntimeFoundation

final class HermesRequestOrchestratorTests: XCTestCase {
  func testSubmissionReturnsRequestID() async throws {
    let harness = try Harness()

    let requestID = try await harness.orchestrator.submit(
      bindingID: harness.bindingID,
      prompt: "hello"
    )

    XCTAssertTrue(requestID.rawValue.hasPrefix(HermesRequestID.prefix))
  }

  func testSubmissionTransitionsAcceptedQueuedStartingRunning() async throws {
    let harness = try Harness()

    let requestID = try await harness.orchestrator.submit(
      bindingID: harness.bindingID,
      prompt: "hello"
    )

    let record = try await harness.store.read(requestID: requestID)
    XCTAssertEqual(record.lifecycleState, .running)
    XCTAssertNotNil(record.startedAt)
  }

  func testBindingValidationRejectsUnknownBinding() async throws {
    let harness = try Harness(bindings: [])

    await assertThrowsAsyncError(
      try await harness.orchestrator.submit(bindingID: harness.bindingID, prompt: "hello")
    ) {
      XCTAssertEqual($0 as? HermesRequestOrchestratorError, .invalidBinding)
    }
  }

  func testDisabledBindingRejected() async throws {
    let bindingID = try HermesRequestBindingID(rawValue: "binding:v1:test.binding")
    let harness = try Harness(
      bindings: [HermesRequestBinding(id: bindingID, enabled: false)]
    )

    await assertThrowsAsyncError(
      try await harness.orchestrator.submit(bindingID: bindingID, prompt: "hello")
    ) {
      XCTAssertEqual($0 as? HermesRequestOrchestratorError, .invalidBinding)
    }
  }

  func testPromptLengthRejected() async throws {
    let bindingID = try HermesRequestBindingID(rawValue: "binding:v1:test.binding")
    let harness = try Harness(
      bindings: [HermesRequestBinding(id: bindingID, maximumPromptBytes: 3)]
    )

    await assertThrowsAsyncError(
      try await harness.orchestrator.submit(bindingID: bindingID, prompt: "hello")
    ) {
      XCTAssertEqual($0 as? HermesRequestOrchestratorError, .invalidBinding)
    }
  }

  func testBackendLaunchOnlyWhenRequired() async throws {
    let harness = try Harness()

    _ = try await harness.orchestrator.submit(bindingID: harness.bindingID, prompt: "one")
    _ = try await harness.orchestrator.submit(bindingID: harness.bindingID, prompt: "two")

    XCTAssertEqual(harness.supervisor.startCount, 1)
  }

  func testExistingReadyBackendReuse() async throws {
    let harness = try Harness(prestartedSupervisor: true)

    _ = try await harness.orchestrator.submit(bindingID: harness.bindingID, prompt: "hello")

    XCTAssertEqual(harness.supervisor.startCount, 0)
    XCTAssertEqual(harness.factory.makeCount, 1)
  }

  func testProtocolConnectAndGatewayReadyFlow() async throws {
    let harness = try Harness()

    _ = try await harness.orchestrator.submit(bindingID: harness.bindingID, prompt: "hello")

    let state = await harness.orchestrator.state
    XCTAssertEqual(harness.protocolService.connectCount, 1)
    XCTAssertEqual(state, .ready)
  }

  func testBackendSessionIdentityAttachment() async throws {
    let harness = try Harness()

    let requestID = try await harness.orchestrator.submit(
      bindingID: harness.bindingID,
      prompt: "hello"
    )

    let record = try await harness.store.read(requestID: requestID)
    XCTAssertEqual(record.backendSessionID?.rawValue, "session-1")
  }

  func testProcessLaunchIdentityAttachment() async throws {
    let harness = try Harness()

    let requestID = try await harness.orchestrator.submit(
      bindingID: harness.bindingID,
      prompt: "hello"
    )

    let record = try await harness.store.read(requestID: requestID)
    XCTAssertEqual(record.processLaunchID, harness.supervisor.identity.launchNonce)
  }

  func testPromptSubmittedExactlyOnce() async throws {
    let harness = try Harness()

    _ = try await harness.orchestrator.submit(bindingID: harness.bindingID, prompt: "hello")

    XCTAssertEqual(harness.protocolService.submittedPrompts, ["hello"])
  }

  func testDuplicateExecutionPreventionBySinglePromptPerRequest() async throws {
    let harness = try Harness()

    let requestID = try await harness.orchestrator.submit(
      bindingID: harness.bindingID,
      prompt: "hello"
    )
    let record = try await harness.store.read(requestID: requestID)

    XCTAssertEqual(record.lifecycleState, .running)
    XCTAssertEqual(harness.protocolService.submittedPrompts.count, 1)
  }

  func testBackendLaunchFailureMarksFailed() async throws {
    let harness = try Harness()
    harness.supervisor.startError = HermesProcessFailure.launchFailed("private output")

    await assertThrowsAsyncError(
      try await harness.orchestrator.submit(bindingID: harness.bindingID, prompt: "hello")
    ) {
      guard case .backendLaunchFailure = $0 as? HermesRequestOrchestratorError else {
        return XCTFail("expected backendLaunchFailure")
      }
    }
    let records = try await harness.store.listRecoverableRequests()
    XCTAssertEqual(records.single?.record.lifecycleState, .failed)
  }

  func testProtocolConnectionFailureMarksFailed() async throws {
    let harness = try Harness()
    harness.protocolService.connectError = HermesProtocolClientError.webSocketClosed

    await assertThrowsAsyncError(
      try await harness.orchestrator.submit(bindingID: harness.bindingID, prompt: "hello")
    ) {
      guard case .backendConnectionFailure = $0 as? HermesRequestOrchestratorError else {
        return XCTFail("expected backendConnectionFailure")
      }
    }
    let records = try await harness.store.listRecoverableRequests()
    XCTAssertEqual(records.single?.record.lifecycleState, .failed)
  }

  func testSessionCreationFailureMarksFailed() async throws {
    let harness = try Harness()
    harness.protocolService.createSessionError = HermesProtocolClientError.requestTimedOut

    await assertThrowsAsyncError(
      try await harness.orchestrator.submit(bindingID: harness.bindingID, prompt: "hello")
    ) {
      guard case .sessionCreationFailure = $0 as? HermesRequestOrchestratorError else {
        return XCTFail("expected sessionCreationFailure")
      }
    }
    let records = try await harness.store.listRecoverableRequests()
    XCTAssertEqual(records.single?.record.failure?.code, "session_creation_failure")
  }

  func testPromptSubmissionFailureMarksFailed() async throws {
    let harness = try Harness()
    harness.protocolService.submitPromptError = HermesProtocolClientError.requestTimedOut

    await assertThrowsAsyncError(
      try await harness.orchestrator.submit(bindingID: harness.bindingID, prompt: "hello")
    ) {
      guard case .promptSubmissionFailure = $0 as? HermesRequestOrchestratorError else {
        return XCTFail("expected promptSubmissionFailure")
      }
    }
    let records = try await harness.store.listRecoverableRequests()
    XCTAssertEqual(records.single?.record.failure?.code, "prompt_submission_failure")
  }

  func testStatusQuery() async throws {
    let harness = try Harness()
    let requestID = try await harness.orchestrator.submit(
      bindingID: harness.bindingID,
      prompt: "hello"
    )

    let record = try await harness.orchestrator.status(requestID: requestID)

    XCTAssertEqual(record.requestID, requestID)
  }

  func testCancellationBeforeStart() async throws {
    let harness = try Harness()
    let requestID = try await harness.createQueuedRequest()

    let record = try await harness.orchestrator.cancel(requestID: requestID)

    XCTAssertEqual(record.lifecycleState, .cancelled)
    XCTAssertEqual(harness.protocolService.interruptCount, 0)
  }

  func testCancellationWhileRunning() async throws {
    let harness = try Harness()
    let requestID = try await harness.orchestrator.submit(
      bindingID: harness.bindingID,
      prompt: "hello"
    )

    let record = try await harness.orchestrator.cancel(requestID: requestID)

    XCTAssertEqual(record.lifecycleState, .cancelled)
    XCTAssertEqual(harness.protocolService.interruptCount, 1)
  }

  func testRepeatedCancellationIdempotency() async throws {
    let harness = try Harness()
    let requestID = try await harness.orchestrator.submit(
      bindingID: harness.bindingID,
      prompt: "hello"
    )

    let first = try await harness.orchestrator.cancel(requestID: requestID)
    let second = try await harness.orchestrator.cancel(requestID: requestID)

    XCTAssertEqual(first.lifecycleState, .cancelled)
    XCTAssertEqual(second.lifecycleState, .cancelled)
    XCTAssertEqual(harness.protocolService.interruptCount, 1)
  }

  func testApprovalRequestTransitionsToWaitingForApproval() async throws {
    let harness = try Harness()
    let requestID = try await harness.orchestrator.submit(
      bindingID: harness.bindingID,
      prompt: "hello"
    )

    harness.protocolService.send(
      .approvalRequest(
        HermesApprovalRequest(
          sessionID: "session-1",
          approvalID: "approval-1",
          prompt: "private approval text",
          metadata: ["kind": "fixture"]
        )))
    try await Task.sleep(nanoseconds: 50_000_000)

    let record = try await harness.store.read(requestID: requestID)
    XCTAssertEqual(record.lifecycleState, .waitingForApproval)
  }

  func testTypedApprovalResponse() async throws {
    let harness = try Harness()
    let requestID = try await harness.orchestrator.submit(
      bindingID: harness.bindingID,
      prompt: "hello"
    )
    harness.protocolService.send(
      .approvalRequest(
        HermesApprovalRequest(
          sessionID: "session-1",
          approvalID: "approval-1",
          prompt: nil,
          metadata: [:]
        )))
    try await Task.sleep(nanoseconds: 50_000_000)

    let record = try await harness.orchestrator.respondToApproval(
      requestID: requestID,
      decision: .approve
    )

    XCTAssertEqual(record.lifecycleState, .running)
    XCTAssertEqual(harness.protocolService.approvalDecisions, [.approve])
  }

  func testBackendDisconnectHandling() async throws {
    let harness = try Harness()
    let requestID = try await harness.orchestrator.submit(
      bindingID: harness.bindingID,
      prompt: "hello"
    )

    harness.protocolService.send(
      .backendEvent(
        HermesBackendEvent(
          type: "connection.failure",
          sessionID: "session-1",
          metadata: [:]
        )))
    try await Task.sleep(nanoseconds: 50_000_000)

    let record = try await harness.store.read(requestID: requestID)
    XCTAssertEqual(record.lifecycleState, .interrupted)
  }

  func testRecoveryClassificationForAcceptedQueued() async throws {
    let harness = try Harness()
    let accepted = try await harness.createAcceptedRequest(suffix: "A")
    let queued = try await harness.createQueuedRequest(suffix: "Q")

    try await harness.orchestrator.reconcileRecoverableRequests()

    let acceptedRecord = try await harness.store.read(requestID: accepted)
    let queuedRecord = try await harness.store.read(requestID: queued)
    XCTAssertEqual(acceptedRecord.lifecycleState, .interrupted)
    XCTAssertEqual(queuedRecord.lifecycleState, .interrupted)
  }

  func testRecoveryAgainstSupervisorForStarting() async throws {
    let harness = try Harness()
    let requestID = try await harness.createStartingRequest()

    try await harness.orchestrator.reconcileRecoverableRequests()

    let record = try await harness.store.read(requestID: requestID)
    XCTAssertEqual(record.lifecycleState, .interrupted)
  }

  func testRecoveryAgainstProtocolClientForRunning() async throws {
    let harness = try Harness()
    let requestID = try await harness.createRunningRequest(sessionID: "session-recover")
    harness.protocolService.statusError = HermesProtocolClientError.webSocketClosed

    try await harness.orchestrator.reconcileRecoverableRequests()

    let record = try await harness.store.read(requestID: requestID)
    XCTAssertEqual(record.lifecycleState, .interrupted)
  }

  func testNoAutomaticPromptResubmissionOnRestart() async throws {
    let harness = try Harness()
    _ = try await harness.createQueuedRequest()

    try await harness.orchestrator.reconcileRecoverableRequests()

    XCTAssertEqual(harness.protocolService.submittedPrompts, [])
  }

  func testPromptAndTokenAbsentFromStoredRecords() async throws {
    let harness = try Harness()
    let privatePrompt = "sample redacted body must not persist"
    let requestID = try await harness.orchestrator.submit(
      bindingID: harness.bindingID,
      prompt: privatePrompt
    )

    let data = try JSONEncoder().encode(try await harness.store.read(requestID: requestID))
    let text = String(data: data, encoding: .utf8) ?? ""

    XCTAssertFalse(text.contains(privatePrompt))
    XCTAssertFalse(text.contains(harness.token.rawValue))
    XCTAssertFalse(text.contains("prompt"))
    XCTAssertFalse(text.contains("token"))
  }

  func testShutdownIdempotency() async throws {
    let harness = try Harness()
    _ = try await harness.orchestrator.submit(bindingID: harness.bindingID, prompt: "hello")

    try await harness.orchestrator.shutdown()
    try await harness.orchestrator.shutdown()

    XCTAssertEqual(harness.supervisor.stopCount, 2)
  }

  func testConcurrentSubmissionsAreSerializedCorrectly() async throws {
    let harness = try Harness()

    try await withThrowingTaskGroup(of: HermesRequestID.self) { group in
      for index in 0..<10 {
        group.addTask {
          try await harness.orchestrator.submit(
            bindingID: harness.bindingID,
            prompt: "prompt-\(index)"
          )
        }
      }
      var ids: Set<HermesRequestID> = []
      for try await id in group {
        ids.insert(id)
      }
      XCTAssertEqual(ids.count, 10)
    }

    XCTAssertEqual(harness.protocolService.submittedPrompts.count, 10)
    XCTAssertEqual(harness.supervisor.startCount, 1)
  }

  private final class Harness: @unchecked Sendable {
    let bindingID: HermesRequestBindingID
    let token = HermesBackendSessionToken(rawValue: "fixture-token")
    let store = InMemoryHermesRequestStateStore()
    let supervisor: FakeSupervisor
    let protocolService = FakeProtocolService()
    let factory: FakeProtocolFactory
    let orchestrator: HermesRequestOrchestrator

    init(
      bindings: [HermesRequestBinding]? = nil,
      prestartedSupervisor: Bool = false
    ) throws {
      bindingID = try Self.bindingID()
      let candidate = HermesExecutableCandidate(
        allowlistedCandidatePath: "/tmp/hermes-fixture",
        originalPath: "/tmp/hermes-fixture",
        resolvedPath: "/tmp/hermes-fixture",
        symlinkStatus: .notSymlink
      )
      let configuration = try HermesProcessConfiguration(
        executable: candidate,
        port: 19_123,
        runtimeRoot: URL(fileURLWithPath: "/tmp/hermes-orchestrator-tests"),
        sessionToken: token
      )
      supervisor = FakeSupervisor(configuration: configuration, prestarted: prestartedSupervisor)
      factory = FakeProtocolFactory(service: protocolService)
      orchestrator = HermesRequestOrchestrator(
        bindingRegistry: StaticHermesRequestBindingRegistry(
          bindings: bindings ?? [HermesRequestBinding(id: bindingID)]
        ),
        stateStore: store,
        supervisor: supervisor,
        processConfiguration: configuration,
        protocolFactory: factory,
        gatewayReadyTimeout: 0.1
      )
    }

    func createAcceptedRequest(suffix: String = "A") async throws -> HermesRequestID {
      let id = try Self.requestID(suffix)
      _ = try await store.createAcceptedRequest(
        requestID: id,
        bindingID: bindingID,
        createdAt: Self.date(0)
      )
      return id
    }

    func createQueuedRequest(suffix: String = "Q") async throws -> HermesRequestID {
      let id = try await createAcceptedRequest(suffix: suffix)
      _ = try await store.transitionState(
        requestID: id,
        to: .queued,
        expectedRevision: nil,
        updatedAt: Self.date(1)
      )
      return id
    }

    func createStartingRequest(suffix: String = "S") async throws -> HermesRequestID {
      let id = try await createQueuedRequest(suffix: suffix)
      _ = try await store.transitionState(
        requestID: id,
        to: .starting,
        expectedRevision: nil,
        updatedAt: Self.date(2)
      )
      return id
    }

    func createRunningRequest(sessionID: String, suffix: String = "R") async throws
      -> HermesRequestID
    {
      let id = try await createStartingRequest(suffix: suffix)
      _ = try await store.transitionState(
        requestID: id,
        to: .running,
        expectedRevision: nil,
        updatedAt: Self.date(3)
      )
      _ = try await store.attachBackendSessionIdentity(
        requestID: id,
        backendSessionID: try HermesBackendSessionID(rawValue: sessionID),
        processLaunchID: supervisor.identity.launchNonce,
        expectedRevision: nil,
        updatedAt: Self.date(4)
      )
      return id
    }

    private static func bindingID() throws -> HermesRequestBindingID {
      try HermesRequestBindingID(rawValue: "binding:v1:test.binding")
    }

    private static func requestID(_ suffix: String) throws -> HermesRequestID {
      let padded = (suffix + String(repeating: "A", count: HermesRequestID.encodedRandomLength))
        .prefix(HermesRequestID.encodedRandomLength)
      return try HermesRequestID(rawValue: HermesRequestID.prefix + padded)
    }

    private static func date(_ seconds: TimeInterval) -> Date {
      Date(timeIntervalSince1970: 1_700_000_000 + seconds)
    }
  }

  private final class FakeSupervisor: HermesProcessSupervising, @unchecked Sendable {
    private let lock = NSLock()
    private let configuration: HermesProcessConfiguration
    let identity: HermesProcessIdentity
    var startError: Error?

    private var storedState: HermesProcessState
    private(set) var startCount = 0
    private(set) var stopCount = 0

    init(configuration: HermesProcessConfiguration, prestarted: Bool) {
      self.configuration = configuration
      identity = HermesProcessIdentity(
        pid: 123,
        pgid: 123,
        processStartIdentity: "fixture-start",
        resolvedExecutablePath: configuration.executable.resolvedPath,
        launchNonce: UUID(),
        expectedCommandShape: [configuration.executable.resolvedPath] + configuration.fixedArguments
      )
      storedState = prestarted ? .ready(identity) : .idle
    }

    var state: HermesProcessState {
      lock.withLock { storedState }
    }

    func start(configuration _: HermesProcessConfiguration) throws -> HermesProcessLaunchResult {
      try lock.withLock {
        if let startError {
          storedState = .failed(.launchFailed("redacted"))
          throw startError
        }
        startCount += 1
        storedState = .ready(identity)
      }
      return HermesProcessLaunchResult(
        identity: identity,
        runtimeDirectory: configuration.runtimeRoot,
        launchContext: HermesBackendLaunchContext(
          identity: identity,
          endpoint: try HermesBackendEndpoint(port: configuration.port),
          sessionToken: configuration.sessionToken
        ),
        output: HermesProcessOutputSnapshot(
          stdout: Data(),
          stderr: Data(),
          stdoutTruncated: false,
          stderrTruncated: false
        )
      )
    }

    func stop() throws -> HermesProcessStopResult {
      lock.withLock {
        stopCount += 1
        storedState = .exited(HermesProcessExit(pid: identity.pid, status: 0))
      }
      return HermesProcessStopResult(
        exitStatus: 0,
        output: HermesProcessOutputSnapshot(
          stdout: Data(),
          stderr: Data(),
          stdoutTruncated: false,
          stderrTruncated: false
        ),
        escapedDescendants: []
      )
    }
  }

  private final class FakeProtocolFactory: HermesProtocolServiceFactory, @unchecked Sendable {
    private let lock = NSLock()
    private let service: FakeProtocolService
    private(set) var makeCount = 0

    init(service: FakeProtocolService) {
      self.service = service
    }

    func makeProtocolService(launchContext _: HermesBackendLaunchContext)
      -> HermesProtocolServicing
    {
      lock.withLock {
        makeCount += 1
      }
      return service
    }
  }

  private final class FakeProtocolService: HermesProtocolServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<HermesGatewayEvent>.Continuation?
    private var storedState = HermesProtocolClientState.disconnected
    private var nextSessionNumber = 0

    var connectError: Error?
    var createSessionError: Error?
    var submitPromptError: Error?
    var statusError: Error?
    var interruptStatus = "interrupted"

    private(set) var connectCount = 0
    private(set) var createSessionCount = 0
    private(set) var submittedPrompts: [String] = []
    private(set) var interruptCount = 0
    private(set) var approvalDecisions: [HermesApprovalDecision] = []

    lazy var events: AsyncStream<HermesGatewayEvent> = {
      AsyncStream { continuation in
        self.lock.withLock {
          self.continuation = continuation
        }
      }
    }()

    var state: HermesProtocolClientState {
      lock.withLock { storedState }
    }

    func connectAndWaitUntilReady(timeout _: TimeInterval) async throws {
      try lock.withLock {
        if let connectError {
          storedState = .failed(.webSocketClosed)
          throw connectError
        }
        connectCount += 1
        storedState = .ready
      }
    }

    func createSession() async throws -> HermesSessionCreationResult {
      try lock.withLock {
        if let createSessionError {
          throw createSessionError
        }
        createSessionCount += 1
        nextSessionNumber += 1
        return HermesSessionCreationResult(sessionID: "session-\(nextSessionNumber)")
      }
    }

    func submitPrompt(sessionID _: String, text: String) async throws
      -> HermesPromptSubmissionResult
    {
      try lock.withLock {
        if let submitPromptError {
          throw submitPromptError
        }
        submittedPrompts.append(text)
        return HermesPromptSubmissionResult(status: "streaming")
      }
    }

    func sessionStatus(sessionID _: String) async throws -> HermesSessionStatusResult {
      try lock.withLock {
        if let statusError {
          throw statusError
        }
        return HermesSessionStatusResult(output: "running")
      }
    }

    func interruptSession(sessionID _: String) async throws -> HermesSessionInterruptResult {
      lock.withLock {
        interruptCount += 1
        return HermesSessionInterruptResult(status: interruptStatus)
      }
    }

    func respondToApproval(
      sessionID _: String,
      decision: HermesApprovalDecision,
      all _: Bool?
    ) async throws -> HermesApprovalResponseResult {
      lock.withLock {
        approvalDecisions.append(decision)
      }
      return HermesApprovalResponseResult(resolved: true)
    }

    func close() async {
      lock.withLock {
        storedState = .closed
        continuation?.finish()
      }
    }

    func send(_ event: HermesGatewayEvent) {
      lock.withLock { continuation }?.yield(event)
    }
  }
}

extension Array {
  fileprivate var single: Element? {
    count == 1 ? self[0] : nil
  }
}

extension XCTestCase {
  fileprivate func assertThrowsAsyncError<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (Error) -> Void = { _ in }
  ) async {
    do {
      _ = try await expression()
      XCTFail("Expected error. \(message())", file: file, line: line)
    } catch {
      errorHandler(error)
    }
  }
}
