import CoreServices
import Foundation
import XCTest

@testable import HermesRuntimeFoundation

final class HermesAuthorizedFileRootsTests: XCTestCase {
  private var temporaryDirectory: URL!

  override func setUpWithError() throws {
    temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "HermesAuthorizedFileRootsTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: temporaryDirectory)
  }

  func testRootIDGenerationAndValidation() throws {
    let generated = try HermesAuthorizedRootID.generate()

    XCTAssertEqual(generated.rawValue.count, HermesAuthorizedRootID.maximumLength)
    XCTAssertEqual(try HermesAuthorizedRootID(rawValue: generated.rawValue), generated)
    XCTAssertThrowsError(try HermesAuthorizedRootID(rawValue: "/tmp/private"))
    XCTAssertThrowsError(
      try HermesAuthorizedRootID(rawValue: "hroot_" + String(repeating: "A", count: 42)))
  }

  func testBookmarkSizeValidation() async throws {
    try await forEachRegistry { registry, _ in
      await XCTAssertThrowsHermesAsyncError(
        try await registry.registerBookmark(
          displayName: "too large",
          bookmarkData: Data(
            repeating: 0x41, count: HermesAuthorizedRootRecord.maximumBookmarkBytes + 1),
          createdAt: date(0)
        )
      ) {
        XCTAssertEqual(
          $0 as? HermesAuthorizedRootRegistryError,
          .bookmarkTooLarge(maximumBytes: HermesAuthorizedRootRecord.maximumBookmarkBytes)
        )
      }
    }
  }

  func testRootRegistrationDuplicateListingDeactivateReactivateStaleRemovalAndRevisionConflict()
    async throws
  {
    try await forEachRegistry { registry, policyRoot in
      let root = try makeAuthorizedDirectory(named: "approved", under: policyRoot)
      let bookmark = try bookmarkData(for: root)
      let record = try await registry.registerBookmark(
        displayName: "Test Root",
        bookmarkData: bookmark,
        createdAt: date(0)
      )

      XCTAssertEqual(record.schemaVersion, HermesAuthorizedRootRecord.currentSchemaVersion)
      XCTAssertEqual(record.displayName, "Test Root")
      XCTAssertEqual(record.resolvedRootURL.path, root.resolvingSymlinksInPath().path)
      let read = try await registry.readRoot(record.rootID)
      let listed = try await registry.listRoots()
      XCTAssertEqual(read.rootID, record.rootID)
      XCTAssertEqual(listed.map(\.rootID), [record.rootID])
      XCTAssertFalse(String(describing: record).contains(root.path))

      await XCTAssertThrowsHermesAsyncError(
        try await registry.registerBookmark(
          displayName: "duplicate", bookmarkData: bookmark, createdAt: date(1))
      ) {
        XCTAssertEqual($0 as? HermesAuthorizedRootRegistryError, .duplicateResolvedRoot)
      }

      let inactive = try await registry.deactivateRoot(
        record.rootID,
        expectedRevision: record.revision,
        updatedAt: date(2)
      )
      XCTAssertEqual(inactive.state, .inactive)
      await XCTAssertThrowsHermesAsyncError(try await registry.resolveRoot(record.rootID)) {
        XCTAssertEqual($0 as? HermesAuthorizedRootRegistryError, .inactiveRoot(record.rootID))
      }

      await XCTAssertThrowsHermesAsyncError(
        try await registry.reactivateRoot(
          record.rootID,
          freshBookmarkData: bookmark,
          expectedRevision: record.revision,
          updatedAt: date(3)
        )
      ) {
        XCTAssertEqual(
          $0 as? HermesAuthorizedRootRegistryError, .revisionConflict(expected: 0, actual: 1))
      }

      let active = try await registry.reactivateRoot(
        record.rootID,
        freshBookmarkData: bookmark,
        expectedRevision: inactive.revision,
        updatedAt: date(3)
      )
      XCTAssertEqual(active.state, .active)

      let stale = try await registry.markStale(
        record.rootID,
        expectedRevision: active.revision,
        updatedAt: date(4)
      )
      XCTAssertTrue(stale.bookmarkDataIsStale)

      let cursor = try await registry.updateEventCursor(
        record.rootID,
        eventID: 123,
        expectedRevision: stale.revision
      )
      XCTAssertEqual(cursor.lastObservedFSEventID, 123)
      let unchanged = try await registry.updateEventCursor(
        record.rootID, eventID: 100, expectedRevision: nil)
      XCTAssertEqual(unchanged.lastObservedFSEventID, 123)

      let resolution = try await registry.resolveRoot(record.rootID)
      XCTAssertEqual(resolution.resolvedURL?.path, root.resolvingSymlinksInPath().path)
      if case .rejected = resolution.status {
        XCTFail("ordinary bookmark resolution should not be rejected")
      }

      try await registry.removeRoot(record.rootID, expectedRevision: unchanged.revision)
      let remaining = try await registry.listRoots()
      XCTAssertTrue(remaining.isEmpty)
    }
  }

  func testFileBackedSaveReloadCorruptionUnsupportedSchemaAndSymlinkBoundary() async throws {
    let policyRoot = try makeAuthorizedDirectory(named: "policy", under: temporaryDirectory)
    let root = try makeAuthorizedDirectory(named: "approved", under: policyRoot)
    let registryRoot = temporaryDirectory.appendingPathComponent("registry", isDirectory: true)
    let registry = try FileBackedHermesAuthorizedRootRegistry(
      registryRoot: registryRoot,
      policy: HermesAuthorizedRootPolicy(permittedRootParents: [policyRoot])
    )
    let record = try await registry.registerBookmark(
      displayName: "Reload",
      bookmarkData: bookmarkData(for: root),
      createdAt: date(0)
    )

    let reloaded = try FileBackedHermesAuthorizedRootRegistry(
      registryRoot: registryRoot,
      policy: HermesAuthorizedRootPolicy(permittedRootParents: [policyRoot])
    )
    let loaded = try await reloaded.readRoot(record.rootID)
    XCTAssertEqual(loaded, record)

    let recordFile = registryRoot.appendingPathComponent(record.rootID.rawValue + ".json")
    var json = try String(contentsOf: recordFile)
    json = json.replacingOccurrences(of: "\"schemaVersion\" : 1", with: "\"schemaVersion\" : 99")
    try json.write(to: recordFile, atomically: false, encoding: .utf8)
    await XCTAssertThrowsHermesAsyncError(try await reloaded.readRoot(record.rootID)) {
      XCTAssertEqual($0 as? HermesAuthorizedRootRegistryError, .unsupportedSchemaVersion(99))
    }

    try "{ bad json".write(to: recordFile, atomically: false, encoding: .utf8)
    await XCTAssertThrowsHermesAsyncError(try await reloaded.readRoot(record.rootID)) {
      XCTAssertEqual($0 as? HermesAuthorizedRootRegistryError, .corruptRecord(rootID: nil))
    }

    let outside = temporaryDirectory.appendingPathComponent("outside.json")
    try "{}".write(to: outside, atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(
      at: registryRoot.appendingPathComponent("escape.json"),
      withDestinationURL: outside
    )
    await XCTAssertThrowsHermesAsyncError(try await reloaded.listRoots()) {
      XCTAssertEqual($0 as? HermesAuthorizedRootRegistryError, .storageBoundaryViolation)
    }

    let registryLink = temporaryDirectory.appendingPathComponent("registry-link")
    try FileManager.default.createSymbolicLink(at: registryLink, withDestinationURL: registryRoot)
    XCTAssertThrowsError(
      try FileBackedHermesAuthorizedRootRegistry(
        registryRoot: registryLink,
        policy: HermesAuthorizedRootPolicy(permittedRootParents: [policyRoot])
      )
    ) {
      guard case .storageRootInvalid = $0 as? HermesAuthorizedRootRegistryError else {
        return XCTFail("expected storageRootInvalid, got \($0)")
      }
    }
  }

  func testRootRestrictions() async throws {
    let policyRoot = try makeAuthorizedDirectory(named: "policy", under: temporaryDirectory)
    let registry = InMemoryHermesAuthorizedRootRegistry(
      policy: HermesAuthorizedRootPolicy(permittedRootParents: [policyRoot])
    )

    await assertRegistrationRejects(
      registry, url: URL(fileURLWithPath: "/"), error: .rejectedFilesystemRoot)
    await assertRegistrationRejects(
      registry,
      url: FileManager.default.homeDirectoryForCurrentUser,
      error: .rejectedHomeRoot
    )

    let file = policyRoot.appendingPathComponent("file.txt")
    try "metadata only".write(to: file, atomically: true, encoding: .utf8)
    await assertRegistrationRejects(registry, url: file, error: .rejectedNonDirectory)

    let outside = try makeAuthorizedDirectory(named: "outside", under: temporaryDirectory)
    let symlink = policyRoot.appendingPathComponent("linked-root")
    try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outside)
    await assertRegistrationRejects(registry, url: symlink, error: .rejectedSymlinkRoot)

    let outsidePolicy = try makeAuthorizedDirectory(named: "not-allowed", under: temporaryDirectory)
    await assertRegistrationRejects(registry, url: outsidePolicy, error: .rejectedOutsidePolicy)
  }

  func testRootRelativePathNormalizationAndEscapes() throws {
    let root = try makeAuthorizedDirectory(named: "root", under: temporaryDirectory)
    let child = root.appendingPathComponent("sub/file.txt")
    try FileManager.default.createDirectory(
      at: child.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "private file body must not be captured".write(to: child, atomically: true, encoding: .utf8)

    XCTAssertEqual(
      try HermesAuthorizedRootPathNormalizer.rootRelativePath(eventPath: root.path, rootURL: root)
        .rawValue,
      "."
    )
    XCTAssertEqual(
      try HermesAuthorizedRootPathNormalizer.rootRelativePath(eventPath: child.path, rootURL: root)
        .rawValue,
      "sub/file.txt"
    )
    XCTAssertThrowsError(
      try HermesAuthorizedRootPathNormalizer.rootRelativePath(
        eventPath: root.appendingPathComponent("../root/sub/file.txt").path,
        rootURL: root
      )
    )

    let sibling = root.deletingLastPathComponent().appendingPathComponent(
      root.lastPathComponent + "-sibling")
    try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
    XCTAssertThrowsError(
      try HermesAuthorizedRootPathNormalizer.rootRelativePath(
        eventPath: sibling.appendingPathComponent("file.txt").path,
        rootURL: root
      )
    ) {
      XCTAssertEqual($0 as? HermesAuthorizedRootRegistryError, .rejectedPathEscape)
    }

    let escapeTarget = temporaryDirectory.appendingPathComponent("escape-target")
    try FileManager.default.createDirectory(at: escapeTarget, withIntermediateDirectories: true)
    try "outside".write(
      to: escapeTarget.appendingPathComponent("file.txt"),
      atomically: true,
      encoding: .utf8
    )
    try FileManager.default.createSymbolicLink(
      at: root.appendingPathComponent("link"),
      withDestinationURL: escapeTarget
    )
    XCTAssertThrowsError(
      try HermesAuthorizedRootPathNormalizer.rootRelativePath(
        eventPath: root.appendingPathComponent("link/file.txt").path,
        rootURL: root
      )
    ) {
      XCTAssertEqual($0 as? HermesAuthorizedRootRegistryError, .rejectedPathEscape)
    }
  }

  func testEventNormalizationAndBatchBounds() throws {
    let rootID = try rootID("A")
    XCTAssertEqual(
      HermesFSEventsMonitor.eventKind(
        for: FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated)
      ),
      .created
    )
    XCTAssertEqual(
      HermesFSEventsMonitor.eventKind(
        for: FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)
      ),
      .modified
    )
    XCTAssertEqual(
      HermesFSEventsMonitor.eventKind(
        for: FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed)
      ),
      .renamed
    )
    XCTAssertEqual(
      HermesFSEventsMonitor.eventKind(
        for: FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved)
      ),
      .removed
    )
    XCTAssertEqual(
      HermesFSEventsMonitor.eventKind(
        for: FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged)
      ),
      .rootChanged
    )
    XCTAssertEqual(
      HermesFSEventsMonitor.eventKind(
        for: FSEventStreamEventFlags(kFSEventStreamEventFlagHistoryDone)
      ),
      .historyDone
    )
    XCTAssertEqual(
      HermesFSEventsMonitor.droppedReason(
        for: FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped)
      ),
      .kernelDropped
    )
    XCTAssertEqual(
      HermesFSEventsMonitor.droppedReason(
        for: FSEventStreamEventFlags(kFSEventStreamEventFlagEventIdsWrapped)
      ),
      .eventIDsWrapped
    )

    let event = try HermesFileEvent(
      rootID: rootID,
      kind: .created,
      relativePath: HermesRootRelativePath(rawValue: "a.txt"),
      fseventID: 1,
      timestamp: date(0),
      isDirectory: false,
      flags: HermesFSEventsMonitor.eventFlagSet(
        FSEventStreamEventFlags(
          kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemIsFile))
    )
    _ = try HermesFileEventBatch(
      rootID: rootID,
      events: [event],
      newestEventID: 1,
      replayed: false,
      rescanRequired: false
    )
    XCTAssertThrowsError(
      try HermesFileEventBatch(
        rootID: rootID,
        events: Array(repeating: event, count: HermesFileEventBatch.maximumEventCount + 1),
        newestEventID: 2,
        replayed: false,
        rescanRequired: false
      )
    )
    XCTAssertFalse((try JSONEncoder().encode(event)).contains(Data("private file body".utf8)))
  }

  func testSyntheticBatchHistoryDroppedAndMalformedPathHandling() throws {
    let rootID = try rootID("B")
    let root = try makeAuthorizedDirectory(named: "synthetic-root", under: temporaryDirectory)
    let file = root.appendingPathComponent("file.txt")
    let paths = [file.path, root.path, root.path] as NSArray
    let flags: [FSEventStreamEventFlags] = [
      FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated),
      FSEventStreamEventFlags(kFSEventStreamEventFlagHistoryDone),
      FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped),
    ]
    let ids: [FSEventStreamEventId] = [10, 11, 12]

    let batch = try flags.withUnsafeBufferPointer { flagsPointer in
      try ids.withUnsafeBufferPointer { idsPointer in
        try HermesFSEventsMonitor.normalizeBatch(
          rootID: rootID,
          rootURL: root,
          sinceWhen: 9,
          eventCount: 3,
          paths: paths,
          flags: flagsPointer.baseAddress!,
          eventIDs: idsPointer.baseAddress!,
          timestamp: date(0)
        )
      }
    }

    XCTAssertTrue(batch.replayed)
    XCTAssertTrue(batch.rescanRequired)
    XCTAssertEqual(batch.droppedEventReason, .userDropped)
    XCTAssertEqual(batch.events.map(\.kind), [.created, .historyDone, .rescanRequired])
  }

  func testMonitorStartStopIdempotencyAndLiveFileEvents() async throws {
    let policyRoot = try makeAuthorizedDirectory(named: "policy", under: temporaryDirectory)
    let registry = try FileBackedHermesAuthorizedRootRegistry(
      registryRoot: temporaryDirectory.appendingPathComponent("registry", isDirectory: true),
      policy: HermesAuthorizedRootPolicy(permittedRootParents: [policyRoot])
    )
    let root = try makeAuthorizedDirectory(named: "watched", under: policyRoot)
    let record = try await registry.registerBookmark(
      displayName: "Watched",
      bookmarkData: bookmarkData(for: root),
      createdAt: date(0)
    )
    let collector = BatchCollector()
    let monitor = HermesFSEventsMonitor(
      registry: registry,
      configuration: try HermesFSEventsMonitorConfiguration(latency: 0.10)
    ) { batch in
      collector.append(batch)
    }

    try await monitor.start(records: [record])
    try await monitor.start(records: [record])
    try await Task.sleep(nanoseconds: 750_000_000)

    let file = root.appendingPathComponent("file.txt")
    try "create".write(to: file, atomically: false, encoding: .utf8)
    try await waitUntil { collector.contains(kind: .created, path: "file.txt") }

    let countBeforeModify = collector.eventCount()
    try "modify".write(to: file, atomically: false, encoding: .utf8)
    try await waitUntil {
      collector.eventCount() > countBeforeModify && collector.contains(path: "file.txt")
    }

    let renamed = root.appendingPathComponent("renamed.txt")
    try FileManager.default.moveItem(at: file, to: renamed)
    try await waitUntil { collector.contains(kind: .renamed) }

    let nested = root.appendingPathComponent("nested/child/deep.txt")
    try FileManager.default.createDirectory(
      at: nested.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "nested".write(to: nested, atomically: false, encoding: .utf8)
    try await waitUntil { collector.contains(pathSuffix: "nested/child/deep.txt") }

    try FileManager.default.removeItem(at: renamed)
    try await waitUntil { collector.contains(kind: .removed) }

    try await waitUntil {
      (try? await registry.readRoot(record.rootID).lastObservedFSEventID) ?? 0 > 0
    }
    XCTAssertFalse(collector.allRelativePaths().contains { $0.hasPrefix("/") || $0.contains("..") })

    try await monitor.stop()
    try await monitor.stop()
    let countAfterStop = collector.eventCount()
    try "after stop".write(
      to: root.appendingPathComponent("after-stop.txt"), atomically: false, encoding: .utf8)
    try await Task.sleep(nanoseconds: 500_000_000)
    XCTAssertEqual(collector.eventCount(), countAfterStop)
  }

  func testMonitorRejectsUnauthorizedParentHomeAndRoot() async throws {
    let registry = InMemoryHermesAuthorizedRootRegistry(
      policy: HermesAuthorizedRootPolicy(permittedRootParents: [temporaryDirectory])
    )
    let monitor = HermesFSEventsMonitor(registry: registry) { _ in }
    let rootID = try rootID("C")
    let bookmark = Data(repeating: 1, count: 16)

    let slash = try HermesAuthorizedRootRecord(
      rootID: rootID,
      displayName: "slash",
      resolvedRootURL: URL(fileURLWithPath: "/"),
      bookmarkData: bookmark,
      bookmarkCreatedAt: date(0),
      bookmarkUpdatedAt: date(0)
    )
    await XCTAssertThrowsHermesAsyncError(try await monitor.start(records: [slash])) {
      XCTAssertEqual($0 as? HermesFSEventsMonitorError, .forbiddenRoot)
    }
  }

  private func forEachRegistry(
    _ body: (HermesAuthorizedRootRegistry, URL) async throws -> Void
  ) async throws {
    let policyRoot = try makeAuthorizedDirectory(
      named: "policy-\(UUID().uuidString)", under: temporaryDirectory)
    try await body(
      InMemoryHermesAuthorizedRootRegistry(
        policy: HermesAuthorizedRootPolicy(permittedRootParents: [policyRoot])
      ),
      policyRoot
    )
    try await body(
      try FileBackedHermesAuthorizedRootRegistry(
        registryRoot: temporaryDirectory.appendingPathComponent(
          "registry-\(UUID().uuidString)", isDirectory: true),
        policy: HermesAuthorizedRootPolicy(permittedRootParents: [policyRoot])
      ),
      policyRoot
    )
  }

  private func assertRegistrationRejects(
    _ registry: HermesAuthorizedRootRegistry,
    url: URL,
    error expected: HermesAuthorizedRootRegistryError,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async {
    do {
      _ = try await registry.registerBookmark(
        displayName: "reject",
        bookmarkData: bookmarkData(for: url),
        createdAt: date(0)
      )
      XCTFail("expected rejection", file: file, line: line)
    } catch {
      XCTAssertEqual(error as? HermesAuthorizedRootRegistryError, expected, file: file, line: line)
    }
  }

  private func makeAuthorizedDirectory(named name: String, under parent: URL) throws -> URL {
    let url = parent.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.standardizedFileURL.resolvingSymlinksInPath()
  }

  private func bookmarkData(for url: URL) throws -> Data {
    try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
  }

  private func rootID(_ suffix: String) throws -> HermesAuthorizedRootID {
    let padded =
      (suffix + String(repeating: "A", count: HermesAuthorizedRootID.encodedRandomLength))
      .prefix(HermesAuthorizedRootID.encodedRandomLength)
    return try HermesAuthorizedRootID(rawValue: HermesAuthorizedRootID.prefix + padded)
  }

  private func waitUntil(
    timeout: TimeInterval = 8,
    predicate: @escaping () async throws -> Bool
  ) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if try await predicate() {
        return
      }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    XCTFail("timed out waiting for condition")
  }

  private func date(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: 1_700_000_000 + seconds)
  }
}

private final class BatchCollector: @unchecked Sendable {
  private let queue = DispatchQueue(label: "HermesAuthorizedFileRootsTests.BatchCollector")
  private var batches: [HermesFileEventBatch] = []

  func append(_ batch: HermesFileEventBatch) {
    queue.sync {
      batches.append(batch)
    }
  }

  func contains(kind: HermesFileEventKind, path: String) -> Bool {
    queue.sync {
      batches.flatMap(\.events).contains {
        $0.kind == kind && $0.relativePath.rawValue == path
      }
    }
  }

  func contains(kind: HermesFileEventKind) -> Bool {
    queue.sync {
      batches.flatMap(\.events).contains {
        $0.kind == kind
      }
    }
  }

  func contains(path: String) -> Bool {
    queue.sync {
      batches.flatMap(\.events).contains {
        $0.relativePath.rawValue == path
      }
    }
  }

  func contains(pathSuffix: String) -> Bool {
    queue.sync {
      batches.flatMap(\.events).contains {
        $0.relativePath.rawValue.hasSuffix(pathSuffix)
      }
    }
  }

  func allRelativePaths() -> [String] {
    queue.sync {
      batches.flatMap(\.events).map(\.relativePath.rawValue)
    }
  }

  func eventCount() -> Int {
    queue.sync {
      batches.reduce(0) { $0 + $1.events.count }
    }
  }
}

extension XCTestCase {
  fileprivate func XCTAssertThrowsHermesAsyncError<T>(
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
