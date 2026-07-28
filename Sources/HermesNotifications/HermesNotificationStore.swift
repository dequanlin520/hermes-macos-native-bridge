import Foundation

public protocol HermesNotificationStoring: Sendable {
  func loadPreferences() throws -> HermesNotificationPreferences
  func savePreferences(_ preferences: HermesNotificationPreferences) throws
  func loadNotifications() throws -> [HermesNotificationRecord]
  func saveNotifications(_ records: [HermesNotificationRecord]) throws
  func acknowledge(_ id: UUID, at date: Date) throws
  func resolve(_ id: UUID, at date: Date) throws
  func archive(_ id: UUID, at date: Date) throws
}

public final class HermesNotificationStore: HermesNotificationStoring, @unchecked Sendable {
  private enum Keys {
    static let prefix = "com.hermes.notifications.v1."
    static let preferences = prefix + "preferences"
    static let notifications = prefix + "acknowledgedState"
  }

  private let userDefaults: UserDefaults
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()
  private let lock = NSLock()

  public init(userDefaults: UserDefaults = .standard) {
    self.userDefaults = userDefaults
    encoder.dateEncodingStrategy = .iso8601
    decoder.dateDecodingStrategy = .iso8601
  }

  public func loadPreferences() throws -> HermesNotificationPreferences {
    try lock.withLock {
      guard let data = userDefaults.data(forKey: Keys.preferences) else {
        return HermesNotificationPreferences()
      }
      return try decoder.decode(HermesNotificationPreferences.self, from: data)
    }
  }

  public func savePreferences(_ preferences: HermesNotificationPreferences) throws {
    try lock.withLock {
      let data = try encoder.encode(preferences)
      userDefaults.set(data, forKey: Keys.preferences)
    }
  }

  public func loadNotifications() throws -> [HermesNotificationRecord] {
    try lock.withLock {
      guard let data = userDefaults.data(forKey: Keys.notifications) else { return [] }
      return try decoder.decode([HermesNotificationRecord].self, from: data)
    }
  }

  public func saveNotifications(_ records: [HermesNotificationRecord]) throws {
    try lock.withLock {
      let retained = records.filter { $0.lifecycle == .acknowledged || $0.lifecycle == .resolved || $0.lifecycle == .archived }
      let data = try encoder.encode(retained)
      userDefaults.set(data, forKey: Keys.notifications)
    }
  }

  public func acknowledge(_ id: UUID, at date: Date) throws {
    try update(id, at: date, lifecycle: .acknowledged)
  }

  public func resolve(_ id: UUID, at date: Date) throws {
    try update(id, at: date, lifecycle: .resolved)
  }

  public func archive(_ id: UUID, at date: Date) throws {
    try update(id, at: date, lifecycle: .archived)
  }

  private func update(_ id: UUID, at date: Date, lifecycle: HermesNotificationLifecycle) throws {
    var records = try loadNotifications()
    guard let index = records.firstIndex(where: { $0.id == id }) else { return }
    records[index].lifecycle = lifecycle
    switch lifecycle {
    case .created:
      break
    case .delivered:
      records[index].deliveredAt = date
    case .acknowledged:
      records[index].acknowledgedAt = date
    case .resolved:
      records[index].resolvedAt = date
    case .archived:
      records[index].archivedAt = date
    }
    try saveNotifications(records)
  }
}
