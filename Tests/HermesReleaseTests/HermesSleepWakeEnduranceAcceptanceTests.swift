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

  func testPrepareResumeCleanupModesAreExplicit() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let main = try extractFunction("main", from: script)

    XCTAssertTrue(script.contains("usage: $SCRIPT_NAME prepare|resume|cleanup"))
    XCTAssertTrue(main.contains("prepare)"))
    XCTAssertTrue(main.contains("resume)"))
    XCTAssertTrue(main.contains("cleanup)"))
    XCTAssertTrue(main.contains("OPT_IN_REQUIRED"))
    XCTAssertTrue(main.contains("exit 2"))
  }

  func testExplicitOptInRequirementForRealPhases() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let optIn = try extractFunction("require_opt_in", from: script)
    let prepare = try extractFunction("prepare", from: script)
    let resume = try extractFunction("resume", from: script)

    XCTAssertTrue(optIn.contains("HERMES_SLEEP_WAKE_ACCEPTANCE:-"))
    XCTAssertTrue(optIn.contains("!= \"YES\""))
    XCTAssertTrue(optIn.contains("M14_003_RESULT]=OPT_IN_REQUIRED"))
    XCTAssertTrue(optIn.contains("exit 2"))
    XCTAssertTrue(prepare.contains("require_opt_in"))
    XCTAssertTrue(resume.contains("require_opt_in"))
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

  func testPrepareReturnsWaitingExitFive() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let mapper = try extractFunction("result_exit_code", from: script)
    let prepare = try extractFunction("prepare", from: script)

    XCTAssertTrue(mapper.contains("PASS) return 0"))
    XCTAssertTrue(mapper.contains("FAIL) return 1"))
    XCTAssertTrue(mapper.contains("OPT_IN_REQUIRED) return 2"))
    XCTAssertTrue(mapper.contains("BLOCKED) return 3"))
    XCTAssertTrue(mapper.contains("TIMEOUT) return 4"))
    XCTAssertTrue(mapper.contains("WAITING) return 5"))
    XCTAssertTrue(prepare.contains("RESULT[M14_003_RESULT]=WAITING"))
    XCTAssertTrue(prepare.contains("exit 5"))
    XCTAssertFalse(mapper.contains("FAIL) return 0"))
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

  func testDurableCheckpointSchemaAndUniqueRunIdentifier() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let write = try extractFunction("write_checkpoint", from: script)
    let load = try extractFunction("load_checkpoint", from: script)

    XCTAssertTrue(script.contains("CHECKPOINT_FILE=\"$RUNTIME_ROOT/checkpoint.json\""))
    XCTAssertTrue(script.contains("RUN_ID=\"${HERMES_M14_003_RUN_ID:-m14-003-$(date -u +%Y%m%dT%H%M%SZ)-$$}\""))
    XCTAssertTrue(write.contains("\"schemaVersion\": 1"))
    XCTAssertTrue(write.contains("\"runIdentifier\": run_id"))
    XCTAssertTrue(write.contains("\"runtimeRoot\": \"artifacts/m14-003/runtime\""))
    XCTAssertTrue(write.contains("\"ownedPids\""))
    XCTAssertTrue(write.contains("\"ownership\""))
    XCTAssertTrue(load.contains("value.startswith(\"/\")"))
    XCTAssertTrue(load.contains("invalid relative target"))
  }

  func testForegroundTerminalIndependence() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let prepare = try extractFunction("prepare", from: script)

    XCTAssertTrue(prepare.contains("install_recorder_launch_agent"))
    XCTAssertTrue(prepare.contains("write_checkpoint \"prepare\" \"waiting-for-manual-sleep\""))
    XCTAssertTrue(prepare.contains("trap - EXIT INT TERM HUP"))
    XCTAssertTrue(prepare.contains("exit 5"))
    XCTAssertFalse(prepare.contains("CFRunLoopRun"))
    XCTAssertFalse(prepare.contains("timeout_fail \"real sleep/wake transition was not observed\""))
  }

  func testRecorderLaunchOwnership() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let install = try extractFunction("install_recorder_launch_agent", from: script)
    let write = try extractFunction("write_sleep_wake_recorder", from: script)

    XCTAssertTrue(script.contains("RECORDER_LABEL_PREFIX=\"com.hermes.bridge.m14-003.wake-recorder\""))
    XCTAssertTrue(install.contains("\"Label\": label"))
    XCTAssertTrue(install.contains("\"ProgramArguments\": [\"/usr/bin/swift\""))
    XCTAssertTrue(install.contains("launchctl bootstrap \"$SERVICE_DOMAIN\" \"$RECORDER_PLIST\""))
    XCTAssertTrue(install.contains("RECORDER_PID=\"$(recorder_pid_from_launchctl)\""))
    XCTAssertTrue(write.contains("try? \"\\(getpid())\\n\".write"))
  }

  func testRealSleepEvidenceRequirement() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let helper = try extractFunction("write_sleep_wake_recorder", from: script)
    let verify = try extractFunction("verify_recorder_evidence", from: script)

    XCTAssertTrue(helper.contains("NSWorkspace.willSleepNotification"))
    XCTAssertTrue(helper.contains("sawSleep = true"))
    XCTAssertTrue(helper.contains("append(\"NSWorkspaceWillSleep\")"))
    XCTAssertTrue(verify.contains("\"NSWorkspaceWillSleep\" not in names"))
    XCTAssertTrue(verify.contains("will-sleep evidence required"))
  }

  func testRealWakeEvidenceRequirement() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let helper = try extractFunction("write_sleep_wake_recorder", from: script)
    let verify = try extractFunction("verify_recorder_evidence", from: script)

    XCTAssertTrue(helper.contains("NSWorkspace.didWakeNotification"))
    XCTAssertTrue(helper.contains("sawWake = true"))
    XCTAssertTrue(helper.contains("append(\"NSWorkspaceDidWake\")"))
    XCTAssertTrue(verify.contains("\"NSWorkspaceDidWake\" not in names"))
    XCTAssertTrue(verify.contains("did-wake evidence required"))
  }

  func testUptimeMonotonicEvidenceRequiredAndWallClockOnlyRejected() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let helper = try extractFunction("write_sleep_wake_recorder", from: script)
    let verify = try extractFunction("verify_recorder_evidence", from: script)

    XCTAssertTrue(helper.contains("ProcessInfo.processInfo.systemUptime"))
    XCTAssertTrue(helper.contains("monotonicUptime"))
    XCTAssertTrue(verify.contains("missing monotonic evidence"))
    XCTAssertTrue(verify.contains("wake[\"monotonicUptime\"] < sleep[\"monotonicUptime\"]"))
    XCTAssertTrue(verify.contains("wall clock may be present but cannot be sole evidence"))
    XCTAssertFalse(helper.contains("Date().timeIntervalSince"))
  }

  func testStaleCheckpointAndDuplicateResumeRejected() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let resume = try extractFunction("resume", from: script)

    XCTAssertTrue(resume.contains("checkpoint_run_id"))
    XCTAssertTrue(resume.contains("checkpoint run identifier mismatch"))
    XCTAssertTrue(resume.contains("waiting-for-manual-sleep"))
    XCTAssertTrue(resume.contains("stale or duplicate resume checkpoint"))
    XCTAssertTrue(resume.contains("write_checkpoint \"resume\" \"resuming\""))
  }

  func testDuplicateServiceDetectionAndPostWakeReconnect() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let duplicate = try extractFunction("detect_duplicate_service_instance", from: script)
    let postWake = try extractFunction("post_wake_validation", from: script)

    XCTAssertTrue(duplicate.contains("pid_for_exact_executable \"$SERVICE_EXECUTABLE\""))
    XCTAssertTrue(duplicate.contains("DUPLICATE_SERVICE_INSTANCE_FOUND]=yes"))
    XCTAssertTrue(duplicate.contains("DUPLICATE_SERVICE_INSTANCE_FOUND]=no"))
    XCTAssertTrue(postWake.contains("RESULT[SERVICE_RUNNING_AFTER_WAKE]=yes"))
    XCTAssertTrue(postWake.contains("RESULT[XPC_CONNECTED_AFTER_WAKE]=yes"))
    XCTAssertTrue(postWake.contains("RESULT[APP_RECONNECTED_AFTER_WAKE]=yes"))
    XCTAssertTrue(postWake.contains("RESULT[FINAL_RECONNECT_SUCCEEDED]=yes"))
  }

  func testExactPIDAndLabelCleanupOnly() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let cleanup = try extractFunction("cleanup_owned_state", from: script)

    XCTAssertTrue(cleanup.contains("terminate_pid \"$APP_PID\""))
    XCTAssertTrue(cleanup.contains("terminate_pid \"$RECORDER_PID\""))
    XCTAssertTrue(cleanup.contains("launchctl bootout \"$SERVICE_DOMAIN\" \"$RECORDER_PLIST\""))
    XCTAssertTrue(cleanup.contains("launchctl bootout \"$SERVICE_DOMAIN\" \"$LAUNCH_AGENT_TARGET\""))
    XCTAssertTrue(cleanup.contains("rm -f \"$RECORDER_PLIST\""))
    XCTAssertTrue(cleanup.contains("rm -f \"$LAUNCH_AGENT_TARGET\""))
    XCTAssertTrue(cleanup.contains("rm -rf \"$APP_TARGET\""))
    XCTAssertTrue(script.contains("pid_for_exact_executable \"$APP_EXECUTABLE\""))
    XCTAssertFalse(script.contains("killall"))
    XCTAssertFalse(script.contains("pkill"))
    XCTAssertFalse(script.contains("sudo "))
  }

  func testCleanupAfterTerminalLossPrepareFailureAndResumeFailure() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let cleanupCommand = try extractFunction("cleanup_command", from: script)
    let cleanup = try extractFunction("cleanup_owned_state", from: script)

    XCTAssertTrue(script.contains("trap cleanup EXIT"))
    XCTAssertTrue(script.contains("trap 'RESULT[M14_003_RESULT]=FAIL; exit 130' INT TERM HUP"))
    XCTAssertTrue(cleanup.contains("[[ -r \"$CHECKPOINT_FILE\" ]] && load_checkpoint || true"))
    XCTAssertTrue(cleanup.contains("write_checkpoint \"cleanup\" \"cleaned\""))
    XCTAssertTrue(cleanupCommand.contains("cleanup_owned_state"))
    XCTAssertTrue(cleanupCommand.contains("ENVIRONMENT_RESTORED"))
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

  func testFinalPassExitZeroAndFailNeverExitsZero() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let mapper = try extractFunction("result_exit_code", from: script)
    let resume = try extractFunction("resume", from: script)

    XCTAssertTrue(mapper.contains("PASS) return 0"))
    XCTAssertTrue(mapper.contains("FAIL) return 1"))
    XCTAssertTrue(resume.contains("result_exit_code"))
    XCTAssertTrue(resume.contains("exit $?"))
    XCTAssertFalse(mapper.contains("FAIL) return 0"))
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

    XCTAssertTrue(doc.contains("Scripts/m14_003_sleep_wake_endurance_acceptance.sh prepare"))
    XCTAssertTrue(doc.contains("Scripts/m14_003_sleep_wake_endurance_acceptance.sh resume"))
    XCTAssertTrue(doc.contains("Scripts/m14_003_sleep_wake_endurance_acceptance.sh cleanup"))
    XCTAssertTrue(doc.contains("WAITING_FOR_MANUAL_SLEEP=yes"))
    XCTAssertTrue(doc.contains("~/Applications/Hermes Bridge.app"))
    XCTAssertTrue(doc.contains("~/Library/LaunchAgents/com.hermes.bridge.plist"))
    XCTAssertTrue(doc.contains("artifacts/m14-003/runtime"))
    XCTAssertTrue(doc.contains("M14_003_RESULT=WAITING"))
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
