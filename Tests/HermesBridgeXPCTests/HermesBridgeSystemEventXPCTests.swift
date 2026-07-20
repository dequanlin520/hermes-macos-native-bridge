import Foundation
import HermesRuntimeFoundation
import XCTest

@testable import HermesBridgeXPC

final class HermesBridgeSystemEventXPCTests: XCTestCase {
  func testEventIDValidationAndKindCatalog() throws {
    let id = try HermesSystemEventID.generate()
    XCTAssertTrue(HermesSystemEventID.isValid(id.rawValue))
    XCTAssertThrowsError(try HermesSystemEventID(rawValue: "bad"))
    XCTAssertEqual(Set(HermesSystemEventKind.allCases).count, 17)
    XCTAssertTrue(HermesSystemEventKind.allCases.contains(.activeApplicationChanged))
  }

  func testSafeApplicationIdentityAndPublicPayloadOmitPrivateFields() throws {
    let identity = HermesSafeApplicationIdentity(
      bundleIdentifier: "com.example.Helper;rm -rf",
      localizedName: "Helper\u{0000} Window")
    let event = try HermesSystemEvent(
      eventID: .generate(),
      kind: .applicationLaunched,
      source: .workspace,
      application: identity,
      reasonCode: "app_launch"
    )
    let payload = HermesBridgeSystemEventSummary(event: event)
    let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(payload), encoding: .utf8))

    XCTAssertEqual(payload.applicationBundleIdentifier, "com.example.Helper")
    XCTAssertFalse(encoded.localizedCaseInsensitiveContains("executable"))
    XCTAssertFalse(encoded.localizedCaseInsensitiveContains("pid"))
    XCTAssertFalse(encoded.localizedCaseInsensitiveContains("windowTitle"))
    XCTAssertFalse(encoded.localizedCaseInsensitiveContains("clipboard"))
    XCTAssertFalse(encoded.localizedCaseInsensitiveContains("keystroke"))
    XCTAssertFalse(encoded.localizedCaseInsensitiveContains("Prompt"))
    XCTAssertFalse(encoded.localizedCaseInsensitiveContains("token"))
    XCTAssertFalse(encoded.contains("/Users/"))
  }

  func testNetworkNormalizationAndDuplicateDebounce() async throws {
    let harness = Harness()
    let sub = try await harness.client.createSystemEventSubscription(kinds: [
      .networkAvailable, .networkInterfaceChanged, .networkExpensiveChanged,
      .networkConstrainedChanged,
    ])
    let id = try HermesSystemEventSubscriptionID(rawValue: sub.subscriptionID)
    let state = HermesNetworkPathState(
      status: .available,
      interface: .wifi,
      expensive: true,
      constrained: true
    )

    await harness.coordinator.ingestNetworkState(state)
    await harness.coordinator.ingestNetworkState(state)
    let first = try await harness.client.pollSystemEventSubscription(subscriptionID: id)
    let second = try await harness.client.pollSystemEventSubscription(subscriptionID: id)
    let third = try await harness.client.pollSystemEventSubscription(subscriptionID: id)
    let fourth = try await harness.client.pollSystemEventSubscription(subscriptionID: id)
    let empty = try await harness.client.pollSystemEventSubscription(subscriptionID: id)

    XCTAssertEqual(first.events.first?.kind, .networkAvailable)
    XCTAssertEqual(second.events.first?.networkInterface, .wifi)
    XCTAssertEqual(third.events.first?.networkExpensive, true)
    XCTAssertEqual(fourth.events.first?.networkConstrained, true)
    XCTAssertTrue(empty.events.isEmpty)
  }

  func testWorkspaceSessionAndServiceEventsOrdering() async throws {
    let harness = Harness()
    let sub = try await harness.client.createSystemEventSubscription(
      kinds: HermesSystemEventKind.allCases)
    let id = try HermesSystemEventSubscriptionID(rawValue: sub.subscriptionID)
    await harness.coordinator.ingestWorkspace(
      kind: .applicationLaunched,
      application: HermesSafeApplicationIdentity(
        bundleIdentifier: "com.example.Launch", localizedName: "Launch"))
    await harness.coordinator.ingestWorkspace(
      kind: .applicationTerminated,
      application: HermesSafeApplicationIdentity(
        bundleIdentifier: "com.example.Term", localizedName: "Term"))
    await harness.coordinator.ingestWorkspace(
      kind: .activeApplicationChanged,
      application: HermesSafeApplicationIdentity(
        bundleIdentifier: "com.example.Active", localizedName: "Active"))
    for kind in [
      HermesSystemEventKind.systemWillSleep, .systemDidWake, .screenDidSleep, .screenDidWake,
      .sessionLocked, .sessionUnlocked,
    ] {
      await harness.coordinator.ingestWorkspace(kind: kind, application: nil)
    }
    await harness.coordinator.ingestServiceHealth(.degraded)

    var observed: [HermesSystemEventKind] = []
    var newest: UInt64 = 0
    for _ in 0..<10 {
      let batch = try await harness.client.pollSystemEventSubscription(subscriptionID: id)
      observed.append(contentsOf: batch.events.map(\.kind))
      XCTAssertGreaterThanOrEqual(batch.newestEventOrdinal, newest)
      newest = batch.newestEventOrdinal
    }

    XCTAssertEqual(
      observed,
      [
        .applicationLaunched, .applicationTerminated, .activeApplicationChanged,
        .systemWillSleep, .systemDidWake, .screenDidSleep, .screenDidWake,
        .sessionLocked, .sessionUnlocked, .bridgeServiceDegraded,
      ])
  }

  func testSubscriptionPollAckCancelExpiryOverflowIsolationAndShutdown() async throws {
    let harness = Harness(inactivityTimeout: 0.05)
    let first = try await harness.client.createSystemEventSubscription(kinds: [.applicationLaunched]
    )
    let second = try await harness.client.createSystemEventSubscription(kinds: [
      .applicationTerminated
    ])
    let firstID = try HermesSystemEventSubscriptionID(rawValue: first.subscriptionID)
    let secondID = try HermesSystemEventSubscriptionID(rawValue: second.subscriptionID)

    for index in 0..<(HermesBridgeSystemEventCoordinator.maximumPendingBatchesPerSubscription + 2) {
      await harness.coordinator.ingestWorkspace(
        kind: .applicationLaunched,
        application: HermesSafeApplicationIdentity(
          bundleIdentifier: "com.example.\(index)",
          localizedName: "Helper"))
    }
    await harness.coordinator.ingestWorkspace(
      kind: .applicationTerminated,
      application: HermesSafeApplicationIdentity(
        bundleIdentifier: "com.example.Done", localizedName: "Done"))

    let overflow = try await harness.client.pollSystemEventSubscription(subscriptionID: firstID)
    let isolated = try await harness.client.pollSystemEventSubscription(subscriptionID: secondID)
    XCTAssertTrue(overflow.resyncRequired)
    XCTAssertEqual(overflow.droppedEventReason, "slow_consumer")
    XCTAssertEqual(isolated.events.first?.kind, .applicationTerminated)

    let ack = try await harness.client.acknowledgeSystemEventBatch(
      subscriptionID: firstID,
      acknowledgedEventOrdinal: overflow.newestEventOrdinal
    )
    let duplicate = try await harness.client.acknowledgeSystemEventBatch(
      subscriptionID: firstID,
      acknowledgedEventOrdinal: overflow.newestEventOrdinal
    )
    XCTAssertEqual(ack.acknowledgedEventID, duplicate.acknowledgedEventID)
    await assertThrowsAsyncError(
      try await harness.client.acknowledgeSystemEventBatch(
        subscriptionID: firstID,
        acknowledgedEventOrdinal: overflow.newestEventOrdinal + 100
      )
    ) {
      XCTAssertEqual($0 as? HermesBridgeXPCClientError, .service(.acknowledgementRejected))
    }

    _ = try await harness.client.cancelSystemEventSubscription(subscriptionID: firstID)
    _ = try await harness.client.cancelSystemEventSubscription(subscriptionID: firstID)
    let expiring = try await harness.client.createSystemEventSubscription(kinds: [.screenDidWake])
    let expiringID = try HermesSystemEventSubscriptionID(rawValue: expiring.subscriptionID)
    try await Task.sleep(nanoseconds: 80_000_000)
    await assertThrowsAsyncError(
      try await harness.client.pollSystemEventSubscription(subscriptionID: expiringID)
    ) {
      XCTAssertEqual($0 as? HermesBridgeXPCClientError, .service(.subscriptionExpired))
    }

    await harness.coordinator.shutdown()
    let status = try await harness.coordinator.monitorStatus()
    XCTAssertEqual(status.status.activeSubscriptionCount, 0)
  }

  func testXPCInProcessAnonymousAndAuditSubscriptionEvents() async throws {
    let store = InMemoryAuditStore()
    let harness = Harness(auditStore: store)
    let version = try await harness.client.protocolVersion()
    let capabilities = try await harness.client.capabilities()
    XCTAssertEqual(version.version, HermesBridgeProtocolVersion(major: 1, minor: 4))
    XCTAssertTrue(capabilities.capabilities.contains(.systemEventObservation))

    let sub = try await harness.client.createSystemEventSubscription(kinds: [.bridgeServiceDegraded]
    )
    let id = try HermesSystemEventSubscriptionID(rawValue: sub.subscriptionID)
    await harness.coordinator.ingestServiceHealth(.degraded)
    let batch = try await harness.client.pollSystemEventSubscription(subscriptionID: id)
    _ = try await harness.client.cancelSystemEventSubscription(subscriptionID: id)
    XCTAssertEqual(batch.events.first?.kind, .bridgeServiceDegraded)

    let fixture = AnonymousFixture(handler: harness.coordinator)
    let anonymousClient = HermesBridgeXPCClient(transport: fixture.makeTransport(), timeout: 1)
    _ = try await anonymousClient.systemEventMonitorStatus()
    await anonymousClient.close()
    fixture.close()

    let kinds = await store.events.map(\.kind)
    XCTAssertTrue(kinds.contains(.systemEventSubscriptionCreated))
    XCTAssertTrue(kinds.contains(.systemEventSubscriptionCancelled))
    XCTAssertTrue(kinds.contains(.serviceHealthTransition))
  }

  private final class Harness {
    let coordinator: HermesBridgeSystemEventCoordinator
    let client: HermesBridgeXPCClient

    init(
      inactivityTimeout: TimeInterval = 30,
      auditStore: any HermesAuditStore = NoopHermesAuditStore()
    ) {
      coordinator = HermesBridgeSystemEventCoordinator(
        inactivityTimeout: inactivityTimeout,
        productionMonitorsEnabled: false
      )
      client = HermesBridgeXPCClient(
        transport: InProcessTransport(
          dispatcher: HermesBridgeXPCRequestDispatcher(
            handler: coordinator,
            auditStore: auditStore
          )),
        timeout: 1
      )
    }
  }
}

private struct InProcessTransport: HermesBridgeXPCTransport {
  let dispatcher: HermesBridgeXPCRequestDispatcher

  func send(_ requestData: Data) async throws -> Data {
    await dispatcher.handle(requestData)
  }

  func close() {}
}

private actor InMemoryAuditStore: HermesAuditStore {
  private(set) var events: [HermesAuditEvent] = []

  func append(_ event: HermesAuditEvent) async throws {
    events.append(event)
  }

  func query(_ query: HermesAuditQuery) async throws -> [HermesAuditEvent] {
    var filtered = events
    if let start = query.start {
      filtered = filtered.filter { $0.timestamp >= start }
    }
    if let end = query.end {
      filtered = filtered.filter { $0.timestamp <= end }
    }
    if let kinds = query.kinds {
      filtered = filtered.filter { kinds.contains($0.kind) }
    }
    if let correlationID = query.correlationID {
      filtered = filtered.filter { $0.correlationID == correlationID }
    }
    return Array(filtered.prefix(query.limit))
  }
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
