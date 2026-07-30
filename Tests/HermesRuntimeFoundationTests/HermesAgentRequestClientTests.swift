import Foundation
import XCTest

@testable import HermesRuntimeFoundation

final class HermesAgentRequestClientTests: XCTestCase {
  func testSafeSyntheticRequestConstructionAndIdentityValidation() async throws {
    let service = FakeRequestService(statusOutputs: ["idle"])
    let client = HermesAgentRequestClient(
      descriptor: descriptor(),
      serviceFactory: { service },
      now: { "2026-07-30T12:00:00Z" }
    )

    let request = try await client.submitSafeSyntheticRequest()

    XCTAssertEqual(request.identity.rawValue, "session-1")
    XCTAssertEqual(request.identitySyntaxCategory, "token-like")
    XCTAssertEqual(request.creationTimestamp, "2026-07-30T12:00:00Z")
    XCTAssertTrue(service.connected)
    XCTAssertEqual(service.createdSessions, 1)
    XCTAssertFalse(String(describing: request.identity).contains("session-1"))
  }

  func testRequestResponseParsingRejectsMissingIdentity() async {
    let service = FakeRequestService(createdSessionID: "")
    let client = HermesAgentRequestClient(descriptor: descriptor(), serviceFactory: { service })

    await XCTAssertThrowsAgentProtocolAsyncError(try await client.submitSafeSyntheticRequest()) {
      XCTAssertEqual(($0 as? HermesAgentProtocolError)?.reasonCode, "request.identity-missing")
    }
  }

  func testStatusStateMapping() async throws {
    let service = FakeRequestService(statusOutputs: [
      "queued", "running", "awaiting approval", "cancelling", "interrupted", "complete",
      "failed", "opaque",
    ])
    let client = HermesAgentRequestClient(descriptor: descriptor(), serviceFactory: { service })
    let request = try await client.submitSafeSyntheticRequest()

    var states: [HermesAgentRequestState] = []
    for _ in 0..<8 {
      states.append(try await client.observeStatus(for: request))
    }

    XCTAssertEqual(
      states,
      [.queued, .running, .awaitingApproval, .cancelling, .cancelled, .completed, .failed, .unknown]
    )
  }

  func testExactRequestCancellation() async throws {
    let service = FakeRequestService(interruptStatus: "interrupted")
    let client = HermesAgentRequestClient(descriptor: descriptor(), serviceFactory: { service })
    let request = try await client.submitSafeSyntheticRequest()

    let result = try await client.cancel(request: request, targetIdentity: request.identity)

    XCTAssertTrue(result.accepted)
    XCTAssertTrue(result.targetIdentityMatched)
    XCTAssertEqual(result.terminalState, .cancelled)
    XCTAssertEqual(service.interruptedSessionIDs, ["session-1"])
  }

  func testWrongRequestCancellationRejected() async throws {
    let service = FakeRequestService()
    let client = HermesAgentRequestClient(descriptor: descriptor(), serviceFactory: { service })
    let request = try await client.submitSafeSyntheticRequest()
    let wrong = try HermesAgentRequestIdentity(rawValue: "session-2")

    await XCTAssertThrowsAgentProtocolAsyncError(try await client.cancel(request: request, targetIdentity: wrong)) {
      XCTAssertEqual(($0 as? HermesAgentProtocolError)?.reasonCode, "request.identity-mismatch")
    }
    XCTAssertTrue(service.interruptedSessionIDs.isEmpty)
  }

  func testTooFastRequestProducesSupportedUnexercisedCapability() throws {
    let baseline = descriptor()
    let classified = baseline.exercised(cancel: .supportedUnexercised)

    XCTAssertEqual(classified.cancel.status, .supportedUnexercised)
    XCTAssertEqual(classified.cancel.routeCategory, "jsonrpc-websocket-session-interrupt")
  }

  func testApprovalUnsupported() async throws {
    let unsupported = descriptor(approvalStatus: .unsupported)
    let service = FakeRequestService()
    let client = HermesAgentRequestClient(descriptor: unsupported, serviceFactory: { service })
    let request = try await client.submitSafeSyntheticRequest()
    let approval = HermesAgentApprovalDescriptor(
      approvalIDCategory: "none",
      requestIdentity: request.identity,
      safeSyntheticFixture: true,
      reasonCode: "approval.unsupported"
    )

    await XCTAssertThrowsAgentProtocolAsyncError(
      try await client.submitApprovalDecision(.approve, approval: approval)
    ) {
      XCTAssertEqual(($0 as? HermesAgentProtocolError)?.reasonCode, "protocol.approval-route-unsupported")
    }
  }

  func testApprovalSupportedButUnsafeTriggerRejected() async throws {
    let service = FakeRequestService()
    let client = HermesAgentRequestClient(descriptor: descriptor(), serviceFactory: { service })
    let request = try await client.submitSafeSyntheticRequest()
    let approval = HermesAgentApprovalDescriptor(
      approvalIDCategory: "fixture",
      requestIdentity: request.identity,
      safeSyntheticFixture: false,
      reasonCode: "approval.trigger-unsafe"
    )

    await XCTAssertThrowsAgentProtocolAsyncError(
      try await client.submitApprovalDecision(.approve, approval: approval)
    ) {
      XCTAssertEqual(($0 as? HermesAgentProtocolError)?.reasonCode, "approval.trigger-unsafe")
    }
    XCTAssertTrue(service.approvalDecisions.isEmpty)
  }

  func testHarmlessSyntheticApprovalFixture() async throws {
    let service = FakeRequestService()
    let client = HermesAgentRequestClient(descriptor: descriptor(), serviceFactory: { service })
    let request = try await client.submitSafeSyntheticRequest()
    let approval = HermesAgentApprovalDescriptor(
      approvalIDCategory: "fixture",
      requestIdentity: request.identity,
      safeSyntheticFixture: true,
      reasonCode: "approval.synthetic-fixture"
    )

    let resolved = try await client.submitApprovalDecision(.reject, approval: approval)

    XCTAssertTrue(resolved)
    XCTAssertEqual(service.approvalDecisions, ["reject"])
  }

  func testReconnectRequestContinuity() async throws {
    let first = FakeRequestService(statusOutputs: ["running"])
    let second = FakeRequestService(statusOutputs: ["idle"])
    let services = FakeRequestServiceFactory([first, second])
    let client = HermesAgentRequestClient(descriptor: descriptor(), serviceFactory: {
      services.next()
    })
    let request = try await client.submitSafeSyntheticRequest()

    let state = try await client.reconnectAndObserve(request: request)

    XCTAssertTrue(first.closed)
    XCTAssertTrue(second.connected)
    XCTAssertEqual(state, .completed)
    XCTAssertEqual(second.statusSessionIDs, ["session-1"])
  }

  private func descriptor(
    approvalStatus: HermesAgentProtocolCapabilityStatus = .supportedUnexercised
  ) -> HermesAgentProtocolDescriptor {
    HermesAgentProtocolDescriptor(
      protocolFamily: "hermes-jsonrpc-websocket",
      protocolVersion: "0.18.2",
      request: HermesAgentProtocolCapability(
        status: .supportedUnexercised,
        routeCategory: "jsonrpc-websocket-session-create",
        reasonCode: "protocol.request-advertised"
      ),
      status: HermesAgentProtocolCapability(
        status: .supportedUnexercised,
        routeCategory: "jsonrpc-websocket-session-status",
        reasonCode: "protocol.status-advertised"
      ),
      cancel: HermesAgentProtocolCapability(
        status: .supportedUnexercised,
        routeCategory: "jsonrpc-websocket-session-interrupt",
        reasonCode: "protocol.cancel-advertised"
      ),
      approval: HermesAgentProtocolCapability(
        status: approvalStatus,
        routeCategory: approvalStatus == .unsupported ? "unsupported" : "jsonrpc-websocket-approval-respond",
        reasonCode: approvalStatus == .unsupported
          ? "protocol.approval-route-unsupported"
          : "protocol.approval-supported-no-harmless-trigger"
      ),
      authenticationRequired: true,
      authenticationCategory: "loopback_token",
      ephemeralCredentialIsolated: true,
      streamingModesAdvertised: ["websocket-jsonrpc-events"],
      metadataSource: "test"
    )
  }
}

private final class FakeRequestService: HermesAgentRequestProtocolServing, @unchecked Sendable {
  var connected = false
  var closed = false
  var createdSessions = 0
  var statusOutputs: [String?]
  var statusSessionIDs: [String] = []
  var interruptedSessionIDs: [String] = []
  var approvalDecisions: [String] = []
  let createdSessionID: String
  let interruptStatus: String

  init(
    createdSessionID: String = "session-1",
    statusOutputs: [String?] = ["idle"],
    interruptStatus: String = "interrupted"
  ) {
    self.createdSessionID = createdSessionID
    self.statusOutputs = statusOutputs
    self.interruptStatus = interruptStatus
  }

  func fetchStatus() async throws -> HermesBackendStatus {
    let data = Data(
      #"{"version":"0.18.2","auth_required":true,"auth_mode":"loopback_token"}"#.utf8)
    return try JSONDecoder().decode(HermesBackendStatus.self, from: data)
  }

  func connectAndWaitUntilReady(timeout _: TimeInterval) async throws {
    connected = true
  }

  func createSession() async throws -> HermesSessionCreationResult {
    createdSessions += 1
    return HermesSessionCreationResult(sessionID: createdSessionID)
  }

  func sessionStatus(sessionID: String) async throws -> HermesSessionStatusResult {
    statusSessionIDs.append(sessionID)
    let output = statusOutputs.isEmpty ? nil : statusOutputs.removeFirst()
    return HermesSessionStatusResult(output: output ?? nil)
  }

  func interruptSession(sessionID: String) async throws -> HermesSessionInterruptResult {
    interruptedSessionIDs.append(sessionID)
    return HermesSessionInterruptResult(status: interruptStatus)
  }

  func respondToApproval(
    sessionID _: String,
    decision: HermesApprovalDecision,
    all _: Bool?
  ) async throws -> HermesApprovalResponseResult {
    approvalDecisions.append(decision.rawValue)
    return HermesApprovalResponseResult(resolved: true)
  }

  func close() async {
    closed = true
  }
}

private final class FakeRequestServiceFactory: @unchecked Sendable {
  private let lock = NSLock()
  private var services: [FakeRequestService]

  init(_ services: [FakeRequestService]) {
    self.services = services
  }

  func next() -> FakeRequestService {
    lock.withLock {
      services.removeFirst()
    }
  }
}

private func XCTAssertThrowsAgentProtocolAsyncError<T>(
  _ expression: @autoclosure () async throws -> T,
  _ errorHandler: (Error) -> Void = { _ in },
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  do {
    _ = try await expression()
    XCTFail("expected async error", file: file, line: line)
  } catch {
    errorHandler(error)
  }
}
