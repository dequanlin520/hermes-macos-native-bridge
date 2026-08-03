import Foundation
import HermesBridgeXPC
import HermesRuntimeFoundation

public protocol HermesOnboardingReadinessProviding: Sendable {
  func checkService() async -> HermesOnboardingServiceReadiness
  func checkAgent() async -> HermesOnboardingAgentReadiness
  func checkPermissions() async -> HermesOnboardingPermissionReadiness
  func testConnection() async -> HermesOnboardingConnectionReadiness
}

public protocol HermesOnboardingXPCReadinessClient: Sendable {
  func connect() async throws -> HermesBridgeCapabilitiesPayload
  func protocolVersion() async throws -> HermesBridgeProtocolVersionPayload
  func capabilities() async throws -> HermesBridgeCapabilitiesPayload
  func discoverAgent() async throws -> HermesBridgeAgentDiscoveryPayload
  func execute(_ command: HermesRuntimeCommand) async throws -> HermesRuntimeCommandResult
}

extension HermesBridgeRuntimeClientAdapter: HermesOnboardingXPCReadinessClient {}

public struct HermesOnboardingProductionReadinessProvider: HermesOnboardingReadinessProviding {
  private let client: any HermesOnboardingXPCReadinessClient
  private let permissionsDoctor: HermesPermissionsDoctor
  private let evidence: @Sendable () -> HermesPermissionsDoctorEvidence

  public init(
    client: any HermesOnboardingXPCReadinessClient,
    permissionsDoctor: HermesPermissionsDoctor = HermesPermissionsDoctor(),
    evidence: @escaping @Sendable () -> HermesPermissionsDoctorEvidence = {
      HermesPermissionsDoctorEvidence(executableURL: Bundle.main.executableURL)
    }
  ) {
    self.client = client
    self.permissionsDoctor = permissionsDoctor
    self.evidence = evidence
  }

  public func checkService() async -> HermesOnboardingServiceReadiness {
    do {
      let version = try await client.protocolVersion().version
      let capabilities = try await client.capabilities()
      let compatible = HermesBridgeProtocolVersion.current.isCompatible(with: version)
        && HermesBridgeProtocolVersion.current.isCompatible(with: capabilities.protocolVersion)
      return HermesOnboardingServiceReadiness(
        serviceAvailable: true,
        xpcConnected: true,
        protocolVersion: version.description,
        protocolCompatible: compatible,
        healthStatus: compatible ? .healthy : .degraded,
        safeMessage: compatible ? "Bridge Service is available." : "Bridge Service protocol is incompatible."
      )
    } catch {
      return HermesOnboardingServiceReadiness(
        serviceAvailable: false,
        xpcConnected: false,
        protocolVersion: nil,
        protocolCompatible: false,
        healthStatus: .unavailable,
        safeMessage: "Bridge Service is unavailable."
      )
    }
  }

  public func checkAgent() async -> HermesOnboardingAgentReadiness {
    do {
      let capabilities = try await client.capabilities()
      guard capabilities.capabilities.contains(.agentDiscovery) else {
        return HermesOnboardingAgentReadiness(status: .unknown, safeMessage: "Agent status is unknown.")
      }
      let discovery = try await client.discoverAgent()
      switch discovery.status {
      case .available:
        return HermesOnboardingAgentReadiness(status: .available, safeMessage: "Hermes Agent is available.")
      case .unavailable:
        return HermesOnboardingAgentReadiness(status: .unavailable, safeMessage: "Hermes Agent is unavailable.")
      case .incompatible:
        return HermesOnboardingAgentReadiness(status: .incompatible, safeMessage: "Hermes Agent is incompatible.")
      case .unknown:
        return HermesOnboardingAgentReadiness(status: .unknown, safeMessage: "Agent status is unknown.")
      }
    } catch {
      return HermesOnboardingAgentReadiness(status: .unknown, safeMessage: "Agent status is unknown.")
    }
  }

  public func checkPermissions() async -> HermesOnboardingPermissionReadiness {
    let report = permissionsDoctor.report(evidence: evidence())
    let supported: [(HermesPermissionKind, HermesOnboardingPermissionKind)] = [
      (.inputMonitoring, .inputMonitoring),
      (.accessibility, .accessibility),
      (.automation, .automation),
      (.screenRecording, .screenRecording),
      (.fullDiskAccess, .fullDiskAccess),
      (.microphone, .microphone),
      (.camera, .camera),
      (.notifications, .notifications),
    ]
    let checks = supported.map { sourceKind, targetKind in
      let check = report.checks.first { $0.kind == sourceKind }
      let status = HermesOnboardingPermissionStatus(
        permissionStatus: check?.currentStatus,
        permissionState: check?.state ?? .unknown
      )
      let blocksFirstRun = check?.blocksFirstRun ?? status.isBlocking
      let remediation = remediationAction(
        for: targetKind,
        blocksFirstRun: blocksFirstRun
      )
      return HermesOnboardingPermissionCheck(
        kind: targetKind,
        status: status,
        classification: check?.classification.rawValue ?? "required-for-core",
        blocksFirstRun: blocksFirstRun,
        capabilityOwner: check?.capabilityOwner ?? "unknown",
        reason: check?.userReadableReason ?? "",
        remediation: remediation
      )
    }
    return HermesOnboardingPermissionReadiness(permissions: checks)
  }

  public func testConnection() async -> HermesOnboardingConnectionReadiness {
    do {
      let capabilities = try await client.connect()
      let result = try await client.execute(.listSessions)
      guard case .sessionList = result else {
        return HermesOnboardingConnectionReadiness(
          requestSucceeded: false,
          protocolCompatible: false,
          healthStatus: .unavailable,
          safeMessage: "Connection test returned an unexpected safe response."
        )
      }
      let compatible = HermesBridgeProtocolVersion.current.isCompatible(
        with: capabilities.protocolVersion
      )
      return HermesOnboardingConnectionReadiness(
        requestSucceeded: true,
        protocolCompatible: compatible,
        healthStatus: compatible ? .healthy : .degraded,
        safeMessage: compatible ? "Connection test passed." : "Connection protocol is incompatible."
      )
    } catch {
      return HermesOnboardingConnectionReadiness(
        requestSucceeded: false,
        protocolCompatible: false,
        healthStatus: .unavailable,
        safeMessage: "Connection test failed."
      )
    }
  }

  private func remediationAction(
    for kind: HermesOnboardingPermissionKind,
    blocksFirstRun: Bool
  ) -> HermesOnboardingRemediationAction? {
    guard blocksFirstRun else { return nil }
    return .openSystemSettings(kind)
  }
}

extension HermesOnboardingPermissionStatus {
  init(permissionStatus: HermesPermissionCurrentStatus?, permissionState: HermesPermissionState) {
    if let permissionStatus {
      switch permissionStatus {
      case .granted:
        self = .granted
      case .denied, .misconfigured:
        self = .denied
      case .restricted:
        self = .restricted
      case .notDetermined:
        self = .notDetermined
      case .unavailable:
        self = .unavailable
      case .notApplicable:
        self = .notApplicable
      case .unknown:
        self = .unknown
      case .notRequired:
        self = .notRequired
      case .featureTriggered:
        self = .featureTriggered
      case .unsupported:
        self = .unsupported
      }
      return
    }
    switch permissionState {
    case .granted:
      self = .granted
    case .denied:
      self = .denied
    case .restricted:
      self = .restricted
    case .notDetermined:
      self = .notDetermined
    case .unavailable:
      self = .unavailable
    case .notApplicable:
      self = .notApplicable
    case .misconfigured:
      self = .denied
    case .unknown:
      self = .unknown
    }
  }
}
