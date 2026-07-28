import Foundation
import HermesBridgeServiceManager
import HermesBridgeXPC
import HermesRuntimeFoundation

public enum HermesRecoveryIssueCategory: String, CaseIterable, Codable, Equatable, Sendable {
  case bridgeServiceUnavailable
  case xpcConnectionFailed
  case protocolIncompatible
  case agentUnavailable
  case agentIncompatible
  case accessibilityPermissionMissing
  case automationPermissionMissing
  case screenRecordingPermissionMissing
  case notificationsPermissionMissing
  case unknownReadinessFailure
}

public enum HermesRecoveryPermissionPane: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case accessibility = "Accessibility"
  case automation = "Automation"
  case screenRecording = "Screen Recording"
  case notifications = "Notifications"

  public var permissionKind: HermesPermissionKind {
    switch self {
    case .accessibility: return .accessibility
    case .automation: return .automation
    case .screenRecording: return .screenRecording
    case .notifications: return .notifications
    }
  }
}

public enum HermesRecoveryActionType: Codable, Equatable, Hashable, Sendable {
  case retryConnection
  case restartBridgeService
  case refreshAgentDiscovery
  case rerunPermissionsCheck
  case openSystemSettings(HermesRecoveryPermissionPane)
  case openDiagnostics
  case showUpgradeRequired
  case rerunReadiness
  case dismiss
}

public enum HermesRecoveryState: String, CaseIterable, Codable, Equatable, Sendable {
  case idle
  case evaluating
  case actionAvailable
  case executing
  case verifying
  case recovered
  case stillBlocked
  case failed
}

public enum HermesRecoveryVerification: String, CaseIterable, Codable, Equatable, Sendable {
  case serviceHealth
  case protocolCompatibility
  case agentDiscovery
  case permissionCheck
  case readinessCheck
  case diagnosticsRoute
  case none
}

public struct HermesRecoveryAction: Identifiable, Codable, Equatable, Sendable {
  public var id: String { actionType.stableIdentifier }
  public let issue: HermesRecoveryIssueCategory
  public let actionType: HermesRecoveryActionType
  public let isAutomatic: Bool
  public let requiresConfirmation: Bool
  public let explanation: String
  public let expectedVerification: HermesRecoveryVerification

  public init(
    issue: HermesRecoveryIssueCategory,
    actionType: HermesRecoveryActionType,
    isAutomatic: Bool,
    requiresConfirmation: Bool,
    explanation: String,
    expectedVerification: HermesRecoveryVerification
  ) {
    self.issue = issue
    self.actionType = actionType
    self.isAutomatic = isAutomatic
    self.requiresConfirmation = requiresConfirmation
    self.explanation = HermesRecoveryRedactor.safeText(explanation)
    self.expectedVerification = expectedVerification
  }
}

public struct HermesRecoverySnapshot: Equatable, Sendable {
  public let state: HermesRecoveryState
  public let issue: HermesRecoveryIssueCategory?
  public let actions: [HermesRecoveryAction]
  public let selectedAction: HermesRecoveryActionType?
  public let message: String
  public let clientProtocolVersion: String
  public let compatibilityStatus: String?

  public init(
    state: HermesRecoveryState = .idle,
    issue: HermesRecoveryIssueCategory? = nil,
    actions: [HermesRecoveryAction] = [],
    selectedAction: HermesRecoveryActionType? = nil,
    message: String = "Recovery is idle.",
    clientProtocolVersion: String = HermesBridgeProtocolVersion.current.description,
    compatibilityStatus: String? = nil
  ) {
    self.state = state
    self.issue = issue
    self.actions = actions
    self.selectedAction = selectedAction
    self.message = HermesRecoveryRedactor.safeText(message)
    self.clientProtocolVersion = HermesRecoveryRedactor.safeToken(clientProtocolVersion)
    self.compatibilityStatus = compatibilityStatus.map(HermesRecoveryRedactor.safeText)
  }
}

public extension HermesRecoveryActionType {
  var stableIdentifier: String {
    switch self {
    case .retryConnection: return "retryConnection"
    case .restartBridgeService: return "restartBridgeService"
    case .refreshAgentDiscovery: return "refreshAgentDiscovery"
    case .rerunPermissionsCheck: return "rerunPermissionsCheck"
    case .openSystemSettings(let permission): return "openSystemSettings.\(permission.rawValue)"
    case .openDiagnostics: return "openDiagnostics"
    case .showUpgradeRequired: return "showUpgradeRequired"
    case .rerunReadiness: return "rerunReadiness"
    case .dismiss: return "dismiss"
    }
  }

  var auditReasonCode: String {
    HermesRecoveryRedactor.safeToken(stableIdentifier.replacingOccurrences(of: ".", with: "_"))
  }
}

public enum HermesRecoveryActionCatalog {
  public static func actions(for issue: HermesRecoveryIssueCategory) -> [HermesRecoveryAction] {
    switch issue {
    case .bridgeServiceUnavailable, .xpcConnectionFailed:
      return [
        HermesRecoveryAction(
          issue: issue,
          actionType: .retryConnection,
          isAutomatic: true,
          requiresConfirmation: false,
          explanation: "Reconnect to the existing Bridge Service before changing service state.",
          expectedVerification: .serviceHealth
        ),
        HermesRecoveryAction(
          issue: issue,
          actionType: .restartBridgeService,
          isAutomatic: false,
          requiresConfirmation: true,
          explanation: "Restart the owned user Bridge Service through the existing lifecycle boundary.",
          expectedVerification: .serviceHealth
        ),
        HermesRecoveryAction(
          issue: issue,
          actionType: .openDiagnostics,
          isAutomatic: false,
          requiresConfirmation: false,
          explanation: "Open Diagnostics for more detail.",
          expectedVerification: .diagnosticsRoute
        ),
      ]
    case .protocolIncompatible:
      return [
        HermesRecoveryAction(
          issue: issue,
          actionType: .showUpgradeRequired,
          isAutomatic: false,
          requiresConfirmation: false,
          explanation: "Show the required upgrade path without downgrading protocol semantics.",
          expectedVerification: .protocolCompatibility
        ),
        HermesRecoveryAction(
          issue: issue,
          actionType: .openDiagnostics,
          isAutomatic: false,
          requiresConfirmation: false,
          explanation: "Open Diagnostics for sanitized compatibility details.",
          expectedVerification: .diagnosticsRoute
        ),
      ]
    case .agentUnavailable, .agentIncompatible:
      return [
        HermesRecoveryAction(
          issue: issue,
          actionType: .refreshAgentDiscovery,
          isAutomatic: true,
          requiresConfirmation: false,
          explanation: "Ask the Bridge Service to rediscover Hermes Agent.",
          expectedVerification: .agentDiscovery
        ),
        HermesRecoveryAction(
          issue: issue,
          actionType: .openDiagnostics,
          isAutomatic: false,
          requiresConfirmation: false,
          explanation: "Open Diagnostics for additional health context.",
          expectedVerification: .diagnosticsRoute
        ),
      ]
    case .accessibilityPermissionMissing:
      return permissionActions(issue: issue, permission: .accessibility)
    case .automationPermissionMissing:
      return permissionActions(issue: issue, permission: .automation)
    case .screenRecordingPermissionMissing:
      return permissionActions(issue: issue, permission: .screenRecording)
    case .notificationsPermissionMissing:
      return permissionActions(issue: issue, permission: .notifications)
    case .unknownReadinessFailure:
      return [
        HermesRecoveryAction(
          issue: issue,
          actionType: .rerunReadiness,
          isAutomatic: true,
          requiresConfirmation: false,
          explanation: "Rerun the original readiness check.",
          expectedVerification: .readinessCheck
        ),
        HermesRecoveryAction(
          issue: issue,
          actionType: .openDiagnostics,
          isAutomatic: false,
          requiresConfirmation: false,
          explanation: "Open Diagnostics for supported checks.",
          expectedVerification: .diagnosticsRoute
        ),
      ]
    }
  }

  private static func permissionActions(
    issue: HermesRecoveryIssueCategory,
    permission: HermesRecoveryPermissionPane
  ) -> [HermesRecoveryAction] {
    [
      HermesRecoveryAction(
        issue: issue,
        actionType: .openSystemSettings(permission),
        isAutomatic: false,
        requiresConfirmation: false,
        explanation: "Open the fixed System Settings pane for \(permission.rawValue).",
        expectedVerification: .permissionCheck
      ),
      HermesRecoveryAction(
        issue: issue,
        actionType: .rerunPermissionsCheck,
        isAutomatic: true,
        requiresConfirmation: false,
        explanation: "Rerun the Permissions Doctor check.",
        expectedVerification: .permissionCheck
      ),
    ]
  }
}

public enum HermesRecoveryRedactor {
  public static func safeToken(_ value: String) -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-")
    }
    return String((filtered.isEmpty ? "unknown" : filtered).prefix(80))
  }

  public static func safeText(_ value: String) -> String {
    var output = String(value.prefix(240))
    let patterns = [
      (#"(?i)\b(token|password|credential|secret|api[_ -]?key)\s*[:=]\s*[^,\s]+"#, "$1=<redacted>"),
      (#"/(?:Users|private|var|tmp|Applications|System|Library)/[^\s,"')]+"#, "<redacted-path>"),
      (#"\bpid\s*[:=]\s*\d+\b"#, "<redacted-process-id>"),
      (#"\bprocess\s+id\s*[:=]\s*\d+\b"#, "<redacted-process-id>"),
    ]
    for (pattern, template) in patterns {
      output = output.replacingOccurrences(
        of: pattern,
        with: template,
        options: [.regularExpression, .caseInsensitive]
      )
    }
    return String(output.prefix(240))
  }
}
