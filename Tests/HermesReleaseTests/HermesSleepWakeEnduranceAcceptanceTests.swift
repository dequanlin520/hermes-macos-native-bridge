import Foundation
import XCTest

final class HermesSleepWakeEnduranceAcceptanceTests: XCTestCase {
  private var root: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private func read(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }

  func testExplicitOptInRequirement() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")

    XCTAssertTrue(script.contains("HERMES_SLEEP_WAKE_ACCEPTANCE:-"))
    XCTAssertTrue(script.contains("!= \"YES\""))
    XCTAssertTrue(script.contains("M14_003_RESULT]=OPT_IN_REQUIRED"))
    XCTAssertTrue(script.contains("exit 2"))
    XCTAssertTrue(script.contains("opt-in required"))
  }

  func testNoAutomaticSleepCommandOrGuiAutomation() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")

    XCTAssertFalse(script.contains("pmset"))
    XCTAssertFalse(script.contains("sleepnow"))
    XCTAssertFalse(script.contains("osascript"))
    XCTAssertFalse(script.contains("CGEvent"))
    XCTAssertTrue(script.contains("Manual action required: put this Mac to sleep"))
    XCTAssertTrue(script.contains("WAITING_FOR_MANUAL_SLEEP=yes"))
  }

  func testExactlyFivePreSleepRestartCycles() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let cycles = try extractFunction("perform_pre_sleep_restart_cycles", from: script)

    XCTAssertTrue(script.contains("RESTART_CYCLES_EXPECTED=5"))
    XCTAssertTrue(script.contains("PRE_SLEEP_RESTART_CYCLES_EXPECTED \"$RESTART_CYCLES_EXPECTED\""))
    XCTAssertTrue(cycles.contains("for cycle in {1..5}; do"))
    XCTAssertTrue(cycles.contains("RESULT[PRE_SLEEP_RESTART_CYCLES_PASSED]=\"$cycle\""))
    XCTAssertFalse(cycles.contains("{1..4}"))
    XCTAssertFalse(cycles.contains("{1..6}"))
  }

  func testRestartTimeoutHandling() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let wait = try extractFunction("wait_for_service_pid", from: script)
    let restart = try extractFunction("controlled_service_restart", from: script)

    XCTAssertTrue(wait.contains("local deadline=$(( $(date +%s) + 20 ))"))
    XCTAssertTrue(wait.contains("return 1"))
    XCTAssertTrue(restart.contains("wait_for_service_pid"))
    XCTAssertTrue(script.contains("perform_pre_sleep_restart_cycles || fail"))
    XCTAssertTrue(script.contains("TIMEOUT) return 4"))
  }

  func testServiceOwnershipBoundary() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let scan = try extractFunction("scan_runtime_ownership", from: script)

    XCTAssertTrue(scan.contains("Sources/HermesBridgeApp"))
    XCTAssertTrue(scan.contains("Sources/HermesBridgeService"))
    XCTAssertTrue(scan.contains("HermesBridgeCompositionRoot"))
    XCTAssertTrue(scan.contains("RESULT[APP_OWNS_RUNTIME_AFTER_WAKE]=no"))
    XCTAssertTrue(scan.contains("RESULT[SERVICE_OWNS_RUNTIME_AFTER_WAKE]=yes"))
  }

  func testAppExitLeavesServiceRunningAndRelaunchReconnects() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")

    XCTAssertTrue(script.contains("terminate_pid \"$APP_PID\""))
    XCTAssertTrue(script.contains("service_pid_from_launchctl"))
    XCTAssertTrue(script.contains("RESULT[APP_EXIT_LEFT_SERVICE_RUNNING]=yes"))
    XCTAssertTrue(script.contains("RESULT[APP_RELAUNCHED_BEFORE_SLEEP]=yes"))
    XCTAssertTrue(script.contains("RESULT[PRE_SLEEP_RECONNECT_SUCCEEDED]=yes"))
  }

  func testRealSleepEvidenceRequirement() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let helper = try extractFunction("write_sleep_wake_helper", from: script)

    XCTAssertTrue(helper.contains("NSWorkspace.willSleepNotification"))
    XCTAssertTrue(helper.contains("sawSleep = true"))
    XCTAssertTrue(helper.contains("REAL_SLEEP_DETECTED=\\(sawSleep ? \"yes\" : \"no\")"))
    XCTAssertTrue(script.contains("grep -q '^REAL_SLEEP_DETECTED=yes$'"))
  }

  func testRealWakeEvidenceRequirement() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let helper = try extractFunction("write_sleep_wake_helper", from: script)

    XCTAssertTrue(helper.contains("NSWorkspace.didWakeNotification"))
    XCTAssertTrue(helper.contains("sawWake = true"))
    XCTAssertTrue(helper.contains("REAL_WAKE_DETECTED=\\(sawWake ? \"yes\" : \"no\")"))
    XCTAssertTrue(script.contains("grep -q '^REAL_WAKE_DETECTED=yes$'"))
  }

  func testWallClockOnlyDetectionIsProhibited() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let helper = try extractFunction("write_sleep_wake_helper", from: script)

    XCTAssertTrue(helper.contains("ProcessInfo.processInfo.systemUptime"))
    XCTAssertTrue(helper.contains("sleepToWakeUptime"))
    XCTAssertTrue(helper.contains("NSWorkspace.shared.notificationCenter"))
    XCTAssertFalse(helper.contains("Date().timeIntervalSince"))
  }

  func testWakeTimeoutSemantics() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let timeout = try extractFunction("timeout_fail", from: script)
    let wait = try extractFunction("wait_for_real_sleep_wake", from: script)

    XCTAssertTrue(script.contains("WAKE_TIMEOUT_SECONDS"))
    XCTAssertTrue(timeout.contains("RESULT[WAKE_TIMEOUT_OCCURRED]=yes"))
    XCTAssertTrue(timeout.contains("RESULT[M14_003_RESULT]=TIMEOUT"))
    XCTAssertTrue(timeout.contains("exit 4"))
    XCTAssertTrue(wait.contains("timeout_fail \"real sleep/wake transition was not observed\""))
  }

  func testDuplicateServiceDetection() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let duplicate = try extractFunction("detect_duplicate_service_instance", from: script)

    XCTAssertTrue(duplicate.contains("pid_for_exact_executable \"$SERVICE_EXECUTABLE\""))
    XCTAssertTrue(duplicate.contains("DUPLICATE_SERVICE_INSTANCE_FOUND]=yes"))
    XCTAssertTrue(duplicate.contains("DUPLICATE_SERVICE_INSTANCE_FOUND]=no"))
    XCTAssertTrue(script.contains("detect_duplicate_service_instance || return 1"))
  }

  func testPostWakeReconnect() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let postWake = try extractFunction("post_wake_validation", from: script)

    XCTAssertTrue(postWake.contains("launchctl print \"$SERVICE_DOMAIN/$LABEL\""))
    XCTAssertTrue(postWake.contains("RESULT[SERVICE_RUNNING_AFTER_WAKE]=yes"))
    XCTAssertTrue(postWake.contains("RESULT[XPC_CONNECTED_AFTER_WAKE]=yes"))
    XCTAssertTrue(postWake.contains("RESULT[APP_RECONNECTED_AFTER_WAKE]=yes"))
    XCTAssertTrue(postWake.contains("RESULT[FINAL_RECONNECT_SUCCEEDED]=yes"))
  }

  func testExactPIDAndLabelCleanup() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let cleanup = try extractFunction("cleanup", from: script)

    XCTAssertTrue(cleanup.contains("terminate_pid \"$APP_PID\""))
    XCTAssertTrue(cleanup.contains("launchctl bootout \"$SERVICE_DOMAIN\" \"$LAUNCH_AGENT_TARGET\""))
    XCTAssertTrue(cleanup.contains("rm -f \"$LAUNCH_AGENT_TARGET\""))
    XCTAssertTrue(cleanup.contains("rm -rf \"$APP_TARGET\""))
    XCTAssertTrue(script.contains("pid_for_exact_executable \"$APP_EXECUTABLE\""))
    XCTAssertFalse(script.contains("killall"))
    XCTAssertFalse(script.contains("pkill"))
    XCTAssertFalse(script.contains("sudo "))
  }

  func testInterruptionCleanup() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")

    XCTAssertTrue(script.contains("trap cleanup EXIT"))
    XCTAssertTrue(script.contains("trap 'RESULT[M14_003_RESULT]=FAIL; exit 130' INT TERM HUP"))
    XCTAssertTrue(script.contains("APP_INSTALLED_BY_RUN"))
    XCTAssertTrue(script.contains("LAUNCH_AGENT_INSTALLED_BY_RUN"))
    XCTAssertTrue(script.contains("SERVICE_BOOTSTRAPPED_BY_RUN"))
  }

  func testRealHermesHomeIntegrity() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let snapshot = try extractFunction("write_real_home_integrity_snapshot", from: script)
    let compare = try extractFunction("set_real_home_modified_result", from: script)

    XCTAssertTrue(script.contains("REAL_HERMES_HOME=\"$HOME/.hermes\""))
    XCTAssertTrue(snapshot.contains("os.lstat(path)"))
    XCTAssertTrue(snapshot.contains("os.walk(root, followlinks=False)"))
    XCTAssertFalse(snapshot.contains("read_text"))
    XCTAssertFalse(snapshot.contains("read_bytes"))
    XCTAssertFalse(script.contains("rm -rf \"$REAL_HERMES_HOME\""))
    XCTAssertTrue(compare.contains("RESULT[REAL_HERMES_HOME_MODIFIED]=yes"))
    XCTAssertTrue(compare.contains("RESULT[REAL_HERMES_HOME_MODIFIED]=no"))
  }

  func testExitCodeMapping() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let mapper = try extractFunction("result_exit_code", from: script)

    XCTAssertTrue(mapper.contains("PASS) return 0"))
    XCTAssertTrue(mapper.contains("FAIL) return 1"))
    XCTAssertTrue(mapper.contains("OPT_IN_REQUIRED) return 2"))
    XCTAssertTrue(mapper.contains("BLOCKED) return 3"))
    XCTAssertTrue(mapper.contains("TIMEOUT) return 4"))
    XCTAssertFalse(mapper.contains("FAIL) return 0"))
    XCTAssertFalse(mapper.contains("BLOCKED) return 0"))
    XCTAssertFalse(mapper.contains("TIMEOUT) return 0"))
  }

  func testDuplicateAndMissingResultKeyRejection() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let keys = try extractOrderedKeys(from: script)
    let required = [
      "EXPLICIT_OPT_IN_CONFIRMED",
      "USER_SCOPE_ONLY",
      "COLLISION_CHECK_PASSED",
      "RELEASE_APP_BUILT",
      "APP_INSTALLED",
      "LAUNCH_AGENT_INSTALLED",
      "INITIAL_XPC_CONNECTED",
      "PRE_SLEEP_RESTART_CYCLES_EXPECTED",
      "PRE_SLEEP_RESTART_CYCLES_PASSED",
      "APP_EXIT_LEFT_SERVICE_RUNNING",
      "APP_RELAUNCHED_BEFORE_SLEEP",
      "PRE_SLEEP_RECONNECT_SUCCEEDED",
      "WAITING_FOR_MANUAL_SLEEP",
      "REAL_SLEEP_DETECTED",
      "REAL_WAKE_DETECTED",
      "WAKE_TIMEOUT_OCCURRED",
      "SERVICE_RUNNING_AFTER_WAKE",
      "XPC_CONNECTED_AFTER_WAKE",
      "APP_RECONNECTED_AFTER_WAKE",
      "SERVICE_OWNS_RUNTIME_AFTER_WAKE",
      "APP_OWNS_RUNTIME_AFTER_WAKE",
      "DUPLICATE_SERVICE_INSTANCE_FOUND",
      "FINAL_SERVICE_RESTARTED",
      "FINAL_RECONNECT_SUCCEEDED",
      "HERMES_AGENT_STATUS",
      "AGENT_DEPENDENT_CHECK",
      "SUDO_USED",
      "BROAD_PROCESS_KILL_USED",
      "REAL_HERMES_HOME_MODIFIED",
      "APP_TARGET_CLEANED",
      "LAUNCH_AGENT_TARGET_CLEANED",
      "ACCEPTANCE_PROCESS_REMAINING",
      "ENVIRONMENT_RESTORED",
      "GENERATED_ARTIFACT_TRACKED_BY_GIT",
      "M14_003_RESULT",
    ]

    XCTAssertEqual(keys, required)
    XCTAssertEqual(Set(keys).count, keys.count)
    XCTAssertTrue(script.contains("Duplicate result key"))
    XCTAssertTrue(script.contains("Missing result key"))
    XCTAssertTrue(script.contains("Unexpected result key"))
  }

  func testDocumentationExists() throws {
    let doc = try read("Docs/Release/M14_003SleepWakeEnduranceAcceptance.md")

    XCTAssertTrue(doc.contains("HERMES_SLEEP_WAKE_ACCEPTANCE=YES"))
    XCTAssertTrue(doc.contains("WAITING_FOR_MANUAL_SLEEP=yes"))
    XCTAssertTrue(doc.contains("~/Applications/Hermes Bridge.app"))
    XCTAssertTrue(doc.contains("~/Library/LaunchAgents/com.hermes.bridge.plist"))
    XCTAssertTrue(doc.contains("artifacts/m14-003/runtime"))
  }

  private func extractOrderedKeys(from script: String) throws -> [String] {
    let pattern = #"ORDERED_KEYS=\(\n(?<body>.*?)\n\)"#
    let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
    let range = NSRange(script.startIndex..., in: script)
    let match = try XCTUnwrap(regex.firstMatch(in: script, range: range))
    let bodyRange = try XCTUnwrap(Range(match.range(withName: "body"), in: script))
    return script[bodyRange]
      .split { $0 == " " || $0 == "\n" || $0 == "\t" }
      .map(String.init)
  }

  private func extractFunction(_ name: String, from script: String) throws -> String {
    let marker = "\(name)() {"
    guard let start = script.range(of: marker)?.lowerBound else {
      XCTFail("Missing function \(name)")
      return ""
    }
    var depth = 0
    var sawOpeningBrace = false
    var index = start
    while index < script.endIndex {
      let character = script[index]
      if character == "{" {
        depth += 1
        sawOpeningBrace = true
      } else if character == "}" {
        depth -= 1
        if sawOpeningBrace && depth == 0 {
          let end = script.index(after: index)
          return String(script[start..<end])
        }
      }
      index = script.index(after: index)
    }
    XCTFail("Unterminated function \(name)")
    return ""
  }
}
