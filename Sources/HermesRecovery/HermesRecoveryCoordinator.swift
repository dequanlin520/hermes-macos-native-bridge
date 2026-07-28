import Foundation
import HermesBridgeServiceManager
import HermesBridgeXPC
import HermesRuntimeFoundation

public final class HermesRecoveryCoordinator: @unchecked Sendable {
  private let provider: any HermesRecoveryProviding
  private var snapshot: HermesRecoverySnapshot

  public init(provider: any HermesRecoveryProviding) {
    self.provider = provider
    self.snapshot = HermesRecoverySnapshot()
  }

  public var currentSnapshot: HermesRecoverySnapshot {
    snapshot
  }

  @discardableResult
  public func evaluate(issue: HermesRecoveryIssueCategory) async -> HermesRecoverySnapshot {
    snapshot = HermesRecoverySnapshot(
      state: .evaluating,
      issue: issue,
      message: "Evaluating guided recovery."
    )
    if issue == .protocolIncompatible {
      let compatibility = await provider.protocolCompatibility()
      snapshot = HermesRecoverySnapshot(
        state: .actionAvailable,
        issue: issue,
        actions: HermesRecoveryActionCatalog.actions(for: issue),
        message: "Bridge protocol compatibility requires an upgrade path.",
        clientProtocolVersion: compatibility.clientProtocol,
        compatibilityStatus: compatibility.status
      )
      return snapshot
    }
    snapshot = HermesRecoverySnapshot(
      state: .actionAvailable,
      issue: issue,
      actions: HermesRecoveryActionCatalog.actions(for: issue),
      message: "Guided recovery action is available."
    )
    return snapshot
  }

  @discardableResult
  public func perform(
    _ actionType: HermesRecoveryActionType,
    confirmed: Bool = false
  ) async -> HermesRecoverySnapshot {
    guard let issue = snapshot.issue else {
      snapshot = HermesRecoverySnapshot(state: .failed, message: "No recovery issue is active.")
      return snapshot
    }
    let actions = HermesRecoveryActionCatalog.actions(for: issue)
    guard let action = actions.first(where: { $0.actionType == actionType }) else {
      snapshot = HermesRecoverySnapshot(
        state: .failed,
        issue: issue,
        actions: actions,
        selectedAction: actionType,
        message: "Action is not available for this issue."
      )
      return snapshot
    }
    guard !action.requiresConfirmation || confirmed else {
      snapshot = HermesRecoverySnapshot(
        state: .actionAvailable,
        issue: issue,
        actions: actions,
        selectedAction: actionType,
        message: "Typed confirmation is required before changing service state."
      )
      return snapshot
    }

    snapshot = HermesRecoverySnapshot(
      state: .executing,
      issue: issue,
      actions: actions,
      selectedAction: actionType,
      message: action.explanation
    )

    let result = await execute(actionType, issue: issue)
    snapshot = HermesRecoverySnapshot(
      state: .verifying,
      issue: issue,
      actions: actions,
      selectedAction: actionType,
      message: "Verifying recovery result."
    )

    let finalState = result ? HermesRecoveryState.recovered : HermesRecoveryState.stillBlocked
    let finalMessage = result ? "Recovery verified." : "Recovery is still blocked."
    snapshot = HermesRecoverySnapshot(
      state: finalState,
      issue: issue,
      actions: actions,
      selectedAction: actionType,
      message: finalMessage
    )
    await provider.recordAudit(action: actionType, target: issue, result: finalState)
    return snapshot
  }

  private func execute(_ action: HermesRecoveryActionType, issue: HermesRecoveryIssueCategory) async -> Bool {
    switch action {
    case .retryConnection:
      return await provider.reconnect()
    case .restartBridgeService:
      if await provider.reconnect() {
        return true
      }
      let status = await provider.serviceStatus()
      guard status != .notInstalled && status != .invalidInstallation else {
        return false
      }
      guard await provider.restartBridgeService() else {
        return false
      }
      return await provider.reconnect()
    case .refreshAgentDiscovery:
      let payload = await provider.discoverAgent()
      switch issue {
      case .agentUnavailable:
        return payload.status == .available
      case .agentIncompatible:
        return payload.status == .available && payload.compatibility == .compatible
      default:
        return false
      }
    case .rerunPermissionsCheck:
      guard let permission = permissionPane(for: issue) else { return false }
      return await provider.permissionState(for: permission) == .granted
    case .openSystemSettings(let permission):
      await provider.openSystemSettings(permission: permission)
      return await provider.permissionState(for: permission) == .granted
    case .openDiagnostics:
      return false
    case .showUpgradeRequired:
      let compatibility = await provider.protocolCompatibility()
      return compatibility.compatible
    case .rerunReadiness:
      return await provider.rerunReadiness()
    case .dismiss:
      return true
    }
  }

  private func permissionPane(for issue: HermesRecoveryIssueCategory) -> HermesRecoveryPermissionPane? {
    switch issue {
    case .accessibilityPermissionMissing: return .accessibility
    case .automationPermissionMissing: return .automation
    case .screenRecordingPermissionMissing: return .screenRecording
    case .notificationsPermissionMissing: return .notifications
    case .bridgeServiceUnavailable, .xpcConnectionFailed, .protocolIncompatible,
      .agentUnavailable, .agentIncompatible, .unknownReadinessFailure:
      return nil
    }
  }
}
