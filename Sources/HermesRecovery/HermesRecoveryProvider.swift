import AppKit
import Foundation
import HermesBridgeServiceManager
import HermesBridgeXPC
import HermesRuntimeFoundation

public enum HermesRecoveryProviderError: Error, Equatable, Sendable {
  case unsupportedAction
  case confirmationRequired
}

public protocol HermesRecoveryXPCConnecting: Sendable {
  @discardableResult
  func connect() async throws -> HermesBridgeCapabilitiesPayload
  func protocolVersion() async throws -> HermesBridgeProtocolVersionPayload
  func capabilities() async throws -> HermesBridgeCapabilitiesPayload
  func discoverAgent() async throws -> HermesBridgeAgentDiscoveryPayload
}

public protocol HermesRecoveryServiceControlling: Sendable {
  func status() async -> HermesBridgeServiceStatus
  func restart() async throws -> HermesBridgeHealthCheckResult
}

public protocol HermesRecoveryPermissionChecking: Sendable {
  func permissionState(for permission: HermesRecoveryPermissionPane) async -> HermesPermissionState
}

public protocol HermesRecoverySystemSettingsOpening: Sendable {
  @MainActor
  func open(permission: HermesRecoveryPermissionPane)
}

public protocol HermesRecoveryReadinessRerunning: Sendable {
  func rerunReadiness() async -> Bool
}

public protocol HermesRecoveryAuditRecording: Sendable {
  func recordRecovery(
    action: HermesRecoveryActionType,
    target: HermesRecoveryIssueCategory,
    result: HermesRecoveryState,
    timestamp: Date
  ) async
}

public protocol HermesRecoveryProviding: Sendable {
  func serviceStatus() async -> HermesBridgeServiceStatus
  func reconnect() async -> Bool
  func restartBridgeService() async -> Bool
  func protocolCompatibility() async -> HermesRecoveryProtocolCompatibility
  func discoverAgent() async -> HermesBridgeAgentDiscoveryPayload
  func permissionState(for permission: HermesRecoveryPermissionPane) async -> HermesPermissionState
  @MainActor
  func openSystemSettings(permission: HermesRecoveryPermissionPane)
  func rerunReadiness() async -> Bool
  func recordAudit(action: HermesRecoveryActionType, target: HermesRecoveryIssueCategory, result: HermesRecoveryState) async
}

public struct HermesRecoveryProtocolCompatibility: Equatable, Sendable {
  public let clientProtocol: String
  public let serviceProtocol: String?
  public let compatible: Bool
  public let status: String

  public init(
    clientProtocol: String = HermesBridgeProtocolVersion.current.description,
    serviceProtocol: String?,
    compatible: Bool,
    status: String
  ) {
    self.clientProtocol = HermesRecoveryRedactor.safeToken(clientProtocol)
    self.serviceProtocol = serviceProtocol.map(HermesRecoveryRedactor.safeToken)
    self.compatible = compatible
    self.status = HermesRecoveryRedactor.safeText(status)
  }
}

public struct HermesRecoveryProductionProvider: HermesRecoveryProviding {
  private let xpc: any HermesRecoveryXPCConnecting
  private let service: any HermesRecoveryServiceControlling
  private let permissions: any HermesRecoveryPermissionChecking
  private let settingsOpener: any HermesRecoverySystemSettingsOpening
  private let readiness: any HermesRecoveryReadinessRerunning
  private let audit: any HermesRecoveryAuditRecording

  public init(
    xpc: any HermesRecoveryXPCConnecting,
    service: any HermesRecoveryServiceControlling = HermesRecoveryBridgeServiceManagerAdapter(),
    permissions: any HermesRecoveryPermissionChecking = HermesRecoveryPermissionsDoctorAdapter(),
    settingsOpener: any HermesRecoverySystemSettingsOpening = HermesRecoverySystemSettingsOpener(),
    readiness: any HermesRecoveryReadinessRerunning = HermesRecoveryNoopReadinessRerunner(),
    audit: any HermesRecoveryAuditRecording = HermesRecoveryNoopAuditRecorder()
  ) {
    self.xpc = xpc
    self.service = service
    self.permissions = permissions
    self.settingsOpener = settingsOpener
    self.readiness = readiness
    self.audit = audit
  }

  public func serviceStatus() async -> HermesBridgeServiceStatus {
    await service.status()
  }

  public func reconnect() async -> Bool {
    do {
      let capabilities = try await xpc.connect()
      return capabilities.protocolVersion.major == HermesBridgeProtocolVersion.current.major
    } catch {
      return false
    }
  }

  public func restartBridgeService() async -> Bool {
    do {
      let health = try await service.restart()
      return health.isHealthy
    } catch {
      return false
    }
  }

  public func protocolCompatibility() async -> HermesRecoveryProtocolCompatibility {
    do {
      let version = try await xpc.protocolVersion()
      let compatible = HermesBridgeProtocolVersion.current.isCompatible(with: version.version)
      return HermesRecoveryProtocolCompatibility(
        serviceProtocol: version.version.description,
        compatible: compatible,
        status: compatible ? "compatible" : "client_requires_1.8"
      )
    } catch {
      return HermesRecoveryProtocolCompatibility(
        serviceProtocol: nil,
        compatible: false,
        status: "compatibility_unavailable"
      )
    }
  }

  public func discoverAgent() async -> HermesBridgeAgentDiscoveryPayload {
    (try? await xpc.discoverAgent()) ?? HermesBridgeAgentDiscoveryPayload(status: .unknown)
  }

  public func permissionState(for permission: HermesRecoveryPermissionPane) async -> HermesPermissionState {
    await permissions.permissionState(for: permission)
  }

  @MainActor
  public func openSystemSettings(permission: HermesRecoveryPermissionPane) {
    settingsOpener.open(permission: permission)
  }

  public func rerunReadiness() async -> Bool {
    await readiness.rerunReadiness()
  }

  public func recordAudit(
    action: HermesRecoveryActionType,
    target: HermesRecoveryIssueCategory,
    result: HermesRecoveryState
  ) async {
    await audit.recordRecovery(action: action, target: target, result: result, timestamp: Date())
  }
}

extension HermesBridgeRuntimeClientAdapter: HermesRecoveryXPCConnecting {}
public struct HermesRecoveryBridgeServiceManagerAdapter: HermesRecoveryServiceControlling, @unchecked Sendable {
  private let manager: HermesBridgeServiceManager

  public init(manager: HermesBridgeServiceManager = HermesBridgeServiceManager()) {
    self.manager = manager
  }

  public func status() async -> HermesBridgeServiceStatus {
    await manager.status()
  }

  public func restart() async throws -> HermesBridgeHealthCheckResult {
    try await manager.restart()
  }
}

public struct HermesRecoveryPermissionsDoctorAdapter: HermesRecoveryPermissionChecking {
  private let doctor: HermesPermissionsDoctor
  private let evidence: @Sendable () -> HermesPermissionsDoctorEvidence

  public init(
    doctor: HermesPermissionsDoctor = HermesPermissionsDoctor(),
    evidence: @escaping @Sendable () -> HermesPermissionsDoctorEvidence = {
      HermesPermissionsDoctorEvidence(executableURL: Bundle.main.executableURL)
    }
  ) {
    self.doctor = doctor
    self.evidence = evidence
  }

  public func permissionState(for permission: HermesRecoveryPermissionPane) async -> HermesPermissionState {
    doctor.report(evidence: evidence()).checks.first { $0.kind == permission.permissionKind }?.state ?? .unknown
  }
}

public struct HermesRecoverySystemSettingsOpener: HermesRecoverySystemSettingsOpening {
  public init() {}

  @MainActor
  public func open(permission: HermesRecoveryPermissionPane) {
    let url: URL
    switch permission {
    case .accessibility:
      url = HermesSystemSettingsRemediationURL.accessibility
    case .automation:
      url = HermesSystemSettingsRemediationURL.automation
    case .screenRecording:
      url = HermesSystemSettingsRemediationURL.screenRecording
    case .notifications:
      url = HermesSystemSettingsRemediationURL.notifications
    }
    NSWorkspace.shared.open(url)
  }
}

public struct HermesRecoveryNoopReadinessRerunner: HermesRecoveryReadinessRerunning {
  public init() {}
  public func rerunReadiness() async -> Bool { false }
}

public struct HermesRecoveryNoopAuditRecorder: HermesRecoveryAuditRecording {
  public init() {}
  public func recordRecovery(
    action _: HermesRecoveryActionType,
    target _: HermesRecoveryIssueCategory,
    result _: HermesRecoveryState,
    timestamp _: Date
  ) async {}
}

public struct HermesRecoveryAuditStoreRecorder: HermesRecoveryAuditRecording {
  private let store: any HermesAuditStore

  public init(store: any HermesAuditStore) {
    self.store = store
  }

  public func recordRecovery(
    action: HermesRecoveryActionType,
    target: HermesRecoveryIssueCategory,
    result: HermesRecoveryState,
    timestamp: Date
  ) async {
    let outcome: HermesAuditOutcome = result == .recovered ? .succeeded : (result == .failed ? .failed : .unavailable)
    let metadata = (try? HermesAuditMetadata([
      "action": action.auditReasonCode,
      "target": target.rawValue,
      "result": result.rawValue,
    ])) ?? (try! HermesAuditMetadata())
    let event = try? HermesAuditEvent.make(
      kind: .doctorExecuted,
      actor: .xpcClient,
      outcome: outcome,
      reasonCode: "guided_recovery",
      metadata: metadata,
      timestamp: timestamp
    )
    if let event {
      try? await store.append(event)
    }
  }
}
