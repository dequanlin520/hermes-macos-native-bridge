import Foundation

public protocol HermesTimelineReadable: Sendable {
  func latest(limit: Int) throws -> [HermesTimelineItem]
}

public protocol HermesTimelineStoring: HermesTimelineReadable {
  @discardableResult
  func append(_ item: HermesTimelineItem, policy: HermesTimelinePolicy) throws -> HermesTimelinePolicyDecision
  func clearHistory() throws
}

public final class HermesTimelineStore: HermesTimelineStoring, @unchecked Sendable {
  private enum Keys {
    static let suiteName = "com.hermes.timeline.v1"
    static let items = "com.hermes.timeline.v1.items"
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

  public func latest(limit: Int = 50) throws -> [HermesTimelineItem] {
    try lock.withLock {
      Array(try loadUnlocked().prefix(max(0, limit)))
    }
  }

  @discardableResult
  public func append(
    _ item: HermesTimelineItem,
    policy: HermesTimelinePolicy = HermesTimelinePolicy()
  ) throws -> HermesTimelinePolicyDecision {
    try lock.withLock {
      var items = try loadUnlocked()
      let decision = policy.evaluate(item, existingItems: items)
      switch decision {
      case .allow:
        items.insert(item, at: 0)
      case .collapsed(let existingItemID):
        if let index = items.firstIndex(where: { $0.id == existingItemID }) {
          items[index].duplicateCount += 1
          items[index].lastSeenAt = item.timestamp
        }
      case .rejectedCategory:
        break
      }
      items = policy.applyRetention(items)
      try saveUnlocked(items)
      return decision
    }
  }

  public func clearHistory() throws {
    try lock.withLock {
      try saveUnlocked([])
    }
  }

  private func loadUnlocked() throws -> [HermesTimelineItem] {
    guard let data = userDefaults.data(forKey: Keys.items) else { return [] }
    return try decoder.decode([HermesTimelineItem].self, from: data)
  }

  private func saveUnlocked(_ items: [HermesTimelineItem]) throws {
    let safeItems = items.map { item in
      HermesTimelineItem(
        id: item.id,
        timestamp: item.timestamp,
        category: item.category,
        title: item.title,
        summary: item.summary,
        status: item.status,
        duplicateCount: item.duplicateCount,
        lastSeenAt: item.lastSeenAt
      )
    }
    let data = try encoder.encode(safeItems)
    userDefaults.set(data, forKey: Keys.items)
  }
}
