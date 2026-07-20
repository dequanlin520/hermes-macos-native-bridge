import ApplicationServices
import Foundation
import Security

public enum HermesPermissionKind: String, Codable, CaseIterable, Equatable, Sendable {
  case appSandbox
  case userSelectedFiles
  case accessibility
  case automation
  case screenRecording
  case launchAgent
  case machService
  case securityScopedBookmarks
  case authorizedFileRoots
  case notifications
  case appIntentMetadata
  case signing
  case hardenedRuntime
  case notarization
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
}

public struct HermesPermissionCheck: Codable, Equatable, Sendable {
  public let kind: HermesPermissionKind
  public let state: HermesPermissionState
  public let detailCode: String
  public let remediationCode: HermesPermissionRemediationCode?

  public init(
    kind: HermesPermissionKind,
    state: HermesPermissionState,
    detailCode: String,
    remediationCode: HermesPermissionRemediationCode? = nil
  ) {
    self.kind = kind
    self.state = state
    self.detailCode = Self.safeToken(detailCode)
    self.remediationCode = remediationCode
  }

  private static func safeToken(_ value: String) -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-")
    }
    return String((filtered.isEmpty ? "unknown" : filtered).prefix(64))
  }
}

public struct HermesPermissionsDoctorReport: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public let generatedAt: Date
  public let checks: [HermesPermissionCheck]

  public init(
    schemaVersion: Int = currentSchemaVersion,
    generatedAt: Date = Date(),
    checks: [HermesPermissionCheck]
  ) {
    self.schemaVersion = schemaVersion
    self.generatedAt = generatedAt
    let byKind = Dictionary(uniqueKeysWithValues: checks.map { ($0.kind, $0) })
    self.checks = HermesPermissionKind.allCases.map {
      byKind[$0]
        ?? HermesPermissionCheck(kind: $0, state: .unknown, detailCode: "not_checked")
    }
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
      .configureDeveloperID, .notarizeRelease:
      return nil
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

  public init(
    executableURL: URL? = nil,
    launchAgentInstalled: Bool? = nil,
    machServiceAvailable: Bool? = nil,
    authorizedRootCount: Int? = nil,
    staleAuthorizedRootCount: Int? = nil,
    securityScopedBookmarkAvailable: Bool? = nil,
    appIntentMetadataPresent: Bool? = nil,
    notificationsRelevant: Bool = true
  ) {
    self.executableURL = executableURL?.standardizedFileURL
    self.launchAgentInstalled = launchAgentInstalled
    self.machServiceAvailable = machServiceAvailable
    self.authorizedRootCount = authorizedRootCount
    self.staleAuthorizedRootCount = staleAuthorizedRootCount
    self.securityScopedBookmarkAvailable = securityScopedBookmarkAvailable
    self.appIntentMetadataPresent = appIntentMetadataPresent
    self.notificationsRelevant = notificationsRelevant
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
        kind: .accessibility,
        state: dependencies.accessibilityTrusted() ? .granted : .notDetermined,
        detailCode: "preflight_only",
        remediationCode: dependencies.accessibilityTrusted() ? nil : .openAccessibilitySettings
      ),
      HermesPermissionCheck(
        kind: .automation,
        state: .notDetermined,
        detailCode: "no_nonprompting_public_probe",
        remediationCode: .openAutomationSettings
      ),
      HermesPermissionCheck(
        kind: .screenRecording,
        state: dependencies.screenCaptureAccess(),
        detailCode: "preflight_only",
        remediationCode: dependencies.screenCaptureAccess() == .granted
          ? nil : .openScreenRecordingSettings
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
    return HermesPermissionsDoctorReport(checks: checks)
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
}
