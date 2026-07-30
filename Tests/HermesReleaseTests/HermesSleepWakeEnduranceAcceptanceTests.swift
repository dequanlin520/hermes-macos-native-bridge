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

    XCTAssertTrue(script.contains("\"$POWER_LOG_COMMAND\" -g log"))
    XCTAssertFalse(script.contains("sleepnow"))
    XCTAssertFalse(script.contains(" schedule "))
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

  func testBoundedMacOSSystemPowerLogIsPrimarySleepWakeEvidence() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let prepare = try extractFunction("record_power_log_prepare_checkpoint", from: script)
    let verify = try extractFunction("verify_system_power_log_evidence", from: script)
    let resume = try extractFunction("resume", from: script)

    XCTAssertTrue(script.contains("POWER_LOG_COMMAND=\"/usr/bin/pmset\""))
    XCTAssertTrue(prepare.contains("POWER_LOG_PREPARE_UTC"))
    XCTAssertTrue(prepare.contains("POWER_LOG_PREPARE_EPOCH"))
    XCTAssertTrue(prepare.contains("POWER_LOG_PREPARE_LOCAL_OFFSET"))
    XCTAssertTrue(prepare.contains("POWER_LOG_PREPARE_MONOTONIC"))
    XCTAssertTrue(prepare.contains("process_info_system_uptime"))
    XCTAssertFalse(prepare.contains("POWER_LOG_PREPARE_BOUNDARY"))
    XCTAssertTrue(try read("Scripts/m14_003_power_log_evidence.py").contains("\"provider\": \"pmset -g log\""))
    XCTAssertTrue(verify.contains("Scripts/m14_003_power_log_evidence.py verify"))
    XCTAssertTrue(resume.contains("verify_system_power_log_evidence"))
    XCTAssertLessThan(
      try XCTUnwrap(resume.range(of: "verify_system_power_log_evidence")?.lowerBound),
      try XCTUnwrap(resume.range(of: "verify_recorder_evidence")?.lowerBound)
    )
  }

  func testSystemPowerLogAcceptsOnlyExplicitSystemSleepAndWake() throws {
    let helper = try read("Scripts/m14_003_power_log_evidence.py")

    XCTAssertTrue(helper.contains("Entering Sleep state"))
    XCTAssertTrue(helper.contains("Sleep Entered"))
    XCTAssertTrue(helper.contains("System Sleep"))
    XCTAssertTrue(helper.contains("Entering DarkWake state"))
    XCTAssertTrue(helper.contains("Software Sleep"))
    XCTAssertTrue(helper.contains("Wake from Normal Sleep"))
    XCTAssertTrue(helper.contains("DarkWake to FullWake"))
    XCTAssertTrue(helper.contains("System Wake"))
    XCTAssertTrue(helper.contains("rejected-display-sleep"))
    XCTAssertTrue(helper.contains("rejected-display-wake"))
    XCTAssertTrue(helper.contains("rejected-maintenance-wake"))
    XCTAssertTrue(helper.contains("rejected-sleepservice"))
    XCTAssertTrue(helper.contains("rejected-wake-request"))
    XCTAssertTrue(helper.contains("rejected-user-active"))
    XCTAssertTrue(helper.contains("rejected-assertions"))
    XCTAssertTrue(helper.contains("rejected-darkwake"))
    XCTAssertTrue(helper.contains("rejected-out-of-bounds"))
  }

  func testPowerLogNegativeCasesHaveSpecificReasons() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let helper = try read("Scripts/m14_003_power_log_evidence.py")
    let resume = try extractFunction("resume", from: script)

    XCTAssertTrue(helper.contains("epoch < prepare_epoch - BOUNDARY_TOLERANCE_SECONDS"))
    XCTAssertTrue(helper.contains("epoch > resume_epoch + BOUNDARY_TOLERANCE_SECONDS"))
    XCTAssertTrue(helper.contains("rejected-out-of-bounds"))
    XCTAssertTrue(helper.contains("fail(\"invalid-system-event-order\")"))
    XCTAssertTrue(helper.contains("fail(\"system-sleep-missing\")"))
    XCTAssertTrue(helper.contains("fail(\"system-wake-missing\")"))
    XCTAssertTrue(helper.contains("fail(\"invalid-uptime-evidence\")"))
    XCTAssertTrue(resume.contains("timeout_fail \"$system_power_verify_error\""))
    XCTAssertFalse(resume.contains("timeout_fail \"will-sleep-missing\""))
  }

  func testPowerLogCheckpointUsesIntegerEpochSchema() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let checkpoint = try extractFunction("write_checkpoint", from: script)

    XCTAssertTrue(checkpoint.contains("final.exists()"))
    XCTAssertTrue(checkpoint.contains("checkpoint.get(\"runIdentifier\") != run_id"))
    XCTAssertTrue(checkpoint.contains("merge_dict(checkpoint, updates)"))
    XCTAssertTrue(checkpoint.contains("\"epochSeconds\": power_log_epoch_value"))
    XCTAssertTrue(checkpoint.contains("\"utcISO8601\": power_log_prepare_utc"))
    XCTAssertTrue(checkpoint.contains("\"localTimezoneOffset\": power_log_prepare_local_offset"))
    XCTAssertTrue(checkpoint.contains("\"systemUptime\": power_log_uptime_value"))
    XCTAssertTrue(checkpoint.contains("\"createdAtMonotonic\": power_log_monotonic_value"))
    XCTAssertFalse(checkpoint.contains("cursorBoundary"))
    XCTAssertFalse(checkpoint.contains("wallClockUTC"))
  }

  func testCheckpointUpdatesAreMergePreservingAndRejectRunIDMismatch() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let checkpoint = try extractFunction("write_checkpoint", from: script)

    XCTAssertTrue(checkpoint.contains("checkpoint = json.loads(final.read_text"))
    XCTAssertTrue(checkpoint.contains("raise SystemExit(\"run-id-mismatch\")"))
    XCTAssertTrue(checkpoint.contains("def merge_dict(base, updates):"))
    XCTAssertTrue(checkpoint.contains("if isinstance(value, dict) and isinstance(base.get(key), dict):"))
    XCTAssertTrue(checkpoint.contains("base[key] = value"))
    XCTAssertFalse(checkpoint.contains("payload = json.dumps(updates"))
    XCTAssertTrue(checkpoint.contains("if power_log_prepare_utc:"))
    XCTAssertTrue(checkpoint.contains("checkpoint[\"powerLogCheckpoint\"] = {"))
  }

  func testPrepareReadBackGatePreventsWaitingWithMissingBoundaryFields() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let prepare = try extractFunction("prepare", from: script)
    let validate = try extractFunction("validate_checkpoint_before_waiting", from: script)

    XCTAssertTrue(prepare.contains("write_checkpoint \"prepare\" \"waiting-for-manual-sleep\""))
    XCTAssertTrue(prepare.contains("validate_checkpoint_before_waiting || fail"))
    XCTAssertLessThan(
      try XCTUnwrap(prepare.range(of: "validate_checkpoint_before_waiting")?.lowerBound),
      try XCTUnwrap(prepare.range(of: "RESULT[WAITING_FOR_MANUAL_SLEEP]=yes")?.lowerBound)
    )
    XCTAssertTrue(validate.contains("powerLogCheckpoint"))
    XCTAssertTrue(validate.contains("epochSeconds\", int"))
    XCTAssertTrue(validate.contains("utcISO8601\", str"))
    XCTAssertTrue(validate.contains("localTimezoneOffset\", str"))
    XCTAssertTrue(validate.contains("systemUptime\", (int, float)"))
    XCTAssertTrue(validate.contains("createdAtMonotonic\", (int, float)"))
    XCTAssertTrue(validate.contains("systemPowerLogEvidence"))
    XCTAssertTrue(validate.contains("wakeEvidence"))
    XCTAssertTrue(validate.contains("realHomeSnapshotBefore"))
    XCTAssertTrue(validate.contains("recorderLabel"))
    XCTAssertTrue(validate.contains("suspendedByM14003"))
  }

  func testDiagnosticCheckpointPreservesFailureEvidenceAndRedactsPrivatePaths() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let diagnostic = try extractFunction("preserve_diagnostic_checkpoint", from: script)
    let fail = try extractFunction("fail", from: script)
    let timeout = try extractFunction("timeout_fail", from: script)

    XCTAssertTrue(diagnostic.contains("DIAGNOSTIC_DIR"))
    XCTAssertTrue(diagnostic.contains("failureReason"))
    XCTAssertTrue(diagnostic.contains("phaseOrdering"))
    XCTAssertTrue(diagnostic.contains("/Users/<redacted>"))
    XCTAssertTrue(diagnostic.contains("<redacted-path>"))
    XCTAssertTrue(diagnostic.contains("os.fsync(handle.fileno())"))
    XCTAssertTrue(diagnostic.contains("os.replace(tmp, target)"))
    XCTAssertTrue(fail.contains("preserve_diagnostic_checkpoint"))
    XCTAssertTrue(timeout.contains("preserve_diagnostic_checkpoint"))
  }

  func testInspectCheckpointModeIsReadOnlyAndSchemaAware() throws {
    let runID = "m14-003-inspect-\(UUID().uuidString)"
    let runtime = root.appendingPathComponent("artifacts/m14-003/runtime")
    let checkpoint = runtime.appendingPathComponent("checkpoint.json")
    try writePowerLogCheckpoint(to: checkpoint, checkpointEpoch: 1_785_386_012, runID: runID)
    try? FileManager.default.removeItem(at: root.appendingPathComponent("artifacts/m14-003/result.txt"))
    let before = try Data(contentsOf: checkpoint)

    let result = try runAcceptanceScript(
      ["inspect-checkpoint"],
      optIn: false,
      extraEnvironment: ["HERMES_M14_003_RUN_ID": runID]
    )

    XCTAssertEqual(result.exitCode, 0, result.combinedOutput)
    XCTAssertEqual(try Data(contentsOf: checkpoint), before)
    XCTAssertTrue(result.combinedOutput.contains("run_id_match=yes"))
    XCTAssertTrue(result.combinedOutput.contains("required_fields=ok"))
    XCTAssertTrue(result.combinedOutput.contains("power_boundary_epoch=1785386012"))
    XCTAssertTrue(result.combinedOutput.contains("utc_timestamp=present-string"))
    XCTAssertTrue(result.combinedOutput.contains("timezone_offset=present-string"))
    XCTAssertTrue(result.combinedOutput.contains("recorder_identity=ok"))
    XCTAssertTrue(result.combinedOutput.contains("quiescence_completeness=complete"))
    XCTAssertTrue(result.combinedOutput.contains("checkpoint_schema_version=1"))
    XCTAssertFalse(result.combinedOutput.contains("/Users/"))
    XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("artifacts/m14-003/result.txt").path))
  }

  func testDiagnosePowerEvidencePrefersMatchingDiagnosticCheckpointAfterCleanup() throws {
    let runID = "m14-003-diagnostic-\(UUID().uuidString)"
    let runtime = root.appendingPathComponent("artifacts/m14-003/runtime")
    let diagnostics = root.appendingPathComponent("artifacts/m14-003/diagnostics")
    let active = runtime.appendingPathComponent("checkpoint.json")
    let diagnostic = diagnostics.appendingPathComponent("\(runID)-checkpoint.json")
    let fixture = try temporaryDirectory().appendingPathComponent("pmset.log")
    try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: diagnostics, withIntermediateDirectories: true)
    try writeReducedCheckpoint(to: active, runID: runID)
    try writePowerLogCheckpoint(to: diagnostic, checkpointEpoch: 1_785_386_012, runID: runID)
    try """
    2026-07-30 04:33:34 UTC Sleep Entering Sleep state
    2026-07-30 04:33:39 UTC Wake Wake from Normal Sleep
    """.write(to: fixture, atomically: true, encoding: .utf8)

    let result = try runAcceptanceScript(
      ["diagnose-power-evidence"],
      optIn: false,
      extraEnvironment: [
        "HERMES_M14_003_RUN_ID": runID,
        "HERMES_M14_003_POWER_LOG_FIXTURE": fixture.path,
        "HERMES_M14_003_FIXTURE_RESUME_EPOCH": "1785386020",
      ]
    )

    XCTAssertEqual(result.exitCode, 0, result.combinedOutput)
    XCTAssertTrue(result.combinedOutput.contains("checkpoint_epoch=1785386012"))
    XCTAssertFalse(result.combinedOutput.contains("checkpoint=invalid reason=power-log-boundary-invalid"))
  }

  func testPowerLogParserAcceptsTimestampFormsAndOrderedFullSleepWakePair() throws {
    let log = """
    2026-07-29 21:33:34.500 -0700   Sleep                Entering Sleep state due to 'Software Sleep pid=449'
    unrelated row without a timestamp
    2026-07-29    21:33:39 PDT Wake                 Wake from Normal Sleep [CDNVA] : due to HID Activity
    """

    let result = try runPowerLogVerifier(log: log)

    XCTAssertEqual(result.exitCode, 0, result.combinedOutput)
    let evidence = try XCTUnwrap(result.evidence)
    XCTAssertEqual(evidence["systemSleepEpochSeconds"] as? Int, 1_785_386_014)
    XCTAssertEqual(evidence["systemWakeEpochSeconds"] as? Int, 1_785_386_019)
  }

  func testPowerLogParserAcceptsTimezoneOffsetAndVariableWhitespace() throws {
    let log = """
    2026-07-30 04:33:34 +0000 Sleep Entering Sleep state
    2026-07-30 04:33:39 +00:00    Wake    Wake from Normal Sleep
    """

    let result = try runPowerLogVerifier(log: log)

    XCTAssertEqual(result.exitCode, 0, result.combinedOutput)
  }

  func testPowerLogParserAcceptsObservedSoftwareSleepDarkWakeAndFullWakeRows() throws {
    let log = """
    2026-07-29 22:38:00 -0700 Sleep               \tEntering DarkWake state due to 'Software Sleep pid=449':TCPKeepAlive=active Using AC (Charge:0%) 52 secs
    2026-07-29 22:38:52 -0700 Wake                \tDarkWake to FullWake from Deep Idle [CDNVA] : due to HID Activity Using AC (Charge:0%)
    """

    let result = try runPowerLogVerifier(
      log: log,
      checkpointEpoch: 1_785_389_863,
      resumeEpoch: 1_785_389_953
    )

    XCTAssertEqual(result.exitCode, 0, result.combinedOutput)
    let evidence = try XCTUnwrap(result.evidence)
    XCTAssertEqual(evidence["systemSleepEpochSeconds"] as? Int, 1_785_389_880)
    XCTAssertEqual(evidence["systemWakeEpochSeconds"] as? Int, 1_785_389_932)
  }

  func testPowerLogParserAcceptsSleepEnteredAndSystemRowsWithoutExactDomainShape() throws {
    let log = """
    2026-07-30 04:33:34 UTC Sleep/Wake UUID       \tSleep Entered [CDNVA]
    2026-07-30 04:33:39 UTC Kernel Client         \tSystem Wake from sleep
    """

    let result = try runPowerLogVerifier(log: log)

    XCTAssertEqual(result.exitCode, 0, result.combinedOutput)
  }

  func testPowerLogParserIsLocaleIndependent() throws {
    let log = """
    2026-07-30 04:33:34 UTC Sleep Entering Sleep state
    2026-07-30 04:33:39 GMT Wake Wake from Normal Sleep
    """

    let result = try runPowerLogVerifier(log: log, locale: "fr_FR.UTF-8")

    XCTAssertEqual(result.exitCode, 0, result.combinedOutput)
  }

  func testPowerLogRejectsDarkWakeMaintenanceDisplayAndAssertionRows() throws {
    let log = """
    2026-07-30 04:33:34 UTC Sleep Entering DarkWake state due to 'Network Wake'
    2026-07-30 04:33:35 UTC Assertions PID 354(powerd) Created PreventSystemSleep "secret-process"
    2026-07-30 04:33:36 UTC Notification Display is turned off
    2026-07-30 04:33:37 UTC Notification Display is turned on
    2026-07-30 04:33:38 UTC Wake Maintenance SleepService Wake
    """

    let diagnostic = try runPowerLogDiagnostic(log: log)
    XCTAssertTrue(diagnostic.combinedOutput.contains("rejection_reason=rejected-darkwake"))
    XCTAssertTrue(diagnostic.combinedOutput.contains("rejection_reason=rejected-assertions"))
    XCTAssertTrue(diagnostic.combinedOutput.contains("rejection_reason=rejected-display-sleep"))
    XCTAssertTrue(diagnostic.combinedOutput.contains("rejection_reason=rejected-display-wake"))
    XCTAssertTrue(diagnostic.combinedOutput.contains("rejection_reason=rejected-maintenance-wake"))

    let result = try runPowerLogVerifier(log: log)
    XCTAssertEqual(result.exitCode, 1)
    XCTAssertTrue(result.combinedOutput.contains("system-sleep-missing"))
  }

  func testPowerLogRejectsWakeRequestsAndDarkWakeOnlyRows() throws {
    let log = """
    2026-07-30 04:33:34 UTC Sleep Entering DarkWake state due to 'Software Sleep pid=449':TCPKeepAlive=active
    2026-07-30 04:33:35 UTC WakeRequests Clients requested wake events
    2026-07-30 04:33:36 UTC Wake DarkWake from Deep Idle due to Maintenance
    """

    let diagnostic = try runPowerLogDiagnostic(log: log)
    XCTAssertTrue(diagnostic.combinedOutput.contains("rejection_reason=rejected-wake-request"))
    XCTAssertTrue(diagnostic.combinedOutput.contains("rejection_reason=rejected-maintenance-wake"))

    let result = try runPowerLogVerifier(log: log)
    XCTAssertEqual(result.exitCode, 1)
    XCTAssertTrue(result.combinedOutput.contains("system-wake-missing"))
  }

  func testPowerLogBoundedIntervalRejectsHistoricalAndPostResumeEvents() throws {
    let log = """
    2026-07-30 04:33:00 UTC Sleep Entering Sleep state
    2026-07-30 04:33:34 UTC Sleep Entering Sleep state
    2026-07-30 04:33:39 UTC Wake Wake from Normal Sleep
    2026-07-30 04:34:00 UTC Wake Wake from Normal Sleep
    """

    let result = try runPowerLogVerifier(log: log)

    XCTAssertEqual(result.exitCode, 0, result.combinedOutput)
    let events = try XCTUnwrap(result.evidence?["events"] as? [[String: Any]])
    XCTAssertTrue(events.contains { $0["rejectionReason"] as? String == "before-checkpoint" })
    XCTAssertTrue(events.contains { $0["rejectionReason"] as? String == "after-resume" })
  }

  func testPowerLogSpecificMissingAndOrderingReasons() throws {
    XCTAssertTrue(try runPowerLogVerifier(log: "2026-07-30 04:33:39 UTC Wake Wake from Normal Sleep\n").combinedOutput.contains("invalid-system-event-order"))
    XCTAssertTrue(try runPowerLogVerifier(log: "2026-07-30 04:33:34 UTC Sleep Entering Sleep state\n").combinedOutput.contains("system-wake-missing"))
    XCTAssertTrue(try runPowerLogVerifier(log: "2026-07-30 04:33:34 UTC Assertions PID 1(powerd) Summary UserIsActive\n").combinedOutput.contains("system-sleep-missing"))
    XCTAssertTrue(
      try runPowerLogVerifier(
        log: """
        2026-07-30 04:33:34 UTC Sleep Entering Sleep state
        2026-07-30 04:33:34 UTC Wake Wake from Normal Sleep
        """
      ).combinedOutput.contains("system-wake-missing")
    )
  }

  func testPowerLogBoundaryInvalidIsReservedForMalformedCheckpointOnly() throws {
    let malformed = try runPowerLogVerifier(
      log: "2026-07-30 04:33:34 UTC Sleep Entering Sleep state\n",
      checkpointEpoch: "1785386012"
    )
    XCTAssertTrue(malformed.combinedOutput.contains("power-log-boundary-invalid"))

    let resumeBeforeCheckpoint = try runPowerLogVerifier(
      log: "2026-07-30 04:33:34 UTC Sleep Entering Sleep state\n",
      resumeEpoch: 1_785_386_000
    )
    XCTAssertTrue(resumeBeforeCheckpoint.combinedOutput.contains("power-log-boundary-invalid"))

    let unparseable = try runPowerLogVerifier(log: "not a pmset timestamp\n")
    XCTAssertFalse(unparseable.combinedOutput.contains("power-log-boundary-invalid"))
    XCTAssertTrue(unparseable.combinedOutput.contains("system-sleep-missing"))
  }

  func testPowerEvidenceDiagnosticModeIsReadOnlyAndRedactsOutput() throws {
    let temp = try temporaryDirectory()
    let checkpoint = temp.appendingPathComponent("checkpoint.json")
    let fixture = temp.appendingPathComponent("pmset.log")
    try writePowerLogCheckpoint(to: checkpoint, checkpointEpoch: 1_785_386_012)
    try """
    2026-07-30 04:33:34 UTC Sleep Entering Sleep state due to /Users/jerry/private/token
    2026-07-30 04:33:39 UTC Wake Wake from Normal Sleep UUID C2EF653C-7A3B-4F92-B1AB-12BBC66C6C63 pid=449
    """.write(to: fixture, atomically: true, encoding: .utf8)
    try? FileManager.default.removeItem(at: root.appendingPathComponent("artifacts/m14-003/result.txt"))

    let result = try runAcceptanceScript(
      ["diagnose-power-evidence"],
      optIn: false,
      extraEnvironment: [
        "HERMES_M14_003_CHECKPOINT_FIXTURE": checkpoint.path,
        "HERMES_M14_003_POWER_LOG_FIXTURE": fixture.path,
        "HERMES_M14_003_FIXTURE_RESUME_EPOCH": "1785386020",
      ]
    )

    XCTAssertEqual(result.exitCode, 0, result.combinedOutput)
    XCTAssertTrue(result.combinedOutput.contains("candidate event_epoch=1785386014 event_kind=sleep"))
    XCTAssertTrue(result.combinedOutput.contains("sanitized_message_shape=Sleep Entering Sleep state"))
    XCTAssertTrue(result.combinedOutput.contains("/Users/<redacted>"))
    XCTAssertTrue(result.combinedOutput.contains("<uuid>"))
    XCTAssertTrue(result.combinedOutput.contains("pid=<redacted>"))
    XCTAssertFalse(result.combinedOutput.contains("private/token"))
    XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("artifacts/m14-003/result.txt").path))
  }

  func testPowerEvidenceDiagnosticPrintsSanitizedRejectedCandidates() throws {
    let diagnostic = try runPowerLogDiagnostic(
      log: """
      2026-07-30 04:33:34 UTC Assertions PID 354(powerd) Created PreventSystemSleep "/Users/someone/private/token"
      malformed row without timestamp
      """
    )

    XCTAssertEqual(diagnostic.exitCode, 0, diagnostic.combinedOutput)
    XCTAssertTrue(diagnostic.combinedOutput.contains("candidate event_epoch=1785386014 event_kind=rejected"))
    XCTAssertTrue(diagnostic.combinedOutput.contains("rejection_reason=rejected-assertions"))
    XCTAssertTrue(diagnostic.combinedOutput.contains("sanitized_message_shape=Assertions PID <redacted> Created PreventSystemSleep"))
    XCTAssertFalse(diagnostic.combinedOutput.contains("/Users/someone"))
    XCTAssertFalse(diagnostic.combinedOutput.contains("private/token"))
    XCTAssertFalse(diagnostic.combinedOutput.contains("malformed row without timestamp"))
  }

  func testPowerEvidenceDiagnosticReportsMalformedCheckpointWithoutTraceback() throws {
    let temp = try temporaryDirectory()
    let checkpoint = temp.appendingPathComponent("checkpoint.json")
    let fixture = temp.appendingPathComponent("pmset.log")
    try "partial\n".write(to: checkpoint, atomically: true, encoding: .utf8)
    try "2026-07-30 04:33:34 UTC Sleep Entering Sleep state\n".write(to: fixture, atomically: true, encoding: .utf8)

    let result = try runPythonHelper(
      arguments: [
        "diagnose",
        "--checkpoint", checkpoint.path,
        "--run-id", "m14-003-test",
        "--fixture-log", fixture.path,
        "--fixture-prepare-epoch", "1785386012",
        "--fixture-resume-epoch", "1785386020",
      ],
      standardInput: ""
    )

    XCTAssertEqual(result.exitCode, 0, result.combinedOutput)
    XCTAssertTrue(result.combinedOutput.contains("checkpoint=invalid reason=power-log-boundary-invalid"))
    XCTAssertFalse(result.combinedOutput.contains("Traceback"))
  }

  func testIOKitAndNSWorkspaceRemainCorroboratingOnly() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let helper = try extractFunction("write_sleep_wake_recorder", from: script)
    let iokit = try extractFunction("verify_recorder_evidence", from: script)
    let resume = try extractFunction("resume", from: script)

    XCTAssertTrue(helper.contains("IORegisterForSystemPower"))
    XCTAssertTrue(helper.contains("kIOMessageSystemWillSleep"))
    XCTAssertTrue(helper.contains("IOAllowPowerChange"))
    XCTAssertTrue(helper.contains("append(\"IOKitSystemWillSleep\")"))
    XCTAssertTrue(helper.contains("append(\"IOKitSystemHasPoweredOn\")"))
    XCTAssertTrue(helper.contains("append(\"NSWorkspaceWillSleep\")"))
    XCTAssertTrue(helper.contains("append(\"NSWorkspaceDidWake\")"))
    XCTAssertTrue(iokit.contains("will-sleep-missing"))
    XCTAssertTrue(resume.contains("verify_recorder_evidence >/dev/null 2>&1 || true"))
    XCTAssertFalse(resume.contains("timeout_fail \"$recorder_verify_error\""))
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
    let parser = try read("Scripts/m14_003_power_log_evidence.py")

    XCTAssertTrue(helper.contains("ProcessInfo.processInfo.systemUptime"))
    XCTAssertTrue(helper.contains("monotonicUptime"))
    XCTAssertTrue(helper.contains("recorderInstanceIdentifier"))
    XCTAssertTrue(helper.contains("eventSequenceNumber"))
    XCTAssertTrue(helper.contains("currentExecutablePath"))
    XCTAssertTrue(parser.contains("invalid-system-event-order"))
    XCTAssertTrue(parser.contains("invalid-uptime-evidence"))
    XCTAssertTrue(parser.contains("system-sleep-missing"))
    XCTAssertTrue(parser.contains("system-wake-missing"))
    XCTAssertTrue(parser.contains("power-log-boundary-invalid"))
    XCTAssertTrue(parser.contains("resume_uptime < prepare_uptime"))
    XCTAssertTrue(parser.contains("(resume_epoch - prepare_epoch) + BOUNDARY_TOLERANCE_SECONDS < (resume_uptime - prepare_uptime)"))
    XCTAssertFalse(helper.contains("Date().timeIntervalSince"))
  }

  func testResumeAcceptsRecorderReplacementUnderExactLaunchdLabel() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let validate = try extractFunction("validate_resume_recorder_identity", from: script)
    let process = try extractFunction("validate_recorder_process_identity", from: script)
    let plist = try extractFunction("validate_recorder_plist_contract", from: script)

    XCTAssertTrue(script.contains("RECORDER_EXECUTABLE=\"/usr/bin/swift\""))
    XCTAssertTrue(validate.contains("launchctl print \"$SERVICE_DOMAIN/$RECORDER_LABEL\""))
    XCTAssertTrue(validate.contains("recorder_pid_from_launchctl"))
    XCTAssertTrue(validate.contains("\"$launchd_pid\" == \"$RECORDER_PID\""))
    XCTAssertTrue(validate.contains("RECORDER_PID=\"$launchd_pid\""))
    XCTAssertTrue(validate.contains("write_checkpoint \"resume\" \"recorder-restarted\""))
    XCTAssertTrue(process.contains("current_uid=\"$(id -u)\""))
    XCTAssertTrue(process.contains("[[ \"$PARSED_UID\" == \"$current_uid\" ]]"))
    XCTAssertTrue(process.contains("expected_executable_path"))
    XCTAssertTrue(process.contains("currentExecutablePath"))
    XCTAssertTrue(process.contains("[[ \"$PARSED_COMM\" == \"$expected_executable_path\""))
    XCTAssertTrue(plist.contains("plist.get(\"Label\") != label"))
    XCTAssertTrue(plist.contains("arguments != expected"))
    XCTAssertTrue(plist.contains("run_id"))
    XCTAssertTrue(plist.contains("evidence"))
    XCTAssertFalse(validate.contains("pgrep"))
    XCTAssertFalse(process.contains("pgrep"))
  }

  func testResumeUsesPersistedEvidenceNotPrepareTimeRecorderPIDContinuity() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let resume = try extractFunction("resume", from: script)
    let evidence = try extractFunction("verify_recorder_evidence", from: script)
    let ready = try extractFunction("verify_recorder_ready", from: script)

    XCTAssertTrue(ready.contains("RECORDER_FAILURE_REASON=\"recorder-not-ready\""))
    XCTAssertTrue(evidence.contains("recorder-never-ready"))
    XCTAssertTrue(evidence.contains("will-sleep-missing"))
    XCTAssertTrue(evidence.contains("wake-missing"))
    XCTAssertTrue(resume.contains("validate_resume_recorder_identity"))
    XCTAssertTrue(resume.contains("verify_system_power_log_evidence"))
    XCTAssertTrue(resume.contains("system-sleep-missing|system-wake-missing|invalid-system-event-order|power-log-boundary-invalid|invalid-uptime-evidence"))
    XCTAssertTrue(resume.contains("verify_recorder_evidence >/dev/null 2>&1 || true"))
    XCTAssertFalse(evidence.contains("kill -0 \"$RECORDER_PID\""))
    XCTAssertFalse(resume.contains("verify_recorder_ready"))
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
    XCTAssertTrue(record.contains("seen_roots"))
    XCTAssertTrue(record.contains("duplicate real Hermes root PID"))
    XCTAssertTrue(record.contains("for root_pid in \"${roots[@]}\""))
  }

  func testThreeRootPIDCompletenessDiagnosticsAndRepresentation() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let record = try extractFunction("record_real_hermes_quiescence", from: script)
    let diagnostics = try extractFunction("print_quiescence_diagnostics", from: script)
    let prepare = try extractFunction("prepare", from: script)
    let checkpoint = try extractFunction("write_checkpoint", from: script)

    XCTAssertTrue(record.contains("ROOT_PIDS_EXPECTED=${#roots[@]}"))
    XCTAssertTrue(record.contains("ROOT_PIDS_VALIDATED=$(( ROOT_PIDS_VALIDATED + 1 ))"))
    XCTAssertTrue(record.contains("ROOT_PIDS_REPRESENTED="))
    XCTAssertTrue(record.contains("QUIESCED_MEMBER_COUNT=${#REAL_HERMES_RECORDED_PIDS[@]}"))
    XCTAssertTrue(record.contains("QUIESCENCE_COMPLETE=yes"))
    XCTAssertTrue(record.contains("missing represented root PID"))
    XCTAssertTrue(record.contains("\"isRoot\": pid_int in supplied_root_set"))
    XCTAssertTrue(checkpoint.contains("\"operatorProvidedRootPids\": [record[\"pid\"]"))
    XCTAssertTrue(diagnostics.contains("ROOT_PIDS_EXPECTED=$ROOT_PIDS_EXPECTED"))
    XCTAssertTrue(diagnostics.contains("ROOT_PIDS_VALIDATED=$ROOT_PIDS_VALIDATED"))
    XCTAssertTrue(diagnostics.contains("ROOT_PIDS_REPRESENTED=$ROOT_PIDS_REPRESENTED"))
    XCTAssertTrue(diagnostics.contains("QUIESCED_MEMBER_COUNT=$QUIESCED_MEMBER_COUNT"))
    XCTAssertTrue(diagnostics.contains("QUIESCENCE_COMPLETE=$QUIESCENCE_COMPLETE"))
    XCTAssertTrue(prepare.contains("print_quiescence_diagnostics"))
    XCTAssertLessThan(
      try XCTUnwrap(prepare.range(of: "print_quiescence_diagnostics")?.lowerBound),
      try XCTUnwrap(prepare.range(of: "RESULT[WAITING_FOR_MANUAL_SLEEP]=yes")?.lowerBound)
    )
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
    XCTAssertTrue(stop.contains("update_real_hermes_pid_suspended_checkpoint \"$pid\""))
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
    let finalRestore = try extractFunction("restore_real_hermes_after_final_decision", from: script)
    let trapCleanup = try extractFunction("cleanup", from: script)
    let signal = try extractFunction("resume_real_hermes_recorded_pids", from: script)

    XCTAssertFalse(cleanup.contains("resume_real_hermes_recorded_pids"))
    XCTAssertTrue(finalRestore.contains("resume_real_hermes_recorded_pids"))
    XCTAssertLessThan(
      try XCTUnwrap(trapCleanup.range(of: "finish_result")?.lowerBound),
      try XCTUnwrap(trapCleanup.range(of: "restore_real_hermes_after_final_decision")?.lowerBound)
    )
    XCTAssertTrue(script.contains("trap cleanup EXIT"))
    XCTAssertTrue(script.contains("timeout_fail"))
    XCTAssertTrue(signal.contains("suspendedByM14003"))
    XCTAssertTrue(signal.contains("/bin/kill -CONT \"$pid\""))
    XCTAssertTrue(signal.contains("AGENT_RESUME_STARTED"))
    XCTAssertTrue(signal.contains("AGENT_RESUME_COMPLETED"))
    XCTAssertFalse(signal.contains("kill -CONT -"))
    XCTAssertFalse(script.contains("killall"))
    XCTAssertFalse(script.contains("pkill"))
    XCTAssertFalse(script.contains("sudo "))
  }

  func testPassRequiresQuiescenceCheckpointAndRealHomeIntegrity() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let resume = try extractFunction("resume", from: script)
    let verify = try extractFunction("verify_real_hermes_quiescence_complete", from: script)
    let finish = try extractFunction("finish_result", from: script)

    XCTAssertTrue(resume.contains("verify_real_hermes_quiescence_complete"))
    XCTAssertTrue(verify.contains("suspendedByM14003"))
    XCTAssertTrue(verify.contains("real-hermes-quiescence-incomplete"))
    XCTAssertTrue(finish.contains("REAL_HERMES_HOME_MODIFIED"))
    XCTAssertTrue(finish.contains("ENVIRONMENT_RESTORED"))
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
    XCTAssertTrue(compare.contains("REAL_HOME_INTEGRITY_FINALIZED"))
    XCTAssertTrue(compare.contains("REAL_HOME_COMPARED_BEFORE_AGENT_RESUME"))
  }

  func testRealHomeComparisonOccursBeforeSIGCONTAndIsNotRepeatedAfterResume() throws {
    let script = try read("Scripts/m14_003_sleep_wake_endurance_acceptance.sh")
    let cleanup = try extractFunction("cleanup_owned_state", from: script)
    let trapCleanup = try extractFunction("cleanup", from: script)
    let resume = try extractFunction("resume", from: script)

    XCTAssertTrue(script.contains("REAL_HOME_BASELINE_CAPTURED"))
    XCTAssertTrue(script.contains("REAL_HOME_COMPARED_BEFORE_AGENT_RESUME"))
    XCTAssertTrue(script.contains("AGENT_RESUME_STARTED"))
    XCTAssertTrue(script.contains("AGENT_RESUME_COMPLETED"))
    XCTAssertTrue(cleanup.contains("set_real_home_modified_result"))
    XCTAssertLessThan(
      try XCTUnwrap(trapCleanup.range(of: "finish_result")?.lowerBound),
      try XCTUnwrap(trapCleanup.range(of: "restore_real_hermes_after_final_decision")?.lowerBound)
    )
    XCTAssertFalse(resume.contains("finish_result\n  FINISHED=\"yes\""))
  }

  func testPowerLogRedactsSensitiveDetails() throws {
    let helper = try read("Scripts/m14_003_power_log_evidence.py")

    XCTAssertTrue(helper.contains("/Users/<redacted>"))
    XCTAssertTrue(helper.contains("/<path-redacted>"))
    XCTAssertTrue(helper.contains("<uuid>"))
    XCTAssertTrue(helper.contains("=<redacted>"))
    XCTAssertTrue(helper.contains("return value[:240]"))
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

  private func runAcceptanceScript(
    _ arguments: [String],
    optIn: Bool,
    extraEnvironment: [String: String] = [:]
  ) throws -> (exitCode: Int32, combinedOutput: String) {
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
    for (key, value) in extraEnvironment {
      environment[key] = value
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

  private func runPowerLogVerifier(
    log: String,
    checkpointEpoch: Any = 1_785_386_012,
    resumeEpoch: Int = 1_785_386_020,
    locale: String? = nil
  ) throws -> (exitCode: Int32, combinedOutput: String, evidence: [String: Any]?) {
    let temp = try temporaryDirectory()
    let checkpoint = temp.appendingPathComponent("checkpoint.json")
    let evidence = temp.appendingPathComponent("evidence.json")
    try writePowerLogCheckpoint(to: checkpoint, checkpointEpoch: checkpointEpoch)
    let result = try runPythonHelper(
      arguments: [
        "verify",
        "--checkpoint", checkpoint.path,
        "--evidence", evidence.path,
        "--run-id", "m14-003-test",
        "--resume-utc", "2026-07-30T04:33:40Z",
        "--resume-epoch", "\(resumeEpoch)",
        "--resume-uptime", "108.0",
      ],
      standardInput: log,
      locale: locale
    )
    var parsedEvidence: [String: Any]?
    if FileManager.default.fileExists(atPath: evidence.path) {
      let data = try Data(contentsOf: evidence)
      parsedEvidence = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
    return (result.exitCode, result.combinedOutput, parsedEvidence)
  }

  private func runPowerLogDiagnostic(log: String) throws -> (exitCode: Int32, combinedOutput: String) {
    let temp = try temporaryDirectory()
    let checkpoint = temp.appendingPathComponent("checkpoint.json")
    let fixture = temp.appendingPathComponent("pmset.log")
    try writePowerLogCheckpoint(to: checkpoint, checkpointEpoch: 1_785_386_012)
    try log.write(to: fixture, atomically: true, encoding: .utf8)
    return try runPythonHelper(
      arguments: [
        "diagnose",
        "--checkpoint", checkpoint.path,
        "--run-id", "m14-003-test",
        "--fixture-log", fixture.path,
        "--fixture-resume-epoch", "1785386020",
      ],
      standardInput: ""
    )
  }

  private func runPythonHelper(
    arguments: [String],
    standardInput: String,
    locale: String? = nil
  ) throws -> (exitCode: Int32, combinedOutput: String) {
    let process = Process()
    process.currentDirectoryURL = root
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = ["Scripts/m14_003_power_log_evidence.py"] + arguments
    var environment = ProcessInfo.processInfo.environment
    if let locale {
      environment["LC_TIME"] = locale
      environment["LANG"] = locale
    }
    process.environment = environment
    let input = Pipe()
    let output = Pipe()
    process.standardInput = input
    process.standardOutput = output
    process.standardError = output
    try process.run()
    input.fileHandleForWriting.write(Data(standardInput.utf8))
    input.fileHandleForWriting.closeFile()
    process.waitUntilExit()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
  }

  private func writePowerLogCheckpoint(
    to url: URL,
    checkpointEpoch: Any,
    runID: String = "m14-003-test"
  ) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let checkpoint: [String: Any] = [
      "schemaVersion": 1,
      "runIdentifier": runID,
      "phase": "prepare",
      "status": "waiting-for-manual-sleep",
      "createdAtMonotonicUptime": 40.0,
      "updatedAtEpochSeconds": 1_785_386_012,
      "serviceDomain": "gui/current-user",
      "serviceLabel": "com.hermes.bridge",
      "recorderLabel": "com.hermes.bridge.m14-003.wake-recorder.\(runID)",
      "targets": [
        "app": "Applications/Hermes Bridge.app",
        "launchAgent": "Library/LaunchAgents/com.hermes.bridge.plist",
        "recorderLaunchAgent": "Library/LaunchAgents/com.hermes.bridge.m14-003.wake-recorder.\(runID).plist",
        "appExecutable": "Applications/Hermes Bridge.app/Contents/MacOS/HermesBridgeApp",
        "serviceExecutable": "Applications/Hermes Bridge.app/Contents/Library/HermesBridge/HermesBridgeService",
      ],
      "ownedPids": [
        "app": NSNull(),
        "service": NSNull(),
        "recorder": 12345,
      ],
      "ownership": [
        "appInstalledByRun": true,
        "launchAgentInstalledByRun": true,
        "serviceBootstrappedByRun": true,
        "recorderBootstrappedByRun": true,
      ],
      "restartCyclesExpected": 5,
      "resultFile": "artifacts/m14-003/result.txt",
      "runtimeRoot": "artifacts/m14-003/runtime",
      "wakeEvidence": "artifacts/m14-003/runtime/wake-recorder-evidence.jsonl",
      "systemPowerLogEvidence": "artifacts/m14-003/runtime/system-power-log-evidence.json",
      "wakeRecorderReady": "artifacts/m14-003/runtime/wake-recorder-ready.json",
      "realHomeSnapshotBefore": "artifacts/m14-003/runtime/real-home-before.snapshot",
      "realHermesQuiescence": [
        "operatorProvidedRootPids": [],
        "records": [],
      ],
      "powerLogCheckpoint": [
        "runIdentifier": runID,
        "epochSeconds": checkpointEpoch,
        "utcISO8601": "2026-07-30T04:33:32Z",
        "localTimezoneOffset": "+0000",
        "systemUptime": 100.0,
        "createdAtMonotonic": 50.0,
      ],
    ]
    let data = try JSONSerialization.data(withJSONObject: checkpoint, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url)
  }

  private func writeReducedCheckpoint(to url: URL, runID: String) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let checkpoint: [String: Any] = [
      "schemaVersion": 1,
      "runIdentifier": runID,
      "phase": "cleanup",
      "status": "cleaned",
      "ownership": [
        "appInstalledByRun": false,
        "launchAgentInstalledByRun": false,
        "serviceBootstrappedByRun": false,
        "recorderBootstrappedByRun": false,
      ],
    ]
    let data = try JSONSerialization.data(withJSONObject: checkpoint, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url)
  }

  private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("hermes-m14-003-tests")
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
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
