import Foundation
import SwiftUI

@MainActor
public final class HermesTimelineViewModel: ObservableObject {
  @Published public private(set) var snapshot: HermesTimelineSnapshot
  @Published public private(set) var lastErrorMessage: String?

  private let store: any HermesTimelineStoring
  private let limit: Int

  public init(
    store: any HermesTimelineStoring = HermesTimelineStore(),
    limit: Int = 100
  ) {
    self.store = store
    self.limit = limit
    self.snapshot = HermesTimelineSnapshot()
  }

  public func refresh() {
    do {
      snapshot = HermesTimelineSnapshot(items: try store.latest(limit: limit))
      lastErrorMessage = nil
    } catch {
      lastErrorMessage = HermesTimelineRedactor.safeText(String(describing: error), limit: 160)
    }
  }

  public func clearHistory() {
    do {
      try store.clearHistory()
      refresh()
    } catch {
      lastErrorMessage = HermesTimelineRedactor.safeText(String(describing: error), limit: 160)
    }
  }
}
