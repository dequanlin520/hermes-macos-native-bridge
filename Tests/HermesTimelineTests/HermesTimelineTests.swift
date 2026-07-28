import Foundation
@testable import HermesDashboard
@testable import HermesRuntimeFoundation
@testable import HermesTimeline
import XCTest

final class HermesTimelineTests: XCTestCase {
  func testRuntimeEventConvertsToTimelineItems() {
    let event = runtimeEvent(kind: .sessionRunning, status: .running, gatewayRunning: true)

    let items = HermesTimelineItem.items(for: event)

    XCTAssertTrue(items.contains { $0.category == .runtimeStarted })
    XCTAssertTrue(items.contains { $0.category == .connectionEstablished })
    XCTAssertEqual(Set(items.map(\.status)), [.completed])
  }

  func testCollectorSubscribesToRuntimeEventBusAndCreatesTimeline() async throws {
    let store = InMemoryTimelineStore()
    let collector = HermesTimelineCollector(store: store)
    let eventBus = HermesRuntimeEventBus()

    collector.start(eventBus: eventBus)
    eventBus.publish(runtimeEvent(kind: .sessionRunning, status: .running, gatewayRunning: true))
    try await waitUntil {
      (try? store.latest(limit: 10).isEmpty == false) == true
    }

    let items = try store.latest(limit: 10)
    XCTAssertTrue(items.contains { $0.category == .runtimeStarted })
    XCTAssertTrue(collector.isRunning)
    collector.stop()
  }

  func testStorePersistsTimelineItems() throws {
    let defaults = isolatedDefaults()
    let store = HermesTimelineStore(userDefaults: defaults)
    try store.clearHistory()
    let item = timelineItem(category: .runtimeStarted)

    try store.append(item, policy: HermesTimelinePolicy(retentionLimit: 10))

    let reloadedStore = HermesTimelineStore(userDefaults: defaults)
    XCTAssertEqual(try reloadedStore.latest(limit: 10).map(\.category), [.runtimeStarted])
  }

  func testRetentionPolicyIsApplied() throws {
    let store = InMemoryTimelineStore()
    let policy = HermesTimelinePolicy(retentionLimit: 2, duplicateSuppressionSeconds: 0)

    try store.append(timelineItem(category: .runtimeStarted, timestamp: Date(timeIntervalSince1970: 1)), policy: policy)
    try store.append(timelineItem(category: .runtimeStopped, timestamp: Date(timeIntervalSince1970: 2)), policy: policy)
    try store.append(timelineItem(category: .runtimeRecovered, timestamp: Date(timeIntervalSince1970: 3)), policy: policy)

    let categories = try store.latest(limit: 10).map(\.category)
    XCTAssertEqual(categories, [.runtimeRecovered, .runtimeStopped])
  }

  func testDuplicateEventsCollapse() throws {
    let store = InMemoryTimelineStore()
    let policy = HermesTimelinePolicy(retentionLimit: 10, duplicateSuppressionSeconds: 300)
    let first = timelineItem(category: .connectionLost, timestamp: Date(timeIntervalSince1970: 10))
    let duplicate = timelineItem(category: .connectionLost, timestamp: Date(timeIntervalSince1970: 20))

    try store.append(first, policy: policy)
    let decision = try store.append(duplicate, policy: policy)

    let items = try store.latest(limit: 10)
    XCTAssertEqual(items.count, 1)
    XCTAssertEqual(items.first?.duplicateCount, 2)
    XCTAssertEqual(decision, .collapsed(existingItemID: first.id))
  }

  func testClearHistoryRemovesTimelineItems() throws {
    let store = InMemoryTimelineStore()
    try store.append(timelineItem(category: .runtimeStarted), policy: HermesTimelinePolicy())

    try store.clearHistory()

    XCTAssertEqual(try store.latest(limit: 10), [])
  }

  func testSensitiveRuntimeDataIsRedacted() {
    let event = runtimeEvent(
      kind: .sessionFailed,
      status: .failed,
      errorMessage: "token=abc password=hunter2 PID 9123 /Users/jerry/private.swift Hermes.A.B.crash()"
    )

    let text = HermesTimelineItem.items(for: event).map { "\($0.title) \($0.summary)" }.joined(separator: " ")

    XCTAssertFalse(text.localizedCaseInsensitiveContains("abc"))
    XCTAssertFalse(text.localizedCaseInsensitiveContains("hunter2"))
    XCTAssertFalse(text.contains("/Users/jerry"))
    XCTAssertFalse(text.contains("9123"))
    XCTAssertFalse(text.contains("Hermes.A.B.crash"))
  }

  func testDashboardOnlyReadsTimeline() async throws {
    let reader = RecordingTimelineReader(items: [timelineItem(category: .runtimeStarted)])
    let controller = HermesDashboardController(commandAPI: RecordingDashboardCommandAPI(), timelineReader: reader)

    let state = await controller.load()

    XCTAssertEqual(state.latestActivities.map(\.category), [.runtimeStarted])
    XCTAssertEqual(reader.latestCalls, [5, 5])

    let dashboardSource = try String(
      contentsOfFile: "Sources/HermesDashboard/HermesDashboardController.swift",
      encoding: .utf8
    )
    XCTAssertFalse(dashboardSource.contains("HermesTimelineCollector"))
    XCTAssertFalse(dashboardSource.contains(".append("))
  }

  func testNotificationDoesNotOwnTimeline() throws {
    let notificationSource = try String(
      contentsOfFile: "Sources/HermesNotifications/HermesNotificationCenter.swift",
      encoding: .utf8
    )

    XCTAssertFalse(notificationSource.contains("HermesTimelineCollector"))
    XCTAssertFalse(notificationSource.contains("HermesTimelineStore"))
    XCTAssertFalse(notificationSource.contains("HermesTimelineItem"))
  }

  func testRuntimeOwnershipBoundary() throws {
    let appSource = try String(
      contentsOfFile: "Sources/HermesBridgeApp/HermesAppCompositionRoot.swift",
      encoding: .utf8
    )
    let timelineSources = try timelineSourceText()

    XCTAssertFalse(appSource.contains("HermesRuntimeEventBus("))
    XCTAssertFalse(appSource.contains("HermesRuntimeSessionManager("))
    XCTAssertFalse(appSource.contains("HermesProcessSupervisor("))
    XCTAssertFalse(appSource.contains("HermesBackendAdapter("))
    XCTAssertFalse(appSource.contains("HermesProtocolClient("))
    XCTAssertFalse(timelineSources.contains("HermesProcessSupervisor"))
    XCTAssertFalse(timelineSources.contains("HermesBackendAdapter"))
    XCTAssertFalse(timelineSources.contains("HermesProtocolClient"))
    XCTAssertFalse(timelineSources.contains("Process("))
    XCTAssertFalse(timelineSources.contains("sudo"))
    XCTAssertFalse(timelineSources.contains("NSWorkspace.shared.open"))
  }

  private func runtimeEvent(
    kind: HermesRuntimeEventKind,
    status: HermesRuntimeSessionStatus,
    gatewayRunning: Bool? = nil,
    errorMessage: String? = nil
  ) -> HermesRuntimeEvent {
    HermesRuntimeEvent(
      kind: kind,
      session: HermesRuntimeEventSessionSummary(
        snapshot: HermesRuntimeSessionSnapshot(
          sessionID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
          backendIdentity: nil,
          processIdentity: nil,
          startTime: Date(timeIntervalSince1970: 1_800_000_000),
          currentStatus: status,
          capabilities: HermesRuntimeCapabilities(
            authMode: nil,
            desktopContract: 3,
            gatewayRunning: gatewayRunning,
            gatewayState: "ready",
            gatewayBusy: false,
            gatewayDrainable: true,
            activeAgents: 0
          ),
          lastError: errorMessage.map(HermesRuntimeSessionError.init(message:)),
          shutdownReason: status == .stopped ? .requested : nil
        )
      ),
      occurredAt: Date(timeIntervalSince1970: 1_800_000_100)
    )
  }

  private func timelineItem(
    category: HermesTimelineCategory,
    timestamp: Date = Date(timeIntervalSince1970: 1_800_000_000)
  ) -> HermesTimelineItem {
    HermesTimelineItem(
      id: UUID(),
      timestamp: timestamp,
      category: category,
      title: category.rawValue,
      summary: "Timeline item",
      status: .completed
    )
  }

  private func isolatedDefaults() -> UserDefaults {
    let suiteName = "com.hermes.timeline.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
  }

  private func waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    predicate: @escaping () -> Bool
  ) async throws {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
      if predicate() { return }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("Timed out waiting for condition")
  }

  private func timelineSourceText() throws -> String {
    let root = URL(fileURLWithPath: "Sources/HermesTimeline", isDirectory: true)
    let urls = try FileManager.default.contentsOfDirectory(
      at: root,
      includingPropertiesForKeys: nil
    )
    return try urls
      .filter { $0.pathExtension == "swift" }
      .map { try String(contentsOf: $0, encoding: .utf8) }
      .joined(separator: "\n")
  }
}

private final class InMemoryTimelineStore: HermesTimelineStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var items: [HermesTimelineItem] = []

  func latest(limit: Int) throws -> [HermesTimelineItem] {
    lock.withLock { Array(items.prefix(limit)) }
  }

  @discardableResult
  func append(
    _ item: HermesTimelineItem,
    policy: HermesTimelinePolicy
  ) throws -> HermesTimelinePolicyDecision {
    lock.withLock {
      let decision = policy.evaluate(item, existingItems: items)
      switch decision {
      case .allow:
        items.insert(item, at: 0)
      case .collapsed(let existingItemID):
        if let index = items.firstIndex(where: { $0.id == existingItemID }) {
          items[index].duplicateCount += 1
          items[index].lastSeenAt = item.timestamp
        }
      case .rejectedCategory:
        break
      }
      items = policy.applyRetention(items)
      return decision
    }
  }

  func clearHistory() throws {
    lock.withLock {
      items.removeAll()
    }
  }
}

private final class RecordingTimelineReader: HermesTimelineReadable, @unchecked Sendable {
  private let lock = NSLock()
  private let items: [HermesTimelineItem]
  private(set) var latestCalls: [Int] = []

  init(items: [HermesTimelineItem]) {
    self.items = items
  }

  func latest(limit: Int) throws -> [HermesTimelineItem] {
    lock.withLock {
      latestCalls.append(limit)
      return Array(items.prefix(limit))
    }
  }
}

private final class RecordingDashboardCommandAPI: HermesDashboardRuntimeCommandExecuting,
  @unchecked Sendable
{
  private let sessionID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

  func execute(_ command: HermesRuntimeCommand) async throws -> HermesRuntimeCommandResult {
    switch command {
    case .createSession, .getSessionStatus:
      return .sessionStatus(status(.running))
    case .startSession, .stopSession:
      return .sessionStatus(status(.running))
    case .listSessions:
      return .sessionList([status(.running)])
    case .subscribeEvents:
      return .eventSubscription(HermesRuntimeCommandEventSubscription(id: UUID(), events: AsyncStream { $0.finish() }))
    }
  }

  private func status(_ currentStatus: HermesRuntimeSessionStatus) -> HermesRuntimeCommandSessionStatus {
    HermesRuntimeCommandSessionStatus(
      snapshot: HermesRuntimeSessionSnapshot(
        sessionID: sessionID,
        backendIdentity: nil,
        processIdentity: nil,
        startTime: Date(timeIntervalSince1970: 1_800_000_000),
        currentStatus: currentStatus,
        capabilities: nil,
        lastError: nil,
        shutdownReason: nil
      )
    )
  }
}
