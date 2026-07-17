import Foundation
import XCTest

@testable import HermesRuntimeFoundation

final class HermesRequestStateStoreTests: XCTestCase {
  private var temporaryDirectory: URL!

  override func setUpWithError() throws {
    temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "HermesRequestStateStoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: temporaryDirectory)
  }

  func testRequestIDGenerationAndParsing() throws {
    let generated = try HermesRequestID.generate()

    XCTAssertEqual(generated.rawValue.count, HermesRequestID.maximumLength)
    XCTAssertEqual(try HermesRequestID(rawValue: generated.rawValue), generated)
    XCTAssertThrowsError(try HermesRequestID(rawValue: "../escape"))
    XCTAssertThrowsError(try HermesRequestID(rawValue: "hrq_" + String(repeating: "A", count: 42)))
  }

  func testBindingIDValidation() throws {
    XCTAssertEqual(
      try HermesRequestBindingID(rawValue: "binding:v1:daily.status").rawValue,
      "binding:v1:daily.status")
    XCTAssertThrowsError(try HermesRequestBindingID(rawValue: ""))
    XCTAssertThrowsError(try HermesRequestBindingID(rawValue: "binding:v1:../escape"))
    XCTAssertThrowsError(
      try HermesRequestBindingID(rawValue: "binding:v1:" + String(repeating: "a", count: 200)))
  }

  func testAcceptedRecordCreationAndDuplicateRejection() async throws {
    try await forEachStore { store in
      let id = try requestID("A")
      let record = try await store.createAcceptedRequest(
        requestID: id,
        bindingID: bindingID(),
        createdAt: date(0)
      )

      XCTAssertEqual(record.lifecycleState, .accepted)
      XCTAssertEqual(record.revision, 0)
      await XCTAssertThrowsAsyncError(
        try await store.createAcceptedRequest(
          requestID: id, bindingID: bindingID(), createdAt: date(1))
      ) {
        XCTAssertEqual($0 as? HermesRequestStateStoreError, .duplicateRequest(id))
      }
    }
  }

  func testValidStateTransitions() async throws {
    try await forEachStore { store in
      let id = try await create(store)

      var record = try await store.transitionState(
        requestID: id, to: .queued, expectedRevision: 0, updatedAt: date(1))
      record = try await store.transitionState(
        requestID: id, to: .starting, expectedRevision: record.revision, updatedAt: date(2))
      record = try await store.transitionState(
        requestID: id, to: .running, expectedRevision: record.revision, updatedAt: date(3))
      XCTAssertEqual(record.startedAt, date(3))
      record = try await store.transitionState(
        requestID: id, to: .waitingForApproval, expectedRevision: record.revision,
        updatedAt: date(4))
      record = try await store.transitionState(
        requestID: id, to: .running, expectedRevision: record.revision, updatedAt: date(5))
      let result = try HermesRequestResultMetadata(
        availability: .available,
        completedAt: date(6),
        contentClass: .text,
        redactedSummary: "done",
        bridgeOwnedResultLocator: "bridge-result:v1:abc"
      )
      record = try await store.markCompleted(
        requestID: id,
        result: result,
        expectedRevision: record.revision,
        completedAt: date(6)
      )

      XCTAssertEqual(record.lifecycleState, .completed)
      XCTAssertEqual(record.result, result)
      XCTAssertEqual(record.completedAt, date(6))
    }
  }

  func testInvalidStateTransitionRejection() async throws {
    try await forEachStore { store in
      let id = try await create(store)

      await XCTAssertThrowsAsyncError(
        try await store.markCompleted(
          requestID: id,
          result: resultMetadata(),
          expectedRevision: 0,
          completedAt: date(1)
        )
      ) {
        XCTAssertEqual(
          $0 as? HermesRequestStateStoreError,
          .invalidTransition(from: .accepted, to: .completed)
        )
      }
    }
  }

  func testTerminalStateImmutabilityAndIdempotency() async throws {
    try await forEachStore { store in
      let id = try await createRunning(store)
      let result = try resultMetadata()
      let completed = try await store.markCompleted(
        requestID: id,
        result: result,
        expectedRevision: nil,
        completedAt: date(10)
      )

      let repeated = try await store.markCompleted(
        requestID: id,
        result: result,
        expectedRevision: completed.revision,
        completedAt: date(10)
      )
      XCTAssertEqual(repeated, completed)

      await XCTAssertThrowsAsyncError(
        try await store.transitionState(
          requestID: id, to: .running, expectedRevision: nil, updatedAt: date(11))
      ) {
        XCTAssertEqual(
          $0 as? HermesRequestStateStoreError,
          .invalidTransition(from: .completed, to: .running)
        )
      }
      await XCTAssertThrowsAsyncError(
        try await store.markFailed(
          requestID: id,
          failure: failureMetadata(code: "conflict"),
          expectedRevision: nil,
          completedAt: date(12)
        )
      ) {
        XCTAssertEqual(
          $0 as? HermesRequestStateStoreError,
          .invalidTransition(from: .completed, to: .failed)
        )
      }
    }
  }

  func testCancellationIdempotency() async throws {
    try await forEachStore { store in
      let id = try await createRunning(store)

      let first = try await store.requestCancellation(
        requestID: id, expectedRevision: nil, updatedAt: date(5))
      let second = try await store.requestCancellation(
        requestID: id, expectedRevision: first.revision, updatedAt: date(6))
      let cancelled = try await store.markCancelled(
        requestID: id, expectedRevision: second.revision, completedAt: date(7))
      let repeated = try await store.requestCancellation(
        requestID: id, expectedRevision: cancelled.revision, updatedAt: date(8))

      XCTAssertTrue(first.cancellationRequested)
      XCTAssertEqual(first.lifecycleState, .cancelling)
      XCTAssertEqual(second, first)
      XCTAssertEqual(cancelled.lifecycleState, .cancelled)
      XCTAssertEqual(repeated, cancelled)
    }
  }

  func testUnknownRequestRejection() async throws {
    try await forEachStore { store in
      let id = try requestID("Z")

      await XCTAssertThrowsAsyncError(try await store.read(requestID: id)) {
        XCTAssertEqual($0 as? HermesRequestStateStoreError, .unknownRequest(id))
      }
    }
  }

  func testRevisionIncrementAndOptimisticConflict() async throws {
    try await forEachStore { store in
      let id = try await create(store)

      let queued = try await store.transitionState(
        requestID: id, to: .queued, expectedRevision: 0, updatedAt: date(1))
      XCTAssertEqual(queued.revision, 1)
      await XCTAssertThrowsAsyncError(
        try await store.transitionState(
          requestID: id, to: .starting, expectedRevision: 0, updatedAt: date(2))
      ) {
        XCTAssertEqual(
          $0 as? HermesRequestStateStoreError, .revisionConflict(expected: 0, actual: 1))
      }
    }
  }

  func testBackendSessionAndProcessLaunchAttachment() async throws {
    try await forEachStore { store in
      let id = try await createRunning(store)
      let sessionID = try HermesBackendSessionID(rawValue: "session-123")
      let launchID = UUID()

      let record = try await store.attachBackendSessionIdentity(
        requestID: id,
        backendSessionID: sessionID,
        processLaunchID: launchID,
        expectedRevision: nil,
        updatedAt: date(4)
      )

      XCTAssertEqual(record.backendSessionID, sessionID)
      XCTAssertEqual(record.processLaunchID, launchID)
    }
  }

  func testCompletionAndFailureMetadataValidation() async throws {
    try await forEachStore { store in
      let completeID = try await createRunning(store, suffix: "C")
      let failedID = try await createRunning(store, suffix: "F")
      let result = try resultMetadata()
      let failure = try failureMetadata(code: "backend.unavailable")

      let completed = try await store.markCompleted(
        requestID: completeID,
        result: result,
        expectedRevision: nil,
        completedAt: date(20)
      )
      let failed = try await store.markFailed(
        requestID: failedID,
        failure: failure,
        expectedRevision: nil,
        completedAt: date(21)
      )

      XCTAssertEqual(completed.result, result)
      XCTAssertEqual(failed.failure, failure)
      XCTAssertThrowsError(
        try HermesRequestFailure(
          category: .internalFailure,
          code: "../raw",
          safeMessage: "bad",
          retryable: false
        )
      )
    }
  }

  func testNoTokenOrPromptFieldsInEncodedRecords() async throws {
    let root = temporaryDirectory.appendingPathComponent("encoded", isDirectory: true)
    let store = try FileBackedHermesRequestStateStore(storageRoot: root)
    let id = try await createRunning(store)
    _ = try await store.attachBackendSessionIdentity(
      requestID: id,
      backendSessionID: try HermesBackendSessionID(rawValue: "session-public-id"),
      processLaunchID: UUID(),
      expectedRevision: nil,
      updatedAt: date(3)
    )
    _ = try await store.markFailed(
      requestID: id,
      failure: failureMetadata(code: "safe.failure"),
      expectedRevision: nil,
      completedAt: date(4)
    )

    let data = try Data(contentsOf: root.appendingPathComponent(id.rawValue + ".json"))
    let text = String(data: data, encoding: .utf8) ?? ""
    XCTAssertFalse(text.contains("token"))
    XCTAssertFalse(text.contains("prompt"))
    XCTAssertFalse(text.contains("stderr"))
    XCTAssertFalse(text.contains("secret"))
    XCTAssertFalse(text.contains("body"))
  }

  func testFileBackedSaveReloadAndAtomicReplacement() async throws {
    let root = temporaryDirectory.appendingPathComponent("reload", isDirectory: true)
    let store = try FileBackedHermesRequestStateStore(storageRoot: root)
    let id = try await createRunning(store)
    let fileURL = root.appendingPathComponent(id.rawValue + ".json")
    let before = try Data(contentsOf: fileURL)

    _ = try await store.transitionState(
      requestID: id, to: .waitingForApproval, expectedRevision: nil, updatedAt: date(4))
    let after = try Data(contentsOf: fileURL)
    let reloaded = try FileBackedHermesRequestStateStore(storageRoot: root)
    let record = try await reloaded.read(requestID: id)

    XCTAssertNotEqual(before, after)
    XCTAssertEqual(record.lifecycleState, .waitingForApproval)
    XCTAssertTrue(try temporaryFiles(in: root).isEmpty)
  }

  func testConcurrentMutationSerialization() async throws {
    let store = try FileBackedHermesRequestStateStore(
      storageRoot: temporaryDirectory.appendingPathComponent("concurrent", isDirectory: true))
    let ids = try (0..<20).map { try requestID(String(format: "%02d", $0)) }

    try await withThrowingTaskGroup(of: Void.self) { group in
      for id in ids {
        let bindingID = try bindingID()
        let createdAt = date(0)
        let queuedAt = date(1)
        group.addTask {
          _ = try await store.createAcceptedRequest(
            requestID: id,
            bindingID: bindingID,
            createdAt: createdAt
          )
          _ = try await store.transitionState(
            requestID: id,
            to: .queued,
            expectedRevision: nil,
            updatedAt: queuedAt
          )
        }
      }
      try await group.waitForAll()
    }

    let recoverable = try await store.listRecoverableRequests()
    XCTAssertEqual(recoverable.count, 20)
    XCTAssertTrue(recoverable.allSatisfy { $0.record.lifecycleState == .queued })
  }

  func testCorruptRecordDetectionAndUnsupportedSchemaVersionRejection() async throws {
    let corruptRoot = temporaryDirectory.appendingPathComponent("corrupt", isDirectory: true)
    let corruptStore = try FileBackedHermesRequestStateStore(storageRoot: corruptRoot)
    let corruptID = try await create(corruptStore)
    try "{ bad json".write(
      to: corruptRoot.appendingPathComponent(corruptID.rawValue + ".json"),
      atomically: false,
      encoding: .utf8
    )

    await XCTAssertThrowsAsyncError(try await corruptStore.read(requestID: corruptID)) {
      XCTAssertEqual($0 as? HermesRequestStateStoreError, .corruptRecord(requestID: nil))
    }

    let schemaRoot = temporaryDirectory.appendingPathComponent("schema", isDirectory: true)
    let schemaStore = try FileBackedHermesRequestStateStore(storageRoot: schemaRoot)
    let schemaID = try await create(schemaStore)
    let fileURL = schemaRoot.appendingPathComponent(schemaID.rawValue + ".json")
    var json = try String(contentsOf: fileURL)
    json = json.replacingOccurrences(of: "\"schemaVersion\" : 1", with: "\"schemaVersion\" : 99")
    try json.write(to: fileURL, atomically: false, encoding: .utf8)

    await XCTAssertThrowsAsyncError(try await schemaStore.read(requestID: schemaID)) {
      XCTAssertEqual($0 as? HermesRequestStateStoreError, .unsupportedSchemaVersion(99))
    }
  }

  func testSymlinkPathBoundaryRejection() async throws {
    let root = temporaryDirectory.appendingPathComponent("symlink-root", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let outside = temporaryDirectory.appendingPathComponent("outside.json")
    try "{}".write(to: outside, atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(
      at: root.appendingPathComponent("escape.json"),
      withDestinationURL: outside
    )

    let store = try FileBackedHermesRequestStateStore(storageRoot: root)
    await XCTAssertThrowsAsyncError(try await store.listRecoverableRequests()) {
      XCTAssertEqual($0 as? HermesRequestStateStoreError, .storageBoundaryViolation)
    }

    let rootLink = temporaryDirectory.appendingPathComponent("root-link")
    try FileManager.default.createSymbolicLink(at: rootLink, withDestinationURL: root)
    XCTAssertThrowsError(try FileBackedHermesRequestStateStore(storageRoot: rootLink)) {
      guard case .storageRootInvalid = $0 as? HermesRequestStateStoreError else {
        return XCTFail("expected storageRootInvalid, got \($0)")
      }
    }
  }

  func testBoundedRecordCountEnforcement() async throws {
    try await forEachStore(maximumRecords: 1) { store in
      _ = try await create(store, suffix: "A")
      await XCTAssertThrowsAsyncError(try await create(store, suffix: "B")) {
        XCTAssertEqual($0 as? HermesRequestStateStoreError, .recordLimitExceeded(maximum: 1))
      }
    }
  }

  func testRecoverableListingAndRecoveryClassification() async throws {
    try await forEachStore { store in
      let queuedID = try await create(store, suffix: "Q")
      _ = try await store.transitionState(
        requestID: queuedID, to: .queued, expectedRevision: nil, updatedAt: date(1))

      let startingID = try await create(store, suffix: "S")
      _ = try await store.transitionState(
        requestID: startingID, to: .queued, expectedRevision: nil, updatedAt: date(1))
      _ = try await store.transitionState(
        requestID: startingID, to: .starting, expectedRevision: nil, updatedAt: date(2))

      let runningID = try await createRunning(store, suffix: "R")
      _ = try await store.attachBackendSessionIdentity(
        requestID: runningID,
        backendSessionID: try HermesBackendSessionID(rawValue: "session-R"),
        processLaunchID: UUID(),
        expectedRevision: nil,
        updatedAt: date(5)
      )

      let completedID = try await createRunning(store, suffix: "T")
      _ = try await store.markCompleted(
        requestID: completedID,
        result: resultMetadata(),
        expectedRevision: nil,
        completedAt: date(6)
      )

      let decisions = try await store.listRecoverableRequests()
        .reduce(into: [HermesRequestID: HermesRequestRecoveryDecision]()) {
          $0[$1.record.requestID] = $1.decision
        }

      XCTAssertEqual(decisions[queuedID], .resumeEligible)
      XCTAssertEqual(decisions[startingID], .reconcileWithSupervisor)
      XCTAssertEqual(decisions[runningID], .reconcileWithProtocolClient)
      XCTAssertEqual(decisions[completedID], .noActionTerminal)
    }
  }

  func testRetentionPrunesTerminalRecords() async throws {
    try await forEachStore { store in
      let oldID = try await createRunning(store, suffix: "O")
      let activeID = try await createRunning(store, suffix: "A")
      let newID = try await createRunning(store, suffix: "N")

      _ = try await store.markCompleted(
        requestID: oldID,
        result: resultMetadata(completedAt: date(10)),
        expectedRevision: nil,
        completedAt: date(10)
      )
      _ = try await store.markCompleted(
        requestID: newID,
        result: resultMetadata(completedAt: date(100)),
        expectedRevision: nil,
        completedAt: date(100)
      )

      let pruned = try await store.pruneTerminalRecords(
        policy: HermesRequestRetentionPolicy(terminalRecordAge: 50),
        now: date(80)
      )

      XCTAssertEqual(pruned, 1)
      await XCTAssertThrowsAsyncError(try await store.read(requestID: oldID))
      let active = try await store.read(requestID: activeID)
      let recent = try await store.read(requestID: newID)
      XCTAssertEqual(active.lifecycleState, .running)
      XCTAssertEqual(recent.lifecycleState, .completed)
    }
  }

  func testNoResidualTemporaryFilesAfterSuccessfulWrites() async throws {
    let root = temporaryDirectory.appendingPathComponent("tmp-check", isDirectory: true)
    let store = try FileBackedHermesRequestStateStore(storageRoot: root)
    let id = try await createRunning(store)
    _ = try await store.requestCancellation(
      requestID: id, expectedRevision: nil, updatedAt: date(5))

    XCTAssertTrue(try temporaryFiles(in: root).isEmpty)
  }

  private func forEachStore(
    maximumRecords: Int = 1_000,
    _ body: (HermesRequestStateStore) async throws -> Void
  ) async throws {
    try await body(InMemoryHermesRequestStateStore(maximumRecords: maximumRecords))
    let root = temporaryDirectory.appendingPathComponent(
      "file-\(UUID().uuidString)", isDirectory: true)
    try await body(
      try FileBackedHermesRequestStateStore(storageRoot: root, maximumRecords: maximumRecords)
    )
  }

  private func create(
    _ store: HermesRequestStateStore,
    suffix: String = "A"
  ) async throws -> HermesRequestID {
    let id = try requestID(suffix)
    _ = try await store.createAcceptedRequest(
      requestID: id, bindingID: bindingID(), createdAt: date(0))
    return id
  }

  private func createRunning(
    _ store: HermesRequestStateStore,
    suffix: String = "A"
  ) async throws -> HermesRequestID {
    let id = try await create(store, suffix: suffix)
    _ = try await store.transitionState(
      requestID: id, to: .queued, expectedRevision: nil, updatedAt: date(1))
    _ = try await store.transitionState(
      requestID: id, to: .starting, expectedRevision: nil, updatedAt: date(2))
    _ = try await store.transitionState(
      requestID: id, to: .running, expectedRevision: nil, updatedAt: date(3))
    return id
  }

  private func requestID(_ suffix: String) throws -> HermesRequestID {
    let padded = (suffix + String(repeating: "A", count: HermesRequestID.encodedRandomLength))
      .prefix(HermesRequestID.encodedRandomLength)
    return try HermesRequestID(rawValue: HermesRequestID.prefix + padded)
  }

  private func bindingID() throws -> HermesRequestBindingID {
    try HermesRequestBindingID(rawValue: "binding:v1:test.binding")
  }

  private func resultMetadata(completedAt: Date? = nil) throws -> HermesRequestResultMetadata {
    try HermesRequestResultMetadata(
      availability: .available,
      completedAt: completedAt ?? date(10),
      contentClass: .text,
      redactedSummary: "redacted summary",
      bridgeOwnedResultLocator: "bridge-result:v1:test"
    )
  }

  private func failureMetadata(code: String) throws -> HermesRequestFailure {
    try HermesRequestFailure(
      category: .backendUnavailable,
      code: code,
      safeMessage: "Backend unavailable.",
      retryable: true
    )
  }

  private func temporaryFiles(in root: URL) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
      .filter { $0.lastPathComponent.hasPrefix(".tmp-") }
  }

  private func date(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: 1_700_000_000 + seconds)
  }
}

extension XCTestCase {
  fileprivate func XCTAssertThrowsAsyncError<T>(
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
