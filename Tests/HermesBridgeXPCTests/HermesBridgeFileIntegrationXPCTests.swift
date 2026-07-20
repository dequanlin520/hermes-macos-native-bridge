import Foundation
import HermesRuntimeFoundation
import XCTest

@testable import HermesBridgeXPC

final class HermesBridgeFileIntegrationXPCTests: XCTestCase {
  func testProtocolMinorVersionAndCapabilitiesAdvertiseFileIntegration() async throws {
    let harness = try Harness()

    let version = try await harness.client.protocolVersion()
    let capabilities = try await harness.client.capabilities()

    XCTAssertEqual(version.version, HermesBridgeProtocolVersion(major: 1, minor: 3))
    XCTAssertTrue(capabilities.capabilities.contains(.authorizedRootManagement))
    XCTAssertTrue(capabilities.capabilities.contains(.fileEventObservation))
    XCTAssertTrue(capabilities.capabilities.contains(.bindingDiscovery))
  }

  func testUnsupportedCapabilityForCompositionWithoutFileCoordinator() async throws {
    let client = HermesBridgeXPCClient(
      transport: InProcessTransport(
        dispatcher: HermesBridgeXPCRequestDispatcher(handler: NoFileHandler())),
      timeout: 1
    )

    await assertThrowsAsyncError(try await client.listAuthorizedRoots()) {
      XCTAssertEqual($0 as? HermesBridgeXPCClientError, .service(.unsupportedCapability))
    }
  }

  func testRegisterListStatusAndRedaction() async throws {
    let harness = try Harness()
    let registered = try await harness.registerRoot(displayName: "Docs")

    let listed = try await harness.client.listAuthorizedRoots()
    let status = try await harness.client.authorizedRootStatus(rootID: registered.rootID)
    let resolution = try await harness.client.resolveAuthorizedRoot(rootID: registered.rootID)
    let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(listed), encoding: .utf8))

    XCTAssertEqual(listed.roots.map(\.rootID), [registered.rootID.rawValue])
    XCTAssertEqual(status.root.rootID, registered.rootID.rawValue)
    XCTAssertEqual(resolution.rootID, registered.rootID.rawValue)
    XCTAssertTrue(resolution.resolvedSameAuthorizedRoot)
    XCTAssertFalse(resolution.staleAuthorization)
    XCTAssertTrue(status.root.active)
    XCTAssertFalse(encoded.contains(harness.root.path))
    XCTAssertFalse(encoded.contains("bookmarkData"))
    XCTAssertFalse(encoded.contains("contents"))
  }

  func testPathStringRegistrationIsNotModeledAndOversizedBookmarkRejected() async throws {
    let source = try String(
      contentsOfFile: "Sources/HermesBridgeXPC/HermesBridgeXPCModels.swift",
      encoding: .utf8
    )
    let harness = try Harness()

    await assertThrowsAsyncError(
      try await harness.client.registerAuthorizedRoot(
        displayName: "too-big",
        bookmarkData: Data(
          repeating: 1,
          count: HermesBridgeRegisterAuthorizedRootPayload.maximumBookmarkBytes + 1
        )
      )
    ) {
      XCTAssertEqual($0 as? HermesBridgeXPCClientError, .service(.bookmarkTooLarge))
    }
    XCTAssertFalse(source.contains("registerAuthorizedRootPath"))
    XCTAssertFalse(source.contains("path: String"))
  }

  func testDuplicateAuthorizedRootMapsToTypedError() async throws {
    let harness = try Harness()
    _ = try await harness.registerRoot(displayName: "Docs")

    await assertThrowsAsyncError(
      try await harness.client.registerAuthorizedRoot(
        displayName: "Duplicate",
        bookmarkData: try harness.bookmarkData()
      )
    ) {
      XCTAssertEqual($0 as? HermesBridgeXPCClientError, .service(.duplicateAuthorizedRoot))
    }
  }

  func testRefreshDeactivateReactivateAndRemoveRoot() async throws {
    let harness = try Harness()
    let registered = try await harness.registerRoot(displayName: "Docs")
    let deactivated = try await harness.client.deactivateAuthorizedRoot(
      rootID: registered.rootID,
      expectedRevision: registered.revision
    )

    let reactivated = try await harness.client.reactivateAuthorizedRoot(
      rootID: registered.rootID,
      bookmarkData: try harness.bookmarkData(),
      expectedRevision: deactivated.root.revision
    )
    let refreshed = try await harness.client.refreshAuthorizedRoot(
      rootID: registered.rootID,
      bookmarkData: try harness.bookmarkData(),
      expectedRevision: reactivated.root.revision
    )
    let removed = try await harness.client.removeAuthorizedRoot(
      rootID: registered.rootID,
      expectedRevision: refreshed.root.revision
    )

    XCTAssertFalse(deactivated.root.active)
    XCTAssertTrue(reactivated.root.active)
    XCTAssertEqual(removed.root.rootID, registered.rootID.rawValue)
    await assertThrowsAsyncError(
      try await harness.client.authorizedRootStatus(rootID: registered.rootID)
    ) {
      XCTAssertEqual($0 as? HermesBridgeXPCClientError, .service(.rootNotFound))
    }
  }

  func testUnknownRootAndInactiveRootSubscriptionRejection() async throws {
    let harness = try Harness()
    let registered = try await harness.registerRoot(displayName: "Docs")
    _ = try await harness.client.deactivateAuthorizedRoot(rootID: registered.rootID)
    let unknown = try HermesAuthorizedRootID.generate()

    await assertThrowsAsyncError(try await harness.client.authorizedRootStatus(rootID: unknown)) {
      XCTAssertEqual($0 as? HermesBridgeXPCClientError, .service(.rootNotFound))
    }
    await assertThrowsAsyncError(
      try await harness.client.createFileEventSubscription(rootIDs: [registered.rootID])
    ) {
      XCTAssertEqual($0 as? HermesBridgeXPCClientError, .service(.rootInactive))
    }
  }

  func testCreateSubscriptionRootCountBoundAndEmptyPoll() async throws {
    let harness = try Harness()
    let registered = try await harness.registerRoot(displayName: "Docs")

    let subscription = try await harness.client.createFileEventSubscription(rootIDs: [
      registered.rootID
    ])
    let empty = try await harness.client.pollFileEventSubscription(
      subscriptionID: try HermesBridgeFileEventSubscriptionID(
        rawValue: subscription.subscriptionID),
      timeoutMilliseconds: 1
    )

    XCTAssertEqual(subscription.rootIDs, [registered.rootID.rawValue])
    XCTAssertTrue(empty.events.isEmpty)
    await assertThrowsAsyncError(
      try await harness.client.createFileEventSubscription(
        rootIDs: Array(
          repeating: registered.rootID,
          count: HermesBridgeFileIntegrationCoordinator.maximumRootsPerSubscription + 1)
      )
    ) {
      XCTAssertEqual($0 as? HermesBridgeXPCClientError, .service(.malformedPayload))
    }
  }

  func testPollEventBatchRelativePathsBoundsReplayHistoryAndDropReason() async throws {
    let harness = try Harness()
    let registered = try await harness.registerRoot(displayName: "Docs")
    let subscription = try await harness.client.createFileEventSubscription(rootIDs: [
      registered.rootID
    ])
    let subscriptionID = try HermesBridgeFileEventSubscriptionID(
      rawValue: subscription.subscriptionID)

    try await harness.coordinator.ingest(
      batch: harness.batch(
        rootID: registered.rootID,
        paths: ["alpha.txt", "renamed.txt"],
        newest: 10,
        replayed: true,
        includeHistoryDone: true,
        rescanRequired: true,
        droppedReason: .kernelDropped
      ))
    let polled = try await harness.client.pollFileEventSubscription(subscriptionID: subscriptionID)
    let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(polled), encoding: .utf8))

    XCTAssertEqual(polled.rootID, registered.rootID.rawValue)
    XCTAssertEqual(polled.newestEventID, 10)
    XCTAssertTrue(polled.replayed)
    XCTAssertTrue(polled.historyDone)
    XCTAssertTrue(polled.rescanRequired)
    XCTAssertEqual(polled.droppedEventReason, "kernelDropped")
    XCTAssertLessThanOrEqual(
      polled.events.count, HermesBridgeFileEventBatchPayload.maximumEventCount)
    XCTAssertLessThanOrEqual(
      try JSONEncoder().encode(polled).count, HermesBridgeFileEventBatchPayload.maximumEncodedBytes)
    XCTAssertTrue(polled.events.allSatisfy { !$0.relativePath.hasPrefix("/") })
    XCTAssertFalse(encoded.contains(harness.root.path))
    XCTAssertFalse(encoded.contains("file-secret"))
    XCTAssertFalse(encoded.contains("Prompt"))
    XCTAssertFalse(encoded.contains("token"))
  }

  func testAcknowledgeDuplicateInvalidCancelAndExpiry() async throws {
    let harness = try Harness(inactivityTimeout: 0.05)
    let registered = try await harness.registerRoot(displayName: "Docs")
    let subscription = try await harness.client.createFileEventSubscription(rootIDs: [
      registered.rootID
    ])
    let subscriptionID = try HermesBridgeFileEventSubscriptionID(
      rawValue: subscription.subscriptionID)
    try await harness.coordinator.ingest(
      batch: harness.batch(rootID: registered.rootID, paths: ["a.txt"], newest: 5))
    _ = try await harness.client.pollFileEventSubscription(subscriptionID: subscriptionID)

    let ack = try await harness.client.acknowledgeFileEventBatch(
      subscriptionID: subscriptionID,
      acknowledgedEventID: 5
    )
    let duplicate = try await harness.client.acknowledgeFileEventBatch(
      subscriptionID: subscriptionID,
      acknowledgedEventID: 5
    )

    XCTAssertEqual(ack.acknowledgedEventID, 5)
    XCTAssertEqual(duplicate.acknowledgedEventID, 5)
    await assertThrowsAsyncError(
      try await harness.client.acknowledgeFileEventBatch(
        subscriptionID: subscriptionID,
        acknowledgedEventID: 99
      )
    ) {
      XCTAssertEqual($0 as? HermesBridgeXPCClientError, .service(.acknowledgementRejected))
    }
    _ = try await harness.client.cancelFileEventSubscription(subscriptionID: subscriptionID)
    _ = try await harness.client.cancelFileEventSubscription(subscriptionID: subscriptionID)

    let expiring = try await harness.client.createFileEventSubscription(rootIDs: [registered.rootID]
    )
    let expiringID = try HermesBridgeFileEventSubscriptionID(rawValue: expiring.subscriptionID)
    try await Task.sleep(nanoseconds: 80_000_000)
    await assertThrowsAsyncError(
      try await harness.client.pollFileEventSubscription(subscriptionID: expiringID)
    ) {
      XCTAssertEqual($0 as? HermesBridgeXPCClientError, .service(.subscriptionExpired))
    }
  }

  func testSlowConsumerOverflowConcurrentIsolationShutdownAndAnonymousRoundTrip() async throws {
    let harness = try Harness()
    let first = try await harness.registerRoot(displayName: "First")
    let second = try await harness.registerRoot(displayName: "Second", root: harness.secondRoot)
    let firstSub = try await harness.client.createFileEventSubscription(rootIDs: [first.rootID])
    let secondSub = try await harness.client.createFileEventSubscription(rootIDs: [second.rootID])
    let firstID = try HermesBridgeFileEventSubscriptionID(rawValue: firstSub.subscriptionID)
    let secondID = try HermesBridgeFileEventSubscriptionID(rawValue: secondSub.subscriptionID)

    for index
      in 0..<(HermesBridgeFileIntegrationCoordinator.maximumPendingBatchesPerSubscription + 2)
    {
      try await harness.coordinator.ingest(
        batch: harness.batch(
          rootID: first.rootID,
          paths: ["overflow-\(index).txt"],
          newest: UInt64(index + 1)
        ))
    }
    try await harness.coordinator.ingest(
      batch: harness.batch(rootID: second.rootID, paths: ["only-second.txt"], newest: 50))

    let overflow = try await harness.client.pollFileEventSubscription(subscriptionID: firstID)
    let isolated = try await harness.client.pollFileEventSubscription(subscriptionID: secondID)
    XCTAssertTrue(overflow.rescanRequired)
    XCTAssertNotEqual(isolated.rootID, first.rootID.rawValue)
    XCTAssertEqual(isolated.events.first?.relativePath, "only-second.txt")

    let fixture = AnonymousFixture(handler: harness.coordinator)
    let anonymousClient = HermesBridgeXPCClient(transport: fixture.makeTransport(), timeout: 1)
    _ = try await anonymousClient.listAuthorizedRoots()
    await anonymousClient.close()
    fixture.close()

    await harness.coordinator.shutdown()
    let status = try await harness.coordinator.fileEventMonitorStatus()
    XCTAssertEqual(status.activeSubscriptionCount, 0)
  }

  private final class Harness {
    let temporaryDirectory: URL
    let root: URL
    let secondRoot: URL
    let registry: InMemoryHermesAuthorizedRootRegistry
    let coordinator: HermesBridgeFileIntegrationCoordinator
    let client: HermesBridgeXPCClient

    init(inactivityTimeout: TimeInterval = 30) throws {
      temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("hermes-m5-002-\(UUID().uuidString)", isDirectory: true)
      root = temporaryDirectory.appendingPathComponent("root", isDirectory: true)
      secondRoot = temporaryDirectory.appendingPathComponent("second", isDirectory: true)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
      registry = InMemoryHermesAuthorizedRootRegistry(
        policy: HermesAuthorizedRootPolicy(permittedRootParents: [temporaryDirectory])
      )
      coordinator = HermesBridgeFileIntegrationCoordinator(
        registry: registry,
        inactivityTimeout: inactivityTimeout
      )
      client = HermesBridgeXPCClient(
        transport: InProcessTransport(
          dispatcher: HermesBridgeXPCRequestDispatcher(handler: coordinator)),
        timeout: 1
      )
    }

    func bookmarkData(root: URL? = nil) throws -> Data {
      try (root ?? self.root).bookmarkData(
        options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    func registerRoot(displayName: String, root: URL? = nil) async throws
      -> (rootID: HermesAuthorizedRootID, revision: Int)
    {
      let payload = try await client.registerAuthorizedRoot(
        displayName: displayName,
        bookmarkData: try bookmarkData(root: root)
      )
      return (try HermesAuthorizedRootID(rawValue: payload.root.rootID), payload.root.revision)
    }

    func batch(
      rootID: HermesAuthorizedRootID,
      paths: [String],
      newest: UInt64,
      replayed: Bool = false,
      includeHistoryDone: Bool = false,
      rescanRequired: Bool = false,
      droppedReason: HermesFileEventDroppedReason? = nil
    ) throws -> HermesFileEventBatch {
      var events = try paths.enumerated().map { index, path in
        try HermesFileEvent(
          rootID: rootID,
          kind: .modified,
          relativePath: HermesRootRelativePath(rawValue: path),
          fseventID: newest + UInt64(index),
          timestamp: Date(),
          isDirectory: false,
          flags: [try HermesFileEventFlag(rawValue: "ItemModified")]
        )
      }
      if includeHistoryDone {
        events.append(
          try HermesFileEvent(
            rootID: rootID,
            kind: .historyDone,
            relativePath: HermesRootRelativePath(rawValue: HermesRootRelativePath.rootMarker),
            fseventID: newest,
            timestamp: Date(),
            isDirectory: nil,
            flags: [try HermesFileEventFlag(rawValue: "HistoryDone")]
          ))
      }
      return try HermesFileEventBatch(
        rootID: rootID,
        events: events,
        newestEventID: newest,
        replayed: replayed,
        rescanRequired: rescanRequired,
        droppedEventReason: droppedReason
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

private actor NoFileHandler: HermesBridgeRequestHandling {
  func submit(bindingID _: HermesRequestBindingID, prompt _: String) async throws -> HermesRequestID
  {
    try HermesRequestID(rawValue: HermesRequestID.prefix + String(repeating: "B", count: 43))
  }

  func status(requestID _: HermesRequestID) async throws -> HermesRequestRecord {
    throw HermesBridgeXPCError.unsupportedOperation
  }

  func cancel(requestID _: HermesRequestID) async throws -> HermesRequestRecord {
    throw HermesBridgeXPCError.unsupportedOperation
  }

  func respondToApproval(
    requestID _: HermesRequestID,
    decision _: HermesApprovalResponseDecision
  ) async throws -> HermesRequestRecord {
    throw HermesBridgeXPCError.unsupportedOperation
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
