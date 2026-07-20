import Foundation
import HermesRuntimeFoundation
import XCTest

@testable import HermesBridgeXPC

final class HermesBridgeEventPolicyXPCTests: XCTestCase {
  func testEventPolicyManagementInProcessAndAnonymousRoundTrip() async throws {
    let handler = PolicyHandler()
    let client = HermesBridgeXPCClient(
      transport: InProcessTransport(
        dispatcher: HermesBridgeXPCRequestDispatcher(handler: handler)),
      timeout: 1
    )
    let capabilities = try await client.capabilities()
    XCTAssertEqual(capabilities.protocolVersion, HermesBridgeProtocolVersion(major: 1, minor: 5))
    XCTAssertTrue(capabilities.capabilities.contains(.systemEventPolicyManagement))

    let policy = try makePolicy("hepol_xpc")
    let created = try await client.createEventPolicy(policy).policy
    XCTAssertEqual(created.id, policy.id)
    let listed = try await client.listEventPolicies()
    XCTAssertEqual(listed.policies.map(\.id), [policy.id])
    let dryRun = try await client.evaluateEventPolicyDryRun(
      event: try event(kind: .networkAvailable, networkStatus: .available))
    XCTAssertEqual(dryRun.evaluations.map(\.decision), [.matchedDryRun])
    let paused = try await client.pauseEventPolicies().status.paused
    let resumed = try await client.resumeEventPolicies().status.paused
    XCTAssertTrue(paused)
    XCTAssertFalse(resumed)
    _ = try await client.disableEventPolicy(id: policy.id, expectedRevision: created.revision)

    let fixture = AnonymousFixture(handler: handler)
    let anonymous = HermesBridgeXPCClient(transport: fixture.makeTransport(), timeout: 1)
    _ = try await anonymous.eventPolicyEngineStatus()
    await anonymous.close()
    fixture.close()
  }

  private func makePolicy(_ id: String) throws -> HermesEventPolicy {
    try HermesEventPolicy(
      id: HermesEventPolicyID(rawValue: id),
      conditions: [
        .eventKindEquals(.networkAvailable),
        .networkAvailabilityEquals(.available),
      ],
      actions: [.recordAuditEvent(reasonCode: "matched")]
    )
  }
}

private actor PolicyHandler: HermesBridgeRequestHandling {
  private var policies: [HermesEventPolicyID: HermesEventPolicy] = [:]
  private var paused = false

  nonisolated func submit(bindingID _: HermesRequestBindingID, prompt _: String) async throws
    -> HermesRequestID
  {
    throw HermesBridgeXPCError.unsupportedCapability
  }

  nonisolated func status(requestID _: HermesRequestID) async throws -> HermesRequestRecord {
    throw HermesBridgeXPCError.unsupportedCapability
  }

  nonisolated func cancel(requestID _: HermesRequestID) async throws -> HermesRequestRecord {
    throw HermesBridgeXPCError.unsupportedCapability
  }

  nonisolated func respondToApproval(
    requestID _: HermesRequestID,
    decision _: HermesApprovalResponseDecision
  ) async throws -> HermesRequestRecord {
    throw HermesBridgeXPCError.unsupportedCapability
  }

  func listEventPolicies() async throws -> HermesBridgeEventPolicyListPayload {
    HermesBridgeEventPolicyListPayload(
      policies: policies.values.sorted { $0.id.rawValue < $1.id.rawValue })
  }

  func createEventPolicy(_ policy: HermesEventPolicy) async throws -> HermesBridgeEventPolicyPayload
  {
    policies[policy.id] = policy
    return HermesBridgeEventPolicyPayload(policy: policy)
  }

  func updateEventPolicy(_ policy: HermesEventPolicy, expectedRevision _: Int) async throws
    -> HermesBridgeEventPolicyPayload
  {
    policies[policy.id] = policy
    return HermesBridgeEventPolicyPayload(policy: policy)
  }

  func enableEventPolicy(id: HermesEventPolicyID, expectedRevision _: Int?) async throws
    -> HermesBridgeEventPolicyPayload
  {
    var policy = try existing(id)
    policy.enabled = true
    policies[id] = policy
    return HermesBridgeEventPolicyPayload(policy: policy)
  }

  func disableEventPolicy(id: HermesEventPolicyID, expectedRevision _: Int?) async throws
    -> HermesBridgeEventPolicyPayload
  {
    var policy = try existing(id)
    policy.enabled = false
    policies[id] = policy
    return HermesBridgeEventPolicyPayload(policy: policy)
  }

  func removeEventPolicy(id: HermesEventPolicyID, expectedRevision _: Int?) async throws
    -> HermesBridgeEventPolicyIDPayload
  {
    policies.removeValue(forKey: id)
    return HermesBridgeEventPolicyIDPayload(policyID: id)
  }

  func evaluateEventPolicyDryRun(event: HermesSystemEvent) async throws
    -> HermesBridgeEventPolicyEvaluationResultPayload
  {
    let evaluations = policies.values.sorted { $0.id.rawValue < $1.id.rawValue }.compactMap {
      policy in
      try? HermesEventPolicyEvaluation(
        policyID: policy.id,
        policyRevision: policy.revision,
        eventID: event.eventID,
        eventKind: event.kind,
        actionKind: policy.actions.first?.kind,
        decision: .matchedDryRun,
        reasonCode: "dry_run"
      )
    }
    return HermesBridgeEventPolicyEvaluationResultPayload(evaluations: evaluations)
  }

  func eventPolicyEngineStatus() async throws -> HermesBridgeEventPolicyEngineStatusPayload {
    HermesBridgeEventPolicyEngineStatusPayload(
      status: HermesEventPolicyEngineStatus(
        enabledPolicyCount: policies.values.filter(\.enabled).count,
        paused: paused,
        emergencyStopped: false,
        circuitBreakerOpen: false,
        consecutiveFailures: 0,
        recentDecisions: []
      ))
  }

  func pauseEventPolicies() async throws -> HermesBridgeEventPolicyEngineStatusPayload {
    paused = true
    return try await eventPolicyEngineStatus()
  }

  func resumeEventPolicies() async throws -> HermesBridgeEventPolicyEngineStatusPayload {
    paused = false
    return try await eventPolicyEngineStatus()
  }

  private func existing(_ id: HermesEventPolicyID) throws -> HermesEventPolicy {
    guard let policy = policies[id] else { throw HermesBridgeXPCError.requestNotFound }
    return policy
  }
}

private struct InProcessTransport: HermesBridgeXPCTransport {
  let dispatcher: HermesBridgeXPCRequestDispatcher

  func send(_ requestData: Data) async throws -> Data {
    await dispatcher.handle(requestData)
  }

  func close() {}
}

private final class AnonymousFixture: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
  private let listener = NSXPCListener.anonymous()
  private let service: HermesBridgeXPCService

  init(handler: HermesBridgeRequestHandling) {
    service = HermesBridgeXPCService(handler: handler)
    super.init()
    listener.delegate = self
    listener.resume()
  }

  func listener(_: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
    connection.exportedInterface = NSXPCInterface(with: HermesBridgeXPCProtocol.self)
    connection.exportedObject = service
    connection.resume()
    return true
  }

  func makeTransport() -> AnonymousTransport {
    let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
    connection.remoteObjectInterface = NSXPCInterface(with: HermesBridgeXPCProtocol.self)
    connection.resume()
    return AnonymousTransport(connection: connection)
  }

  func close() {
    service.invalidate()
    listener.invalidate()
  }
}

private final class AnonymousTransport: HermesBridgeXPCTransport, @unchecked Sendable {
  private let connection: NSXPCConnection

  init(connection: NSXPCConnection) {
    self.connection = connection
  }

  func send(_ requestData: Data) async throws -> Data {
    guard let proxy = connection.remoteObjectProxy as? HermesBridgeXPCProtocol else {
      throw HermesBridgeXPCClientError.interrupted
    }
    return await withCheckedContinuation { continuation in
      proxy.handleRequest(requestData) { continuation.resume(returning: $0) }
    }
  }

  func close() {
    connection.invalidate()
  }
}

private func event(
  kind: HermesSystemEventKind,
  networkStatus: HermesNetworkStatusClassification? = nil
) throws -> HermesSystemEvent {
  try HermesSystemEvent(
    eventID: .generate(),
    kind: kind,
    source: .testFixture,
    networkStatus: networkStatus,
    reasonCode: "fixture"
  )
}
