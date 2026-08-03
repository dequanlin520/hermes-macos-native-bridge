import ApplicationServices
import Foundation
import Security

public enum HermesPermissionKind: String, Codable, CaseIterable, Equatable, Sendable {
  case appSandbox
  case userSelectedFiles
  case inputMonitoring
  case accessibility
  case automation
  case screenRecording
  case fullDiskAccess
  case microphone
  case camera
  case launchAgent
  case machService
  case securityScopedBookmarks
  case authorizedFileRoots
  case notifications
  case appIntentMetadata
  case auditSigningKey
  case auditKeychain
  case auditTrustAnchor
  case auditUnsignedLegacySegments
  case auditInvalidSignatures
  case auditUnknownSigner
  case signing
  case hardenedRuntime
  case notarization
}

public enum HermesPermissionClassification: String, Codable, CaseIterable, Equatable, Sendable {
  case requiredForCore = "required-for-core"
  case requiredForEnabledFeature = "required-for-enabled-feature"
  case optional
  case unsupported
  case notApplicable = "not-applicable"
}

public enum HermesPermissionCurrentStatus: String, Codable, CaseIterable, Equatable, Sendable {
  case granted
  case denied
  case restricted
  case notDetermined = "not-determined"
  case unavailable
  case notApplicable = "not-applicable"
  case misconfigured
  case unknown
  case notRequired = "not-required"
  case featureTriggered = "feature-triggered"
  case unsupported
}

public enum HermesPermissionState: String, Codable, CaseIterable, Equatable, Sendable {
  case granted
  case denied
  case restricted
  case notDetermined
  case unavailable
  case notApplicable
  case misconfigured
  case unknown
}

public enum HermesPermissionRemediationCode: String, Codable, CaseIterable, Equatable, Sendable {
  case openAccessibilitySettings
  case openScreenRecordingSettings
  case openAutomationSettings
  case openNotificationsSettings
  case reinstallService
  case restartService
  case refreshFolderAuthorization
  case rebuildSignedApp
  case configureDeveloperID
  case notarizeRelease
  case createAuditSigningKey
  case unlockKeychain
  case exportAuditTrustAnchor
  case rotateAuditSigningKey
  case verifyAuditLog
  case configureAuditSigningAccess
  case resumeAuditKeyRotation
  case resetAuditSigningConfiguration
}

public struct HermesPermissionCheck: Codable, Equatable, Sendable {
  public let kind: HermesPermissionKind
  public let classification: HermesPermissionClassification
  public let currentStatus: HermesPermissionCurrentStatus
  public let state: HermesPermissionState
  public let blocksFirstRun: Bool
  public let capabilityOwner: String
  public let userReadableReason: String
  public let settingsDestination: String?
  public let detailCode: String
  public let remediationCode: HermesPermissionRemediationCode?

  public init(
    kind: HermesPermissionKind,
    state: HermesPermissionState,
    detailCode: String,
    classification: HermesPermissionClassification? = nil,
    currentStatus: HermesPermissionCurrentStatus? = nil,
    blocksFirstRun: Bool? = nil,
    capabilityOwner: String? = nil,
    userReadableReason: String? = nil,
    remediationCode: HermesPermissionRemediationCode? = nil
  ) {
    self.kind = kind
    let policy = HermesRC1PermissionPolicy.policy(for: kind)
    self.classification = classification ?? policy.classification
    self.currentStatus = currentStatus ?? policy.currentStatus ?? HermesPermissionCurrentStatus(state)
    self.state = state
    self.blocksFirstRun = blocksFirstRun ?? (self.classification == .requiredForCore && state.isBlocking)
    self.capabilityOwner = Self.safeDisplay(capabilityOwner ?? policy.capabilityOwner)
    self.userReadableReason = Self.safeDisplay(userReadableReason ?? policy.userReadableReason)
    self.settingsDestination = remediationCode
      .flatMap(HermesSystemSettingsRemediationURL.url(for:))?
      .absoluteString
    self.detailCode = Self.safeToken(detailCode)
    self.remediationCode = remediationCode
  }

  private static func safeToken(_ value: String) -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-")
    }
    return String((filtered.isEmpty ? "unknown" : filtered).prefix(64))
  }

  private static func safeDisplay(_ value: String) -> String {
    let filtered = value.unicodeScalars.filter { scalar in
      scalar.value >= 0x20 && scalar.value != 0x7F
        && scalar != "/" && scalar != ":" && scalar != "{" && scalar != "}"
    }
    return String(String.UnicodeScalarView(filtered)).prefixString(180)
  }
}

public struct HermesPermissionsDoctorReport: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public let generatedAt: Date
  public let checks: [HermesPermissionCheck]
  public let auditIntegrity: HermesAuditExportIntegrityEvidence?

  public init(
    schemaVersion: Int = currentSchemaVersion,
    generatedAt: Date = Date(),
    checks: [HermesPermissionCheck],
    auditIntegrity: HermesAuditExportIntegrityEvidence? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.generatedAt = generatedAt
    let byKind = Dictionary(uniqueKeysWithValues: checks.map { ($0.kind, $0) })
    self.checks = HermesPermissionKind.allCases.map {
      byKind[$0]
        ?? HermesPermissionCheck(kind: $0, state: .unknown, detailCode: "not_checked")
    }
    self.auditIntegrity = auditIntegrity
  }

  public var blockingFirstRunChecks: [HermesPermissionCheck] {
    checks.filter(\.blocksFirstRun)
  }

  public var optionalPermissionCount: Int {
    checks.filter { $0.classification == .optional || $0.classification == .requiredForEnabledFeature }.count
  }

  public var rc1ModelParity: Bool {
    let byKind = Dictionary(uniqueKeysWithValues: checks.map { ($0.kind, $0) })
    return HermesPermissionKind.allCases.allSatisfy { kind in
      guard let check = byKind[kind] else { return false }
      let policy = HermesRC1PermissionPolicy.policy(for: kind)
      return check.classification == policy.classification
        && check.blocksFirstRun == (check.classification == .requiredForCore && check.state.isBlocking)
    }
  }

  public var corePermissionGatePassed: Bool {
    blockingFirstRunChecks.isEmpty
  }
}

public struct HermesSystemSettingsRemediationURL: Equatable, Sendable {
  public static let accessibility = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
  public static let screenRecording = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
  public static let automation = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
  public static let notifications = URL(
    string: "x-apple.systempreferences:com.apple.preference.notifications")!

  public static func url(for code: HermesPermissionRemediationCode) -> URL? {
    switch code {
    case .openAccessibilitySettings:
      return accessibility
    case .openScreenRecordingSettings:
      return screenRecording
    case .openAutomationSettings:
      return automation
    case .openNotificationsSettings:
      return notifications
    case .reinstallService, .restartService, .refreshFolderAuthorization, .rebuildSignedApp,
      .configureDeveloperID, .notarizeRelease, .createAuditSigningKey, .unlockKeychain,
      .exportAuditTrustAnchor, .rotateAuditSigningKey, .verifyAuditLog,
      .configureAuditSigningAccess, .resumeAuditKeyRotation, .resetAuditSigningConfiguration:
      return nil
    }
  }
}

public struct HermesRC1PermissionPolicy: Equatable, Sendable {
  public let classification: HermesPermissionClassification
  public let currentStatus: HermesPermissionCurrentStatus?
  public let capabilityOwner: String
  public let userReadableReason: String

  public static func policy(for kind: HermesPermissionKind) -> Self {
    switch kind {
    case .inputMonitoring:
      return Self(
        classification: .unsupported,
        currentStatus: .notRequired,
        capabilityOwner: "product-scope",
        userReadableReason: "RC1 does not include keyboard monitoring or GUI Computer Use."
      )
    case .accessibility:
      return Self(
        classification: .unsupported,
        currentStatus: .notRequired,
        capabilityOwner: "product-scope",
        userReadableReason: "RC1 exposes no enabled production feature that uses Accessibility APIs."
      )
    case .automation:
      return Self(
        classification: .requiredForEnabledFeature,
        currentStatus: .featureTriggered,
        capabilityOwner: "app-intents",
        userReadableReason: "Automation is requested only when an approved Shortcut or Apple Event operation is invoked."
      )
    case .screenRecording:
      return Self(
        classification: .unsupported,
        currentStatus: .notRequired,
        capabilityOwner: "product-scope",
        userReadableReason: "RC1 does not include screen capture or screen control."
      )
    case .fullDiskAccess:
      return Self(
        classification: .unsupported,
        currentStatus: .notRequired,
        capabilityOwner: "file-authorization",
        userReadableReason: "RC1 file access uses user-selected paths and scoped authorization."
      )
    case .microphone:
      return Self(
        classification: .unsupported,
        currentStatus: .notRequired,
        capabilityOwner: "product-scope",
        userReadableReason: "RC1 does not capture microphone audio."
      )
    case .camera:
      return Self(
        classification: .unsupported,
        currentStatus: .notRequired,
        capabilityOwner: "product-scope",
        userReadableReason: "RC1 does not capture camera video."
      )
    case .notifications:
      return Self(
        classification: .optional,
        currentStatus: nil,
        capabilityOwner: "native-app",
        userReadableReason: "Notifications are optional user-facing alerts and do not gate core readiness."
      )
    case .appSandbox, .userSelectedFiles, .launchAgent, .machService,
      .securityScopedBookmarks, .authorizedFileRoots, .appIntentMetadata, .auditSigningKey,
      .auditKeychain, .auditTrustAnchor, .auditUnsignedLegacySegments, .auditInvalidSignatures,
      .auditUnknownSigner, .signing, .hardenedRuntime, .notarization:
      return Self(
        classification: .notApplicable,
        currentStatus: nil,
        capabilityOwner: "diagnostics",
        userReadableReason: "This is diagnostic configuration evidence, not a macOS privacy grant required for First Run."
      )
    }
  }
}

public struct HermesPermissionsDoctorEvidence: Equatable, Sendable {
  public let executableURL: URL?
  public let launchAgentInstalled: Bool?
  public let machServiceAvailable: Bool?
  public let authorizedRootCount: Int?
  public let staleAuthorizedRootCount: Int?
  public let securityScopedBookmarkAvailable: Bool?
  public let appIntentMetadataPresent: Bool?
  public let notificationsRelevant: Bool
  public let auditIntegrity: HermesAuditExportIntegrityEvidence?
  public let auditSigningStatus: HermesAuditSigningStatus?

  public init(
    executableURL: URL? = nil,
    launchAgentInstalled: Bool? = nil,
    machServiceAvailable: Bool? = nil,
    authorizedRootCount: Int? = nil,
    staleAuthorizedRootCount: Int? = nil,
    securityScopedBookmarkAvailable: Bool? = nil,
    appIntentMetadataPresent: Bool? = nil,
    notificationsRelevant: Bool = true,
    auditIntegrity: HermesAuditExportIntegrityEvidence? = nil,
    auditSigningStatus: HermesAuditSigningStatus? = nil
  ) {
    self.executableURL = executableURL?.standardizedFileURL
    self.launchAgentInstalled = launchAgentInstalled
    self.machServiceAvailable = machServiceAvailable
    self.authorizedRootCount = authorizedRootCount
    self.staleAuthorizedRootCount = staleAuthorizedRootCount
    self.securityScopedBookmarkAvailable = securityScopedBookmarkAvailable
    self.appIntentMetadataPresent = appIntentMetadataPresent
    self.notificationsRelevant = notificationsRelevant
    self.auditIntegrity = auditIntegrity
    self.auditSigningStatus = auditSigningStatus
  }
}

public struct HermesPermissionsDoctorDependencies: Sendable {
  public let accessibilityTrusted: @Sendable () -> Bool
  public let screenCaptureAccess: @Sendable () -> HermesPermissionState
  public let signingSummary: @Sendable (URL) -> HermesCodeSigningPermissionSummary

  public init(
    accessibilityTrusted: @escaping @Sendable () -> Bool = {
      AXIsProcessTrusted()
    },
    screenCaptureAccess: @escaping @Sendable () -> HermesPermissionState = {
      if #available(macOS 10.15, *) {
        return CGPreflightScreenCaptureAccess() ? .granted : .notDetermined
      }
      return .unavailable
    },
    signingSummary: @escaping @Sendable (URL) -> HermesCodeSigningPermissionSummary = {
      HermesCodeSigningPermissionSummary.current(url: $0)
    }
  ) {
    self.accessibilityTrusted = accessibilityTrusted
    self.screenCaptureAccess = screenCaptureAccess
    self.signingSummary = signingSummary
  }
}

public struct HermesCodeSigningPermissionSummary: Equatable, Sendable {
  public let signed: Bool
  public let appSandbox: Bool
  public let userSelectedFiles: Bool
  public let hardenedRuntime: Bool
  public let developerID: Bool
  public let notarization: HermesPermissionState

  public init(
    signed: Bool,
    appSandbox: Bool,
    userSelectedFiles: Bool,
    hardenedRuntime: Bool,
    developerID: Bool,
    notarization: HermesPermissionState = .unavailable
  ) {
    self.signed = signed
    self.appSandbox = appSandbox
    self.userSelectedFiles = userSelectedFiles
    self.hardenedRuntime = hardenedRuntime
    self.developerID = developerID
    self.notarization = notarization
  }

  public static func current(url: URL) -> HermesCodeSigningPermissionSummary {
    var staticCode: SecStaticCode?
    let createResult = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
    guard createResult == errSecSuccess, let staticCode else {
      return HermesCodeSigningPermissionSummary(
        signed: false,
        appSandbox: false,
        userSelectedFiles: false,
        hardenedRuntime: false,
        developerID: false
      )
    }
    var information: CFDictionary?
    let flags = SecCSFlags(rawValue: kSecCSSigningInformation | kSecCSRequirementInformation)
    let infoResult = SecCodeCopySigningInformation(staticCode, flags, &information)
    guard infoResult == errSecSuccess, let dictionary = information as? [String: Any] else {
      return HermesCodeSigningPermissionSummary(
        signed: false,
        appSandbox: false,
        userSelectedFiles: false,
        hardenedRuntime: false,
        developerID: false
      )
    }
    let entitlements =
      dictionary[kSecCodeInfoEntitlementsDict as String] as? [String: Any] ?? [:]
    let team = dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    let flagsValue = dictionary[kSecCodeInfoStatus as String] as? UInt32 ?? 0
    return HermesCodeSigningPermissionSummary(
      signed: true,
      appSandbox: entitlements["com.apple.security.app-sandbox"] as? Bool == true,
      userSelectedFiles: entitlements["com.apple.security.files.user-selected.read-write"] as? Bool
        == true
        || entitlements["com.apple.security.files.user-selected.read-only"] as? Bool == true,
      hardenedRuntime: flagsValue & SecCodeSignatureFlags.runtime.rawValue != 0,
      developerID: team != nil && team?.isEmpty == false,
      notarization: .unavailable
    )
  }
}

public struct HermesPermissionsDoctor: Sendable {
  private let dependencies: HermesPermissionsDoctorDependencies

  public init(
    dependencies: HermesPermissionsDoctorDependencies = HermesPermissionsDoctorDependencies()
  ) {
    self.dependencies = dependencies
  }

  public func report(evidence: HermesPermissionsDoctorEvidence) -> HermesPermissionsDoctorReport {
    let signing =
      evidence.executableURL.map { dependencies.signingSummary($0) }
      ?? HermesCodeSigningPermissionSummary(
        signed: false,
        appSandbox: false,
        userSelectedFiles: false,
        hardenedRuntime: false,
        developerID: false
      )

    let checks = [
      HermesPermissionCheck(
        kind: .appSandbox,
        state: signing.appSandbox ? .granted : .notApplicable,
        detailCode: signing.appSandbox ? "entitlement_present" : "not_sandboxed"
      ),
      HermesPermissionCheck(
        kind: .userSelectedFiles,
        state: signing.userSelectedFiles
          ? .granted : (signing.appSandbox ? .misconfigured : .notApplicable),
        detailCode: signing.userSelectedFiles ? "entitlement_present" : "entitlement_absent",
        remediationCode: signing.appSandbox && !signing.userSelectedFiles ? .rebuildSignedApp : nil
      ),
      HermesPermissionCheck(
        kind: .inputMonitoring,
        state: .notApplicable,
        detailCode: "not_required_by_rc1"
      ),
      HermesPermissionCheck(
        kind: .accessibility,
        state: .notApplicable,
        detailCode: "not_required_by_rc1"
      ),
      HermesPermissionCheck(
        kind: .automation,
        state: .notDetermined,
        detailCode: "feature_triggered_only"
      ),
      HermesPermissionCheck(
        kind: .screenRecording,
        state: .notApplicable,
        detailCode: "not_required_by_rc1"
      ),
      HermesPermissionCheck(
        kind: .fullDiskAccess,
        state: .notApplicable,
        detailCode: "not_required_by_rc1"
      ),
      HermesPermissionCheck(
        kind: .microphone,
        state: .notApplicable,
        detailCode: "not_required_by_rc1"
      ),
      HermesPermissionCheck(
        kind: .camera,
        state: .notApplicable,
        detailCode: "not_required_by_rc1"
      ),
      HermesPermissionCheck(
        kind: .launchAgent,
        state: state(for: evidence.launchAgentInstalled),
        detailCode: evidence.launchAgentInstalled == true ? "installed" : "not_visible",
        remediationCode: evidence.launchAgentInstalled == true ? nil : .reinstallService
      ),
      HermesPermissionCheck(
        kind: .machService,
        state: state(for: evidence.machServiceAvailable),
        detailCode: evidence.machServiceAvailable == true ? "available" : "unavailable",
        remediationCode: evidence.machServiceAvailable == true ? nil : .restartService
      ),
      HermesPermissionCheck(
        kind: .securityScopedBookmarks,
        state: state(for: evidence.securityScopedBookmarkAvailable),
        detailCode: evidence.securityScopedBookmarkAvailable == true ? "available" : "unavailable",
        remediationCode: evidence.securityScopedBookmarkAvailable == true
          ? nil : .refreshFolderAuthorization
      ),
      HermesPermissionCheck(
        kind: .authorizedFileRoots,
        state: authorizedRootState(
          count: evidence.authorizedRootCount,
          stale: evidence.staleAuthorizedRootCount
        ),
        detailCode: authorizedRootDetail(
          count: evidence.authorizedRootCount,
          stale: evidence.staleAuthorizedRootCount
        ),
        remediationCode: (evidence.staleAuthorizedRootCount ?? 0) > 0
          ? .refreshFolderAuthorization : nil
      ),
      HermesPermissionCheck(
        kind: .notifications,
        state: evidence.notificationsRelevant ? .unknown : .notApplicable,
        detailCode: evidence.notificationsRelevant
          ? "not_queried_without_user_action" : "not_relevant",
        remediationCode: evidence.notificationsRelevant ? .openNotificationsSettings : nil
      ),
      HermesPermissionCheck(
        kind: .appIntentMetadata,
        state: state(for: evidence.appIntentMetadataPresent),
        detailCode: evidence.appIntentMetadataPresent == true
          ? "metadata_present" : "metadata_missing",
        remediationCode: evidence.appIntentMetadataPresent == true ? nil : .rebuildSignedApp
      ),
      HermesPermissionCheck(
        kind: .auditSigningKey,
        state: evidence.auditSigningStatus?.signingAvailable == true ? .granted : .misconfigured,
        detailCode: evidence.auditSigningStatus?.state.rawValue ?? "not_configured",
        remediationCode: evidence.auditSigningStatus?.signingAvailable == true
          ? nil : .configureAuditSigningAccess
      ),
      HermesPermissionCheck(
        kind: .auditKeychain,
        state: auditKeychainState(evidence.auditSigningStatus),
        detailCode: auditKeychainDetail(evidence.auditSigningStatus),
        remediationCode: auditKeychainState(evidence.auditSigningStatus) == .granted
          ? nil : .unlockKeychain
      ),
      HermesPermissionCheck(
        kind: .auditTrustAnchor,
        state: (evidence.auditSigningStatus?.trustAnchorCount ?? 0) > 0 ? .granted : .misconfigured,
        detailCode: (evidence.auditSigningStatus?.trustAnchorCount ?? 0) > 0
          ? "anchor_present" : "anchor_missing",
        remediationCode: (evidence.auditSigningStatus?.trustAnchorCount ?? 0) > 0
          ? nil : .exportAuditTrustAnchor
      ),
      HermesPermissionCheck(
        kind: .auditUnsignedLegacySegments,
        state: evidence.auditIntegrity?.state == .verifiedUnsigned ? .restricted : .notApplicable,
        detailCode: evidence.auditIntegrity?.state == .verifiedUnsigned
          ? "unsigned_legacy_segments" : "no_unsigned_legacy_state",
        remediationCode: evidence.auditIntegrity?.state == .verifiedUnsigned
          ? .rotateAuditSigningKey : nil
      ),
      HermesPermissionCheck(
        kind: .auditInvalidSignatures,
        state: evidence.auditIntegrity?.state == .signatureInvalid ? .misconfigured : .granted,
        detailCode: evidence.auditIntegrity?.state == .signatureInvalid
          ? "invalid_signature" : "no_invalid_signature",
        remediationCode: evidence.auditIntegrity?.state == .signatureInvalid
          ? .verifyAuditLog : nil
      ),
      HermesPermissionCheck(
        kind: .auditUnknownSigner,
        state: evidence.auditIntegrity?.state == .unknownSigner ? .misconfigured : .granted,
        detailCode: evidence.auditIntegrity?.state == .unknownSigner
          ? "unknown_signer" : "known_signers_only",
        remediationCode: evidence.auditIntegrity?.state == .unknownSigner
          ? .exportAuditTrustAnchor : nil
      ),
      HermesPermissionCheck(
        kind: .signing,
        state: signing.signed ? .granted : .misconfigured,
        detailCode: signing.signed ? "signed" : "unsigned",
        remediationCode: signing.signed ? nil : .rebuildSignedApp
      ),
      HermesPermissionCheck(
        kind: .hardenedRuntime,
        state: signing.hardenedRuntime ? .granted : .misconfigured,
        detailCode: signing.hardenedRuntime ? "enabled" : "disabled",
        remediationCode: signing.hardenedRuntime ? nil : .rebuildSignedApp
      ),
      HermesPermissionCheck(
        kind: .notarization,
        state: signing.notarization,
        detailCode: signing.notarization == .granted ? "notarized" : "not_checked_locally",
        remediationCode: signing.notarization == .granted ? nil : .notarizeRelease
      ),
    ]
    return HermesPermissionsDoctorReport(checks: checks, auditIntegrity: evidence.auditIntegrity)
  }

  private func state(for value: Bool?) -> HermesPermissionState {
    guard let value else { return .unknown }
    return value ? .granted : .denied
  }

  private func authorizedRootState(count: Int?, stale: Int?) -> HermesPermissionState {
    guard let count else { return .unknown }
    if (stale ?? 0) > 0 { return .restricted }
    return count > 0 ? .granted : .notDetermined
  }

  private func authorizedRootDetail(count: Int?, stale: Int?) -> String {
    guard let count else { return "unknown" }
    if (stale ?? 0) > 0 { return "stale_authorization" }
    return count > 0 ? "roots_present" : "no_roots"
  }

  private func auditKeychainState(_ status: HermesAuditSigningStatus?) -> HermesPermissionState {
    guard let status else { return .unknown }
    switch status.state {
    case .active, .missing:
      return .granted
    case .locked:
      return .restricted
    case .duplicate, .inaccessible:
      return .misconfigured
    case .retired:
      return .notApplicable
    }
  }

  private func auditKeychainDetail(_ status: HermesAuditSigningStatus?) -> String {
    guard let status else { return "not_checked" }
    switch status.state {
    case .active, .missing:
      return "available"
    case .locked:
      return "locked"
    case .duplicate:
      return "duplicate_key"
    case .inaccessible:
      return "inaccessible"
    case .retired:
      return "retired"
    }
  }
}

extension HermesPermissionState {
  fileprivate var isBlocking: Bool {
    switch self {
    case .denied, .restricted, .notDetermined, .misconfigured, .unknown:
      return true
    case .granted, .unavailable, .notApplicable:
      return false
    }
  }
}

extension HermesPermissionCurrentStatus {
  fileprivate init(_ state: HermesPermissionState) {
    switch state {
    case .granted: self = .granted
    case .denied: self = .denied
    case .restricted: self = .restricted
    case .notDetermined: self = .notDetermined
    case .unavailable: self = .unavailable
    case .notApplicable: self = .notApplicable
    case .misconfigured: self = .misconfigured
    case .unknown: self = .unknown
    }
  }
}

extension String {
  fileprivate func prefixString(_ count: Int) -> String {
    String(prefix(count))
  }
}
