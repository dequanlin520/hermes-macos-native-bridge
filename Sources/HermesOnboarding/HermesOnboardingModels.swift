import Foundation
import HermesRecovery
import HermesRuntimeFoundation

public enum HermesOnboardingState: String, CaseIterable, Equatable, Sendable {
  case welcome
  case checkingService
  case serviceUnavailable
  case checkingAgent
  case agentUnavailable
  case checkingPermissions
  case permissionsRequired
  case testingConnection
  case connectionFailed
  case ready
}

public enum HermesOnboardingStep: String, CaseIterable, Equatable, Sendable {
  case welcome
  case service
  case agent
  case permissions
  case connection
  case ready
}

public enum HermesOnboardingPermissionKind: String, CaseIterable, Codable, Equatable, Sendable {
  case accessibility = "Accessibility"
  case automation = "Automation"
  case screenRecording = "Screen Recording"
  case notifications = "Notifications"
}

public enum HermesOnboardingPermissionStatus: String, Codable, Equatable, Sendable {
  case granted
  case denied
  case restricted
  case notDetermined
  case unavailable
  case notApplicable
  case unknown

  public var isBlocking: Bool {
    switch self {
    case .denied, .restricted, .notDetermined, .unknown:
      return true
    case .granted, .unavailable, .notApplicable:
      return false
    }
  }
}

public enum HermesOnboardingAgentStatus: String, Codable, Equatable, Sendable {
  case available
  case unavailable
  case incompatible
  case unknown
}

public enum HermesOnboardingHealthStatus: String, Codable, Equatable, Sendable {
  case healthy
  case degraded
  case unavailable
  case unknown
}

public enum HermesOnboardingRemediationAction: Equatable, Hashable, Sendable {
  case retry
  case `continue`
  case openSystemSettings(HermesOnboardingPermissionKind)
  case openDiagnostics
  case openRecovery(HermesRecoveryIssueCategory)
  case reopenOnboarding
  case finish
}

public struct HermesOnboardingServiceReadiness: Equatable, Sendable {
  public let serviceAvailable: Bool
  public let xpcConnected: Bool
  public let protocolVersion: String?
  public let protocolCompatible: Bool
  public let healthStatus: HermesOnboardingHealthStatus
  public let safeMessage: String

  public init(
    serviceAvailable: Bool,
    xpcConnected: Bool,
    protocolVersion: String?,
    protocolCompatible: Bool,
    healthStatus: HermesOnboardingHealthStatus,
    safeMessage: String = ""
  ) {
    self.serviceAvailable = serviceAvailable
    self.xpcConnected = xpcConnected
    self.protocolVersion = protocolVersion
    self.protocolCompatible = protocolCompatible
    self.healthStatus = healthStatus
    self.safeMessage = HermesOnboardingRedactor.safeMessage(safeMessage)
  }

  public var isReady: Bool {
    serviceAvailable && xpcConnected && protocolCompatible
  }
}

public struct HermesOnboardingAgentReadiness: Equatable, Sendable {
  public let status: HermesOnboardingAgentStatus
  public let safeMessage: String

  public init(status: HermesOnboardingAgentStatus, safeMessage: String = "") {
    self.status = status
    self.safeMessage = HermesOnboardingRedactor.safeMessage(safeMessage)
  }

  public var isReady: Bool {
    status == .available
  }
}

public struct HermesOnboardingPermissionReadiness: Equatable, Sendable {
  public let permissions: [HermesOnboardingPermissionCheck]

  public init(permissions: [HermesOnboardingPermissionCheck]) {
    self.permissions = permissions
  }

  public var isReady: Bool {
    permissions.allSatisfy { !$0.status.isBlocking }
  }
}

public struct HermesOnboardingPermissionCheck: Equatable, Identifiable, Sendable {
  public var id: String { kind.rawValue }
  public let kind: HermesOnboardingPermissionKind
  public let status: HermesOnboardingPermissionStatus
  public let remediation: HermesOnboardingRemediationAction?

  public init(
    kind: HermesOnboardingPermissionKind,
    status: HermesOnboardingPermissionStatus,
    remediation: HermesOnboardingRemediationAction? = nil
  ) {
    self.kind = kind
    self.status = status
    self.remediation = remediation
  }
}

public struct HermesOnboardingConnectionReadiness: Equatable, Sendable {
  public let requestSucceeded: Bool
  public let protocolCompatible: Bool
  public let healthStatus: HermesOnboardingHealthStatus
  public let safeMessage: String

  public init(
    requestSucceeded: Bool,
    protocolCompatible: Bool,
    healthStatus: HermesOnboardingHealthStatus,
    safeMessage: String = ""
  ) {
    self.requestSucceeded = requestSucceeded
    self.protocolCompatible = protocolCompatible
    self.healthStatus = healthStatus
    self.safeMessage = HermesOnboardingRedactor.safeMessage(safeMessage)
  }

  public var isReady: Bool {
    requestSucceeded && protocolCompatible && healthStatus != .unavailable
  }
}

public struct HermesOnboardingSnapshot: Equatable, Sendable {
  public var state: HermesOnboardingState
  public var step: HermesOnboardingStep
  public var status: String
  public var explanation: String
  public var availableActions: [HermesOnboardingRemediationAction]
  public var service: HermesOnboardingServiceReadiness?
  public var agent: HermesOnboardingAgentReadiness?
  public var permissions: HermesOnboardingPermissionReadiness?
  public var connection: HermesOnboardingConnectionReadiness?

  public init(
    state: HermesOnboardingState = .welcome,
    step: HermesOnboardingStep = .welcome,
    status: String = "Ready to check this Mac",
    explanation: String = "Hermes Bridge will verify service, agent, permission, and connection readiness.",
    availableActions: [HermesOnboardingRemediationAction] = [.continue],
    service: HermesOnboardingServiceReadiness? = nil,
    agent: HermesOnboardingAgentReadiness? = nil,
    permissions: HermesOnboardingPermissionReadiness? = nil,
    connection: HermesOnboardingConnectionReadiness? = nil
  ) {
    self.state = state
    self.step = step
    self.status = HermesOnboardingRedactor.safeMessage(status)
    self.explanation = HermesOnboardingRedactor.safeMessage(explanation)
    self.availableActions = availableActions
    self.service = service
    self.agent = agent
    self.permissions = permissions
    self.connection = connection
  }
}

public struct HermesOnboardingCompletionRecord: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1
  public static let requiredSchemaVersion = 1

  public let schemaVersion: Int
  public let completedAt: Date
  public let completedSteps: [HermesOnboardingStep.RawValue]

  public init(
    schemaVersion: Int = currentSchemaVersion,
    completedAt: Date = Date(),
    completedSteps: [HermesOnboardingStep] = HermesOnboardingStep.allCases
  ) {
    self.schemaVersion = schemaVersion
    self.completedAt = completedAt
    self.completedSteps = completedSteps.map(\.rawValue)
  }

  public var isCompleteForCurrentSchema: Bool {
    schemaVersion >= Self.requiredSchemaVersion
      && Set(completedSteps) == Set(HermesOnboardingStep.allCases.map(\.rawValue))
  }
}

public protocol HermesOnboardingCompletionPersisting: Sendable {
  func loadCompletionRecord() -> HermesOnboardingCompletionRecord?
  func saveCompletionRecord(_ record: HermesOnboardingCompletionRecord)
  func clearCompletionRecord()
}

public final class HermesOnboardingUserDefaultsCompletionStore: HermesOnboardingCompletionPersisting,
  @unchecked Sendable
{
  public static let defaultKey = "com.hermes.bridge.onboarding.completion.v1"

  private let defaults: UserDefaults
  private let key: String

  public init(
    defaults: UserDefaults = .standard,
    key: String = HermesOnboardingUserDefaultsCompletionStore.defaultKey
  ) {
    self.defaults = defaults
    self.key = key
  }

  public func loadCompletionRecord() -> HermesOnboardingCompletionRecord? {
    guard let data = defaults.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(HermesOnboardingCompletionRecord.self, from: data)
  }

  public func saveCompletionRecord(_ record: HermesOnboardingCompletionRecord) {
    guard let data = try? JSONEncoder().encode(record) else { return }
    defaults.set(data, forKey: key)
  }

  public func clearCompletionRecord() {
    defaults.removeObject(forKey: key)
  }
}

public enum HermesOnboardingRedactor {
  public static func safeMessage(_ value: String) -> String {
    var output = value
    output = output.replacingOccurrences(
      of: #"/Users/[^\s]+"#,
      with: "[private-path]",
      options: .regularExpression
    )
    output = output.replacingOccurrences(
      of: #"(?i)(token|credential|secret)[=:][^\s]+"#,
      with: "$1=[redacted]",
      options: .regularExpression
    )
    output = output.replacingOccurrences(
      of: #"(?i)\bpid\s*[=:]\s*\d+\b"#,
      with: "pid=[redacted]",
      options: .regularExpression
    )
    output = output.replacingOccurrences(
      of: #"\b[0-9]{3,}\b"#,
      with: "[number]",
      options: .regularExpression
    )
    return String(output.prefix(240))
  }
}
