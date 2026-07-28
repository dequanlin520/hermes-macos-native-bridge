import Foundation
import UserNotifications

public enum HermesNotificationCategory: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case runtimeDegraded
  case agentDisconnected
  case permissionRequired
  case updateAvailable
  case updateFailed
  case recoveryRequired
  case serviceRestarted
  case connectionRecovered
}

public enum HermesNotificationLifecycle: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case created
  case delivered
  case acknowledged
  case resolved
  case archived
}

public enum HermesNotificationSeverity: Int, CaseIterable, Codable, Comparable, Equatable, Sendable {
  case info = 0
  case warning = 1
  case critical = 2

  public static func < (lhs: HermesNotificationSeverity, rhs: HermesNotificationSeverity) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

public struct HermesNotificationPreferences: Codable, Equatable, Sendable {
  public var enabledCategories: Set<HermesNotificationCategory>
  public var minimumSeverity: HermesNotificationSeverity
  public var duplicateSuppressionSeconds: TimeInterval
  public var cooldownSeconds: TimeInterval

  public init(
    enabledCategories: Set<HermesNotificationCategory> = Set(HermesNotificationCategory.allCases),
    minimumSeverity: HermesNotificationSeverity = .info,
    duplicateSuppressionSeconds: TimeInterval = 300,
    cooldownSeconds: TimeInterval = 0
  ) {
    self.enabledCategories = enabledCategories
    self.minimumSeverity = minimumSeverity
    self.duplicateSuppressionSeconds = duplicateSuppressionSeconds
    self.cooldownSeconds = cooldownSeconds
  }

  public func categoryEnabled(_ category: HermesNotificationCategory) -> Bool {
    enabledCategories.contains(category)
  }
}

public struct HermesNotificationAction: Codable, Equatable, Sendable {
  public let identifier: String
  public let title: String

  public init(identifier: String, title: String) {
    self.identifier = HermesNotificationRedactor.safeIdentifier(identifier)
    self.title = HermesNotificationRedactor.safeText(title, limit: 80)
  }
}

public struct HermesNotificationRecord: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let category: HermesNotificationCategory
  public let severity: HermesNotificationSeverity
  public let title: String
  public let body: String
  public let actionIdentifier: String?
  public let duplicateKey: String
  public let createdAt: Date
  public var deliveredAt: Date?
  public var acknowledgedAt: Date?
  public var resolvedAt: Date?
  public var archivedAt: Date?
  public var lifecycle: HermesNotificationLifecycle

  public init(
    id: UUID = UUID(),
    category: HermesNotificationCategory,
    severity: HermesNotificationSeverity,
    title: String,
    body: String,
    actionIdentifier: String? = nil,
    duplicateKey: String? = nil,
    createdAt: Date = Date(),
    lifecycle: HermesNotificationLifecycle = .created
  ) {
    self.id = id
    self.category = category
    self.severity = severity
    self.title = HermesNotificationRedactor.safeText(title, limit: 120)
    self.body = HermesNotificationRedactor.safeText(body, limit: 320)
    self.actionIdentifier = actionIdentifier.map(HermesNotificationRedactor.safeIdentifier)
    self.duplicateKey = HermesNotificationRedactor.safeIdentifier(
      duplicateKey ?? "\(category.rawValue):\(self.title):\(self.body)"
    )
    self.createdAt = createdAt
    self.lifecycle = lifecycle
  }

  public func content() -> UNMutableNotificationContent {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.categoryIdentifier = category.rawValue
    if let actionIdentifier {
      content.userInfo = ["actionIdentifier": actionIdentifier]
    }
    return content
  }
}

public enum HermesNotificationRedactor {
  public static func safeText(_ value: String, limit: Int = 320) -> String {
    var output = String(value.prefix(limit))
    let replacements: [(String, String)] = [
      (#"(?i)\b(token|password|api[_ -]?key|credential|secret)\s*[:=]\s*[^,\s]+"#, "$1=<redacted>"),
      (#"(?i)\bbearer\s+[A-Za-z0-9._~+/\-=]+"#, "bearer <redacted>"),
      (#"/(?:Users|private|var|tmp|Applications)/[^\s,"')]+"#, "<redacted-path>"),
      (#"\bPID\s*[:=]?\s*\d+\b"#, "PID <redacted>"),
      (#"\bpid\s*[:=]?\s*\d+\b"#, "pid <redacted>"),
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
    return String(String(filtered).prefix(160))
  }
}
