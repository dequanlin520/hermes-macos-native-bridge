import Foundation

public enum HermesTimelinePolicyDecision: Equatable, Sendable {
  case allow
  case rejectedCategory
  case collapsed(existingItemID: UUID)
}

public struct HermesTimelinePolicy: Sendable {
  public var allowedCategories: Set<HermesTimelineCategory>
  public var retentionLimit: Int
  public var duplicateSuppressionSeconds: TimeInterval

  public init(
    allowedCategories: Set<HermesTimelineCategory> = Set(HermesTimelineCategory.allCases),
    retentionLimit: Int = 500,
    duplicateSuppressionSeconds: TimeInterval = 300
  ) {
    self.allowedCategories = allowedCategories
    self.retentionLimit = max(1, retentionLimit)
    self.duplicateSuppressionSeconds = max(0, duplicateSuppressionSeconds)
  }

  public func evaluate(
    _ candidate: HermesTimelineItem,
    existingItems: [HermesTimelineItem]
  ) -> HermesTimelinePolicyDecision {
    guard allowedCategories.contains(candidate.category) else {
      return .rejectedCategory
    }
    guard duplicateSuppressionSeconds > 0 else {
      return .allow
    }
    if let duplicate = existingItems.first(where: { existing in
      existing.duplicateKey == candidate.duplicateKey
        && candidate.timestamp.timeIntervalSince(existing.lastSeenAt) <= duplicateSuppressionSeconds
    }) {
      return .collapsed(existingItemID: duplicate.id)
    }
    return .allow
  }

  public func applyRetention(_ items: [HermesTimelineItem]) -> [HermesTimelineItem] {
    Array(items.sorted { $0.timestamp > $1.timestamp }.prefix(retentionLimit))
  }
}
