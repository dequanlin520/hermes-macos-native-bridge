import Foundation
@testable import HermesBridgeApp
@testable import HermesBridgeAppAcceptanceSupport
import XCTest

@MainActor
final class HermesProductionAppBundleAcceptanceTests: XCTestCase {
  func testM11003ResultSchemaKeysAreStableAndOrdered() throws {
    let script = try String(
      contentsOfFile: "Scripts/m11_003_production_app_bundle_acceptance.sh",
      encoding: .utf8
    )
    let expectedKeys = [
      "APP_BUNDLE_BUILT",
      "APP_EXECUTABLE_PRESENT",
      "INFO_PLIST_VALID",
      "BUNDLE_IDENTIFIERS_VALID",
      "REQUIRED_COMPONENTS_EMBEDDED",
      "XPC_PROTOCOL_1_7",
      "APP_OWNS_CONCRETE_RUNTIME",
      "SERVICE_OWNS_RUNTIME",
      "APP_PROCESS_STARTED",
      "XPC_CONNECTION_SUCCEEDED",
      "DASHBOARD_ROUTE_AVAILABLE",
      "LOGS_ROUTE_AVAILABLE",
      "SETTINGS_ROUTE_AVAILABLE",
      "DIAGNOSTICS_ROUTE_AVAILABLE",
      "SESSION_STARTED",
      "EVENT_RECEIVED",
      "RUNTIME_SURVIVED_APP_EXIT",
      "APP_RELAUNCHED",
      "CLIENT_RECONNECTED",
      "EXPLICIT_STOP_FORWARDED_ONCE",
      "SESSION_STOPPED",
      "DEVELOPER_PATH_EXPOSED",
      "TOKEN_EXPOSED",
      "PRIVATE_KEY_EXPOSED",
      "PID_EXPOSED",
      "SIGNING_STATE",
      "APPLICATIONS_MODIFIED",
      "PERMANENT_INSTALLATION",
      "RESIDUAL_PROCESS",
      "ACCEPTANCE_SUPPORT_ISOLATED",
      "RELEASE_CONTAINS_ACCEPTANCE_CONTROLLER",
      "RELEASE_ACCEPTS_TEST_LAUNCH_ARGUMENTS",
      "RELEASE_CONTAINS_ACCEPTANCE_SENTINELS",
      "M11_003_RESULT",
    ]
    let renderedKeys = script.components(separatedBy: "\n").compactMap { line -> String? in
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard trimmed.hasPrefix("print -r -- \""),
        trimmed.contains("=${RESULT[") || trimmed.contains("=${RESULT[M11_003_RESULT]}")
      else {
        return nil
      }
      return trimmed
        .replacingOccurrences(of: "print -r -- \"", with: "")
        .components(separatedBy: "=")
        .first
    }

    XCTAssertEqual(renderedKeys.suffix(expectedKeys.count), expectedKeys)
  }

  func testAcceptanceScriptDoesNotInstallOrUseForbiddenTerminationPatterns() throws {
    let script = try String(
      contentsOfFile: "Scripts/m11_003_production_app_bundle_acceptance.sh",
      encoding: .utf8
    )

    XCTAssertFalse(script.contains("sudo "))
    XCTAssertFalse(script.contains("/Applications/"))
    XCTAssertFalse(script.contains("killall"))
    XCTAssertFalse(script.contains("pkill"))
    XCTAssertFalse(script.contains("osascript"))
    XCTAssertFalse(script.contains("~/.hermes"))
    XCTAssertTrue(script.contains("launchctl bootstrap"))
    XCTAssertTrue(script.contains("launchctl bootout"))
    XCTAssertTrue(script.contains("kill -TERM \"$APP_PID\""))
  }

  func testAcceptanceSupportParsesHarnessLaunchArguments() throws {
    XCTAssertNil(HermesM11003AcceptanceController.fromCommandLine(arguments: ["HermesBridgeApp"]))
    XCTAssertNotNil(
      HermesM11003AcceptanceController.fromCommandLine(arguments: [
        "HermesBridgeApp",
        "--hermes-m11-003-acceptance",
        "start-and-hold",
        "/tmp/state",
        "/tmp/evidence",
      ]))
  }

  func testProductionAppSourceDoesNotReferenceAcceptanceSupport() throws {
    let sourceRoot = URL(fileURLWithPath: "Sources/HermesBridgeApp", isDirectory: true)
    let fileURLs = try FileManager.default.contentsOfDirectory(
      at: sourceRoot,
      includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "swift" }

    let combinedSource = try fileURLs.map {
      try String(contentsOf: $0, encoding: .utf8)
    }.joined(separator: "\n")

    XCTAssertFalse(combinedSource.contains("HermesM11003AcceptanceController"))
    XCTAssertFalse(combinedSource.contains("HermesBridgeAppAcceptanceSupport"))
    XCTAssertFalse(combinedSource.contains("--hermes-m11-003-acceptance"))
  }

  func testAcceptanceSupportIsOwnedByDedicatedPackageTargets() throws {
    let manifest = try String(contentsOfFile: "Package.swift", encoding: .utf8)

    XCTAssertTrue(manifest.contains("name: \"HermesBridgeAppAcceptanceSupport\""))
    XCTAssertTrue(manifest.contains("name: \"HermesBridgeAppAcceptanceHarness\""))
    XCTAssertTrue(manifest.contains("name: \"HermesBridgeAppExecutable\""))
    XCTAssertTrue(manifest.contains(".define(\"HERMES_M11_003_ACCEPTANCE_SUPPORT\")"))
    XCTAssertTrue(
      manifest.contains(
        """
        name: "HermesBridgeAppExecutable",
              dependencies: ["HermesBridgeApp"]
        """
      )
    )
  }

  func testReleaseMembershipExcludesAcceptanceSourceFiles() throws {
    let project = try String(
      contentsOfFile: "Packaging/HermesBridgeApp/HermesBridgeApp.xcodeproj/project.pbxproj",
      encoding: .utf8
    )
    let manifest = try String(contentsOfFile: "Package.swift", encoding: .utf8)

    XCTAssertFalse(project.contains("HermesM11003AcceptanceController.swift"))
    XCTAssertFalse(project.contains("HermesBridgeAppAcceptanceSupport"))
    XCTAssertTrue(manifest.contains("targets: [\"HermesBridgeAppExecutable\"]"))
    XCTAssertTrue(manifest.contains("targets: [\"HermesBridgeAppAcceptanceHarness\"]"))
  }

  func testAppTargetConstructsNoConcreteRuntimeGraphTypes() throws {
    let sourceRoot = URL(fileURLWithPath: "Sources/HermesBridgeApp", isDirectory: true)
    let fileURLs = try FileManager.default.contentsOfDirectory(
      at: sourceRoot,
      includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "swift" }

    let combinedSource = try fileURLs.map {
      try String(contentsOf: $0, encoding: .utf8)
    }.joined(separator: "\n")

    for forbidden in [
      "HermesRuntimeSessionManager(",
      "HermesRuntimeEventBus(",
      "HermesRuntimeCommandAPI(",
      "HermesProcessSupervisor(",
      "HermesBackendAdapter(",
      "HermesProtocolClient(",
    ] {
      XCTAssertFalse(combinedSource.contains(forbidden), forbidden)
    }
  }
}
