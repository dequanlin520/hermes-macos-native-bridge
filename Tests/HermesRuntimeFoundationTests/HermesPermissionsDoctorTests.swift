import Foundation
import XCTest

@testable import HermesRuntimeFoundation

final class HermesPermissionsDoctorTests: XCTestCase {
  func testPermissionKindsAreComplete() {
    XCTAssertEqual(
      HermesPermissionKind.allCases.map(\.rawValue),
      [
        "appSandbox",
        "userSelectedFiles",
        "inputMonitoring",
        "accessibility",
        "automation",
        "screenRecording",
        "fullDiskAccess",
        "microphone",
        "camera",
        "launchAgent",
        "machService",
        "securityScopedBookmarks",
        "authorizedFileRoots",
        "notifications",
        "appIntentMetadata",
        "auditSigningKey",
        "auditKeychain",
        "auditTrustAnchor",
        "auditUnsignedLegacySegments",
        "auditInvalidSignatures",
        "auditUnknownSigner",
        "signing",
        "hardenedRuntime",
        "notarization",
      ])
  }

  func testAccessibilityIsFeatureScopedAndDoesNotBlockRC1FirstRun() {
    let accessibility = doctor(accessibility: false).report(evidence: .init()).check(.accessibility)
    XCTAssertEqual(accessibility.classification, .unsupported)
    XCTAssertEqual(accessibility.currentStatus, .notRequired)
    XCTAssertEqual(accessibility.state, .notApplicable)
    XCTAssertFalse(accessibility.blocksFirstRun)
    XCTAssertNil(accessibility.remediationCode)
  }

  func testNoCoreRCFeatureRequiresInputMonitoringScreenRecordingOrFullDiskAccess() {
    let report = doctor(screen: .notDetermined).report(evidence: .init())
    for kind in [
      HermesPermissionKind.inputMonitoring,
      .screenRecording,
      .fullDiskAccess,
    ] {
      let check = report.check(kind)
      XCTAssertEqual(check.currentStatus, .notRequired, kind.rawValue)
      XCTAssertEqual(check.state, .notApplicable, kind.rawValue)
      XCTAssertFalse(check.blocksFirstRun, kind.rawValue)
      XCTAssertNil(check.remediationCode, kind.rawValue)
    }
  }

  func testRC1PermissionModelDoesNotRunAXOrScreenPreflightsForUnsupportedCapabilities() {
    let calls = CallCounter()
    let doctor = HermesPermissionsDoctor(
      dependencies: HermesPermissionsDoctorDependencies(
        accessibilityTrusted: {
          calls.incrementAccessibility()
          return false
        },
        screenCaptureAccess: {
          calls.incrementScreen()
          return .notDetermined
        },
        signingSummary: { _ in .unsigned }
      ))
    _ = doctor.report(evidence: .init())
    XCTAssertEqual(calls.accessibility, 0)
    XCTAssertEqual(calls.screen, 0)
  }

  func testAutomationIsFeatureTriggeredAndDoesNotBlockRC1FirstRun() {
    let automation = doctor().report(evidence: .init()).check(.automation)
    XCTAssertEqual(automation.classification, .requiredForEnabledFeature)
    XCTAssertEqual(automation.currentStatus, .featureTriggered)
    XCTAssertFalse(automation.blocksFirstRun)
    XCTAssertNil(automation.remediationCode)
  }

  func testCleanUserCorePermissionGatePassesWithoutManualTCCGrants() {
    let report = doctor(accessibility: false, screen: .notDetermined).report(evidence: .init())

    XCTAssertTrue(report.corePermissionGatePassed)
    XCTAssertEqual(report.blockingFirstRunChecks.count, 0)
    XCTAssertTrue(report.rc1ModelParity)
    XCTAssertEqual(report.check(.inputMonitoring).currentStatus, .notRequired)
    XCTAssertEqual(report.check(.accessibility).currentStatus, .notRequired)
    XCTAssertEqual(report.check(.screenRecording).currentStatus, .notRequired)
    XCTAssertEqual(report.check(.fullDiskAccess).currentStatus, .notRequired)
    XCTAssertEqual(report.check(.automation).currentStatus, .featureTriggered)
  }

  func testFixedRemediationCodesAndSystemSettingsURLs() {
    XCTAssertEqual(HermesPermissionRemediationCode.allCases.count, 18)
    XCTAssertEqual(
      HermesSystemSettingsRemediationURL.url(for: .openAccessibilitySettings)?.absoluteString,
      "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )
    XCTAssertEqual(
      HermesSystemSettingsRemediationURL.url(for: .openScreenRecordingSettings)?.absoluteString,
      "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )
    XCTAssertEqual(
      HermesSystemSettingsRemediationURL.url(for: .openAutomationSettings)?.absoluteString,
      "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
    )
    XCTAssertEqual(
      HermesSystemSettingsRemediationURL.url(for: .openNotificationsSettings)?.absoluteString,
      "x-apple.systempreferences:com.apple.preference.notifications"
    )
    XCTAssertNil(HermesSystemSettingsRemediationURL.url(for: .restartService))
  }

  func testEntitlementSigningHardenedRuntimeAndNotarizationChecks() {
    let report = doctor(
      signing: HermesCodeSigningPermissionSummary(
        signed: true,
        appSandbox: true,
        userSelectedFiles: true,
        hardenedRuntime: true,
        developerID: true,
        notarization: .unavailable
      )
    ).report(evidence: .init(executableURL: URL(fileURLWithPath: "/tmp/app")))
    XCTAssertEqual(report.check(.appSandbox).state, .granted)
    XCTAssertEqual(report.check(.userSelectedFiles).state, .granted)
    XCTAssertEqual(report.check(.signing).state, .granted)
    XCTAssertEqual(report.check(.hardenedRuntime).state, .granted)
    XCTAssertEqual(report.check(.notarization).state, .unavailable)
  }

  func testLaunchAgentXPCAuthorizedRootsAndSecurityScopeChecks() {
    let report = doctor().report(
      evidence: HermesPermissionsDoctorEvidence(
        launchAgentInstalled: true,
        machServiceAvailable: false,
        authorizedRootCount: 2,
        staleAuthorizedRootCount: 1,
        securityScopedBookmarkAvailable: true,
        appIntentMetadataPresent: false
      ))
    XCTAssertEqual(report.check(.launchAgent).state, .granted)
    XCTAssertEqual(report.check(.machService).state, .denied)
    XCTAssertEqual(report.check(.authorizedFileRoots).state, .restricted)
    XCTAssertEqual(report.check(.authorizedFileRoots).remediationCode, .refreshFolderAuthorization)
    XCTAssertEqual(report.check(.securityScopedBookmarks).state, .granted)
    XCTAssertEqual(report.check(.appIntentMetadata).state, .denied)
  }

  func testAuditIntegrityEvidenceIsSafeSummaryOnly() {
    let report = doctor().report(
      evidence: HermesPermissionsDoctorEvidence(
        auditIntegrity: HermesAuditExportIntegrityEvidence(
          report: HermesAuditVerificationReport(
            state: .verifiedUnsigned,
            verifiedSegmentCount: 1,
            verifiedEventCount: 2,
            issueCodes: []
          ))))

    XCTAssertEqual(report.auditIntegrity?.state, .verifiedUnsigned)
    XCTAssertEqual(report.auditIntegrity?.verifiedEventCount, 2)
    XCTAssertFalse(String(describing: report).contains("/Users/"))
  }

  func testAuditSigningDoctorStates() throws {
    let report = doctor().report(
      evidence: HermesPermissionsDoctorEvidence(
        auditIntegrity: HermesAuditExportIntegrityEvidence(
          report: HermesAuditVerificationReport(
            state: .unknownSigner,
            verifiedSegmentCount: 1,
            verifiedEventCount: 2,
            issueCodes: [.unknownSigner]
          )),
        auditSigningStatus: HermesAuditSigningStatus(
          signingAvailable: false,
          state: .locked,
          activeSignerID: try HermesAuditSignerID(rawValue: "hasg_doctor"),
          activeFingerprintPrefix: "abc123abc123",
          trustAnchorCount: 1,
          remediationCode: "AUDIT_SIGNING_KEYCHAIN_CHECK"
        )
      ))
    XCTAssertEqual(report.check(.auditSigningKey).state, .misconfigured)
    XCTAssertEqual(report.check(.auditKeychain).state, .restricted)
    XCTAssertEqual(report.check(.auditTrustAnchor).state, .granted)
    XCTAssertEqual(report.check(.auditUnknownSigner).state, .misconfigured)
    XCTAssertFalse(String(describing: report).contains("/Users/"))
  }

  private func doctor(
    accessibility: Bool = false,
    screen: HermesPermissionState = .notDetermined,
    signing: HermesCodeSigningPermissionSummary = .unsigned
  ) -> HermesPermissionsDoctor {
    HermesPermissionsDoctor(
      dependencies: HermesPermissionsDoctorDependencies(
        accessibilityTrusted: { accessibility },
        screenCaptureAccess: { screen },
        signingSummary: { _ in signing }
      ))
  }
}

private final class CallCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var accessibilityStorage = 0
  private var screenStorage = 0

  var accessibility: Int { lock.withLock { accessibilityStorage } }
  var screen: Int { lock.withLock { screenStorage } }

  func incrementAccessibility() {
    lock.withLock { accessibilityStorage += 1 }
  }

  func incrementScreen() {
    lock.withLock { screenStorage += 1 }
  }
}

extension HermesPermissionsDoctorReport {
  fileprivate func check(_ kind: HermesPermissionKind) -> HermesPermissionCheck {
    checks.first { $0.kind == kind }!
  }
}

extension HermesCodeSigningPermissionSummary {
  fileprivate static let unsigned = HermesCodeSigningPermissionSummary(
    signed: false,
    appSandbox: false,
    userSelectedFiles: false,
    hardenedRuntime: false,
    developerID: false
  )
}
