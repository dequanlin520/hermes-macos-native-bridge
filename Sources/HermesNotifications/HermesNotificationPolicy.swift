import Foundation

public enum HermesNotificationPolicyDecision: Equatable, Sendable {
  case allow
  case suppressedDisabledCategory
  case suppressedSeverity
  case suppressedCooldown
  case collapsed(existingNotificationID: UUID)
}

public struct HermesNotificationPolicy: Sendable {
  public var preferences: HermesNotificationPreferences
  private let now: @Sendable () -> Date

  public init(
    preferences: HermesNotificationPreferences = HermesNotificationPreferences(),
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.preferences = preferences
    self.now = now
  }

  public func evaluate(
    _ candidate: HermesNotificationRecord,
    existingNotifications: [HermesNotificationRecord]
  ) -> HermesNotificationPolicyDecision {
    guard preferences.categoryEnabled(candidate.category) else {
      return .suppressedDisabledCategory
    }
    guard candidate.severity >= preferences.minimumSeverity else {
      return .suppressedSeverity
    }
    let currentTime = now()
    let sameCategory = existingNotifications.filter { $0.category == candidate.category }
    if preferences.cooldownSeconds > 0,
      sameCategory.contains(where: { currentTime.timeIntervalSince($0.createdAt) < preferences.cooldownSeconds })
    {
      return .suppressedCooldown
    }
    if let duplicate = existingNotifications.first(where: { existing in
      existing.duplicateKey == candidate.duplicateKey
        && currentTime.timeIntervalSince(existing.createdAt) <= preferences.duplicateSuppressionSeconds
        && existing.lifecycle != .archived
    }) {
      return .collapsed(existingNotificationID: duplicate.id)
    }
    return .allow
  }
}
