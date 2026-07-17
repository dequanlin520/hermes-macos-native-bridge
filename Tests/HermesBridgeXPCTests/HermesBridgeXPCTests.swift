import Foundation
import HermesRuntimeFoundation
import XCTest

@testable import HermesBridgeXPC

final class HermesBridgeXPCTests: XCTestCase {
  func testSupportedVersionHandshake() async throws {
    let harness = try Harness()

    let response = try await harness.send(.protocolVersion)

    guard case .success(.protocolVersion(let payload)) = response.result else {
      return XCTFail("expected protocol version")
    }
    XCTAssertEqual(payload.version, .current)
  }

  func testUnsupportedMajorVersionRejected() async throws {
    let harness = try Harness()

    let response = try await harness.send(.protocolVersion, version: .init(major: 99, minor: 0))

    XCTAssertFailure(response, .unsupportedProtocolVersion)
  }

  func testMinorVersionCompatibility() async throws {
    let harness = try Harness()

    let response = try await harness.send(.capabilities, version: .init(major: 1, minor: 99))

    guard case .success(.capabilities(let payload)) = response.result else {
      return XCTFail("expected capabilities")
    }
    XCTAssertEqual(payload.protocolVersion.major, 1)
  }

  func testCapabilityResponse() async throws {
    let harness = try Harness()

    let response = try await harness.send(.capabilities)

    guard case .success(.capabilities(let payload)) = response.result else {
      return XCTFail("expected capabilities")
    }
    XCTAssertEqual(Set(payload.capabilities), Set(HermesBridgeCapability.allCases))
  }

  func testSubmitDispatch() async throws {
    let harness = try Harness()

    let response = try await harness.sendSubmit(prompt: "hello")

    guard case .success(.submit(let payload)) = response.result else {
      return XCTFail("expected submit")
    }
    XCTAssertEqual(payload.requestID, harness.requestID.rawValue)
    let submittedPrompts = await harness.handler.submittedPrompts()
    XCTAssertEqual(submittedPrompts, ["hello"])
  }

  func testStatusDispatch() async throws {
    let harness = try Harness()

    let response = try await harness.sendStatus()

    guard case .success(.status(let payload)) = response.result else {
      return XCTFail("expected status")
    }
    XCTAssertEqual(payload.lifecycleState, "running")
  }

  func testCancelDispatch() async throws {
    let harness = try Harness()

    let response = try await harness.sendCancel()

    guard case .success(.cancel(let payload)) = response.result else {
      return XCTFail("expected cancel")
    }
    XCTAssertEqual(payload.lifecycleState, "cancelled")
    let cancelCount = await harness.handler.cancelCountValue()
    XCTAssertEqual(cancelCount, 1)
  }

  func testApprovalResponseDispatch() async throws {
    let harness = try Harness()

    let response = try await harness.sendApproval(decision: .approve)

    guard case .success(.approvalResponse(let payload)) = response.result else {
      return XCTFail("expected approval response")
    }
    XCTAssertEqual(payload.lifecycleState, "running")
    let approvalDecisions = await harness.handler.approvalDecisionValues()
    XCTAssertEqual(approvalDecisions, [.approve])
  }

  func testCorrelationIDPreservation() async throws {
    let harness = try Harness()
    let correlationID = try HermesBridgeCorrelationID(rawValue: "corr-preserved")

    let response = try await harness.send(.capabilities, correlationID: correlationID)

    XCTAssertEqual(response.correlationID, correlationID)
  }

  func testMalformedEnvelopeRejection() async throws {
    let harness = try Harness()

    let responseData = await harness.dispatcher.handle(Data("{".utf8))
    let response = try harness.decodeResponse(from: responseData)

    XCTAssertFailure(response, .malformedPayload)
  }

  func testUnknownOperationRejection() async throws {
    let harness = try Harness()
    let data = Data(
      """
      {"protocolVersion":{"major":1,"minor":0},"correlationID":"unknown-op","operation":"execute"}
      """.utf8)

    let responseData = await harness.dispatcher.handle(data)
    let response = try harness.decodeResponse(from: responseData)

    XCTAssertFailure(response, .unsupportedOperation)
    XCTAssertEqual(response.correlationID.rawValue, "unknown-op")
  }

  func testMissingPayloadRejection() async throws {
    let harness = try Harness()

    let response = try await harness.send(.submit)

    XCTAssertFailure(response, .malformedPayload)
  }

  func testOversizedEnvelopeRejection() async throws {
    let harness = try Harness()

    let data = Data(repeating: 0x20, count: HermesBridgeRequestEnvelope.maximumEnvelopeBytes + 1)
    let responseData = await harness.dispatcher.handle(data)
    let response = try harness.decodeResponse(from: responseData)

    XCTAssertFailure(response, .oversizedPayload)
  }

  func testOversizedPromptRejection() async throws {
    let harness = try Harness()

    let response = try await harness.sendSubmit(
      prompt: String(repeating: "x", count: HermesBridgeRequestEnvelope.maximumPromptBytes + 1)
    )

    XCTAssertFailure(response, .oversizedPayload)
  }

  func testInvalidRequestIDRejection() async throws {
    let harness = try Harness()

    let response = try await harness.sendStatus(requestID: "bad-request-id")

    XCTAssertFailure(response, .malformedPayload)
  }

  func testInvalidBindingRejection() async throws {
    let harness = try Harness()

    let response = try await harness.sendSubmit(bindingID: "not-a-binding", prompt: "hello")

    XCTAssertFailure(response, .invalidBinding)
  }

  func testInvalidApprovalDecisionRejection() async throws {
    let harness = try Harness()
    let data = Data(
      """
      {"protocolVersion":{"major":1,"minor":0},"correlationID":"bad-approval","operation":"approvalResponse","approvalResponse":{"requestID":"\(harness.requestID.rawValue)","decision":"maybe"}}
      """.utf8)

    let responseData = await harness.dispatcher.handle(data)
    let response = try harness.decodeResponse(from: responseData)

    XCTAssertFailure(response, .malformedPayload)
  }

  func testOrchestratorErrorRedaction() async throws {
    let harness = try Harness()
    await harness.handler.setSubmitError(.backendLaunchFailure("sensitive-backend-marker"))

    let response = try await harness.sendSubmit(prompt: "hello")

    XCTAssertFailure(response, .serviceUnavailable)
    XCTAssertNoDisallowedText(response, disallowed: ["sensitive-backend-marker"])
  }

  func testInternalErrorDoesNotExposePrompt() async throws {
    let harness = try Harness()
    await harness.handler.setSubmitError(.stateStoreFailure("sensitive-prompt-marker"))

    let response = try await harness.sendSubmit(prompt: "sensitive-prompt-marker")

    XCTAssertFailure(response, .internalFailure)
    XCTAssertNoDisallowedText(response, disallowed: ["sensitive-prompt-marker"])
  }

  func testInternalErrorDoesNotExposeBackendToken() async throws {
    let harness = try Harness()
    await harness.handler.setStatusError(.backendConnectionFailure("sensitive-transport-marker"))

    let response = try await harness.sendStatus()

    XCTAssertFailure(response, .serviceUnavailable)
    XCTAssertNoDisallowedText(response, disallowed: ["sensitive-transport-marker"])
  }

  func testConcurrentRequestLimit() async throws {
    let handler = FakeBridgeHandler()
    await handler.blockStatusCalls()
    let dispatcher = HermesBridgeXPCRequestDispatcher(
      handler: handler,
      maximumConcurrentRequests: 1
    )
    let harness = try Harness(handler: handler, dispatcher: dispatcher)
    let firstStarted = XCTestExpectation(description: "first status started")
    await handler.setStatusStartedExpectation(firstStarted)

    async let first = harness.sendStatus()
    await fulfillment(of: [firstStarted], timeout: 1)
    let second = try await harness.sendStatus()
    await handler.releaseStatusCalls()
    _ = try await first

    XCTAssertFailure(second, .serviceUnavailable)
  }

  func testClientTimeout() async throws {
    let client = HermesBridgeXPCClient(transport: HangingTransport(), timeout: 0.01)

    await assertThrowsAsyncError(try await client.capabilities()) {
      XCTAssertEqual($0 as? HermesBridgeXPCClientError, .timedOut)
    }
  }

  func testClientInterruption() async throws {
    let client = HermesBridgeXPCClient(transport: FailingTransport(error: .interrupted))

    await assertThrowsAsyncError(try await client.capabilities()) {
      XCTAssertEqual($0 as? HermesBridgeXPCClientError, .interrupted)
    }
  }

  func testRepeatedClientCloseIsIdempotent() async throws {
    let transport = CapturingTransport()
    let client = HermesBridgeXPCClient(transport: transport)

    await client.close()
    await client.close()

    XCTAssertEqual(transport.closeCount, 1)
  }

  func testResponseDecodingFailure() async throws {
    let client = HermesBridgeXPCClient(transport: StaticTransport(response: Data("not-json".utf8)))

    await assertThrowsAsyncError(try await client.capabilities()) {
      XCTAssertEqual($0 as? HermesBridgeXPCClientError, .responseDecodingFailure)
    }
  }

  func testNoGenericOperationExposure() throws {
    let source = try String(
      contentsOfFile:
        "Sources/HermesBridgeXPC/HermesBridgeXPCClient.swift",
      encoding: .utf8
    )

    XCTAssertFalse(source.contains("public func send("))
    XCTAssertFalse(source.contains("public func handleRequest"))
    XCTAssertTrue(source.contains("public func submit"))
    XCTAssertTrue(source.contains("public func status"))
    XCTAssertTrue(source.contains("public func cancel"))
  }

  func testSubmitReturnsBeforeBackgroundCompletion() async throws {
    let handler = FakeBridgeHandler()
    await handler.setDelayBackgroundCompletion(true)
    let client = HermesBridgeXPCClient(
      transport: InProcessTransport(dispatcher: HermesBridgeXPCRequestDispatcher(handler: handler)),
      timeout: 1
    )

    let requestID = try await client.submit(bindingID: try Harness.bindingID(), prompt: "hello")

    let expectedRequestID = await handler.requestIDValue()
    let backgroundCompleted = await handler.backgroundCompletedValue()
    XCTAssertEqual(requestID, expectedRequestID)
    XCTAssertFalse(backgroundCompleted)
  }

  func testStatusAndCancelAreSeparateOperations() async throws {
    let harness = try Harness()

    _ = try await harness.sendStatus()
    _ = try await harness.sendCancel()

    let statusCount = await harness.handler.statusCountValue()
    let cancelCount = await harness.handler.cancelCountValue()
    XCTAssertEqual(statusCount, 1)
    XCTAssertEqual(cancelCount, 1)
  }

  func testInProcessClientServiceRoundTrip() async throws {
    let harness = try Harness()
    let client = HermesBridgeXPCClient(
      transport: InProcessTransport(dispatcher: harness.dispatcher),
      timeout: 1
    )

    let capabilities = try await client.connect()
    let requestID = try await client.submit(bindingID: harness.bindingID, prompt: "hello")
    let status = try await client.status(requestID: requestID)

    XCTAssertTrue(capabilities.capabilities.contains(.submitRequest))
    XCTAssertEqual(status.requestID, harness.requestID.rawValue)
  }

  func testAnonymousNSXPCInterfaceRoundTrip() async throws {
    let fixture = AnonymousXPCFixture(handler: FakeBridgeHandler())
    let client = HermesBridgeXPCClient(transport: fixture.makeTransport(), timeout: 1)

    let capabilities = try await client.connect()
    let requestID = try await client.submit(bindingID: try Harness.bindingID(), prompt: "hello")

    await client.close()
    fixture.close()
    XCTAssertTrue(capabilities.capabilities.contains(.requestStatus))
    XCTAssertEqual(requestID, try Harness.requestID())
  }

  func testNoResidualTestXPCProcessOrService() throws {
    let output = try shell("pgrep -fl com.hermes.m2-007-test || true")

    XCTAssertTrue(output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
  }

  private final class Harness: @unchecked Sendable {
    let handler: FakeBridgeHandler
    let dispatcher: HermesBridgeXPCRequestDispatcher
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let bindingID: HermesRequestBindingID
    let requestID: HermesRequestID

    init(
      handler: FakeBridgeHandler = FakeBridgeHandler(),
      dispatcher: HermesBridgeXPCRequestDispatcher? = nil
    ) throws {
      self.handler = handler
      self.dispatcher = dispatcher ?? HermesBridgeXPCRequestDispatcher(handler: handler)
      bindingID = try Self.bindingID()
      requestID = try Self.requestID()
    }

    static func bindingID() throws -> HermesRequestBindingID {
      try HermesRequestBindingID(rawValue: "binding:v1:test.binding")
    }

    static func requestID() throws -> HermesRequestID {
      try HermesRequestID(rawValue: HermesRequestID.prefix + String(repeating: "A", count: 43))
    }

    func send(
      _ operation: HermesBridgeOperation,
      version: HermesBridgeProtocolVersion = .current,
      correlationID: HermesBridgeCorrelationID = try! HermesBridgeCorrelationID(rawValue: "corr")
    ) async throws -> HermesBridgeResponseEnvelope {
      try await sendEnvelope(
        HermesBridgeRequestEnvelope(
          protocolVersion: version,
          correlationID: correlationID,
          operation: operation
        ))
    }

    func sendSubmit(
      bindingID: String? = nil,
      prompt: String
    ) async throws -> HermesBridgeResponseEnvelope {
      try await sendEnvelope(
        HermesBridgeRequestEnvelope(
          correlationID: try HermesBridgeCorrelationID(rawValue: "submit-corr"),
          operation: .submit,
          submit: HermesBridgeSubmitPayload(
            bindingID: bindingID ?? self.bindingID.rawValue,
            prompt: prompt
          )
        ))
    }

    func sendStatus(requestID: String? = nil) async throws -> HermesBridgeResponseEnvelope {
      try await sendEnvelope(
        HermesBridgeRequestEnvelope(
          correlationID: try HermesBridgeCorrelationID(rawValue: "status-corr"),
          operation: .status,
          status: HermesBridgeRequestIDPayload(requestID: requestID ?? self.requestID.rawValue)
        ))
    }

    func sendCancel() async throws -> HermesBridgeResponseEnvelope {
      try await sendEnvelope(
        HermesBridgeRequestEnvelope(
          correlationID: try HermesBridgeCorrelationID(rawValue: "cancel-corr"),
          operation: .cancel,
          cancel: HermesBridgeRequestIDPayload(requestID: requestID.rawValue)
        ))
    }

    func sendApproval(decision: HermesBridgeApprovalDecision) async throws
      -> HermesBridgeResponseEnvelope
    {
      try await sendEnvelope(
        HermesBridgeRequestEnvelope(
          correlationID: try HermesBridgeCorrelationID(rawValue: "approval-corr"),
          operation: .approvalResponse,
          approvalResponse: HermesBridgeApprovalResponsePayload(
            requestID: requestID.rawValue,
            decision: decision
          )
        ))
    }

    func sendEnvelope(_ envelope: HermesBridgeRequestEnvelope) async throws
      -> HermesBridgeResponseEnvelope
    {
      let responseData = await dispatcher.handle(try encoder.encode(envelope))
      return try decodeResponse(from: responseData)
    }

    func decodeResponse(from data: Data) throws -> HermesBridgeResponseEnvelope {
      try decoder.decode(HermesBridgeResponseEnvelope.self, from: data)
    }
  }
}

private actor FakeBridgeHandler: HermesBridgeRequestHandling {
  let bindingID = try! HermesRequestBindingID(rawValue: "binding:v1:test.binding")
  let requestID = try! HermesRequestID(
    rawValue: HermesRequestID.prefix + String(repeating: "A", count: 43)
  )
  var delayBackgroundCompletion = false
  var backgroundCompleted = true
  var approvalDecisions: [HermesApprovalResponseDecision] = []
  var cancelCount = 0
  var statusCount = 0
  private var prompts: [String] = []
  private var submitError: HermesRequestOrchestratorError?
  private var statusError: HermesRequestOrchestratorError?
  private var statusBlocked = false
  private var statusStartedExpectation: XCTestExpectation?
  private var statusContinuations: [CheckedContinuation<Void, Never>] = []

  func submittedPrompts() -> [String] {
    prompts
  }

  func cancelCountValue() -> Int {
    cancelCount
  }

  func statusCountValue() -> Int {
    statusCount
  }

  func approvalDecisionValues() -> [HermesApprovalResponseDecision] {
    approvalDecisions
  }

  func setDelayBackgroundCompletion(_ enabled: Bool) {
    delayBackgroundCompletion = enabled
  }

  func backgroundCompletedValue() -> Bool {
    backgroundCompleted
  }

  func requestIDValue() -> HermesRequestID {
    requestID
  }

  func setSubmitError(_ error: HermesRequestOrchestratorError) {
    submitError = error
  }

  func setStatusError(_ error: HermesRequestOrchestratorError) {
    statusError = error
  }

  func blockStatusCalls() {
    statusBlocked = true
  }

  func releaseStatusCalls() {
    statusBlocked = false
    let continuations = statusContinuations
    statusContinuations = []
    for continuation in continuations {
      continuation.resume()
    }
  }

  func setStatusStartedExpectation(_ expectation: XCTestExpectation) {
    statusStartedExpectation = expectation
  }

  func submit(bindingID: HermesRequestBindingID, prompt: String) async throws -> HermesRequestID {
    if let submitError {
      throw submitError
    }
    guard bindingID == self.bindingID else {
      throw HermesRequestOrchestratorError.invalidBinding
    }
    prompts.append(prompt)
    if delayBackgroundCompletion {
      backgroundCompleted = false
      Task {
        try? await Task.sleep(nanoseconds: 200_000_000)
        self.finishBackground()
      }
    } else {
      backgroundCompleted = true
    }
    return requestID
  }

  func status(requestID: HermesRequestID) async throws -> HermesRequestRecord {
    if let statusError {
      throw statusError
    }
    statusCount += 1
    statusStartedExpectation?.fulfill()
    if statusBlocked {
      await withCheckedContinuation { continuation in
        statusContinuations.append(continuation)
      }
    }
    guard requestID == self.requestID else {
      throw HermesRequestOrchestratorError.requestNotFound
    }
    return try record(state: .running)
  }

  func cancel(requestID: HermesRequestID) async throws -> HermesRequestRecord {
    cancelCount += 1
    guard requestID == self.requestID else {
      throw HermesRequestOrchestratorError.requestNotFound
    }
    return try record(state: .cancelled, cancellationRequested: true)
  }

  func respondToApproval(
    requestID: HermesRequestID,
    decision: HermesApprovalResponseDecision
  ) async throws -> HermesRequestRecord {
    guard requestID == self.requestID else {
      throw HermesRequestOrchestratorError.requestNotFound
    }
    approvalDecisions.append(decision)
    return try record(state: .running)
  }

  private func finishBackground() {
    backgroundCompleted = true
  }

  private func record(
    state: HermesRequestLifecycleState,
    cancellationRequested: Bool = false
  ) throws -> HermesRequestRecord {
    try HermesRequestRecord(
      requestID: requestID,
      bindingID: bindingID,
      lifecycleState: state,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      updatedAt: Date(timeIntervalSince1970: 1_700_000_001),
      startedAt: state == .running ? Date(timeIntervalSince1970: 1_700_000_001) : nil,
      completedAt: state.isTerminal ? Date(timeIntervalSince1970: 1_700_000_002) : nil,
      cancellationRequested: cancellationRequested
    )
  }
}

private struct InProcessTransport: HermesBridgeXPCTransport {
  let dispatcher: HermesBridgeXPCRequestDispatcher

  func send(_ requestData: Data) async throws -> Data {
    await dispatcher.handle(requestData)
  }

  func close() {}
}

private final class AnonymousXPCFixture: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
  private let listener = NSXPCListener.anonymous()
  private let service: HermesBridgeXPCService

  init(handler: HermesBridgeRequestHandling) {
    self.service = HermesBridgeXPCService(handler: handler)
    super.init()
    listener.delegate = self
    listener.resume()
  }

  func listener(
    _: NSXPCListener,
    shouldAcceptNewConnection newConnection: NSXPCConnection
  ) -> Bool {
    newConnection.exportedInterface = NSXPCInterface(with: HermesBridgeXPCProtocol.self)
    newConnection.exportedObject = service
    newConnection.resume()
    return true
  }

  func makeTransport() -> AnonymousNSXPCTransport {
    let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
    connection.remoteObjectInterface = NSXPCInterface(with: HermesBridgeXPCProtocol.self)
    connection.resume()
    return AnonymousNSXPCTransport(connection: connection)
  }

  func close() {
    service.invalidate()
    listener.invalidate()
  }
}

private final class AnonymousNSXPCTransport: HermesBridgeXPCTransport, @unchecked Sendable {
  private let lock = NSLock()
  private let connection: NSXPCConnection
  private var closed = false

  init(connection: NSXPCConnection) {
    self.connection = connection
  }

  func send(_ requestData: Data) async throws -> Data {
    let proxy: HermesBridgeXPCProtocol = try lock.withLock {
      if closed {
        throw HermesBridgeXPCClientError.invalidated
      }
      guard let proxy = connection.remoteObjectProxy as? HermesBridgeXPCProtocol else {
        throw HermesBridgeXPCClientError.interrupted
      }
      return proxy
    }
    return await withCheckedContinuation { continuation in
      proxy.handleRequest(requestData) { data in
        continuation.resume(returning: data)
      }
    }
  }

  func close() {
    lock.withLock {
      if closed {
        return
      }
      closed = true
      connection.invalidate()
    }
  }
}

private struct HangingTransport: HermesBridgeXPCTransport {
  func send(_: Data) async throws -> Data {
    try await Task.sleep(nanoseconds: 5_000_000_000)
    return Data()
  }

  func close() {}
}

private struct FailingTransport: HermesBridgeXPCTransport {
  let error: HermesBridgeXPCClientError

  func send(_: Data) async throws -> Data {
    throw error
  }

  func close() {}
}

private final class CapturingTransport: HermesBridgeXPCTransport, @unchecked Sendable {
  private let lock = NSLock()
  private(set) var closeCount = 0

  func send(_: Data) async throws -> Data {
    Data()
  }

  func close() {
    lock.withLock {
      closeCount += 1
    }
  }
}

private struct StaticTransport: HermesBridgeXPCTransport {
  let response: Data

  func send(_: Data) async throws -> Data {
    response
  }

  func close() {}
}

private func XCTAssertFailure(
  _ response: HermesBridgeResponseEnvelope,
  _ code: HermesBridgeXPCError,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  guard case .failure(let payload) = response.result else {
    return XCTFail("expected failure", file: file, line: line)
  }
  XCTAssertEqual(payload.code, code, file: file, line: line)
}

private func XCTAssertNoDisallowedText(
  _ response: HermesBridgeResponseEnvelope,
  disallowed: [String],
  file: StaticString = #filePath,
  line: UInt = #line
) {
  let encoded = String(data: (try? JSONEncoder().encode(response)) ?? Data(), encoding: .utf8) ?? ""
  for value in disallowed {
    XCTAssertFalse(encoded.contains(value), file: file, line: line)
  }
}

private func shell(_ command: String) throws -> String {
  let process = Process()
  let pipe = Pipe()
  process.executableURL = URL(fileURLWithPath: "/bin/zsh")
  process.arguments = ["-lc", command]
  process.standardOutput = pipe
  try process.run()
  process.waitUntilExit()
  return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}

extension XCTestCase {
  fileprivate func assertThrowsAsyncError<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (Error) -> Void
  ) async {
    do {
      _ = try await expression()
      XCTFail("Expected error", file: file, line: line)
    } catch {
      errorHandler(error)
    }
  }
}
