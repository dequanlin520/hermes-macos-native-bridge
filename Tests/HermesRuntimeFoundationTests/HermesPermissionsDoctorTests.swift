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
        "accessibility",
        "automation",
        "screenRecording",
        "launchAgent",
        "machService",
        "securityScopedBookmarks",
        "authorizedFileRoots",
        "notifications",
        "appIntentMetadata",
        "signing",
        "hardenedRuntime",
        "notarization",
      ])
  }

  func testAccessibilityGrantedAndDeniedMapping() {
    let granted = doctor(accessibility: true).report(evidence: .init()).check(.accessibility)
    XCTAssertEqual(granted.state, .granted)
    XCTAssertNil(granted.remediationCode)

    let denied = doctor(accessibility: false).report(evidence: .init()).check(.accessibility)
    XCTAssertEqual(denied.state, .notDetermined)
    XCTAssertEqual(denied.remediationCode, .openAccessibilitySettings)
  }

  func testScreenRecordingGrantedNotDeterminedAndUnsupportedMapping() {
    XCTAssertEqual(
      doctor(screen: .granted).report(evidence: .init()).check(.screenRecording).state,
      .granted
    )
    XCTAssertEqual(
      doctor(screen: .notDetermined).report(evidence: .init()).check(.screenRecording).state,
      .notDetermined
    )
    XCTAssertEqual(
      doctor(screen: .unavailable).report(evidence: .init()).check(.screenRecording).state,
      .unavailable
    )
  }

  func testNoPromptingChecksUseInjectedPreflightOnly() {
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
    XCTAssertGreaterThanOrEqual(calls.accessibility, 1)
    XCTAssertGreaterThanOrEqual(calls.screen, 1)
  }

  func testFixedRemediationCodesAndSystemSettingsURLs() {
    XCTAssertEqual(HermesPermissionRemediationCode.allCases.count, 10)
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
