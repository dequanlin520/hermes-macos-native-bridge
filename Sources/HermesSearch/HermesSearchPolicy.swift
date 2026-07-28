import Foundation

public struct HermesSearchPolicy: Equatable, Sendable {
  public var categories: Set<HermesSearchCategory>?
  public var minimumSeverity: HermesSearchSeverity?
  public var startDate: Date?
  public var endDate: Date?
  public var resultLimit: Int

  public init(
    categories: Set<HermesSearchCategory>? = nil,
    minimumSeverity: HermesSearchSeverity? = nil,
    startDate: Date? = nil,
    endDate: Date? = nil,
    resultLimit: Int = 100
  ) {
    self.categories = categories
    self.minimumSeverity = minimumSeverity
    self.startDate = startDate
    self.endDate = endDate
    self.resultLimit = min(max(1, resultLimit), 500)
  }

  public init(query: HermesSearchQuery) {
    self.init(
      categories: query.categories,
      minimumSeverity: query.minimumSeverity,
      startDate: query.startDate,
      endDate: query.endDate,
      resultLimit: query.limit
    )
  }

  public func includes(_ record: HermesSearchRecord) -> Bool {
    if let categories, !categories.contains(record.category) { return false }
    if let minimumSeverity, record.severity < minimumSeverity { return false }
    if let startDate, record.timestamp < startDate { return false }
    if let endDate, record.timestamp > endDate { return false }
    return true
  }

  public func apply(to records: [HermesSearchRecord], text: String = "") -> [HermesSearchRecord] {
    let needle = HermesSearchRedactor.safeText(text, limit: 160).lowercased()
    let filtered = records.filter { record in
      includes(record) && (needle.isEmpty || record.searchableText.contains(needle))
    }
    .sorted {
      if $0.timestamp == $1.timestamp { return $0.id < $1.id }
      return $0.timestamp > $1.timestamp
    }
    return Array(filtered.prefix(resultLimit))
  }
}
