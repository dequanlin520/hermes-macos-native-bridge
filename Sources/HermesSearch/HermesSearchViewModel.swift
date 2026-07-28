import Foundation

@MainActor
public final class HermesSearchViewModel: ObservableObject {
  @Published public private(set) var results: [HermesSearchRecord] = []
  @Published public var queryText: String = ""
  @Published public var selectedCategories: Set<HermesSearchCategory>
  @Published public var minimumSeverity: HermesSearchSeverity?
  @Published public var startDate: Date?
  @Published public var endDate: Date?
  @Published public private(set) var lastErrorMessage: String?

  private let store: any HermesSearchStoring
  private var preferences: HermesSearchPreferences

  public init(store: any HermesSearchStoring = HermesSearchStore()) {
    self.store = store
    self.preferences = (try? store.loadPreferences()) ?? HermesSearchPreferences()
    self.selectedCategories = preferences.enabledCategories
    self.minimumSeverity = preferences.minimumSeverity
  }

  public func load() {
    search()
  }

  public func search() {
    do {
      let categories = selectedCategories.isEmpty ? nil : selectedCategories
      let query = HermesSearchQuery(
        text: queryText,
        categories: categories,
        minimumSeverity: minimumSeverity,
        startDate: startDate,
        endDate: endDate,
        limit: preferences.resultLimit
      )
      results = try store.search(query)
      lastErrorMessage = nil
    } catch {
      lastErrorMessage = HermesSearchRedactor.safeText(String(describing: error), limit: 180)
    }
  }

  public func setCategory(_ category: HermesSearchCategory, enabled: Bool) {
    if enabled {
      selectedCategories.insert(category)
    } else {
      selectedCategories.remove(category)
    }
    savePreferences()
    search()
  }

  public func setMinimumSeverity(_ severity: HermesSearchSeverity?) {
    minimumSeverity = severity
    savePreferences()
    search()
  }

  public func setResultLimit(_ limit: Int) {
    preferences.resultLimit = min(max(1, limit), 500)
    savePreferences()
    search()
  }

  private func savePreferences() {
    preferences.enabledCategories = selectedCategories
    preferences.minimumSeverity = minimumSeverity
    do {
      try store.savePreferences(preferences)
      lastErrorMessage = nil
    } catch {
      lastErrorMessage = HermesSearchRedactor.safeText(String(describing: error), limit: 180)
    }
  }
}
