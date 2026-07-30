import Foundation
import XCTest

final class HermesSleepWakeEnduranceAcceptanceTests: XCTestCase {
  private let reservedZshNames = [
    "status",
    "pipestatus",
    "signals",
    "commands",
    "functions",
    "path",
    "match",
    "reply",
  ]

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

  func testZshReservedVariableStatusIsProhibited() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    XCTAssertFalse(try zshReservedNameViolations(in: script).contains { $0.name == "status" })

    XCTAssertTrue(try zshReservedNameViolations(in: "local status=\"started\"\n").contains { $0.name == "status" })
    XCTAssertTrue(try zshReservedNameViolations(in: "typeset status\n").contains { $0.name == "status" })
    XCTAssertTrue(try zshReservedNameViolations(in: "status=started\n").contains { $0.name == "status" })
  }

  func testConfiguredZshReservedNamesAreProhibitedWithoutMatchingCommentsOrStrings() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    XCTAssertEqual(try zshReservedNameViolations(in: script), [])

    for name in reservedZshNames {
      XCTAssertFalse(try zshReservedNameViolations(in: "local \(name)\n").isEmpty, name)
      XCTAssertFalse(try zshReservedNameViolations(in: "typeset \(name)=value\n").isEmpty, name)
      XCTAssertFalse(try zshReservedNameViolations(in: "\(name)=value\n").isEmpty, name)
    }

    let ignored = """
    # local status
    print -r -- "local pipestatus"
    print -r -- 'commands=value'
    RESULT[M14_003_RESULT]=FAIL
    """
    XCTAssertEqual(try zshReservedNameViolations(in: ignored), [])
  }

  func testAtomicCheckpointWriteUsesRuntimeTempFsyncAndRename() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let write = try extractFunction("write_checkpoint", from: script)

    XCTAssertTrue(write.contains("local checkpoint_tmp=\"$RUNTIME_ROOT/.checkpoint.$RUN_ID.$$.$RANDOM.tmp\""))
    XCTAssertTrue(write.contains("tmp.parent != final.parent"))
    XCTAssertTrue(write.contains("handle.flush()"))
    XCTAssertTrue(write.contains("os.fsync(handle.fileno())"))
    XCTAssertTrue(write.contains("json.load(handle)"))
    XCTAssertTrue(write.contains("os.replace(tmp, final)"))
    XCTAssertTrue(write.contains("os.fsync(directory_fd)"))
    XCTAssertFalse(write.contains("Path(path).write_text"))
  }

  func testTemporaryCheckpointCleanupOnFailure() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let write = try extractFunction("write_checkpoint", from: script)
    let failed = try extractFunction("checkpoint_write_failed", from: script)

    XCTAssertTrue(write.contains("rm -f \"$checkpoint_tmp\""))
    XCTAssertTrue(write.contains("HERMES_M14_003_CHECKPOINT_TEST_FAIL_AFTER_TEMP"))
    XCTAssertTrue(failed.contains("rm -f \"$checkpoint_tmp\""))
    XCTAssertTrue(failed.contains("cleanup_owned_state"))
    XCTAssertTrue(failed.contains("RESULT[M14_003_RESULT]=FAIL"))
    XCTAssertTrue(failed.contains("exit 1"))
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
    XCTAssertTrue(install.contains("verify_recorder_ready"))
    XCTAssertTrue(write.contains("try? \"\\(getpid())\\n\".write"))
  }

  func testIOKitIsPrimarySleepEvidenceAndNSWorkspaceOnlyIsInsufficient() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let helper = try extractFunction("write_sleep_wake_recorder", from: script)
    let verify = try extractFunction("verify_recorder_evidence", from: script)

    XCTAssertTrue(helper.contains("IORegisterForSystemPower"))
    XCTAssertTrue(helper.contains("kIOMessageSystemWillSleep"))
    XCTAssertTrue(helper.contains("IOAllowPowerChange"))
    XCTAssertTrue(helper.contains("append(\"IOKitSystemWillSleep\")"))
    XCTAssertTrue(helper.contains("NSWorkspace.willSleepNotification"))
    XCTAssertTrue(helper.contains("append(\"NSWorkspaceWillSleep\")"))
    XCTAssertTrue(verify.contains("\"IOKitSystemWillSleep\" not in names"))
    XCTAssertTrue(verify.contains("will-sleep-missing"))
    XCTAssertFalse(verify.contains("\"NSWorkspaceWillSleep\" not in names"))
  }

  func testIOKitPoweredOnWakeEvidenceRequirement() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let helper = try extractFunction("write_sleep_wake_recorder", from: script)
    let verify = try extractFunction("verify_recorder_evidence", from: script)

    XCTAssertTrue(helper.contains("kIOMessageSystemHasPoweredOn"))
    XCTAssertTrue(helper.contains("append(\"IOKitSystemHasPoweredOn\")"))
    XCTAssertTrue(helper.contains("NSWorkspace.didWakeNotification"))
    XCTAssertTrue(helper.contains("append(\"NSWorkspaceDidWake\")"))
    XCTAssertTrue(verify.contains("\"IOKitSystemHasPoweredOn\" not in names"))
    XCTAssertTrue(verify.contains("wake-missing"))
    XCTAssertFalse(verify.contains("\"NSWorkspaceDidWake\" not in names"))
  }

  func testRecorderReadyHandshakeBlocksPrepareUntilIOKitRunLoopAndWritableEvidence() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let ready = try extractFunction("verify_recorder_ready", from: script)
    let prepare = try extractFunction("prepare", from: script)

    XCTAssertTrue(ready.contains("launchctl print \"$SERVICE_DOMAIN/$RECORDER_LABEL\""))
    XCTAssertTrue(ready.contains("recorder_pid_from_launchctl"))
    XCTAssertTrue(ready.contains("kill -0 \"$RECORDER_PID\""))
    XCTAssertTrue(ready.contains("RECORDER_READY_FILE"))
    XCTAssertTrue(ready.contains("iokitRegistered"))
    XCTAssertTrue(ready.contains("eventLoopActive"))
    XCTAssertTrue(ready.contains("evidenceWritable"))
    XCTAssertTrue(prepare.contains("verify_recorder_ready || fail"))
    XCTAssertTrue(prepare.range(of: #"RESULT\[M14_003_RESULT\]=WAITING"#, options: .regularExpression) != nil)
  }

  func testIOKitRegistrationFailureBlocksPrepare() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let helper = try extractFunction("write_sleep_wake_recorder", from: script)
    let install = try extractFunction("install_recorder_launch_agent", from: script)

    XCTAssertTrue(helper.contains("HERMES_M14_003_FORCE_IOKIT_REGISTRATION_FAILURE"))
    XCTAssertTrue(helper.contains("iokit-registration-failed"))
    XCTAssertTrue(install.contains("HERMES_M14_003_FORCE_IOKIT_REGISTRATION_FAILURE"))
    XCTAssertTrue(install.contains("RECORDER_FAILURE_REASON=\"recorder-not-ready\""))
  }

  func testWillSleepAcknowledgmentPoweredOnCaptureAndEvidenceFsync() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let helper = try extractFunction("write_sleep_wake_recorder", from: script)

    XCTAssertTrue(helper.contains("IOAllowPowerChange(rootPort"))
    XCTAssertTrue(helper.contains("append(\"IOKitSystemHasPoweredOn\")"))
    XCTAssertTrue(helper.contains("handle.synchronize()"))
    XCTAssertTrue(helper.contains("fsync(handle.fileDescriptor)"))
    XCTAssertTrue(helper.contains("fsyncDirectory(containing: evidencePath)"))
    XCTAssertTrue(helper.contains("writeReadyFile"))
  }

  func testEventOrderingRunIDAndUptimeEvidenceRequired() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let helper = try extractFunction("write_sleep_wake_recorder", from: script)
    let verify = try extractFunction("verify_recorder_evidence", from: script)

    XCTAssertTrue(helper.contains("ProcessInfo.processInfo.systemUptime"))
    XCTAssertTrue(helper.contains("monotonicUptime"))
    XCTAssertTrue(verify.contains("run-id-mismatch"))
    XCTAssertTrue(verify.contains("ready_index < sleep_index < wake_index"))
    XCTAssertTrue(verify.contains("invalid-event-order"))
    XCTAssertTrue(verify.contains("invalid-uptime-evidence"))
    XCTAssertTrue(verify.contains("wake[\"monotonicUptime\"] < sleep[\"monotonicUptime\"]"))
    XCTAssertFalse(helper.contains("Date().timeIntervalSince"))
  }

  func testStaleCheckpointAndDuplicateResumeRejected() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let resume = try extractFunction("resume", from: script)

    XCTAssertTrue(resume.contains("checkpoint_run_id"))
    XCTAssertTrue(resume.contains("run-id-mismatch"))
    XCTAssertTrue(resume.contains("waiting-for-manual-sleep"))
    XCTAssertTrue(resume.contains("stale or duplicate resume checkpoint"))
    XCTAssertTrue(resume.contains("write_checkpoint \"resume\" \"resuming\""))
  }

  func testMissingCheckpointResumeReturnsExitOneAndIsHarmless() throws {
    try removeRuntimeCheckpoint()

    let first = try runAcceptanceScript(["resume"], optIn: true)
    let second = try runAcceptanceScript(["resume"], optIn: true)

    for result in [first, second] {
      XCTAssertEqual(result.exitCode, 1)
      XCTAssertEqual(result.combinedOutput.components(separatedBy: "error: missing or invalid durable checkpoint").count - 1, 1)
      XCTAssertFalse(result.combinedOutput.contains("genuine sleep/wake evidence"))
      XCTAssertFalse(result.combinedOutput.contains("post-wake validation"))
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("artifacts/m14-003/runtime/checkpoint.json").path))
    let resultText = try read("artifacts/m14-003/result.txt")
    XCTAssertTrue(resultText.contains("M14_003_RESULT=FAIL"))
  }

  func testNoPartialCheckpointAcceptedByResume() throws {
    let runtime = root.appendingPathComponent("artifacts/m14-003/runtime")
    try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true)
    try "partial\n".write(to: runtime.appendingPathComponent("checkpoint.json"), atomically: true, encoding: .utf8)

    let result = try runAcceptanceScript(["resume"], optIn: true)

    XCTAssertEqual(result.exitCode, 1)
    XCTAssertEqual(result.combinedOutput.components(separatedBy: "error: missing or invalid durable checkpoint").count - 1, 1)
    XCTAssertFalse(result.combinedOutput.contains("REAL_SLEEP_DETECTED=yes"))
    let resultText = try read("artifacts/m14-003/result.txt")
    XCTAssertTrue(resultText.contains("M14_003_RESULT=FAIL"))
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

  func testExplicitRootPIDInputAndExactPGIDEnumeration() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let record = try extractFunction("record_real_hermes_quiescence", from: script)

    XCTAssertTrue(script.contains("REAL_HERMES_ROOT_PIDS=\"${HERMES_REAL_AGENT_ROOT_PIDS:-}\""))
    XCTAssertTrue(script.contains("REAL_HERMES_QUIESCE_OPT_IN=\"${HERMES_QUIESCE_REAL_AGENT:-}\""))
    XCTAssertTrue(record.contains("roots=(\"${(@z)REAL_HERMES_ROOT_PIDS}\")"))
    XCTAssertTrue(record.contains("HERMES_QUIESCE_REAL_AGENT=YES"))
    XCTAssertTrue(record.contains("root_pgid=\"$PARSED_PGID\""))
    XCTAssertTrue(record.contains("enumerate_current_user_process_group \"$root_pgid\""))
    XCTAssertTrue(record.contains("seen_pids"))
    XCTAssertTrue(record.contains("for root_pid in \"${roots[@]}\""))
  }

  func testCurrentUIDEnforcementAndUnrelatedProcessExclusion() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let record = try extractFunction("record_real_hermes_quiescence", from: script)
    let enumerate = try extractFunction("enumerate_current_user_process_group", from: script)

    XCTAssertTrue(record.contains("current_uid=\"$(id -u)\""))
    XCTAssertTrue(record.contains("is not owned by the current UID"))
    XCTAssertTrue(record.contains("[[ \"$member_pgid\" == \"$root_pgid\" ]]"))
    XCTAssertTrue(enumerate.contains("[[ \"$PARSED_PGID\" == \"$pgid\" ]]"))
    XCTAssertFalse(record.contains("pgrep"))
    XCTAssertFalse(record.contains("pid_for_exact_executable"))
  }

  func testPIDStartTimeIdentityValidationBeforeSIGCONT() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let matcher = try extractFunction("process_identity_matches_record", from: script)
    let resume = try extractFunction("resume_real_hermes_recorded_pids", from: script)

    XCTAssertTrue(matcher.contains("expected_uid"))
    XCTAssertTrue(matcher.contains("expected_pgid"))
    XCTAssertTrue(matcher.contains("expected_basename"))
    XCTAssertTrue(matcher.contains("expected_start_time"))
    XCTAssertTrue(matcher.contains("PARSED_START_TIME"))
    XCTAssertTrue(resume.contains("process_identity_matches_record"))
    XCTAssertTrue(resume.contains("/bin/kill -CONT \"$pid\""))
  }

  func testSIGSTOPBeforeWaitingAndSuspendedStateStoredInCheckpoint() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let prepare = try extractFunction("prepare", from: script)
    let stop = try extractFunction("stop_real_hermes_recorded_pids", from: script)
    let checkpoint = try extractFunction("write_checkpoint", from: script)

    XCTAssertTrue(stop.contains("/bin/kill -STOP \"$pid\""))
    XCTAssertTrue(stop.contains("verify_real_hermes_suspended"))
    XCTAssertTrue(stop.contains("update_real_hermes_suspended_checkpoint"))
    XCTAssertTrue(checkpoint.contains("\"realHermesQuiescence\""))
    XCTAssertTrue(checkpoint.contains("\"suspendedByM14003\"") || script.contains("\"suspendedByM14003\""))
    XCTAssertLessThan(
      try XCTUnwrap(prepare.range(of: "stop_real_hermes_recorded_pids")?.lowerBound),
      try XCTUnwrap(prepare.range(of: "RESULT[WAITING_FOR_MANUAL_SLEEP]=yes")?.lowerBound)
    )
  }

  func testSIGCONTOnResumeFailTimeoutInterruptAndCleanupOnlyExactRecordedPIDs() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let cleanup = try extractFunction("cleanup_owned_state", from: script)
    let signal = try extractFunction("resume_real_hermes_recorded_pids", from: script)

    XCTAssertTrue(cleanup.contains("resume_real_hermes_recorded_pids"))
    XCTAssertTrue(script.contains("trap cleanup EXIT"))
    XCTAssertTrue(script.contains("timeout_fail"))
    XCTAssertTrue(signal.contains("suspendedByM14003"))
    XCTAssertTrue(signal.contains("/bin/kill -CONT \"$pid\""))
    XCTAssertFalse(signal.contains("kill -CONT -"))
    XCTAssertFalse(script.contains("killall"))
    XCTAssertFalse(script.contains("pkill"))
    XCTAssertFalse(script.contains("sudo "))
  }

  func testPrepareFailureAfterInstallUsesLiveExactCleanupState() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let cleanup = try extractFunction("cleanup_owned_state", from: script)
    let live = try extractFunction("has_live_owned_state", from: script)
    let failed = try extractFunction("checkpoint_write_failed", from: script)

    XCTAssertTrue(live.contains("APP_INSTALLED_BY_RUN"))
    XCTAssertTrue(live.contains("LAUNCH_AGENT_INSTALLED_BY_RUN"))
    XCTAssertTrue(live.contains("SERVICE_BOOTSTRAPPED_BY_RUN"))
    XCTAssertTrue(live.contains("RECORDER_BOOTSTRAPPED_BY_RUN"))
    XCTAssertTrue(live.contains("APP_PID"))
    XCTAssertTrue(live.contains("SERVICE_PID"))
    XCTAssertTrue(live.contains("RECORDER_PID"))
    XCTAssertTrue(cleanup.contains("if ! has_live_owned_state; then"))
    XCTAssertTrue(cleanup.contains("[[ -r \"$CHECKPOINT_FILE\" ]] && load_checkpoint 2>/dev/null || true"))
    XCTAssertTrue(failed.contains("cleanup_owned_state"))
  }

  func testCleanupRemainsExactPIDLabelAndPathOnly() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let cleanup = try extractFunction("cleanup_owned_state", from: script)

    XCTAssertTrue(cleanup.contains("terminate_pid \"$APP_PID\""))
    XCTAssertTrue(cleanup.contains("terminate_pid \"$RECORDER_PID\""))
    XCTAssertTrue(cleanup.contains("launchctl bootout \"$SERVICE_DOMAIN\" \"$RECORDER_PLIST\""))
    XCTAssertTrue(cleanup.contains("launchctl bootout \"$SERVICE_DOMAIN\" \"$LAUNCH_AGENT_TARGET\""))
    XCTAssertTrue(cleanup.contains("[[ \"$LAUNCH_AGENT_INSTALLED_BY_RUN\" == \"yes\" && -e \"$LAUNCH_AGENT_TARGET\" ]]"))
    XCTAssertTrue(cleanup.contains("[[ \"$APP_INSTALLED_BY_RUN\" == \"yes\" && -e \"$APP_TARGET\" ]]"))
    XCTAssertFalse(cleanup.contains("~/.hermes"))
    XCTAssertFalse(cleanup.contains("Keychain"))
    XCTAssertFalse(script.contains("killall"))
    XCTAssertFalse(script.contains("pkill"))
  }

  func testCleanupAfterTerminalLossPrepareFailureAndResumeFailure() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let cleanupCommand = try extractFunction("cleanup_command", from: script)
    let cleanup = try extractFunction("cleanup_owned_state", from: script)

    XCTAssertTrue(script.contains("trap cleanup EXIT"))
    XCTAssertTrue(script.contains("trap 'RESULT[M14_003_RESULT]=FAIL; exit 130' INT TERM HUP"))
    XCTAssertTrue(cleanup.contains("[[ -r \"$CHECKPOINT_FILE\" ]] && load_checkpoint 2>/dev/null || true"))
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

  private func removeRuntimeCheckpoint() throws {
    let runtime = root.appendingPathComponent("artifacts/m14-003/runtime")
    try? FileManager.default.removeItem(at: runtime.appendingPathComponent("checkpoint.json"))
    try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true)
  }

  private func runAcceptanceScript(_ arguments: [String], optIn: Bool) throws -> (exitCode: Int32, combinedOutput: String) {
    let process = Process()
    process.currentDirectoryURL = root
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["Scripts/m14_003_sleep_wake_endurance_acceptance.sh"] + arguments
    var environment = ProcessInfo.processInfo.environment
    environment["HERMES_M14_003_RUN_ID"] = "m14-003-test-\(UUID().uuidString)"
    if optIn {
      environment["HERMES_SLEEP_WAKE_ACCEPTANCE"] = "YES"
    } else {
      environment.removeValue(forKey: "HERMES_SLEEP_WAKE_ACCEPTANCE")
    }
    process.environment = environment
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
  }

  private func zshReservedNameViolations(in script: String) throws -> [ReservedNameViolation] {
    var violations: [ReservedNameViolation] = []
    for (index, rawLine) in script.components(separatedBy: .newlines).enumerated() {
      let line = stripZshComment(from: rawLine).trimmingCharacters(in: .whitespaces)
      guard !line.isEmpty else { continue }
      if line.hasPrefix("local ") || line.hasPrefix("typeset ") {
        let body = line.split(maxSplits: 1, whereSeparator: \.isWhitespace).dropFirst().joined(separator: " ")
        for token in body.split(whereSeparator: \.isWhitespace) {
          let variable = token.split(separator: "=", maxSplits: 1).first.map(String.init) ?? ""
          if reservedZshNames.contains(variable) {
            violations.append(ReservedNameViolation(line: index + 1, name: variable))
          }
        }
      } else if let equals = line.firstIndex(of: "=") {
        let variable = String(line[..<equals])
        if variable.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil,
           reservedZshNames.contains(variable) {
          violations.append(ReservedNameViolation(line: index + 1, name: variable))
        }
      }
    }
    return violations
  }

  private func stripZshComment(from line: String) -> String {
    var result = ""
    var inSingleQuote = false
    var inDoubleQuote = false
    var previousWasBackslash = false
    for character in line {
      if character == "#" && !inSingleQuote && !inDoubleQuote {
        break
      }
      result.append(character)
      if character == "\\" && !previousWasBackslash {
        previousWasBackslash = true
        continue
      }
      if character == "'" && !inDoubleQuote && !previousWasBackslash {
        inSingleQuote.toggle()
      } else if character == "\"" && !inSingleQuote && !previousWasBackslash {
        inDoubleQuote.toggle()
      }
      previousWasBackslash = false
    }
    return result
  }

  private struct ReservedNameViolation: Equatable {
    let line: Int
    let name: String
  }
}
