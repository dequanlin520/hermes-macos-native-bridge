import Foundation
import HermesRuntimeFoundation

public actor HermesUpdateCoordinator {
  private let provider: any HermesUpdateProviding
  private let audit: any HermesUpdateAuditRecording
  private var snapshot: HermesUpdateSnapshot
  private var activationForwardedReleaseIDs = Set<String>()
  private var rollbackForwarded = false

  public init(
    provider: any HermesUpdateProviding,
    audit: any HermesUpdateAuditRecording = HermesUpdateAuditStoreRecorder()
  ) {
    self.provider = provider
    self.audit = audit
    self.snapshot = HermesUpdateSnapshot()
  }

  public var currentSnapshot: HermesUpdateSnapshot {
    snapshot
  }

  public func checkForUpdate() async -> HermesUpdateSnapshot {
    do {
      snapshot = HermesUpdateSnapshot(
        state: .checking,
        current: try await provider.currentVersionInfo(),
        message: "Checking trusted release metadata."
      )
      await audit.record(kind: .checkStarted, outcome: .started, reasonCode: "check_started", metadata: [:])
      let release = try await provider.checkForUpdate()
      await audit.record(kind: .checkCompleted, outcome: .succeeded, reasonCode: "check_completed", metadata: [:])
      if let release {
        snapshot = HermesUpdateSnapshot(
          state: .updateAvailable,
          current: snapshot.current,
          availableRelease: release,
          message: "A trusted update is available."
        )
        await audit.record(
          kind: .updateOffered,
          outcome: .succeeded,
          reasonCode: "update_offered",
          metadata: ["targetVersion": release.version]
        )
      } else {
        snapshot = HermesUpdateSnapshot(
          state: .upToDate,
          current: snapshot.current,
          message: "Hermes Bridge is up to date."
        )
      }
    } catch {
      fail(error, fallback: .serviceUnavailable, message: "Update check failed.")
      await audit.record(kind: .checkCompleted, outcome: .failed, reasonCode: "check_failed", metadata: [:])
    }
    return snapshot
  }

  public func validateAvailableUpdate() async -> HermesUpdateSnapshot {
    guard let release = snapshot.availableRelease else {
      fail(HermesUpdateValidationError(.manifestInvalid, "missing_release"), fallback: .manifestInvalid, message: "No update is available.")
      return snapshot
    }
    do {
      snapshot = HermesUpdateSnapshot(
        state: .validating,
        current: snapshot.current,
        availableRelease: release,
        message: "Validating release manifest and compatibility."
      )
      _ = try HermesUpdatePolicy.validate(release: release, current: snapshot.current)
      let report = try await provider.validate(release: release)
      guard report.manifestValidated, report.productIdentifierValidated,
        report.versionOrderingValidated, report.appServiceCompatibilityValidated,
        report.xpcCompatibilityValidated, report.checksumValidated,
        report.signingStateValidated, report.provenanceValidated,
        report.productionPayloadValidated, report.acceptancePayloadRejected
      else {
        throw HermesUpdateValidationError(.manifestInvalid, "validation_gate_failed")
      }
      snapshot = HermesUpdateSnapshot(
        state: .awaitingConfirmation,
        current: snapshot.current,
        availableRelease: release,
        validatedRelease: release,
        confirmation: HermesUpdateConfirmation(
          operation: .activateUpdate,
          currentVersion: snapshot.current.serviceVersion,
          targetVersion: release.version,
          rollbackAvailable: snapshot.current.rollbackAvailable || release.rollbackAvailableAfterActivation
        ),
        message: "Validation passed. Confirmation is required before activation."
      )
      await audit.record(
        kind: .validationPassed,
        outcome: .succeeded,
        reasonCode: "validation_passed",
        metadata: ["targetVersion": release.version]
      )
    } catch {
      fail(error, fallback: .manifestInvalid, message: "Update validation failed.")
      await audit.record(kind: .validationFailed, outcome: .failed, reasonCode: failureReason(error), metadata: [:])
    }
    return snapshot
  }

  public func activateConfirmed() async -> HermesUpdateSnapshot {
    guard let release = snapshot.validatedRelease else {
      fail(HermesUpdateValidationError(.confirmationRequired, "validation_required"), fallback: .confirmationRequired, message: "Validation is required before activation.")
      return snapshot
    }
    guard snapshot.confirmation?.operation == .activateUpdate else {
      fail(HermesUpdateValidationError(.confirmationRequired, "confirmation_required"), fallback: .confirmationRequired, message: "Activation confirmation is required.")
      return snapshot
    }
    guard !activationForwardedReleaseIDs.contains(release.releaseID) else {
      return snapshot
    }
    activationForwardedReleaseIDs.insert(release.releaseID)
    await audit.record(
      kind: .activationConfirmed,
      outcome: .accepted,
      reasonCode: "activation_confirmed",
      metadata: ["targetVersion": release.version]
    )
    do {
      snapshot = HermesUpdateSnapshot(
        state: .staging,
        current: snapshot.current,
        availableRelease: release,
        validatedRelease: release,
        confirmation: snapshot.confirmation,
        message: "Service is staging the validated update."
      )
      snapshot = HermesUpdateSnapshot(
        state: .activating,
        current: snapshot.current,
        availableRelease: release,
        validatedRelease: release,
        confirmation: snapshot.confirmation,
        message: "Service is activating the update transaction."
      )
      let result = try await provider.activate(releaseID: release.releaseID)
      snapshot = HermesUpdateSnapshot(
        state: .reconnecting,
        current: HermesUpdateCurrentVersionInfo(
          appVersion: snapshot.current.appVersion,
          serviceVersion: result.activatedVersion,
          rollbackAvailable: result.rollbackAvailable
        ),
        availableRelease: release,
        validatedRelease: release,
        confirmation: snapshot.confirmation,
        message: "Reconnecting to the activated service."
      )
      let reconnected = try await provider.reconnectAndVerify()
      guard reconnected, result.reconnected, result.verifiedCompatible else {
        throw HermesUpdateValidationError(.verificationFailed, "post_activation_verification_failed")
      }
      snapshot = HermesUpdateSnapshot(
        state: .completed,
        current: snapshot.current,
        availableRelease: release,
        validatedRelease: release,
        message: "Update completed and compatibility was verified."
      )
      await audit.record(
        kind: .activationSucceeded,
        outcome: .succeeded,
        reasonCode: "activation_succeeded",
        metadata: ["targetVersion": result.activatedVersion]
      )
    } catch {
      fail(error, fallback: .activationFailed, message: "Activation failed. The current version remains usable.")
      await audit.record(kind: .activationFailed, outcome: .failed, reasonCode: failureReason(error), metadata: [:])
    }
    return snapshot
  }

  public func prepareRollback() async -> HermesUpdateSnapshot {
    let current = (try? await provider.currentVersionInfo()) ?? snapshot.current
    guard current.rollbackAvailable else {
      fail(HermesUpdateValidationError(.rollbackFailed, "rollback_unavailable"), fallback: .rollbackFailed, message: "Rollback is unavailable.")
      return snapshot
    }
    snapshot = HermesUpdateSnapshot(
      state: .rollbackAvailable,
      current: current,
      confirmation: HermesUpdateConfirmation(
        operation: .rollback,
        currentVersion: current.serviceVersion,
        targetVersion: "previous",
        expectedReconnectBehavior: "Bridge Service rolls back and the app reconnects after verification.",
        rollbackAvailable: true
      ),
      message: "Rollback is available. Confirmation is required."
    )
    return snapshot
  }

  public func rollbackConfirmed() async -> HermesUpdateSnapshot {
    guard snapshot.confirmation?.operation == .rollback else {
      fail(HermesUpdateValidationError(.confirmationRequired, "rollback_confirmation_required"), fallback: .confirmationRequired, message: "Rollback confirmation is required.")
      return snapshot
    }
    guard !rollbackForwarded else { return snapshot }
    rollbackForwarded = true
    await audit.record(kind: .rollbackConfirmed, outcome: .accepted, reasonCode: "rollback_confirmed", metadata: [:])
    do {
      snapshot = HermesUpdateSnapshot(
        state: .rollingBack,
        current: snapshot.current,
        confirmation: snapshot.confirmation,
        message: "Service is rolling back to the previous valid version."
      )
      let result = try await provider.rollback()
      snapshot = HermesUpdateSnapshot(
        state: .reconnecting,
        current: HermesUpdateCurrentVersionInfo(
          appVersion: snapshot.current.appVersion,
          serviceVersion: result.activatedVersion,
          rollbackAvailable: result.rollbackAvailable
        ),
        confirmation: snapshot.confirmation,
        message: "Reconnecting after rollback."
      )
      let reconnected = try await provider.reconnectAndVerify()
      guard reconnected, result.reconnected, result.verifiedCompatible else {
        throw HermesUpdateValidationError(.verificationFailed, "rollback_verification_failed")
      }
      snapshot = HermesUpdateSnapshot(
        state: .completed,
        current: snapshot.current,
        message: "Rollback completed and compatibility was verified."
      )
      await audit.record(
        kind: .rollbackSucceeded,
        outcome: .succeeded,
        reasonCode: "rollback_succeeded",
        metadata: ["targetVersion": result.activatedVersion]
      )
    } catch {
      fail(error, fallback: .rollbackFailed, message: "Rollback failed. Recovery is available.")
      await audit.record(kind: .rollbackFailed, outcome: .failed, reasonCode: failureReason(error), metadata: [:])
    }
    return snapshot
  }

  public func windowClosed() async -> HermesUpdateSnapshot {
    snapshot
  }

  private func fail(
    _ error: Error,
    fallback: HermesUpdateFailureCategory,
    message: String
  ) {
    let category = (error as? HermesUpdateValidationError)?.category ?? fallback
    snapshot = HermesUpdateSnapshot(
      state: category == .serviceUnavailable ? .recoveryRequired : .failed,
      current: snapshot.current,
      availableRelease: snapshot.availableRelease,
      validatedRelease: snapshot.validatedRelease,
      confirmation: snapshot.confirmation,
      failure: HermesUpdateFailure(category: category, safeMessage: message),
      message: message
    )
  }

  private func failureReason(_ error: Error) -> String {
    (error as? HermesUpdateValidationError)?.reasonCode ?? "update_failed"
  }
}
