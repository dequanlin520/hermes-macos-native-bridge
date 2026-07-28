import Foundation
import HermesRuntimeFoundation

public final class HermesTimelineCollector: @unchecked Sendable {
  private let store: any HermesTimelineStoring
  private let policy: HermesTimelinePolicy
  private let lock = NSLock()
  private var task: Task<Void, Never>?
  private var subscriptionID: UUID?

  public init(
    store: any HermesTimelineStoring = HermesTimelineStore(),
    policy: HermesTimelinePolicy = HermesTimelinePolicy()
  ) {
    self.store = store
    self.policy = policy
  }

  deinit {
    stop()
  }

  public var isRunning: Bool {
    lock.withLock { task != nil }
  }

  public func start(eventBus: HermesRuntimeEventBus) {
    lock.withLock {
      guard task == nil else { return }
      let subscription = eventBus.subscribe()
      subscriptionID = subscription.id
      task = Task { [store, policy] in
        for await event in subscription.events {
          for item in HermesTimelineItem.items(for: event) {
            _ = try? store.append(item, policy: policy)
          }
        }
      }
    }
  }

  public func stop() {
    let runningTask = lock.withLock {
      let current = task
      task = nil
      subscriptionID = nil
      return current
    }
    runningTask?.cancel()
  }
}
