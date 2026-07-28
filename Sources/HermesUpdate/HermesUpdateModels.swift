import Foundation
import HermesBridgeXPC

public enum HermesUpdateState: String, Codable, CaseIterable, Equatable, Sendable {
  case idle
  case checking
  case upToDate
  case updateAvailable
  case validating
  case awaitingConfirmation
  case staging
  case activating
  case reconnecting
  case completed
  case rollbackAvailable
  case rollingBack
  case failed
  case recoveryRequired
}

public enum HermesUpdateOperation: String, Codable, CaseIterable, Equatable, Sendable {
  case activateUpdate
  case rollback
}

public enum HermesUpdateFailureCategory: String, Codable, CaseIterable, Equatable, Sendable {
  case serviceUnavailable
  case manifestInvalid
  case productMismatch
  case versionOrderingRejected
  case compatibilityRejected
  case checksumInvalid
  case signingInvalid
  case provenanceInvalid
  case nonProductionPayload
  case acceptancePayloadRejected
  case confirmationRequired
  case activationFailed
  case rollbackFailed
  case reconnectFailed
  case verificationFailed
  case unknown
}

public enum HermesUpdateCompatibilityState: String, Codable, CaseIterable, Equatable, Sendable {
  case compatible
  case incompatible
  case unknown
}

public enum HermesUpdateSigningState: String, Codable, CaseIterable, Equatable, Sendable {
  case validDeveloperID
  case validProduction
  case unsigned
  case invalid
  case unknown
}

public enum HermesUpdateProvenanceState: String, Codable, CaseIterable, Equatable, Sendable {
  case verified
  case unavailable
  case invalid
}

public enum HermesUpdateChecksumState: String, Codable, CaseIterable, Equatable, Sendable {
  case verified
  case invalid
  case unavailable
}

public enum HermesUpdateTrustedSource: Codable, Equatable, Sendable {
  case repositoryConfigured(String)

  public var displayName: String {
    switch self {
    case .repositoryConfigured(let identifier):
      return HermesUpdateSanitizer.safeToken(identifier, fallback: "repository-configured")
    }
  }
}

public struct HermesUpdateVersion: Codable, Comparable, Hashable, Sendable,
  CustomStringConvertible
{
  public let rawValue: String
  private let parts: [Int]

  public init(_ rawValue: String) throws {
    let safe = HermesUpdateSanitizer.safeVersion(rawValue)
    guard !safe.isEmpty else {
      throw HermesUpdateValidationError(.manifestInvalid, "invalid_version")
    }
    self.rawValue = safe
    self.parts = safe.split(separator: ".").map { Int($0) ?? 0 }
  }

  public static func < (lhs: HermesUpdateVersion, rhs: HermesUpdateVersion) -> Bool {
    let count = max(lhs.parts.count, rhs.parts.count)
    for index in 0..<count {
      let left = index < lhs.parts.count ? lhs.parts[index] : 0
      let right = index < rhs.parts.count ? rhs.parts[index] : 0
      if left != right { return left < right }
    }
    return false
  }

  public var description: String { rawValue }
}

public struct HermesUpdateCurrentVersionInfo: Codable, Equatable, Sendable {
  public let appVersion: String
  public let serviceVersion: String
  public let xpcProtocolVersion: String
  public let rollbackAvailable: Bool

  public init(
    appVersion: String,
    serviceVersion: String,
    xpcProtocolVersion: String = HermesBridgeProtocolVersion.current.description,
    rollbackAvailable: Bool = false
  ) {
    self.appVersion = HermesUpdateSanitizer.safeVersion(appVersion)
    self.serviceVersion = HermesUpdateSanitizer.safeVersion(serviceVersion)
    self.xpcProtocolVersion = HermesUpdateSanitizer.safeVersion(xpcProtocolVersion)
    self.rollbackAvailable = rollbackAvailable
  }
}

public struct HermesUpdateReleaseMetadata: Codable, Equatable, Sendable {
  public let releaseID: String
  public let productIdentifier: String
  public let version: String
  public let minimumSupportedMacOS: String
  public let compatibleXPCMajor: Int
  public let compatibleXPCMinor: Int
  public let compatibility: HermesUpdateCompatibilityState
  public let checksum: HermesUpdateChecksumState
  public let signing: HermesUpdateSigningState
  public let provenance: HermesUpdateProvenanceState
  public let releaseNotesSummary: String
  public let trustedSource: HermesUpdateTrustedSource
  public let isProductionPayload: Bool
  public let containsAcceptanceContent: Bool
  public let rollbackAvailableAfterActivation: Bool

  public init(
    releaseID: String,
    productIdentifier: String = HermesUpdatePolicy.productIdentifier,
    version: String,
    minimumSupportedMacOS: String = "13.0",
    compatibleXPCMajor: Int = HermesBridgeProtocolVersion.current.major,
    compatibleXPCMinor: Int = HermesBridgeProtocolVersion.current.minor,
    compatibility: HermesUpdateCompatibilityState = .compatible,
    checksum: HermesUpdateChecksumState = .verified,
    signing: HermesUpdateSigningState = .validProduction,
    provenance: HermesUpdateProvenanceState = .verified,
    releaseNotesSummary: String = "Maintenance update.",
    trustedSource: HermesUpdateTrustedSource = .repositoryConfigured("release-policy"),
    isProductionPayload: Bool = true,
    containsAcceptanceContent: Bool = false,
    rollbackAvailableAfterActivation: Bool = true
  ) {
    self.releaseID = HermesUpdateSanitizer.safeToken(releaseID, fallback: "release")
    self.productIdentifier = HermesUpdateSanitizer.safeToken(productIdentifier, fallback: "unknown")
    self.version = HermesUpdateSanitizer.safeVersion(version)
    self.minimumSupportedMacOS = HermesUpdateSanitizer.safeVersion(minimumSupportedMacOS)
    self.compatibleXPCMajor = max(0, compatibleXPCMajor)
    self.compatibleXPCMinor = max(0, compatibleXPCMinor)
    self.compatibility = compatibility
    self.checksum = checksum
    self.signing = signing
    self.provenance = provenance
    self.releaseNotesSummary = HermesUpdateSanitizer.safeText(releaseNotesSummary)
    self.trustedSource = trustedSource
    self.isProductionPayload = isProductionPayload
    self.containsAcceptanceContent = containsAcceptanceContent
    self.rollbackAvailableAfterActivation = rollbackAvailableAfterActivation
  }

  public var releaseVersion: HermesUpdateVersion {
    get throws { try HermesUpdateVersion(version) }
  }
}

public struct HermesUpdateSnapshot: Equatable, Sendable {
  public let state: HermesUpdateState
  public let current: HermesUpdateCurrentVersionInfo
  public let availableRelease: HermesUpdateReleaseMetadata?
  public let validatedRelease: HermesUpdateReleaseMetadata?
  public let confirmation: HermesUpdateConfirmation?
  public let failure: HermesUpdateFailure?
  public let message: String

  public init(
    state: HermesUpdateState = .idle,
    current: HermesUpdateCurrentVersionInfo = HermesUpdateCurrentVersionInfo(
      appVersion: "unknown",
      serviceVersion: "unknown"
    ),
    availableRelease: HermesUpdateReleaseMetadata? = nil,
    validatedRelease: HermesUpdateReleaseMetadata? = nil,
    confirmation: HermesUpdateConfirmation? = nil,
    failure: HermesUpdateFailure? = nil,
    message: String = "Update Center is idle."
  ) {
    self.state = state
    self.current = current
    self.availableRelease = availableRelease
    self.validatedRelease = validatedRelease
    self.confirmation = confirmation
    self.failure = failure
    self.message = HermesUpdateSanitizer.safeText(message)
  }
}

public struct HermesUpdateConfirmation: Codable, Equatable, Sendable {
  public let operation: HermesUpdateOperation
  public let currentVersion: String
  public let targetVersion: String
  public let expectedReconnectBehavior: String
  public let rollbackAvailable: Bool

  public init(
    operation: HermesUpdateOperation,
    currentVersion: String,
    targetVersion: String,
    expectedReconnectBehavior: String = "Bridge Service restarts and the app reconnects after activation.",
    rollbackAvailable: Bool
  ) {
    self.operation = operation
    self.currentVersion = HermesUpdateSanitizer.safeVersion(currentVersion)
    self.targetVersion = HermesUpdateSanitizer.safeVersion(targetVersion)
    self.expectedReconnectBehavior = HermesUpdateSanitizer.safeText(expectedReconnectBehavior)
    self.rollbackAvailable = rollbackAvailable
  }
}

public struct HermesUpdateFailure: Codable, Equatable, Sendable {
  public let category: HermesUpdateFailureCategory
  public let safeMessage: String

  public init(category: HermesUpdateFailureCategory, safeMessage: String) {
    self.category = category
    self.safeMessage = HermesUpdateSanitizer.safeText(safeMessage)
  }
}

public struct HermesUpdateValidationReport: Codable, Equatable, Sendable {
  public let manifestValidated: Bool
  public let productIdentifierValidated: Bool
  public let versionOrderingValidated: Bool
  public let appServiceCompatibilityValidated: Bool
  public let xpcCompatibilityValidated: Bool
  public let checksumValidated: Bool
  public let signingStateValidated: Bool
  public let provenanceValidated: Bool
  public let productionPayloadValidated: Bool
  public let acceptancePayloadRejected: Bool

  public init(
    manifestValidated: Bool = true,
    productIdentifierValidated: Bool = true,
    versionOrderingValidated: Bool = true,
    appServiceCompatibilityValidated: Bool = true,
    xpcCompatibilityValidated: Bool = true,
    checksumValidated: Bool = true,
    signingStateValidated: Bool = true,
    provenanceValidated: Bool = true,
    productionPayloadValidated: Bool = true,
    acceptancePayloadRejected: Bool = true
  ) {
    self.manifestValidated = manifestValidated
    self.productIdentifierValidated = productIdentifierValidated
    self.versionOrderingValidated = versionOrderingValidated
    self.appServiceCompatibilityValidated = appServiceCompatibilityValidated
    self.xpcCompatibilityValidated = xpcCompatibilityValidated
    self.checksumValidated = checksumValidated
    self.signingStateValidated = signingStateValidated
    self.provenanceValidated = provenanceValidated
    self.productionPayloadValidated = productionPayloadValidated
    self.acceptancePayloadRejected = acceptancePayloadRejected
  }
}

public struct HermesUpdateActivationResult: Codable, Equatable, Sendable {
  public let activatedVersion: String
  public let reconnected: Bool
  public let verifiedCompatible: Bool
  public let rollbackAvailable: Bool
  public let partialStageCleaned: Bool

  public init(
    activatedVersion: String,
    reconnected: Bool = true,
    verifiedCompatible: Bool = true,
    rollbackAvailable: Bool = true,
    partialStageCleaned: Bool = true
  ) {
    self.activatedVersion = HermesUpdateSanitizer.safeVersion(activatedVersion)
    self.reconnected = reconnected
    self.verifiedCompatible = verifiedCompatible
    self.rollbackAvailable = rollbackAvailable
    self.partialStageCleaned = partialStageCleaned
  }
}

public typealias HermesUpdateRollbackResult = HermesUpdateActivationResult

public enum HermesUpdatePolicy {
  public static let productIdentifier = "com.hermes.bridge"

  public static func validate(
    release: HermesUpdateReleaseMetadata,
    current: HermesUpdateCurrentVersionInfo
  ) throws -> HermesUpdateValidationReport {
    guard !release.releaseID.isEmpty, !release.version.isEmpty else {
      throw HermesUpdateValidationError(.manifestInvalid, "manifest_invalid")
    }
    guard release.productIdentifier == productIdentifier else {
      throw HermesUpdateValidationError(.productMismatch, "product_mismatch")
    }
    let currentVersion = try HermesUpdateVersion(current.serviceVersion)
    let targetVersion = try release.releaseVersion
    guard targetVersion > currentVersion else {
      throw HermesUpdateValidationError(.versionOrderingRejected, "version_ordering_rejected")
    }
    guard release.compatibility == .compatible else {
      throw HermesUpdateValidationError(.compatibilityRejected, "compatibility_rejected")
    }
    guard release.compatibleXPCMajor == HermesBridgeProtocolVersion.current.major else {
      throw HermesUpdateValidationError(.compatibilityRejected, "xpc_major_incompatible")
    }
    guard release.checksum == .verified else {
      throw HermesUpdateValidationError(.checksumInvalid, "checksum_invalid")
    }
    guard release.signing == .validProduction || release.signing == .validDeveloperID else {
      throw HermesUpdateValidationError(.signingInvalid, "signing_invalid")
    }
    guard release.provenance != .invalid else {
      throw HermesUpdateValidationError(.provenanceInvalid, "provenance_invalid")
    }
    guard release.isProductionPayload else {
      throw HermesUpdateValidationError(.nonProductionPayload, "non_production_payload")
    }
    guard !release.containsAcceptanceContent else {
      throw HermesUpdateValidationError(.acceptancePayloadRejected, "acceptance_payload_rejected")
    }
    return HermesUpdateValidationReport()
  }
}

public struct HermesUpdateValidationError: Error, Equatable, Sendable {
  public let category: HermesUpdateFailureCategory
  public let reasonCode: String

  public init(_ category: HermesUpdateFailureCategory, _ reasonCode: String) {
    self.category = category
    self.reasonCode = HermesUpdateSanitizer.safeToken(reasonCode, fallback: "validation_failed")
  }
}

public enum HermesUpdateSanitizer {
  public static func safeToken(_ value: String, fallback: String = "unknown") -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-")
    }
    return String((filtered.isEmpty ? fallback : filtered).prefix(96))
  }

  public static func safeVersion(_ value: String) -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isNumber || $0 == ".")
    }
    return String((filtered.isEmpty ? "unknown" : filtered).prefix(32))
  }

  public static func safeText(_ value: String) -> String {
    var output = String(value.prefix(240))
    let patterns = [
      (#"(?i)\b(token|password|credential|secret|private[_ -]?key|api[_ -]?key)\s*[:=]\s*[^,\s]+"#, "$1=<redacted>"),
      (#"(?i)\b(bearer)\s+[A-Za-z0-9._~+/\-=]+"#, "$1 <redacted>"),
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
