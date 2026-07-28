import Foundation
import HermesDiagnostics
import HermesLogsViewer
import HermesNotifications
import HermesRuntimeFoundation
import HermesTimeline

public protocol HermesSearchRecordStreaming: Sendable {
  func searchRecords() -> AsyncStream<HermesSearchRecord>
}

public protocol HermesSearchTimelineReading: Sendable {
  func latest(limit: Int) throws -> [HermesTimelineItem]
}

public protocol HermesSearchNotificationReading: Sendable {
  func currentNotifications() async -> [HermesNotificationRecord]
}

public protocol HermesSearchDiagnosticsReading: Sendable {
  func currentState() async -> HermesDiagnosticsState
}

public protocol HermesSearchAuditReading: Sendable {
  func query(_ query: HermesAuditQuery) async throws -> [HermesAuditEvent]
}

extension HermesTimelineStore: HermesSearchTimelineReading {}
extension HermesNotificationCenter: HermesSearchNotificationReading {}
extension HermesDiagnosticsController: HermesSearchDiagnosticsReading {}
extension FileBackedHermesAuditStore: HermesSearchAuditReading {}
extension NoopHermesAuditStore: HermesSearchAuditReading {}

public actor HermesSearchIndexer {
  private let store: any HermesSearchStoring
  private let now: @Sendable () -> Date
  private var streamTasks: [Task<Void, Never>] = []

  public init(
    store: any HermesSearchStoring = HermesSearchStore(),
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.store = store
    self.now = now
  }

  deinit {
    for task in streamTasks {
      task.cancel()
    }
  }

  @discardableResult
  public func index(_ record: HermesSearchRecord) throws -> Bool {
    try store.upsert(record.replacingIndexedAt(now()))
  }

  @discardableResult
  public func index(records: [HermesSearchRecord]) throws -> Int {
    var inserted = 0
    for record in records where try index(record) {
      inserted += 1
    }
    return inserted
  }

  public func indexTimelineItem(_ item: HermesTimelineItem) throws -> Bool {
    try index(HermesSearchRecord(timeline: item, indexedAt: now()))
  }

  public func indexLogEntry(_ entry: HermesRuntimeLogEntry) throws -> Bool {
    try index(HermesSearchRecord(log: entry, indexedAt: now()))
  }

  public func indexNotification(_ record: HermesNotificationRecord) throws -> Bool {
    try index(HermesSearchRecord(notification: record, indexedAt: now()))
  }

  public func indexDiagnosticResult(_ result: HermesDiagnosticResult) throws -> Bool {
    try index(HermesSearchRecord(diagnostic: result, indexedAt: now()))
  }

  public func indexAuditEvent(_ event: HermesAuditEvent) throws -> Bool {
    try index(HermesSearchRecord(audit: event, indexedAt: now()))
  }

  public func bootstrap(
    timeline: (any HermesSearchTimelineReading)? = nil,
    notifications: (any HermesSearchNotificationReading)? = nil,
    diagnostics: (any HermesSearchDiagnosticsReading)? = nil,
    audit: (any HermesSearchAuditReading)? = nil,
    limit: Int = 100
  ) async throws {
    if let timeline {
      _ = try index(records: timeline.latest(limit: limit).map { HermesSearchRecord(timeline: $0, indexedAt: now()) })
    }
    if let notifications {
      _ = try index(
        records: await notifications.currentNotifications().map {
          HermesSearchRecord(notification: $0, indexedAt: now())
        }
      )
    }
    if let diagnostics, let result = await diagnostics.currentState().result {
      _ = try indexDiagnosticResult(result)
    }
    if let audit {
      let events = try await audit.query(try HermesAuditQuery(limit: limit))
      _ = try index(records: events.map { HermesSearchRecord(audit: $0, indexedAt: now()) })
    }
  }

  public func start(streams: [any HermesSearchRecordStreaming]) {
    for stream in streams {
      let records = stream.searchRecords()
      let task = Task { [store, now] in
        for await record in records {
          _ = try? store.upsert(record.replacingIndexedAt(now()))
        }
      }
      streamTasks.append(task)
    }
  }

  public func stop() {
    for task in streamTasks {
      task.cancel()
    }
    streamTasks.removeAll()
  }
}
