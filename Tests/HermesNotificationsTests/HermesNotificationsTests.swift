import Foundation
@testable import HermesNotifications
@testable import HermesRuntimeFoundation
import XCTest

final class HermesNotificationsTests: XCTestCase {
  func testEventBusConversionCreatesRuntimeDegradedNotification() async throws {
    let event = Self.event(kind: .sessionHealthChanged, status: .degraded, error: "gateway unavailable")

    let notification = try XCTUnwrap(
      HermesNotificationCenter.notification(
        for: event,
        now: Self.fixedDate,
        idFactory: { Self.firstID }
      )
    )

    XCTAssertEqual(notification.category, .runtimeDegraded)
    XCTAssertEqual(notification.severity, .warning)
    XCTAssertEqual(notification.title, "Hermes runtime degraded")
    XCTAssertEqual(notification.body, "gateway unavailable")
    XCTAssertEqual(notification.actionIdentifier, "openDiagnostics")
  }

  func testNotificationCenterSubscribesToEventBusAndConvertsRuntimeEvent() async throws {
    let eventBus = HermesRuntimeEventBus()
    let deliverer = RecordingDeliverer()
    let center = HermesNotificationCenter(
      store: InMemoryStore(),
      deliverer: deliverer,
      now: { Self.fixedDate },
      idFactory: { Self.firstID }
    )

    await center.start(eventBus: eventBus)
    eventBus.publish(Self.event(kind: .sessionHealthChanged, status: .degraded, error: "runtime degraded"))

    try await eventually {
      await deliverer.deliveredCount() == 1
    }
    let delivered = await deliverer.deliveredNotifications()
    XCTAssertEqual(delivered.first?.category, .runtimeDegraded)
  }

  func testUpdateNotificationCreated() async throws {
    let deliverer = RecordingDeliverer()
    let center = HermesNotificationCenter(
      store: InMemoryStore(),
      deliverer: deliverer,
      now: { Self.fixedDate },
      idFactory: { Self.firstID }
    )

    let candidate = await center.notifyUpdateAvailable(version: "1.2.3")
    let notification = try XCTUnwrap(candidate)

    XCTAssertEqual(notification.category, .updateAvailable)
    XCTAssertEqual(notification.actionIdentifier, "openUpdateCenter")
    let deliveredCount = await deliverer.deliveredCount()
    XCTAssertEqual(deliveredCount, 1)
  }

  func testRecoveryNotificationCreated() async throws {
    let center = HermesNotificationCenter(
      store: InMemoryStore(),
      deliverer: RecordingDeliverer(),
      now: { Self.fixedDate },
      idFactory: { Self.firstID }
    )

    let candidate = await center.notifyRecoveryRequired(issue: "Bridge service unavailable")
    let notification = try XCTUnwrap(candidate)

    XCTAssertEqual(notification.category, .recoveryRequired)
    XCTAssertEqual(notification.severity, .critical)
    XCTAssertEqual(notification.actionIdentifier, "openRecovery")
  }

  func testPermissionNotificationCreated() async throws {
    let center = HermesNotificationCenter(
      store: InMemoryStore(),
      deliverer: RecordingDeliverer(),
      now: { Self.fixedDate },
      idFactory: { Self.firstID }
    )

    let candidate = await center.notifyPermissionRequired(permission: "Accessibility")
    let notification = try XCTUnwrap(candidate)

    XCTAssertEqual(notification.category, .permissionRequired)
    XCTAssertEqual(notification.actionIdentifier, "openSettings")
  }

  func testDuplicateCollapseSuppressesSameRuntimeFailureWithinFiveMinutes() async throws {
    let clock = LockedClock(Self.fixedDate)
    let deliverer = RecordingDeliverer()
    let center = HermesNotificationCenter(
      store: InMemoryStore(),
      deliverer: deliverer,
      now: clock.now,
      idFactory: IDSequence([Self.firstID, Self.secondID]).next
    )
    let event = Self.event(kind: .sessionHealthChanged, status: .degraded, error: "same runtime failure")

    let first = await center.handle(runtimeEvent: event)
    clock.advance(by: 299)
    let second = await center.handle(runtimeEvent: event)

    XCTAssertEqual(first?.id, Self.firstID)
    XCTAssertEqual(second?.id, Self.firstID)
    let deliveredCount = await deliverer.deliveredCount()
    let notifications = await center.currentNotifications()
    XCTAssertEqual(deliveredCount, 1)
    XCTAssertEqual(notifications.count, 1)
  }

  func testDisabledCategorySuppressesNotification() async throws {
    let store = InMemoryStore()
    var preferences = HermesNotificationPreferences()
    preferences.enabledCategories.remove(.updateAvailable)
    try store.savePreferences(preferences)
    let deliverer = RecordingDeliverer()
    let center = HermesNotificationCenter(
      store: store,
      deliverer: deliverer,
      now: { Self.fixedDate },
      idFactory: { Self.firstID }
    )

    let notification = await center.notifyUpdateAvailable(version: "1.2.3")

    XCTAssertNil(notification)
    let deliveredCount = await deliverer.deliveredCount()
    XCTAssertEqual(deliveredCount, 0)
  }

  func testAcknowledgeAndResolveUpdateLifecycle() async throws {
    let center = HermesNotificationCenter(
      store: InMemoryStore(),
      deliverer: RecordingDeliverer(),
      now: { Self.fixedDate },
      idFactory: { Self.firstID }
    )
    let candidate = await center.notifyUpdateAvailable(version: "1.2.3")
    let notification = try XCTUnwrap(candidate)

    let acknowledged = try await center.acknowledge(notification.id)
    let resolved = try await center.resolve(notification.id)

    XCTAssertEqual(acknowledged?.lifecycle, .acknowledged)
    XCTAssertEqual(resolved?.lifecycle, .resolved)
  }

  func testPersistenceRoundTripUsesUserDefaultsNamespace() throws {
    let suiteName = "HermesNotificationsTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = HermesNotificationStore(userDefaults: defaults)
    var preferences = HermesNotificationPreferences()
    preferences.enabledCategories.remove(.permissionRequired)
    let acknowledged = HermesNotificationRecord(
      id: Self.firstID,
      category: .updateAvailable,
      severity: .info,
      title: "Update",
      body: "Ready",
      createdAt: Self.fixedDate,
      lifecycle: .acknowledged
    )

    try store.savePreferences(preferences)
    try store.saveNotifications([acknowledged])

    XCTAssertEqual(try store.loadPreferences(), preferences)
    XCTAssertEqual(try store.loadNotifications(), [acknowledged])
    XCTAssertNotNil(defaults.object(forKey: "com.hermes.notifications.v1.preferences"))
    XCTAssertNotNil(defaults.object(forKey: "com.hermes.notifications.v1.acknowledgedState"))
  }

  func testSensitiveDataRedactionRemovesTokenPIDPathExecutableAndStackTrace() {
    let redacted = HermesNotificationRedactor.safeText(
      "token=secret password=hunter2 PID 4242 failed at /Users/example/.hermes/bin/hermes and /Applications/Hermes.app/Contents/MacOS/Hermes frame Foo.Bar.baz()"
    )

    XCTAssertFalse(redacted.contains("secret"))
    XCTAssertFalse(redacted.contains("hunter2"))
    XCTAssertFalse(redacted.contains("4242"))
    XCTAssertFalse(redacted.contains("/Users/"))
    XCTAssertFalse(redacted.contains("/Applications/"))
    XCTAssertFalse(redacted.contains("Foo.Bar.baz"))
    XCTAssertTrue(redacted.contains("<redacted-path>"))
  }

  func testRuntimeOwnershipBoundaryDoesNotExposeSupervisorBackendAdapterOrProtocolClient() throws {
    let notificationFiles = try FileManager.default.contentsOfDirectory(
      atPath: "Sources/HermesNotifications"
    )
    let contents = try notificationFiles.map { file in
      try String(contentsOfFile: "Sources/HermesNotifications/\(file)", encoding: .utf8)
    }.joined(separator: "\n")

    XCTAssertFalse(contents.contains("HermesProcessSupervisor"))
    XCTAssertFalse(contents.contains("HermesBackendAdapter"))
    XCTAssertFalse(contents.contains("HermesProtocolClient"))
    XCTAssertFalse(contents.contains("Process("))
    XCTAssertFalse(contents.contains("sudo"))
    XCTAssertFalse(contents.contains("NSWorkspace.shared.open"))
  }

  private static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
  private static let firstID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
  private static let secondID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
  private static let sessionID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!

  private static func event(
    kind: HermesRuntimeEventKind,
    status: HermesRuntimeSessionStatus,
    error: String? = nil
  ) -> HermesRuntimeEvent {
    HermesRuntimeEvent(
      kind: kind,
      session: HermesRuntimeEventSessionSummary(
        snapshot: HermesRuntimeSessionSnapshot(
          sessionID: sessionID,
          backendIdentity: nil,
          processIdentity: nil,
          startTime: nil,
          currentStatus: status,
          capabilities: nil,
          lastError: error.map(HermesRuntimeSessionError.init(message:)),
          shutdownReason: nil
        )
      ),
      occurredAt: fixedDate
    )
  }

  private func eventually(
    timeout: TimeInterval = 2,
    condition: @escaping () async -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if await condition() {
        return
      }
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTFail("Condition was not met before timeout", file: file, line: line)
  }
}

private actor RecordingDeliverer: HermesNativeNotificationDelivering {
  private var delivered: [HermesNotificationRecord] = []

  func requestAuthorization() async -> Bool {
    true
  }

  func deliver(_ notification: HermesNotificationRecord) async throws {
    delivered.append(notification)
  }

  func deliveredNotifications() -> [HermesNotificationRecord] {
    delivered
  }

  func deliveredCount() -> Int {
    delivered.count
  }
}

private final class LockedClock: @unchecked Sendable {
  private var date: Date
  private let lock = NSLock()

  init(_ date: Date) {
    self.date = date
  }

  func now() -> Date {
    lock.withLock { date }
  }

  func advance(by interval: TimeInterval) {
    lock.withLock {
      date = date.addingTimeInterval(interval)
    }
  }
}

private final class InMemoryStore: HermesNotificationStoring, @unchecked Sendable {
  private var preferences = HermesNotificationPreferences()
  private var notifications: [HermesNotificationRecord] = []
  private let lock = NSLock()

  func loadPreferences() throws -> HermesNotificationPreferences {
    lock.withLock { preferences }
  }

  func savePreferences(_ preferences: HermesNotificationPreferences) throws {
    lock.withLock {
      self.preferences = preferences
    }
  }

  func loadNotifications() throws -> [HermesNotificationRecord] {
    lock.withLock { notifications }
  }

  func saveNotifications(_ records: [HermesNotificationRecord]) throws {
    lock.withLock {
      notifications = records
    }
  }

  func acknowledge(_ id: UUID, at date: Date) throws {
    try update(id, lifecycle: .acknowledged, date: date)
  }

  func resolve(_ id: UUID, at date: Date) throws {
    try update(id, lifecycle: .resolved, date: date)
  }

  func archive(_ id: UUID, at date: Date) throws {
    try update(id, lifecycle: .archived, date: date)
  }

  private func update(_ id: UUID, lifecycle: HermesNotificationLifecycle, date: Date) throws {
    lock.withLock {
      guard let index = notifications.firstIndex(where: { $0.id == id }) else { return }
      notifications[index].lifecycle = lifecycle
      switch lifecycle {
      case .created:
        break
      case .delivered:
        notifications[index].deliveredAt = date
      case .acknowledged:
        notifications[index].acknowledgedAt = date
      case .resolved:
        notifications[index].resolvedAt = date
      case .archived:
        notifications[index].archivedAt = date
      }
    }
  }
}

private final class IDSequence: @unchecked Sendable {
  private var ids: [UUID]
  private let lock = NSLock()

  init(_ ids: [UUID]) {
    self.ids = ids
  }

  func next() -> UUID {
    lock.withLock {
      ids.isEmpty ? UUID() : ids.removeFirst()
    }
  }
}
