import Foundation

public final class HermesPrivacyCenter: @unchecked Sendable {
  private let store: any HermesPrivacyStoring
  private let policy: HermesPrivacyPolicy
  private let clock: @Sendable () -> Date
  private let lock = NSLock()

  public init(
    store: any HermesPrivacyStoring = HermesPrivacyStore(),
    policy: HermesPrivacyPolicy = HermesPrivacyPolicy(),
    clock: @escaping @Sendable () -> Date = Date.init
  ) {
    self.store = store
    self.policy = policy
    self.clock = clock
  }

  public func listConsentRecords() throws -> [HermesPrivacyConsentRecord] {
    try lock.withLock {
      let stored = try store.loadConsentRecords()
      if stored.isEmpty {
        let defaults = policy.defaultConsentRecords(now: clock())
        try store.saveConsentRecords(defaults)
        return sorted(defaults)
      }
      let byCategory = Dictionary(uniqueKeysWithValues: stored.map { ($0.category, $0) })
      let complete = try HermesPrivacyConsentCategory.allCases.map { category in
        if let record = byCategory[category] {
          return try policy.sanitized(record)
        }
        return HermesPrivacyConsentRecord(
          category: category,
          status: .denied,
          updatedAt: clock(),
          source: .defaultPolicy
        )
      }
      try store.saveConsentRecords(complete)
      return sorted(complete)
    }
  }

  public func status(for category: HermesPrivacyConsentCategory) throws -> HermesPrivacyConsentStatus {
    try listConsentRecords().first { $0.category == category }?.status ?? .denied
  }

  public func updateConsent(
    category: HermesPrivacyConsentCategory,
    status: HermesPrivacyConsentStatus,
    source: HermesPrivacyConsentSource
  ) throws -> HermesPrivacyConsentRecord {
    try lock.withLock {
      try policy.validate(category: category)
      let records = try store.loadConsentRecords()
      let current = records.first { $0.category == category }
        ?? HermesPrivacyConsentRecord(
          category: category,
          status: .denied,
          updatedAt: clock(),
          source: .defaultPolicy
        )
      let nextStatus = status == .unknown ? .denied : status
      let updated = try policy.sanitized(
        HermesPrivacyConsentRecord(
          id: current.id,
          category: category,
          status: nextStatus,
          updatedAt: clock(),
          source: source
        )
      )
      try store.upsert(updated)
      try store.recordConsentChange(
        HermesPrivacyAuditEvent(
          category: category,
          oldStatus: current.status,
          newStatus: updated.status,
          timestamp: updated.updatedAt
        )
      )
      return updated
    }
  }

  public func updateConsent(
    rawCategory: String,
    status: HermesPrivacyConsentStatus,
    source: HermesPrivacyConsentSource
  ) throws -> HermesPrivacyConsentRecord {
    let category = try policy.category(from: rawCategory)
    return try updateConsent(category: category, status: status, source: source)
  }

  public func loadPreferences() throws -> HermesPrivacyPreferences {
    try store.loadPreferences()
  }

  public func savePreferences(_ preferences: HermesPrivacyPreferences) throws {
    try store.savePreferences(preferences)
  }

  public func loadAuditEvents() throws -> [HermesPrivacyAuditEvent] {
    try store.loadConsentAuditEvents().sorted {
      if $0.timestamp == $1.timestamp { return $0.id.uuidString < $1.id.uuidString }
      return $0.timestamp > $1.timestamp
    }
  }

  public func clearStoredLocalData() throws {
    try store.clearStoredLocalData()
  }

  public var explicitConsentRequired: Bool { policy.explicitConsentRequired }
  public var denyByDefault: Bool { policy.denyByDefault }
  public var appOwnsRuntime: Bool { policy.appOwnsRuntime }
  public var automaticUploadAllowed: Bool { policy.automaticUploadAllowed }
  public var arbitraryActionAllowed: Bool { policy.arbitraryActionAllowed }

  private func sorted(_ records: [HermesPrivacyConsentRecord]) -> [HermesPrivacyConsentRecord] {
    records.sorted { lhs, rhs in
      categoryOrder(lhs.category) < categoryOrder(rhs.category)
    }
  }

  private func categoryOrder(_ category: HermesPrivacyConsentCategory) -> Int {
    HermesPrivacyConsentCategory.allCases.firstIndex(of: category) ?? Int.max
  }
}
