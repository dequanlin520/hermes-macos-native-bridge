import Foundation

public protocol HermesPrivacyAuditRecording: Sendable {
  func recordConsentChange(_ event: HermesPrivacyAuditEvent) throws
  func loadConsentAuditEvents() throws -> [HermesPrivacyAuditEvent]
}

public protocol HermesPrivacyStoring: HermesPrivacyAuditRecording {
  func loadConsentRecords() throws -> [HermesPrivacyConsentRecord]
  func saveConsentRecords(_ records: [HermesPrivacyConsentRecord]) throws
  func upsert(_ record: HermesPrivacyConsentRecord) throws
  func loadPreferences() throws -> HermesPrivacyPreferences
  func savePreferences(_ preferences: HermesPrivacyPreferences) throws
  func clearStoredLocalData() throws
}

public final class HermesPrivacyStore: HermesPrivacyStoring, @unchecked Sendable {
  public enum Namespace {
    public static let suiteName = "com.hermes.privacy.v1"
  }

  private enum Keys {
    static let prefix = "com.hermes.privacy.v1."
    static let consentRecords = prefix + "consentRecords"
    static let preferences = prefix + "preferences"
    static let auditEvents = prefix + "auditEvents"
  }

  private let userDefaults: UserDefaults
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()
  private let lock = NSLock()

  public init(userDefaults: UserDefaults? = nil) {
    self.userDefaults = userDefaults ?? UserDefaults(suiteName: Namespace.suiteName) ?? .standard
    encoder.dateEncodingStrategy = .iso8601
    decoder.dateDecodingStrategy = .iso8601
  }

  public func loadConsentRecords() throws -> [HermesPrivacyConsentRecord] {
    try lock.withLock {
      try loadConsentRecordsUnlocked()
    }
  }

  public func saveConsentRecords(_ records: [HermesPrivacyConsentRecord]) throws {
    try lock.withLock {
      try saveConsentRecordsUnlocked(records)
    }
  }

  public func upsert(_ record: HermesPrivacyConsentRecord) throws {
    try lock.withLock {
      var records = try loadConsentRecordsUnlocked()
      records.removeAll { $0.category == record.category || $0.id == record.id }
      records.append(record)
      try saveConsentRecordsUnlocked(records)
    }
  }

  public func loadPreferences() throws -> HermesPrivacyPreferences {
    try lock.withLock {
      guard let data = userDefaults.data(forKey: Keys.preferences) else {
        return HermesPrivacyPreferences()
      }
      return try decoder.decode(HermesPrivacyPreferences.self, from: data)
    }
  }

  public func savePreferences(_ preferences: HermesPrivacyPreferences) throws {
    try lock.withLock {
      let data = try encoder.encode(preferences)
      userDefaults.set(data, forKey: Keys.preferences)
    }
  }

  public func recordConsentChange(_ event: HermesPrivacyAuditEvent) throws {
    try lock.withLock {
      var events = try loadConsentAuditEventsUnlocked()
      events.insert(event, at: 0)
      let data = try encoder.encode(events)
      userDefaults.set(data, forKey: Keys.auditEvents)
    }
  }

  public func loadConsentAuditEvents() throws -> [HermesPrivacyAuditEvent] {
    try lock.withLock {
      try loadConsentAuditEventsUnlocked()
    }
  }

  public func clearStoredLocalData() throws {
    lock.withLock {
      userDefaults.removeObject(forKey: Keys.consentRecords)
      userDefaults.removeObject(forKey: Keys.preferences)
      userDefaults.removeObject(forKey: Keys.auditEvents)
    }
  }

  private func loadConsentRecordsUnlocked() throws -> [HermesPrivacyConsentRecord] {
    guard let data = userDefaults.data(forKey: Keys.consentRecords) else { return [] }
    return try decoder.decode([HermesPrivacyConsentRecord].self, from: data)
  }

  private func saveConsentRecordsUnlocked(_ records: [HermesPrivacyConsentRecord]) throws {
    let safeRecords = records.map {
      HermesPrivacyConsentRecord(
        id: $0.id,
        category: $0.category,
        status: $0.status == .unknown ? .denied : $0.status,
        updatedAt: $0.updatedAt,
        source: $0.source
      )
    }
    let data = try encoder.encode(safeRecords)
    userDefaults.set(data, forKey: Keys.consentRecords)
  }

  private func loadConsentAuditEventsUnlocked() throws -> [HermesPrivacyAuditEvent] {
    guard let data = userDefaults.data(forKey: Keys.auditEvents) else { return [] }
    return try decoder.decode([HermesPrivacyAuditEvent].self, from: data)
  }
}
