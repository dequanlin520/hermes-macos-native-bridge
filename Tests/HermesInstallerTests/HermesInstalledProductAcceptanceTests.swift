import Foundation
@testable import HermesBridgeServiceManager
import XCTest

final class HermesInstalledProductAcceptanceTests: XCTestCase {
  private let scriptPath = "Scripts/m11_004_installed_product_acceptance.sh"

  func testM11004ResultSchemaKeysAreStableAndOrdered() throws {
    let script = try String(contentsOfFile: scriptPath, encoding: .utf8)
    let expectedKeys = [
      "PRODUCTION_APP_BUILT",
      "ISOLATED_INSTALL_ROOT_USED",
      "APP_INSTALLED",
      "SERVICE_INSTALLED",
      "LAUNCH_CONFIGURATION_INSTALLED",
      "INSTALL_LAYOUT_VALID",
      "ACCEPTANCE_SUPPORT_INSTALLED",
      "DUPLICATE_APP_INSTALLED",
      "DUPLICATE_SERVICE_INSTALLED",
      "XPC_PROTOCOL_1_7",
      "APP_OWNS_CONCRETE_RUNTIME",
      "SERVICE_OWNS_RUNTIME",
      "INSTALLED_APP_STARTED",
      "INSTALLED_SERVICE_STARTED",
      "XPC_CONNECTION_SUCCEEDED",
      "SESSION_STARTED",
      "EVENT_RECEIVED",
      "RUNTIME_SURVIVED_APP_EXIT",
      "APP_RECONNECTED",
      "EXPLICIT_STOP_FORWARDED_ONCE",
      "SESSION_STOPPED",
      "VERSION_A_INSTALLED",
      "UPGRADE_TO_VERSION_B",
      "CONFIG_PRESERVED_ON_UPGRADE",
      "VERSION_B_ACTIVE",
      "ROLLBACK_TO_VERSION_A",
      "VERSION_A_ACTIVE_AFTER_ROLLBACK",
      "XPC_WORKED_AFTER_ROLLBACK",
      "FAILED_UPGRADE_RECOVERED",
      "PARTIAL_FILES_CLEANED",
      "UNINSTALL_SUCCEEDED",
      "APP_REMOVED",
      "SERVICE_REMOVED",
      "LAUNCH_CONFIGURATION_REMOVED",
      "DEVELOPER_PATH_EXPOSED",
      "TOKEN_EXPOSED",
      "PRIVATE_KEY_EXPOSED",
      "ACCEPTANCE_SYMBOL_EXPOSED",
      "APPLICATIONS_MODIFIED",
      "USER_LAUNCH_AGENTS_MODIFIED",
      "REAL_HERMES_HOME_MODIFIED",
      "RESIDUAL_PROCESS",
      "M11_004_RESULT",
    ]

    let renderedKeys = script.components(separatedBy: "\n").compactMap { line -> String? in
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard trimmed == "print -r -- \"$key=${RESULT[$key]}\"" else {
        return nil
      }
      return "ordered-loop"
    }

    XCTAssertEqual(renderedKeys, ["ordered-loop"])
    for key in expectedKeys {
      XCTAssertTrue(script.contains(key), key)
    }
    XCTAssertTrue(script.contains("RESULT[M11_004_RESULT]=$([[ \"$pass\" == \"yes\" ]]"))
  }

  func testIsolatedInstallationPathEnforcement() throws {
    let script = try String(contentsOfFile: scriptPath, encoding: .utf8)

    XCTAssertTrue(script.contains("INSTALL_ROOT=\"$ARTIFACT_DIR/install-root\""))
    XCTAssertTrue(script.contains("[[ \"$INSTALL_ROOT\" == \"$ROOT_DIR/artifacts/m11-004/install-root\" ]]"))
    XCTAssertTrue(script.contains("--artifact-root \"$INSTALL_ROOT\""))
    XCTAssertFalse(script.contains("sudo "))
    XCTAssertFalse(script.contains("killall"))
    XCTAssertFalse(script.contains("pkill"))
    XCTAssertFalse(script.contains("osascript"))
    XCTAssertFalse(script.contains("~/.hermes"))
  }

  func testProductionAndAcceptanceTargetSeparationIsPreserved() throws {
    let manifest = try String(contentsOfFile: "Package.swift", encoding: .utf8)
    let script = try String(contentsOfFile: scriptPath, encoding: .utf8)

    XCTAssertTrue(manifest.contains("name: \"HermesBridgeAppExecutable\""))
    XCTAssertTrue(manifest.contains("name: \"HermesBridgeAppAcceptanceHarness\""))
    XCTAssertTrue(script.contains("swift build --configuration release --product HermesBridgeApp"))
    XCTAssertTrue(script.contains("cp \"$ROOT_DIR/.build/release/HermesBridgeApp\" \"$APP_EXECUTABLE\""))
    XCTAssertFalse(script.contains("cp \"$ROOT_DIR/.build/debug/HermesBridgeAppAcceptanceHarness\" \"$APP_EXECUTABLE\""))
  }

  func testExpectedInstalledTopologyAndDuplicatePrevention() throws {
    let script = try String(contentsOfFile: scriptPath, encoding: .utf8)

    XCTAssertTrue(script.contains("$INSTALLED_APP/Contents/MacOS"))
    XCTAssertTrue(script.contains("$INSTALLED_APP/Contents/Frameworks"))
    XCTAssertTrue(script.contains("$INSTALLED_APP/Contents/XPCServices"))
    XCTAssertTrue(script.contains("$INSTALLED_APP/Contents/Library/HermesBridge"))
    XCTAssertTrue(script.contains("$INSTALLED_APP/Contents/Resources/product-version.json"))
    XCTAssertTrue(script.contains("DUPLICATE_APP_INSTALLED]=no"))
    XCTAssertTrue(script.contains("DUPLICATE_SERVICE_INSTALLED]=no"))
  }

  func testAppServiceOwnershipSeparationIsAsserted() throws {
    let script = try String(contentsOfFile: scriptPath, encoding: .utf8)

    XCTAssertTrue(script.contains("HermesRuntimeSessionManager\\("))
    XCTAssertTrue(script.contains("HermesBridgeCompositionRoot"))
    XCTAssertTrue(script.contains("APP_OWNS_CONCRETE_RUNTIME]=no"))
    XCTAssertTrue(script.contains("SERVICE_OWNS_RUNTIME]=yes"))
  }

  func testXpcRoundTripFromInstalledLayoutIsCovered() throws {
    let script = try String(contentsOfFile: scriptPath, encoding: .utf8)

    XCTAssertTrue(script.contains("/bin/launchctl bootstrap \"$SERVICE_DOMAIN\" \"$TEMP_LAUNCH_AGENT\""))
    XCTAssertTrue(script.contains("$ACCEPTANCE_HARNESS\" --hermes-m11-003-acceptance"))
    XCTAssertTrue(script.contains("XPC_PROTOCOL_1_7"))
    XCTAssertTrue(script.contains("SESSION_STARTED"))
    XCTAssertTrue(script.contains("EVENT_RECEIVED"))
  }

  func testUpgradeRollbackFailedUpgradeAndUninstallCoverage() throws {
    let script = try String(contentsOfFile: scriptPath, encoding: .utf8)

    XCTAssertTrue(script.contains("install_app_bundle_version \"m11-004-A\""))
    XCTAssertTrue(script.contains("upgrade_service_version \"m11-004-B\""))
    XCTAssertTrue(script.contains("rollback_service"))
    XCTAssertTrue(script.contains("--version \"m11-004-bad\""))
    XCTAssertTrue(script.contains("$LIFECYCLE\" uninstall"))
    XCTAssertTrue(script.contains("PARTIAL_FILES_CLEANED]=yes"))
  }

  func testExactProcessCleanupAndPrivateScanning() throws {
    let script = try String(contentsOfFile: scriptPath, encoding: .utf8)

    XCTAssertTrue(script.contains("kill -TERM \"$pid\""))
    XCTAssertTrue(script.contains("launchctl bootout \"$SERVICE_DOMAIN\" \"$TEMP_LAUNCH_AGENT\""))
    XCTAssertTrue(script.contains("DEVELOPER_PATH_EXPOSED"))
    XCTAssertTrue(script.contains("TOKEN_EXPOSED"))
    XCTAssertTrue(script.contains("PRIVATE_KEY_EXPOSED"))
    XCTAssertTrue(script.contains("ACCEPTANCE_SYMBOL_EXPOSED"))
    XCTAssertFalse(script.contains("processID"))
  }

  func testServiceManagerSupportsArtifactOwnedUpgradeRollbackAndUninstall() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("hermes-m11-004-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let layout = HermesBridgeInstallationLayout(
      homeRoot: root.appendingPathComponent("fake-home", isDirectory: true),
      label: "com.hermes.bridge.test.m11-004",
      machService: "com.hermes.bridge.test.m11-004.xpc"
    )

    XCTAssertTrue(layout.homeRoot.path.contains("hermes-m11-004-tests"))
    XCTAssertTrue(layout.applicationSupportRoot.path.hasPrefix(layout.homeRoot.path))
    XCTAssertTrue(layout.launchAgentPlist.path.hasPrefix(layout.homeRoot.path))
    XCTAssertNotEqual(layout.homeRoot, FileManager.default.homeDirectoryForCurrentUser)
  }
}
