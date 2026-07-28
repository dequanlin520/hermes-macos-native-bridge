import Foundation

public protocol HermesSearchStoring: Sendable {
  func loadRecords() throws -> [HermesSearchRecord]
  func saveRecords(_ records: [HermesSearchRecord]) throws
  func upsert(_ record: HermesSearchRecord) throws -> Bool
  func search(_ query: HermesSearchQuery) throws -> [HermesSearchRecord]
  func loadPreferences() throws -> HermesSearchPreferences
  func savePreferences(_ preferences: HermesSearchPreferences) throws
  func clear() throws
}

public final class HermesSearchStore: HermesSearchStoring, @unchecked Sendable {
  private enum Keys {
    static let suiteName = "com.hermes.search.v1"
    static let prefix = "com.hermes.search.v1."
    static let records = prefix + "indexedMetadata"
    static let preferences = prefix + "preferences"
  }

  private let userDefaults: UserDefaults
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()
  private let lock = NSLock()

  public init(userDefaults: UserDefaults? = nil) {
    self.userDefaults = userDefaults ?? UserDefaults(suiteName: Keys.suiteName) ?? .standard
    encoder.dateEncodingStrategy = .iso8601
    decoder.dateDecodingStrategy = .iso8601
  }

  public func loadRecords() throws -> [HermesSearchRecord] {
    try lock.withLock {
      try loadRecordsUnlocked()
    }
  }

  public func saveRecords(_ records: [HermesSearchRecord]) throws {
    try lock.withLock {
      try saveRecordsUnlocked(records)
    }
  }

  @discardableResult
  public func upsert(_ record: HermesSearchRecord) throws -> Bool {
    try lock.withLock {
      var records = try loadRecordsUnlocked()
      if records.contains(where: { $0.id == record.id }) {
        return false
      }
      records.insert(record, at: 0)
      try saveRecordsUnlocked(records)
      return true
    }
  }

  public func search(_ query: HermesSearchQuery) throws -> [HermesSearchRecord] {
    try lock.withLock {
      HermesSearchPolicy(query: query).apply(to: try loadRecordsUnlocked(), text: query.text)
    }
  }

  public func loadPreferences() throws -> HermesSearchPreferences {
    try lock.withLock {
      guard let data = userDefaults.data(forKey: Keys.preferences) else {
        return HermesSearchPreferences()
      }
      return try decoder.decode(HermesSearchPreferences.self, from: data)
    }
  }

  public func savePreferences(_ preferences: HermesSearchPreferences) throws {
    try lock.withLock {
      let data = try encoder.encode(preferences)
      userDefaults.set(data, forKey: Keys.preferences)
    }
  }

  public func clear() throws {
    try lock.withLock {
      try saveRecordsUnlocked([])
      userDefaults.removeObject(forKey: Keys.preferences)
    }
  }

  private func loadRecordsUnlocked() throws -> [HermesSearchRecord] {
    guard let data = userDefaults.data(forKey: Keys.records) else { return [] }
    return try decoder.decode([HermesSearchRecord].self, from: data)
  }

  private func saveRecordsUnlocked(_ records: [HermesSearchRecord]) throws {
    let safeRecords = records.map {
      HermesSearchRecord(
        id: $0.id,
        timestamp: $0.timestamp,
        category: $0.category,
        title: $0.title,
        summary: $0.summary,
        severity: $0.severity,
        source: $0.source,
        indexedAt: $0.indexedAt
      )
    }
    let data = try encoder.encode(safeRecords)
    userDefaults.set(data, forKey: Keys.records)
  }
}
