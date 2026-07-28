import Foundation

public protocol HermesFeedbackStoring: Sendable {
  func loadFeedback() throws -> [HermesFeedbackRecord]
  func saveFeedback(_ records: [HermesFeedbackRecord]) throws
  func upsert(_ record: HermesFeedbackRecord) throws
  func loadPreferences() throws -> HermesFeedbackPreferences
  func savePreferences(_ preferences: HermesFeedbackPreferences) throws
  func clear() throws
}

public final class HermesFeedbackStore: HermesFeedbackStoring, @unchecked Sendable {
  public enum Namespace {
    public static let suiteName = "com.hermes.feedback.v1"
  }

  private enum Keys {
    static let prefix = "com.hermes.feedback.v1."
    static let records = prefix + "records"
    static let preferences = prefix + "preferences"
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

  public func loadFeedback() throws -> [HermesFeedbackRecord] {
    try lock.withLock {
      try loadFeedbackUnlocked()
    }
  }

  public func saveFeedback(_ records: [HermesFeedbackRecord]) throws {
    try lock.withLock {
      try saveFeedbackUnlocked(records)
    }
  }

  public func upsert(_ record: HermesFeedbackRecord) throws {
    try lock.withLock {
      var records = try loadFeedbackUnlocked()
      records.removeAll { $0.id == record.id }
      records.insert(record, at: 0)
      try saveFeedbackUnlocked(records)
    }
  }

  public func loadPreferences() throws -> HermesFeedbackPreferences {
    try lock.withLock {
      guard let data = userDefaults.data(forKey: Keys.preferences) else {
        return HermesFeedbackPreferences()
      }
      return try decoder.decode(HermesFeedbackPreferences.self, from: data)
    }
  }

  public func savePreferences(_ preferences: HermesFeedbackPreferences) throws {
    try lock.withLock {
      let data = try encoder.encode(preferences)
      userDefaults.set(data, forKey: Keys.preferences)
    }
  }

  public func clear() throws {
    try lock.withLock {
      try saveFeedbackUnlocked([])
      userDefaults.removeObject(forKey: Keys.preferences)
    }
  }

  private func loadFeedbackUnlocked() throws -> [HermesFeedbackRecord] {
    guard let data = userDefaults.data(forKey: Keys.records) else { return [] }
    return try decoder.decode([HermesFeedbackRecord].self, from: data)
  }

  private func saveFeedbackUnlocked(_ records: [HermesFeedbackRecord]) throws {
    let safeRecords = records.map {
      HermesFeedbackRecord(
        id: $0.id,
        category: $0.category,
        title: $0.title,
        description: $0.description,
        timestamp: $0.timestamp,
        severity: $0.severity,
        relatedFeature: $0.relatedFeature,
        status: $0.status,
        safeRuntimeContext: $0.safeRuntimeContext
      )
    }
    let data = try encoder.encode(safeRecords)
    userDefaults.set(data, forKey: Keys.records)
  }
}
