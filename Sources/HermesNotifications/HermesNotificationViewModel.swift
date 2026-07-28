import Foundation
import SwiftUI

public struct HermesNotificationRowViewState: Equatable, Identifiable, Sendable {
  public let id: UUID
  public let category: HermesNotificationCategory
  public let lifecycle: HermesNotificationLifecycle
  public let severity: HermesNotificationSeverity
  public let title: String
  public let body: String
  public let createdAt: Date

  public init(record: HermesNotificationRecord) {
    id = record.id
    category = record.category
    lifecycle = record.lifecycle
    severity = record.severity
    title = record.title
    body = record.body
    createdAt = record.createdAt
  }
}

@MainActor
public final class HermesNotificationViewModel: ObservableObject {
  @Published public private(set) var notifications: [HermesNotificationRowViewState]

  private let center: HermesNotificationCenter

  public init(center: HermesNotificationCenter) {
    self.center = center
    self.notifications = []
  }

  public func refresh() {
    Task {
      notifications = await center.currentNotifications().map(HermesNotificationRowViewState.init)
    }
  }

  public func acknowledge(_ id: UUID) {
    Task {
      _ = try? await center.acknowledge(id)
      refresh()
    }
  }

  public func resolve(_ id: UUID) {
    Task {
      _ = try? await center.resolve(id)
      refresh()
    }
  }
}
