import Foundation
import XCTest

final class M5004SandboxedBookmarkLifecycleTests: XCTestCase {
  func testAppEntitlementPolicyIsSandboxedUserSelectedOnly() throws {
    let url = URL(fileURLWithPath: "Packaging/Entitlements/HermesBridgeApp.entitlements")
    let data = try Data(contentsOf: url)
    let plist = try XCTUnwrap(
      PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        as? [String: Any]
    )

    XCTAssertEqual(plist["com.apple.security.app-sandbox"] as? Bool, true)
    XCTAssertEqual(plist["com.apple.security.files.user-selected.read-write"] as? Bool, true)
    XCTAssertNil(plist["com.apple.security.files.downloads.read-write"])
    XCTAssertNil(plist["com.apple.security.files.documents.read-write"])
    XCTAssertNil(plist["com.apple.security.files.home-relative-path.read-write"])
    XCTAssertNil(plist["com.apple.security.files.absolute-path.read-write"])
    XCTAssertNil(plist["com.apple.security.temporary-exception.files.absolute-path.read-write"])
    XCTAssertNil(plist["com.apple.security.get-task-allow"])
    XCTAssertNil(plist["com.apple.security.cs.disable-library-validation"])
    XCTAssertNil(plist["com.apple.security.automation.apple-events"])
    XCTAssertNil(plist["com.apple.security.application-groups"])
  }

  func testSandboxIntegrationScriptHasRequiredResultContractAndBoundaries() throws {
    let source = try script()
    let requiredKeys = [
      "SANDBOXED_APP_BUILD_PASSED",
      "APP_SANDBOX_ENTITLEMENT_PRESENT",
      "USER_SELECTED_RW_ENTITLEMENT_PRESENT",
      "BROAD_FILESYSTEM_ENTITLEMENT_PRESENT",
      "APP_INTENTS_METADATA_PRESENT",
      "SECURITY_SCOPED_BOOKMARK_CREATED",
      "BOOKMARK_PERSISTED_OVER_XPC",
      "APP_RESTART_RESOLUTION_PASSED",
      "SERVICE_RESTART_RESOLUTION_PASSED",
      "SERVICE_SECURITY_SCOPE_STARTED",
      "AUTHORIZED_ROOT_EVENT_OBSERVED",
      "OUTSIDE_ROOT_EVENT_OBSERVED",
      "BOOKMARK_BYTES_EXPOSED",
      "RESIDUAL_APP_PROCESS",
      "RESIDUAL_MONITOR_PROCESS",
      "M5_004_RESULT",
    ]

    XCTAssertTrue(source.contains("--manual-sandbox-bookmark-validation"))
    XCTAssertTrue(source.contains("artifacts/m5-004"))
    XCTAssertTrue(source.contains("HermesBridgeApp.entitlements"))
    XCTAssertTrue(source.contains("codesign --force --sign - --entitlements"))
    XCTAssertFalse(source.contains("Developer ID Application"))
    XCTAssertFalse(source.contains("/Users/jerrysmith"))
    XCTAssertFalse(source.contains("NSHomeDirectory()"))
    for key in requiredKeys {
      XCTAssertTrue(source.contains(key), key)
    }
  }

  func testScriptAvoidsBroadPathInputAndPersonalFolderAutomation() throws {
    let source = try script()

    XCTAssertFalse(source.contains("registerAuthorizedRootPath"))
    XCTAssertFalse(source.contains("TextField("))
    XCTAssertFalse(source.contains("Downloads"))
    XCTAssertFalse(source.contains("Documents"))
    XCTAssertFalse(source.contains("Desktop"))
    XCTAssertTrue(source.contains("selected-root"))
    XCTAssertTrue(source.contains("outside-root"))
  }

  private func script() throws -> String {
    try String(
      contentsOfFile: "Scripts/integration/m5-004-sandboxed-bookmark-lifecycle.zsh",
      encoding: .utf8
    )
  }
}
