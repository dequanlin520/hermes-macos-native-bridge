import XCTest
import HermesBridgeApp
import HermesDashboard
import HermesDiagnostics
import HermesLogsViewer
import HermesNotifications
import HermesRuntimeFoundation
import HermesSearch
import HermesTimeline

final class HermesSearchTests: XCTestCase {
  func testTimelineIsSearchable() async throws {
    let store = makeStore()
    let item = HermesTimelineItem(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
      timestamp: date(1),
      category: .runtimeStarted,
      title: "Runtime started",
      summary: "Hermes is available",
      status: .completed
    )

    let inserted = try await HermesSearchIndexer(store: store).indexTimelineItem(item)
    XCTAssertTrue(inserted)

    let results = try store.search(HermesSearchQuery(text: "available"))
    XCTAssertEqual(results.map(\.category), [.timeline])
    XCTAssertEqual(results.first?.source, .timeline)
  }

  func testLogsAreSearchable() async throws {
    let store = makeStore()
    let entry = HermesRuntimeLogEntry(
      id: 42,
      timestamp: date(2),
      eventType: .sessionFailed,
      severity: .error,
      redactedSummary: "Runtime failed"
    )

    let inserted = try await HermesSearchIndexer(store: store).indexLogEntry(entry)
    XCTAssertTrue(inserted)

    let results = try store.search(HermesSearchQuery(text: "failed"))
    XCTAssertEqual(results.first?.category, .logs)
    XCTAssertEqual(results.first?.severity, .error)
  }

  func testNotificationsAreSearchable() async throws {
    let store = makeStore()
    let record = HermesNotificationRecord(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
      category: .permissionRequired,
      severity: .warning,
      title: "Permission required",
      body: "Automation permission is required.",
      createdAt: date(3)
    )

    let inserted = try await HermesSearchIndexer(store: store).indexNotification(record)
    XCTAssertTrue(inserted)

    let results = try store.search(HermesSearchQuery(text: "automation"))
    XCTAssertEqual(results.first?.category, .notifications)
    XCTAssertEqual(results.first?.source, .notificationCenter)
  }

  func testDiagnosticsAreSearchable() async throws {
    let store = makeStore()
    let result = HermesDiagnosticResult(
      generatedAt: date(4),
      healthSummary: HermesDiagnosticHealthSummary(backendState: .degraded),
      environmentInfo: HermesDiagnosticEnvironmentInfo(
        macOSVersion: "14.0",
        architecture: "arm64",
        hermesVersion: "1.0"
      ),
      sessionDiagnostics: HermesDiagnosticSessionDiagnostics(runningSessions: 1),
      issues: ["Backend degraded"]
    )

    let inserted = try await HermesSearchIndexer(store: store).indexDiagnosticResult(result)
    XCTAssertTrue(inserted)

    let results = try store.search(HermesSearchQuery(text: "backend"))
    XCTAssertEqual(results.first?.category, .diagnostics)
    XCTAssertEqual(results.first?.severity, .warning)
  }

  func testAuditEventsAreSearchable() async throws {
    let store = makeStore()
    let event = try HermesAuditEvent(
      eventID: HermesAuditEventID(rawValue: "haud_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNO12"),
      timestamp: date(5),
      kind: .serviceStarted,
      actor: .service,
      outcome: .succeeded,
      reasonCode: "ok",
      metadata: HermesAuditMetadata(["component": "bridge"])
    )

    let inserted = try await HermesSearchIndexer(store: store).indexAuditEvent(event)
    XCTAssertTrue(inserted)

    let results = try store.search(HermesSearchQuery(text: "bridge"))
    XCTAssertEqual(results.first?.category, .audit)
    XCTAssertEqual(results.first?.source, .auditLog)
  }

  func testFilteringDateRangeAndSeverity() throws {
    let store = makeStore()
    try store.saveRecords([
      HermesSearchRecord(
        id: "one",
        timestamp: date(1),
        category: .timeline,
        title: "Old info",
        summary: "old",
        severity: .info,
        source: .timeline
      ),
      HermesSearchRecord(
        id: "two",
        timestamp: date(2),
        category: .logs,
        title: "Warning log",
        summary: "warning",
        severity: .warning,
        source: .logsViewer
      ),
      HermesSearchRecord(
        id: "three",
        timestamp: date(3),
        category: .audit,
        title: "Audit error",
        summary: "error",
        severity: .error,
        source: .auditLog
      ),
    ])

    let categoryResults = try store.search(HermesSearchQuery(categories: [.logs], limit: 10))
    XCTAssertEqual(categoryResults.map(\.id), ["two"])

    let severityResults = try store.search(HermesSearchQuery(minimumSeverity: .warning, limit: 10))
    XCTAssertEqual(severityResults.map(\.id), ["three", "two"])

    let dateResults = try store.search(HermesSearchQuery(startDate: date(2), endDate: date(2), limit: 10))
    XCTAssertEqual(dateResults.map(\.id), ["two"])
  }

  func testDuplicatePrevention() async throws {
    let store = makeStore()
    let indexer = HermesSearchIndexer(store: store)
    let record = HermesSearchRecord(
      id: "duplicate",
      timestamp: date(1),
      category: .timeline,
      title: "Runtime started",
      summary: "Started",
      severity: .info,
      source: .timeline
    )

    let firstInsert = try await indexer.index(record)
    let secondInsert = try await indexer.index(record)
    XCTAssertTrue(firstInsert)
    XCTAssertFalse(secondInsert)
    XCTAssertEqual(try store.loadRecords().count, 1)
  }

  func testEventDrivenIndexingConsumesStreams() async throws {
    let store = makeStore()
    let stream = SearchRecordStreamFixture()
    let indexer = HermesSearchIndexer(store: store)
    await indexer.start(streams: [stream])

    stream.yield(
      HermesSearchRecord(
        id: "streamed",
        timestamp: date(6),
        category: .timeline,
        title: "Streamed timeline event",
        summary: "Event driven",
        severity: .info,
        source: .timeline
      )
    )

    try await eventually {
      try store.search(HermesSearchQuery(text: "streamed")).count == 1
    }
    await indexer.stop()
  }

  func testPersistenceStoresMetadataAndPreferences() throws {
    let suiteName = "com.hermes.search.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let firstStore = HermesSearchStore(userDefaults: defaults)
    try firstStore.upsert(
      HermesSearchRecord(
        id: "persisted",
        timestamp: date(1),
        category: .notifications,
        title: "Update available",
        summary: "Version available",
        severity: .info,
        source: .notificationCenter
      )
    )
    try firstStore.savePreferences(
      HermesSearchPreferences(resultLimit: 7, enabledCategories: [.notifications], minimumSeverity: .info)
    )

    let secondStore = HermesSearchStore(userDefaults: defaults)
    XCTAssertEqual(try secondStore.loadRecords().map(\.id), ["persisted"])
    XCTAssertEqual(try secondStore.loadPreferences().resultLimit, 7)
    XCTAssertEqual(try secondStore.loadPreferences().enabledCategories, [.notifications])
  }

  func testRedactionRemovesSensitiveData() throws {
    let record = HermesSearchRecord(
      id: "sensitive",
      timestamp: date(1),
      category: .logs,
      title: "token=abc123 password=hunter2 pid=1234 /Users/alice/private.txt",
      summary: "Bearer abc.def.ghi Hermes.Foo.bar() /Applications/Hermes.app",
      severity: .error,
      source: .logsViewer
    )
    let combined = "\(record.title) \(record.summary)"

    XCTAssertFalse(combined.contains("abc123"))
    XCTAssertFalse(combined.contains("hunter2"))
    XCTAssertFalse(combined.contains("/Users/alice"))
    XCTAssertFalse(combined.contains("/Applications/Hermes.app"))
    XCTAssertFalse(combined.contains("pid=1234"))
    XCTAssertFalse(combined.contains("Hermes.Foo.bar()"))
  }

  @MainActor
  func testDashboardIsReadOnlyNavigationOnly() {
    var openCount = 0
    let viewModel = HermesDashboardViewModel(
      commandAPI: NoopDashboardCommandAPI(),
      timelineReader: nil,
      openSearchCenter: {
        openCount += 1
      }
    )

    viewModel.openSearchCenter()

    XCTAssertEqual(openCount, 1)
  }

  func testRuntimeOwnershipBoundaryHasNoForbiddenRuntimeAccess() throws {
    let searchFiles = try FileManager.default.contentsOfDirectory(
      atPath: "Sources/HermesSearch"
    )
    let contents = try searchFiles.map {
      try String(contentsOfFile: "Sources/HermesSearch/\($0)")
    }.joined(separator: "\n")

    XCTAssertFalse(contents.contains("HermesProcessSupervisor"))
    XCTAssertFalse(contents.contains("HermesBackendAdapter"))
    XCTAssertFalse(contents.contains("HermesProtocolClient"))
    XCTAssertFalse(contents.contains("Process("))
    XCTAssertFalse(contents.contains("sudo"))
    XCTAssertFalse(contents.contains("NSWorkspace.shared.open"))
  }

  private func makeStore() -> HermesSearchStore {
    let suiteName = "com.hermes.search.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return HermesSearchStore(userDefaults: defaults)
  }

  private func date(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: seconds)
  }

  private func eventually(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    _ condition: () throws -> Bool
  ) async throws {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
      if try condition() { return }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("condition was not met before timeout")
  }
}

private final class SearchRecordStreamFixture: HermesSearchRecordStreaming, @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: AsyncStream<HermesSearchRecord>.Continuation?

  func searchRecords() -> AsyncStream<HermesSearchRecord> {
    AsyncStream { continuation in
      lock.withLock {
        self.continuation = continuation
      }
    }
  }

  func yield(_ record: HermesSearchRecord) {
    _ = lock.withLock {
      continuation?.yield(record)
    }
  }
}

private struct NoopDashboardCommandAPI: HermesDashboardRuntimeCommandExecuting {
  func execute(_ command: HermesRuntimeCommand) async throws -> HermesRuntimeCommandResult {
    switch command {
    case .createSession:
      return .sessionStatus(
        HermesRuntimeCommandSessionStatus(
          sessionID: UUID(),
          currentStatus: .stopped,
          backendVersion: nil,
          startTime: nil,
          capabilities: nil,
          lastErrorMessage: nil,
          shutdownReason: nil
        )
      )
    default:
      throw NoopDashboardCommandError.unsupportedCommand
    }
  }
}

private enum NoopDashboardCommandError: Error {
  case unsupportedCommand
}
