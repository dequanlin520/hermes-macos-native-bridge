import Foundation
import HermesRuntimeFoundation

public struct HermesLogsViewerState: Equatable, Sendable {
  public var entries: [HermesRuntimeLogEntry]
  public var filter: HermesRuntimeLogFilter
  public var lastErrorMessage: String?

  public init(
    entries: [HermesRuntimeLogEntry] = [],
    filter: HermesRuntimeLogFilter = .all,
    lastErrorMessage: String? = nil
  ) {
    self.entries = entries
    self.filter = filter
    self.lastErrorMessage = lastErrorMessage.map { HermesRuntimeLogEntry.redacted($0) }
  }

  public var filteredEntries: [HermesRuntimeLogEntry] {
    entries.filter(filter.includes)
  }
}

public actor HermesLogsViewerController {
  private let eventBus: HermesRuntimeEventBus
  private let maximumEntries: Int
  private var state: HermesLogsViewerState
  private var eventTask: Task<Void, Never>?
  private var subscriptionID: UUID?

  public init(eventBus: HermesRuntimeEventBus, maximumEntries: Int = 500) {
    self.eventBus = eventBus
    self.maximumEntries = max(1, maximumEntries)
    self.state = HermesLogsViewerState()
  }

  deinit {
    eventTask?.cancel()
    if let subscriptionID {
      eventBus.unsubscribe(subscriptionID)
    }
  }

  public func currentState() -> HermesLogsViewerState {
    state
  }

  public func startEventSubscription(
    onStateChange: (@Sendable (HermesLogsViewerState) async -> Void)? = nil
  ) async {
    guard eventTask == nil else { return }
    let subscription = eventBus.subscribe()
    subscriptionID = subscription.id
    eventTask = Task { [weak self] in
      for await event in subscription.events {
        await self?.record(event: event, onStateChange: onStateChange)
      }
    }
    await onStateChange?(state)
  }

  @discardableResult
  public func setFilter(
    _ filter: HermesRuntimeLogFilter,
    onStateChange: (@Sendable (HermesLogsViewerState) async -> Void)? = nil
  ) async -> HermesLogsViewerState {
    state.filter = filter
    await onStateChange?(state)
    return state
  }

  @discardableResult
  public func clearView(
    onStateChange: (@Sendable (HermesLogsViewerState) async -> Void)? = nil
  ) async -> HermesLogsViewerState {
    state.entries.removeAll()
    state.lastErrorMessage = nil
    await onStateChange?(state)
    return state
  }

  public func cancel() {
    eventTask?.cancel()
    eventTask = nil
    if let subscriptionID {
      eventBus.unsubscribe(subscriptionID)
      self.subscriptionID = nil
    }
  }

  private func record(
    event: HermesRuntimeEvent,
    onStateChange: (@Sendable (HermesLogsViewerState) async -> Void)?
  ) async {
    let entry = HermesRuntimeLogEntry(event: event)
    state.entries.insert(entry, at: 0)
    state.entries = Array(state.entries.prefix(maximumEntries))
    state.lastErrorMessage = entry.severity == .error ? entry.redactedSummary : nil
    await onStateChange?(state)
  }
}
