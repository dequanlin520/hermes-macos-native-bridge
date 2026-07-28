import Foundation
import HermesBridgeXPC
import HermesRuntimeFoundation

public protocol HermesUpdateProviding: Sendable {
  func currentVersionInfo() async throws -> HermesUpdateCurrentVersionInfo
  func checkForUpdate() async throws -> HermesUpdateReleaseMetadata?
  func validate(release: HermesUpdateReleaseMetadata) async throws -> HermesUpdateValidationReport
  func activate(releaseID: String) async throws -> HermesUpdateActivationResult
  func rollback() async throws -> HermesUpdateRollbackResult
  func reconnectAndVerify() async throws -> Bool
}

public protocol HermesUpdateAuditRecording: Sendable {
  func record(
    kind: HermesUpdateAuditKind,
    outcome: HermesAuditOutcome,
    reasonCode: String,
    metadata: [String: String]
  ) async
}

public enum HermesUpdateAuditKind: String, CaseIterable, Equatable, Sendable {
  case checkStarted
  case checkCompleted
  case updateOffered
  case validationPassed
  case validationFailed
  case activationConfirmed
  case activationSucceeded
  case activationFailed
  case rollbackConfirmed
  case rollbackSucceeded
  case rollbackFailed

  var auditEventKind: HermesAuditEventKind {
    switch self {
    case .checkStarted: return .updateCheckStarted
    case .checkCompleted: return .updateCheckCompleted
    case .updateOffered: return .updateOffered
    case .validationPassed: return .updateValidationPassed
    case .validationFailed: return .updateValidationFailed
    case .activationConfirmed: return .updateActivationConfirmed
    case .activationSucceeded: return .updateActivationSucceeded
    case .activationFailed: return .updateActivationFailed
    case .rollbackConfirmed: return .updateRollbackConfirmed
    case .rollbackSucceeded: return .updateRollbackSucceeded
    case .rollbackFailed: return .updateRollbackFailed
    }
  }
}

public struct HermesUpdateAuditStoreRecorder: HermesUpdateAuditRecording {
  private let store: any HermesAuditStore

  public init(store: any HermesAuditStore = NoopHermesAuditStore()) {
    self.store = store
  }

  public func record(
    kind: HermesUpdateAuditKind,
    outcome: HermesAuditOutcome,
    reasonCode: String,
    metadata: [String: String] = [:]
  ) async {
    let safeMetadata = (try? HermesAuditMetadata(metadata)) ?? (try! HermesAuditMetadata())
    let event = try? HermesAuditEvent.make(
      kind: kind.auditEventKind,
      actor: .xpcClient,
      outcome: outcome,
      reasonCode: HermesUpdateSanitizer.safeToken(reasonCode, fallback: "update_event"),
      metadata: safeMetadata
    )
    if let event {
      try? await store.append(event)
    }
  }
}

public struct HermesUpdateProductionProvider: HermesUpdateProviding {
  private let client: HermesBridgeXPCClient
  private let appVersion: @Sendable () -> String

  public init(
    client: HermesBridgeXPCClient,
    appVersion: @escaping @Sendable () -> String = {
      Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }
  ) {
    self.client = client
    self.appVersion = appVersion
  }

  public func currentVersionInfo() async throws -> HermesUpdateCurrentVersionInfo {
    let status = try await client.updateStatus()
    return HermesUpdateCurrentVersionInfo(
      appVersion: appVersion(),
      serviceVersion: status.currentServiceVersion,
      xpcProtocolVersion: status.xpcProtocolVersion,
      rollbackAvailable: status.rollbackAvailable
    )
  }

  public func checkForUpdate() async throws -> HermesUpdateReleaseMetadata? {
    let status = try await client.checkForUpdate()
    return status.availableRelease?.updateReleaseMetadata
  }

  public func validate(release: HermesUpdateReleaseMetadata) async throws
    -> HermesUpdateValidationReport
  {
    let report = try await client.validateUpdate(releaseID: release.releaseID)
    return report.updateValidationReport
  }

  public func activate(releaseID: String) async throws -> HermesUpdateActivationResult {
    let result = try await client.activateUpdate(
      confirmation: HermesBridgeUpdateConfirmationPayload(
        releaseID: releaseID,
        operation: .activateUpdate
      )
    )
    return result.updateActivationResult
  }

  public func rollback() async throws -> HermesUpdateRollbackResult {
    let result = try await client.rollbackUpdate(
      confirmation: HermesBridgeUpdateConfirmationPayload(
        releaseID: "rollback",
        operation: .rollback
      )
    )
    return result.updateActivationResult
  }

  public func reconnectAndVerify() async throws -> Bool {
    _ = try await client.connect()
    return true
  }
}

public struct HermesUpdateUnavailableProvider: HermesUpdateProviding {
  public init() {}

  public func currentVersionInfo() async throws -> HermesUpdateCurrentVersionInfo {
    HermesUpdateCurrentVersionInfo(
      appVersion: "unknown",
      serviceVersion: "unknown",
      rollbackAvailable: false
    )
  }

  public func checkForUpdate() async throws -> HermesUpdateReleaseMetadata? { nil }

  public func validate(release _: HermesUpdateReleaseMetadata) async throws
    -> HermesUpdateValidationReport
  {
    throw HermesUpdateValidationError(.serviceUnavailable, "service_unavailable")
  }

  public func activate(releaseID _: String) async throws -> HermesUpdateActivationResult {
    throw HermesUpdateValidationError(.serviceUnavailable, "service_unavailable")
  }

  public func rollback() async throws -> HermesUpdateRollbackResult {
    throw HermesUpdateValidationError(.serviceUnavailable, "service_unavailable")
  }

  public func reconnectAndVerify() async throws -> Bool { false }
}

extension HermesBridgeUpdateReleasePayload {
  var updateReleaseMetadata: HermesUpdateReleaseMetadata {
    HermesUpdateReleaseMetadata(
      releaseID: releaseID,
      productIdentifier: productIdentifier,
      version: version,
      minimumSupportedMacOS: minimumSupportedMacOS,
      compatibleXPCMajor: compatibleXPCMajor,
      compatibleXPCMinor: compatibleXPCMinor,
      compatibility: HermesUpdateCompatibilityState(rawValue: compatibility.rawValue) ?? .unknown,
      checksum: HermesUpdateChecksumState(rawValue: checksum.rawValue) ?? .unavailable,
      signing: HermesUpdateSigningState(rawValue: signing.rawValue) ?? .unknown,
      provenance: HermesUpdateProvenanceState(rawValue: provenance.rawValue) ?? .unavailable,
      releaseNotesSummary: releaseNotesSummary,
      trustedSource: .repositoryConfigured(trustedSourceIdentifier),
      isProductionPayload: isProductionPayload,
      containsAcceptanceContent: containsAcceptanceContent,
      rollbackAvailableAfterActivation: rollbackAvailableAfterActivation
    )
  }
}

extension HermesBridgeUpdateValidationReportPayload {
  var updateValidationReport: HermesUpdateValidationReport {
    HermesUpdateValidationReport(
      manifestValidated: manifestValidated,
      productIdentifierValidated: productIdentifierValidated,
      versionOrderingValidated: versionOrderingValidated,
      appServiceCompatibilityValidated: appServiceCompatibilityValidated,
      xpcCompatibilityValidated: xpcCompatibilityValidated,
      checksumValidated: checksumValidated,
      signingStateValidated: signingStateValidated,
      provenanceValidated: provenanceValidated,
      productionPayloadValidated: productionPayloadValidated,
      acceptancePayloadRejected: acceptancePayloadRejected
    )
  }
}

extension HermesBridgeUpdateActivationResultPayload {
  var updateActivationResult: HermesUpdateActivationResult {
    HermesUpdateActivationResult(
      activatedVersion: activatedVersion,
      reconnected: reconnected,
      verifiedCompatible: verifiedCompatible,
      rollbackAvailable: rollbackAvailable,
      partialStageCleaned: partialStageCleaned
    )
  }
}
