import Foundation
import HermesRuntimeFoundation

public enum HermesTimelineCategory: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case runtimeStarted
  case runtimeStopped
  case connectionEstablished
  case connectionLost
  case runtimeDegraded
  case runtimeRecovered
  case notificationCreated
  case recoveryStarted
  case recoveryCompleted
  case updateAvailable
  case updateStarted
  case updateCompleted
  case updateRolledBack
}

public enum HermesTimelineStatus: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case informational
  case inProgress
  case completed
  case warning
  case failed
}

public struct HermesTimelineItem: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let timestamp: Date
  public let category: HermesTimelineCategory
  public let title: String
  public let summary: String
  public let status: HermesTimelineStatus
  public var duplicateCount: Int
  public var lastSeenAt: Date

  public init(
    id: UUID = UUID(),
    timestamp: Date,
    category: HermesTimelineCategory,
    title: String,
    summary: String,
    status: HermesTimelineStatus,
    duplicateCount: Int = 1,
    lastSeenAt: Date? = nil
  ) {
    self.id = id
    self.timestamp = timestamp
    self.category = category
    self.title = HermesTimelineRedactor.safeText(title, limit: 120)
    self.summary = HermesTimelineRedactor.safeText(summary, limit: 280)
    self.status = status
    self.duplicateCount = max(1, duplicateCount)
    self.lastSeenAt = lastSeenAt ?? timestamp
  }

  public var duplicateKey: String {
    HermesTimelineRedactor.safeIdentifier(
      "\(category.rawValue).\(status.rawValue).\(title).\(summary)"
    )
  }
}

public struct HermesTimelineSnapshot: Equatable, Sendable {
  public let items: [HermesTimelineItem]

  public init(items: [HermesTimelineItem] = []) {
    self.items = items
  }
}

public enum HermesTimelineRedactor {
  public static func safeText(_ value: String, limit: Int = 280) -> String {
    var output = String(value.prefix(limit))
    let replacements: [(String, String)] = [
      (#"(?i)\b(token|password|api[_ -]?key|credential|secret)\s*[:=]\s*[^,\s]+"#, "$1=<redacted>"),
      (#"(?i)\bbearer\s+[A-Za-z0-9._~+/\-=]+"#, "bearer <redacted>"),
      (#"/(?:Users|private|var|tmp|Applications|Volumes)/[^\s,"')]+"#, "<redacted-path>"),
      (#"(?i)\bPID\s*[:=]?\s*\d+\b"#, "PID <redacted>"),
      (#"(?i)\bprocess\s+id\s*[:=]?\s*\d+\b"#, "process id <redacted>"),
      (#"(?:[A-Za-z_][A-Za-z0-9_]*\.){2,}[A-Za-z_][A-Za-z0-9_]*\([^)]*\)"#, "<redacted-stack-frame>"),
    ]
    for (pattern, replacement) in replacements {
      output = output.replacingOccurrences(
        of: pattern,
        with: replacement,
        options: .regularExpression
      )
    }
    return output
  }

  public static func safeIdentifier(_ value: String) -> String {
    let filtered = value.map { character -> Character in
      if character.isASCII,
        character.isLetter || character.isNumber || character == "." || character == "-" || character == "_"
      {
        return character
      }
      return "-"
    }
    return String(String(filtered).prefix(200))
  }
}

extension HermesTimelineItem {
  public static func items(for event: HermesRuntimeEvent) -> [HermesTimelineItem] {
    let timestamp = event.occurredAt
    let status = event.session.currentStatus
    let gatewayRunning = event.session.capabilities?.gatewayRunning
    var items: [HermesTimelineItem] = []

    switch event.kind {
    case .sessionCreated:
      break
    case .sessionStarting:
      items.append(
        HermesTimelineItem(
          timestamp: timestamp,
          category: .runtimeStarted,
          title: "Hermes runtime starting",
          summary: "A Hermes runtime session is starting.",
          status: .inProgress
        )
      )
    case .sessionRunning:
      items.append(
        HermesTimelineItem(
          timestamp: timestamp,
          category: .runtimeStarted,
          title: "Hermes runtime started",
          summary: "The Hermes runtime is running.",
          status: .completed
        )
      )
      if gatewayRunning != false {
        items.append(
          HermesTimelineItem(
            timestamp: timestamp,
            category: .connectionEstablished,
            title: "Hermes connection established",
            summary: "The runtime connection is available.",
            status: .completed
          )
        )
      }
    case .sessionHealthChanged:
      if status == .degraded || gatewayRunning == false {
        items.append(
          HermesTimelineItem(
            timestamp: timestamp,
            category: .runtimeDegraded,
            title: "Hermes runtime degraded",
            summary: safeRuntimeSummary(event.session.lastErrorMessage) ?? "Runtime health is degraded.",
            status: .warning
          )
        )
        if gatewayRunning == false {
          items.append(
            HermesTimelineItem(
              timestamp: timestamp,
              category: .connectionLost,
              title: "Hermes connection lost",
              summary: "The runtime connection is unavailable.",
              status: .warning
            )
          )
        }
      } else if status == .running {
        items.append(
          HermesTimelineItem(
            timestamp: timestamp,
            category: .runtimeRecovered,
            title: "Hermes runtime recovered",
            summary: "Runtime health returned to normal.",
            status: .completed
          )
        )
        if gatewayRunning == true {
          items.append(
            HermesTimelineItem(
              timestamp: timestamp,
              category: .connectionEstablished,
              title: "Hermes connection established",
              summary: "The runtime connection is available.",
              status: .completed
            )
          )
        }
      }
    case .sessionFailed:
      items.append(
        HermesTimelineItem(
          timestamp: timestamp,
          category: .runtimeDegraded,
          title: "Hermes runtime failed",
          summary: safeRuntimeSummary(event.session.lastErrorMessage) ?? "Runtime reported a failure.",
          status: .failed
        )
      )
    case .sessionStopping:
      items.append(
        HermesTimelineItem(
          timestamp: timestamp,
          category: .runtimeStopped,
          title: "Hermes runtime stopping",
          summary: "A Hermes runtime session is stopping.",
          status: .inProgress
        )
      )
    case .sessionStopped:
      items.append(
        HermesTimelineItem(
          timestamp: timestamp,
          category: .runtimeStopped,
          title: "Hermes runtime stopped",
          summary: event.session.shutdownReason.map { "Stopped: \($0.description)." }
            ?? "The Hermes runtime stopped.",
          status: .completed
        )
      )
    }

    return items
  }

  private static func safeRuntimeSummary(_ message: String?) -> String? {
    guard let message, !message.isEmpty else { return nil }
    return HermesTimelineRedactor.safeText(message, limit: 240)
  }
}
