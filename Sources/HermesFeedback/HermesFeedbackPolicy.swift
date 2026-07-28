import Foundation

public struct HermesFeedbackPolicy: Equatable, Sendable {
  public let minimumDescriptionLength: Int
  public let allowedCategories: Set<HermesFeedbackCategory>

  public init(
    minimumDescriptionLength: Int = 20,
    allowedCategories: Set<HermesFeedbackCategory> = Set(HermesFeedbackCategory.allCases)
  ) {
    self.minimumDescriptionLength = max(1, minimumDescriptionLength)
    self.allowedCategories = allowedCategories
  }

  public func validate(category: HermesFeedbackCategory) throws {
    guard allowedCategories.contains(category) else {
      throw HermesFeedbackValidationError.unsupportedCategory
    }
  }

  public func validate(description: String) throws {
    let redacted = HermesFeedbackRedactor.safeText(description, limit: 2_000)
    let count = redacted.trimmingCharacters(in: .whitespacesAndNewlines).count
    guard count >= minimumDescriptionLength else {
      throw HermesFeedbackValidationError.descriptionTooShort(minimum: minimumDescriptionLength)
    }
  }

  public func sanitized(_ record: HermesFeedbackRecord) throws -> HermesFeedbackRecord {
    try validate(category: record.category)
    try validate(description: record.description)
    return HermesFeedbackRecord(
      id: record.id,
      category: record.category,
      title: record.title,
      description: record.description,
      timestamp: record.timestamp,
      severity: record.severity,
      relatedFeature: record.relatedFeature,
      status: record.status,
      safeRuntimeContext: record.safeRuntimeContext
    )
  }

  public func isDuplicate(_ candidate: HermesFeedbackRecord, in records: [HermesFeedbackRecord])
    -> Bool
  {
    records.contains { record in
      record.id != candidate.id
        && record.status != .archived
        && record.duplicateFingerprint == candidate.duplicateFingerprint
    }
  }

  public func canTransition(from current: HermesFeedbackStatus, to next: HermesFeedbackStatus)
    -> Bool
  {
    switch (current, next) {
    case (.draft, .ready), (.draft, .archived):
      return true
    case (.ready, .draft), (.ready, .submitted), (.ready, .archived):
      return true
    case (.submitted, .resolved), (.submitted, .archived):
      return true
    case (.resolved, .archived):
      return true
    case let (current, next) where current == next:
      return true
    default:
      return false
    }
  }
}
