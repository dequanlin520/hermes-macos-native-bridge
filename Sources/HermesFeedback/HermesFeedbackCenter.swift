import Foundation

public final class HermesFeedbackCenter: @unchecked Sendable {
  private let store: any HermesFeedbackStoring
  private let policy: HermesFeedbackPolicy
  private let lock = NSLock()

  public init(
    store: any HermesFeedbackStoring = HermesFeedbackStore(),
    policy: HermesFeedbackPolicy = HermesFeedbackPolicy()
  ) {
    self.store = store
    self.policy = policy
  }

  public func listFeedback() throws -> [HermesFeedbackRecord] {
    try store.loadFeedback().sorted {
      if $0.timestamp == $1.timestamp { return $0.id.uuidString < $1.id.uuidString }
      return $0.timestamp > $1.timestamp
    }
  }

  public func createFeedback(
    category: HermesFeedbackCategory,
    title: String,
    description: String,
    severity: HermesFeedbackSeverity,
    relatedFeature: String? = nil,
    safeRuntimeContext: HermesFeedbackSafeRuntimeContext? = nil
  ) throws -> HermesFeedbackRecord {
    try lock.withLock {
      let record = HermesFeedbackRecord(
        category: category,
        title: title,
        description: description,
        severity: severity,
        relatedFeature: relatedFeature,
        status: .draft,
        safeRuntimeContext: safeRuntimeContext
      )
      let sanitized = try policy.sanitized(record)
      let existing = try store.loadFeedback()
      guard !policy.isDuplicate(sanitized, in: existing) else {
        throw HermesFeedbackValidationError.duplicateFeedback
      }
      try store.upsert(sanitized)
      return sanitized
    }
  }

  public func update(_ record: HermesFeedbackRecord) throws -> HermesFeedbackRecord {
    try lock.withLock {
      let sanitized = try policy.sanitized(record)
      let existing = try store.loadFeedback()
      guard !policy.isDuplicate(sanitized, in: existing) else {
        throw HermesFeedbackValidationError.duplicateFeedback
      }
      try store.upsert(sanitized)
      return sanitized
    }
  }

  public func transition(id: UUID, to status: HermesFeedbackStatus) throws -> HermesFeedbackRecord {
    try lock.withLock {
      let records = try store.loadFeedback()
      guard let current = records.first(where: { $0.id == id }) else {
        throw HermesFeedbackValidationError.feedbackNotFound
      }
      guard policy.canTransition(from: current.status, to: status) else {
        throw HermesFeedbackValidationError.invalidLifecycleTransition(
          from: current.status,
          to: status
        )
      }
      let updated = current.replacing(status: status)
      try store.upsert(updated)
      return updated
    }
  }

  public func loadPreferences() throws -> HermesFeedbackPreferences {
    try store.loadPreferences()
  }

  public func savePreferences(_ preferences: HermesFeedbackPreferences) throws {
    try store.savePreferences(preferences)
  }
}
