import Foundation
import HermesRuntimeFoundation
import UserNotifications

public protocol HermesNativeNotificationDelivering: Sendable {
  func requestAuthorization() async -> Bool
  func deliver(_ notification: HermesNotificationRecord) async throws
}

public struct HermesUserNotificationsDeliverer: HermesNativeNotificationDelivering {
  public init() {}

  public func requestAuthorization() async -> Bool {
    do {
      return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    } catch {
      return false
    }
  }

  public func deliver(_ notification: HermesNotificationRecord) async throws {
    let request = UNNotificationRequest(
      identifier: notification.id.uuidString,
      content: notification.content(),
      trigger: nil
    )
    try await UNUserNotificationCenter.current().add(request)
  }
}

public actor HermesNotificationCenter {
  public enum Source: String, Equatable, Sendable {
    case runtimeEventBus
    case updateCenter
    case permissionDoctor
    case recoveryCoordinator
    case system
  }

  private let store: any HermesNotificationStoring
  private let deliverer: any HermesNativeNotificationDelivering
  private let now: @Sendable () -> Date
  private let idFactory: @Sendable () -> UUID
  private var policy: HermesNotificationPolicy
  private var notifications: [HermesNotificationRecord]
  private var eventTask: Task<Void, Never>?

  public init(
    store: any HermesNotificationStoring = HermesNotificationStore(),
    deliverer: any HermesNativeNotificationDelivering = HermesUserNotificationsDeliverer(),
    now: @escaping @Sendable () -> Date = Date.init,
    idFactory: @escaping @Sendable () -> UUID = UUID.init
  ) {
    self.store = store
    self.deliverer = deliverer
    self.now = now
    self.idFactory = idFactory
    let preferences = (try? store.loadPreferences()) ?? HermesNotificationPreferences()
    self.policy = HermesNotificationPolicy(preferences: preferences, now: now)
    self.notifications = (try? store.loadNotifications()) ?? []
  }

  deinit {
    eventTask?.cancel()
  }

  public func start(eventBus: HermesRuntimeEventBus) {
    guard eventTask == nil else { return }
    let subscription = eventBus.subscribe()
    eventTask = Task { [weak self] in
      for await event in subscription.events {
        await self?.handle(runtimeEvent: event)
      }
    }
  }

  public func stop() {
    eventTask?.cancel()
    eventTask = nil
  }

  public func currentNotifications() -> [HermesNotificationRecord] {
    notifications
  }

  public func updatePreferences(_ preferences: HermesNotificationPreferences) throws {
    try store.savePreferences(preferences)
    policy.preferences = preferences
  }

  @discardableResult
  public func acknowledge(_ id: UUID) throws -> HermesNotificationRecord? {
    try transition(id, lifecycle: .acknowledged)
  }

  @discardableResult
  public func resolve(_ id: UUID) throws -> HermesNotificationRecord? {
    try transition(id, lifecycle: .resolved)
  }

  @discardableResult
  public func archive(_ id: UUID) throws -> HermesNotificationRecord? {
    try transition(id, lifecycle: .archived)
  }

  @discardableResult
  public func handle(runtimeEvent: HermesRuntimeEvent) async -> HermesNotificationRecord? {
    guard let notification = Self.notification(for: runtimeEvent, now: now(), idFactory: idFactory) else {
      return nil
    }
    return await create(notification, source: .runtimeEventBus)
  }

  @discardableResult
  public func notifyUpdateAvailable(version: String) async -> HermesNotificationRecord? {
    await create(
      HermesNotificationRecord(
        id: idFactory(),
        category: .updateAvailable,
        severity: .info,
        title: "Hermes update available",
        body: "Version \(version) is available.",
        actionIdentifier: "openUpdateCenter",
        duplicateKey: "updateAvailable.\(version)",
        createdAt: now()
      ),
      source: .updateCenter
    )
  }

  @discardableResult
  public func notifyUpdateFailed(reason: String) async -> HermesNotificationRecord? {
    await create(
      HermesNotificationRecord(
        id: idFactory(),
        category: .updateFailed,
        severity: .warning,
        title: "Hermes update failed",
        body: reason,
        actionIdentifier: "openUpdateCenter",
        duplicateKey: "updateFailed.\(HermesNotificationRedactor.safeIdentifier(reason))",
        createdAt: now()
      ),
      source: .updateCenter
    )
  }

  @discardableResult
  public func notifyRecoveryRequired(issue: String) async -> HermesNotificationRecord? {
    await create(
      HermesNotificationRecord(
        id: idFactory(),
        category: .recoveryRequired,
        severity: .critical,
        title: "Hermes recovery required",
        body: issue,
        actionIdentifier: "openRecovery",
        duplicateKey: "recoveryRequired.\(HermesNotificationRedactor.safeIdentifier(issue))",
        createdAt: now()
      ),
      source: .recoveryCoordinator
    )
  }

  @discardableResult
  public func notifyPermissionRequired(permission: String) async -> HermesNotificationRecord? {
    await create(
      HermesNotificationRecord(
        id: idFactory(),
        category: .permissionRequired,
        severity: .warning,
        title: "Hermes permission required",
        body: "\(permission) permission is required.",
        actionIdentifier: "openSettings",
        duplicateKey: "permissionRequired.\(HermesNotificationRedactor.safeIdentifier(permission))",
        createdAt: now()
      ),
      source: .permissionDoctor
    )
  }

  @discardableResult
  public func notifyServiceRestarted() async -> HermesNotificationRecord? {
    await create(
      HermesNotificationRecord(
        id: idFactory(),
        category: .serviceRestarted,
        severity: .info,
        title: "Hermes service restarted",
        body: "The Hermes bridge service restarted.",
        actionIdentifier: "openDiagnostics",
        duplicateKey: "serviceRestarted",
        createdAt: now()
      ),
      source: .system
    )
  }

  private func create(
    _ candidate: HermesNotificationRecord,
    source _: Source
  ) async -> HermesNotificationRecord? {
    switch policy.evaluate(candidate, existingNotifications: notifications) {
    case .allow:
      var record = candidate
      record.lifecycle = .created
      notifications.insert(record, at: 0)
      _ = await deliverer.requestAuthorization()
      do {
        try await deliverer.deliver(record)
        record.lifecycle = .delivered
        record.deliveredAt = now()
        if let index = notifications.firstIndex(where: { $0.id == record.id }) {
          notifications[index] = record
        }
      } catch {
        if let index = notifications.firstIndex(where: { $0.id == record.id }) {
          notifications[index] = record
        }
      }
      try? store.saveNotifications(notifications)
      return record
    case .collapsed(let existingNotificationID):
      return notifications.first(where: { $0.id == existingNotificationID })
    case .suppressedDisabledCategory, .suppressedSeverity, .suppressedCooldown:
      return nil
    }
  }

  private func transition(
    _ id: UUID,
    lifecycle: HermesNotificationLifecycle
  ) throws -> HermesNotificationRecord? {
    guard let index = notifications.firstIndex(where: { $0.id == id }) else { return nil }
    let date = now()
    notifications[index].lifecycle = lifecycle
    switch lifecycle {
    case .created:
      break
    case .delivered:
      notifications[index].deliveredAt = date
    case .acknowledged:
      notifications[index].acknowledgedAt = date
      try store.acknowledge(id, at: date)
    case .resolved:
      notifications[index].resolvedAt = date
      try store.resolve(id, at: date)
    case .archived:
      notifications[index].archivedAt = date
      try store.archive(id, at: date)
    }
    try store.saveNotifications(notifications)
    return notifications[index]
  }

  public static func notification(
    for event: HermesRuntimeEvent,
    now: Date = Date(),
    idFactory: @Sendable () -> UUID = UUID.init
  ) -> HermesNotificationRecord? {
    switch (event.kind, event.session.currentStatus) {
    case (.sessionHealthChanged, .degraded):
      return HermesNotificationRecord(
        id: idFactory(),
        category: .runtimeDegraded,
        severity: .warning,
        title: "Hermes runtime degraded",
        body: event.session.lastErrorMessage ?? "Runtime health is degraded.",
        actionIdentifier: "openDiagnostics",
        duplicateKey: "runtimeDegraded.\(event.session.sessionID.uuidString).\(event.session.lastErrorMessage ?? "health")",
        createdAt: now
      )
    case (.sessionFailed, _):
      return HermesNotificationRecord(
        id: idFactory(),
        category: .recoveryRequired,
        severity: .critical,
        title: "Hermes runtime failed",
        body: event.session.lastErrorMessage ?? "Runtime recovery is required.",
        actionIdentifier: "openRecovery",
        duplicateKey: "runtimeFailed.\(event.session.sessionID.uuidString).\(event.session.lastErrorMessage ?? "failed")",
        createdAt: now
      )
    case (.sessionStopped, _):
      return HermesNotificationRecord(
        id: idFactory(),
        category: .agentDisconnected,
        severity: .warning,
        title: "Hermes agent disconnected",
        body: "The Hermes runtime session stopped.",
        actionIdentifier: "openDiagnostics",
        duplicateKey: "agentDisconnected.\(event.session.sessionID.uuidString)",
        createdAt: now
      )
    case (.sessionRunning, .running), (.sessionHealthChanged, .running):
      return HermesNotificationRecord(
        id: idFactory(),
        category: .connectionRecovered,
        severity: .info,
        title: "Hermes connection recovered",
        body: "Hermes runtime connection is healthy.",
        actionIdentifier: "openDashboard",
        duplicateKey: "connectionRecovered.\(event.session.sessionID.uuidString)",
        createdAt: now
      )
    default:
      return nil
    }
  }
}
