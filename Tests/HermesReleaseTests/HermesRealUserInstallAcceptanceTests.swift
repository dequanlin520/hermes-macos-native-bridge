import Foundation
import XCTest

final class HermesRealUserInstallAcceptanceTests: XCTestCase {
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
    let script = try read("Scripts/m14_002_real_user_install_acceptance.sh")

    XCTAssertTrue(script.contains("HERMES_REAL_USER_INSTALL_ACCEPTANCE:-"))
    XCTAssertTrue(script.contains("!= \"YES\""))
    XCTAssertTrue(script.contains("M14_002_RESULT]=OPT_IN_REQUIRED"))
    XCTAssertTrue(script.contains("exit 2"))
    XCTAssertTrue(script.contains("opt-in required"))
  }

  func testCollisionProtection() throws {
    let script = try read("Scripts/m14_002_real_user_install_acceptance.sh")
    let collision = try extractFunction("detect_collision", from: script)

    XCTAssertTrue(script.contains("detect_collision()"))
    XCTAssertTrue(script.contains("PREEXISTING_APP_FOUND]=yes"))
    XCTAssertTrue(script.contains("PREEXISTING_LAUNCH_AGENT_FOUND]=yes"))
    XCTAssertTrue(script.contains("launchctl print \"$SERVICE_DOMAIN/$LABEL\""))
    XCTAssertTrue(script.contains("BRIDGE_SUPPORT=\"$HOME/Library/Application Support/HermesBridge\""))
    XCTAssertTrue(script.contains("REAL_HERMES_HOME=\"$HOME/.hermes\""))
    XCTAssertTrue(script.contains("BLOCKED_BY_PREEXISTING_INSTALL]=yes"))
    XCTAssertTrue(script.contains("M14_002_RESULT]=BLOCKED"))
    XCTAssertFalse(collision.contains("BRIDGE_SUPPORT"))
    XCTAssertFalse(collision.contains("REAL_HERMES_HOME"))
  }

  func testExistingRealHermesHomeDoesNotCauseCollisionBlocking() throws {
    let script = try read("Scripts/m14_002_real_user_install_acceptance.sh")
    let collision = try extractFunction("detect_collision", from: script)

    XCTAssertTrue(script.contains("PRE_HERMES_HOME_STATE=\"$(path_state \"$REAL_HERMES_HOME\")\""))
    XCTAssertTrue(script.contains("write_real_home_integrity_snapshot \"$INTEGRITY_BEFORE\""))
    XCTAssertTrue(script.contains("set_real_home_modified_result"))
    XCTAssertFalse(collision.contains("[[ -e \"$REAL_HERMES_HOME\""))
    XCTAssertFalse(collision.contains("[[ -L \"$REAL_HERMES_HOME\""))
    XCTAssertFalse(script.contains("find \"$REAL_HERMES_HOME\""))
    XCTAssertFalse(script.contains("cat \"$REAL_HERMES_HOME\""))
    XCTAssertTrue(script.contains("HERMES_CONFIG_DIR=\"$RUNTIME_ROOT/HermesBridge\""))
  }

  func testExactProductionAppCollisionBlocks() throws {
    let script = try read("Scripts/m14_002_real_user_install_acceptance.sh")
    let collision = try extractFunction("detect_collision", from: script)

    XCTAssertTrue(collision.contains("[[ -e \"$APP_TARGET\" || -L \"$APP_TARGET\" ]]"))
    XCTAssertTrue(collision.contains("BLOCKED_REASON=\"production app target exists\""))
    XCTAssertTrue(collision.contains("RESULT[PREEXISTING_APP_FOUND]=yes"))
  }

  func testExactLaunchAgentCollisionBlocks() throws {
    let script = try read("Scripts/m14_002_real_user_install_acceptance.sh")
    let collision = try extractFunction("detect_collision", from: script)

    XCTAssertTrue(collision.contains("[[ -e \"$LAUNCH_AGENT_TARGET\" || -L \"$LAUNCH_AGENT_TARGET\" ]]"))
    XCTAssertTrue(collision.contains("BLOCKED_REASON=\"production LaunchAgent target exists\""))
    XCTAssertTrue(collision.contains("RESULT[PREEXISTING_LAUNCH_AGENT_FOUND]=yes"))
  }

  func testExactLoadedProductionLabelCollisionBlocks() throws {
    let script = try read("Scripts/m14_002_real_user_install_acceptance.sh")
    let collision = try extractFunction("detect_collision", from: script)

    XCTAssertTrue(collision.contains("launchctl print \"$SERVICE_DOMAIN/$LABEL\""))
    XCTAssertTrue(collision.contains("BLOCKED_REASON=\"production launchd label already loaded\""))
  }

  func testExactProductionProcessCollisionBlocks() throws {
    let script = try read("Scripts/m14_002_real_user_install_acceptance.sh")
    let collision = try extractFunction("detect_collision", from: script)

    XCTAssertTrue(collision.contains("pid_for_exact_executable \"$SERVICE_EXECUTABLE\""))
    XCTAssertTrue(collision.contains("pid_for_exact_executable \"$APP_EXECUTABLE\""))
    XCTAssertTrue(collision.contains("BLOCKED_REASON=\"production process already running\""))
    XCTAssertFalse(script.contains("ps ax |"))
  }

  func testActiveAcceptanceLockCollisionBlocks() throws {
    let script = try read("Scripts/m14_002_real_user_install_acceptance.sh")
    let lock = try extractFunction("acquire_acceptance_lock", from: script)

    XCTAssertTrue(script.contains("ACCEPTANCE_LOCK_DIR="))
    XCTAssertTrue(script.contains("ACCEPTANCE_LOCK_OWNED=\"no\""))
    XCTAssertTrue(lock.contains("mkdir \"$ACCEPTANCE_LOCK_DIR\""))
    XCTAssertTrue(lock.contains("kill -0 \"$lock_pid\""))
    XCTAssertTrue(lock.contains("BLOCKED_REASON=\"active acceptance lock exists\""))
    XCTAssertTrue(script.contains("rm -rf \"$ACCEPTANCE_LOCK_DIR\""))
  }

  func testBlockedPreflightResultUsesSkipForAppOwnsRuntime() throws {
    let script = try read("Scripts/m14_002_real_user_install_acceptance.sh")

    XCTAssertTrue(script.contains("APP_OWNS_RUNTIME skip"))
    XCTAssertTrue(script.contains("mark_pre_start_skips()"))
    XCTAssertTrue(script.contains("RESULT[APP_OWNS_RUNTIME]=skip"))
    XCTAssertTrue(script.contains("mark_pre_start_skips\n    print -u2 \"blocked: $BLOCKED_REASON\""))
  }

  func testBlockerLogContainsSpecificNonSensitiveReason() throws {
    let script = try read("Scripts/m14_002_real_user_install_acceptance.sh")

    XCTAssertTrue(script.contains("blocked: $BLOCKED_REASON"))
    XCTAssertTrue(script.contains("production app target exists"))
    XCTAssertTrue(script.contains("production LaunchAgent target exists"))
    XCTAssertTrue(script.contains("production launchd label already loaded"))
    XCTAssertTrue(script.contains("production process already running"))
    XCTAssertTrue(script.contains("active acceptance lock exists"))
  }

  func testGenericInstallOrConfigurationDetectedMessageIsProhibited() throws {
    let script = try read("Scripts/m14_002_real_user_install_acceptance.sh")

    XCTAssertFalse(script.contains("install or configuration detected"))
    XCTAssertFalse(script.contains("pre-existing Hermes Bridge install or configuration detected"))
  }

  func testUserScopePathPolicy() throws {
    let script = try read("Scripts/m14_002_real_user_install_acceptance.sh")

    XCTAssertTrue(script.contains("APP_TARGET=\"$HOME/Applications/$APP_NAME\""))
    XCTAssertTrue(script.contains("LAUNCH_AGENT_TARGET=\"$HOME/Library/LaunchAgents/com.hermes.bridge.plist\""))
    XCTAssertTrue(script.contains("LABEL=\"com.hermes.bridge\""))
    XCTAssertTrue(script.contains("MACH_SERVICE=\"com.hermes.bridge.xpc\""))
    XCTAssertTrue(script.contains("[[ \"$APP_TARGET\" != \"/Applications/\"* ]]"))
  }

  func testLaunchctlGuiDomainPolicy() throws {
    let script = try read("Scripts/m14_002_real_user_install_acceptance.sh")

    XCTAssertTrue(script.contains("SERVICE_DOMAIN=\"gui/$(id -u)\""))
    XCTAssertTrue(script.contains("launchctl bootstrap \"$SERVICE_DOMAIN\" \"$LAUNCH_AGENT_TARGET\""))
    XCTAssertTrue(script.contains("launchctl bootout \"$SERVICE_DOMAIN\" \"$LAUNCH_AGENT_TARGET\""))
    XCTAssertTrue(script.contains("launchctl print \"$SERVICE_DOMAIN/$LABEL\""))
  }

  func testExactPIDAndLabelCleanupPolicy() throws {
    let script = try read("Scripts/m14_002_real_user_install_acceptance.sh")

    XCTAssertTrue(script.contains("terminate_pid \"$APP_PID\""))
    XCTAssertTrue(script.contains("kill -TERM \"$pid\""))
    XCTAssertTrue(script.contains("pid_for_exact_executable \"$APP_EXECUTABLE\""))
    XCTAssertTrue(script.contains("SERVICE_PID"))
    XCTAssertTrue(script.contains("launchctl print \"$SERVICE_DOMAIN/$LABEL\""))
    XCTAssertTrue(script.contains("ACCEPTANCE_PROCESS_REMAINING"))
  }

  func testNoPrivilegedOrBroadProcessKillCommands() throws {
    let script = try read("Scripts/m14_002_real_user_install_acceptance.sh")

    XCTAssertFalse(script.contains("sudo "))
    XCTAssertFalse(script.contains("/usr/bin/sudo"))
    XCTAssertFalse(script.contains("killall"))
    XCTAssertFalse(script.contains("pkill"))
    XCTAssertFalse(script.contains("osascript"))
    XCTAssertTrue(script.contains("SUDO_USED no"))
    XCTAssertTrue(script.contains("BROAD_PROCESS_KILL_USED no"))
  }

  func testNoRealHermesHomeAccessBeyondMetadataGuard() throws {
    let script = try read("Scripts/m14_002_real_user_install_acceptance.sh")

    XCTAssertTrue(script.contains("path_state \"$REAL_HERMES_HOME\""))
    XCTAssertTrue(script.contains("os.lstat(path)"))
    XCTAssertTrue(script.contains("os.walk(root, followlinks=False)"))
    XCTAssertFalse(script.contains("cd \"$REAL_HERMES_HOME\""))
    XCTAssertFalse(script.contains("find \"$REAL_HERMES_HOME\""))
    XCTAssertFalse(script.contains("rm -rf \"$REAL_HERMES_HOME\""))
    XCTAssertFalse(script.contains("cat \"$REAL_HERMES_HOME\""))
    XCTAssertTrue(script.contains("REAL_HERMES_HOME_MODIFIED"))
  }

  func testInterruptionCleanup() throws {
    let script = try read("Scripts/m14_002_real_user_install_acceptance.sh")

    XCTAssertTrue(script.contains("trap cleanup EXIT"))
    XCTAssertTrue(script.contains("trap 'RESULT[M14_002_RESULT]=FAIL; exit 130' INT TERM"))
    XCTAssertTrue(script.contains("SERVICE_BOOTSTRAPPED_BY_RUN"))
    XCTAssertTrue(script.contains("APP_INSTALLED_BY_RUN"))
    XCTAssertTrue(script.contains("LAUNCH_AGENT_INSTALLED_BY_RUN"))
  }

  func testUnavailableAgentSkipSemantics() throws {
    let script = try read("Scripts/m14_002_real_user_install_acceptance.sh")
    let discovery = try extractFunction("discover_agent_status", from: script)

    XCTAssertTrue(script.contains("available|unavailable|incompatible|unknown"))
    XCTAssertTrue(script.contains("RESULT[AGENT_DEPENDENT_CHECK]=skip"))
    XCTAssertTrue(script.contains("HermesReleaseAgentPreflight"))
    XCTAssertTrue(script.contains("unavailable|incompatible|unknown)"))
    XCTAssertFalse(discovery.contains("local status"))
  }

  func testResultKeyCatalogIsCompleteUniqueAndOrdered() throws {
    let script = try read("Scripts/m14_002_real_user_install_acceptance.sh")
    let keys = try extractOrderedKeys(from: script)
    let required = [
      "EXPLICIT_OPT_IN_CONFIRMED",
      "USER_SCOPE_ONLY",
      "PREEXISTING_APP_FOUND",
      "PREEXISTING_LAUNCH_AGENT_FOUND",
      "BLOCKED_BY_PREEXISTING_INSTALL",
      "RELEASE_APP_BUILT",
      "APP_INSTALLED",
      "LAUNCH_AGENT_INSTALLED",
      "LAUNCH_AGENT_BOOTSTRAPPED",
      "APP_LAUNCHED",
      "SERVICE_RUNNING",
      "XPC_PROTOCOL_1_8_CONNECTED",
      "SERVICE_OWNS_RUNTIME",
      "APP_OWNS_RUNTIME",
      "SERVICE_RESTARTED",
      "APP_RECONNECTED_AFTER_RESTART",
      "APP_EXIT_LEFT_SERVICE_RUNNING",
      "APP_RELAUNCHED",
      "FINAL_RECONNECT_SUCCEEDED",
      "HERMES_AGENT_STATUS",
      "AGENT_DEPENDENT_CHECK",
      "SUDO_USED",
      "BROAD_PROCESS_KILL_USED",
      "REAL_HERMES_HOME_MODIFIED",
      "UNRELATED_KEYCHAIN_ACCESSED",
      "APP_TARGET_CLEANED",
      "LAUNCH_AGENT_TARGET_CLEANED",
      "ACCEPTANCE_PROCESS_REMAINING",
      "TEMPORARY_SECRET_REMAINING",
      "GENERATED_ARTIFACT_TRACKED_BY_GIT",
      "ENVIRONMENT_RESTORED",
      "M14_002_RESULT",
    ]

    XCTAssertEqual(keys, required)
    XCTAssertEqual(Set(keys).count, keys.count)
    XCTAssertTrue(script.contains("Duplicate result key"))
    XCTAssertTrue(script.contains("Missing result key"))
  }

  func testFinalResidueDecisionRules() throws {
    let script = try read("Scripts/m14_002_real_user_install_acceptance.sh")

    XCTAssertTrue(script.contains("validate_final_residue()"))
    XCTAssertTrue(script.contains("[[ ! -e \"$APP_TARGET\" ]] && RESULT[APP_TARGET_CLEANED]=yes"))
    XCTAssertTrue(script.contains("[[ ! -e \"$LAUNCH_AGENT_TARGET\" ]] && RESULT[LAUNCH_AGENT_TARGET_CLEANED]=yes"))
    XCTAssertTrue(script.contains("GENERATED_ARTIFACT_TRACKED_BY_GIT"))
    XCTAssertTrue(script.contains("TEMPORARY_SECRET_REMAINING]=no"))
    XCTAssertTrue(script.contains("M14_002_RESULT]=$([[ \"$pass\" == \"yes\" ]]"))
    XCTAssertTrue(script.contains("PASS || print -r -- FAIL"))
  }

  func testFinalExitCodeIsDerivedFromFinalResult() throws {
    let script = try read("Scripts/m14_002_real_user_install_acceptance.sh")
    let mapper = try extractFunction("result_exit_code", from: script)

    XCTAssertTrue(mapper.contains("PASS) return 0"))
    XCTAssertTrue(mapper.contains("OPT_IN_REQUIRED) return 2"))
    XCTAssertTrue(mapper.contains("BLOCKED) return 3"))
    XCTAssertTrue(mapper.contains("FAIL) return 1"))
    XCTAssertTrue(script.contains("finish_result\n  FINISHED=\"yes\"\n  result_exit_code"))
  }

  func testFailResultCanNeverMapToZeroExit() throws {
    let script = try read("Scripts/m14_002_real_user_install_acceptance.sh")
    let mapper = try extractFunction("result_exit_code", from: script)
    let failRange = try XCTUnwrap(mapper.range(of: "FAIL) return 1"))
    let passRange = try XCTUnwrap(mapper.range(of: "PASS) return 0"))

    XCTAssertLessThan(passRange.lowerBound, failRange.lowerBound)
    XCTAssertFalse(mapper.contains("FAIL) return 0"))
    XCTAssertFalse(mapper.contains("*) return 0"))
  }

  func testLaunchAgentCarriesExplicitIsolatedWritableRootConfiguration() throws {
    let script = try read("Scripts/m14_002_real_user_install_acceptance.sh")
    let install = try extractFunction("install_app_and_service", from: script)

    XCTAssertTrue(install.contains(#""EnvironmentVariables""#))
    XCTAssertTrue(install.contains(#""HERMES_BRIDGE_SERVICE_CONFIG": config"#))
    XCTAssertTrue(install.contains(#""HOME": home"#))
    XCTAssertTrue(install.contains(#""CFFIXED_USER_HOME": home"#))
    XCTAssertTrue(install.contains(#""HERMES_HOME": hermes_home"#))
    XCTAssertTrue(install.contains(#""XDG_CONFIG_HOME": xdg_config"#))
    XCTAssertTrue(install.contains(#""XDG_CACHE_HOME": xdg_cache"#))
    XCTAssertTrue(install.contains(#""XDG_DATA_HOME": xdg_data"#))
    XCTAssertTrue(install.contains(#""XDG_STATE_HOME": xdg_state"#))
    XCTAssertTrue(install.contains(#""XDG_RUNTIME_DIR": xdg_runtime"#))
    XCTAssertTrue(script.contains("ISOLATED_HERMES_HOME=\"$RUNTIME_ROOT/hermes-home\""))
    XCTAssertTrue(script.contains("ISOLATED_XDG_CACHE_HOME=\"$RUNTIME_ROOT/xdg-cache\""))
  }

  func testTerminalOnlyEnvironmentIsInsufficientForLaunchd() throws {
    let script = try read("Scripts/m14_002_real_user_install_acceptance.sh")
    let install = try extractFunction("install_app_and_service", from: script)

    XCTAssertTrue(install.contains(#""EnvironmentVariables""#))
    XCTAssertFalse(script.contains("export HERMES_BRIDGE_SERVICE_CONFIG"))
    XCTAssertFalse(script.contains("launchctl setenv"))
  }

  func testAppServiceAndHelpersUseSameIsolatedRuntimeRoot() throws {
    let script = try read("Scripts/m14_002_real_user_install_acceptance.sh")

    XCTAssertTrue(script.contains("RUNTIME_ROOT=\"$ARTIFACT_DIR/runtime\""))
    XCTAssertTrue(script.contains("runtimeRoot\": Path(sys.argv[2]).resolve().as_uri()"))
    XCTAssertTrue(script.contains("requestStateRoot\": Path(sys.argv[3]).resolve().as_uri()"))
    XCTAssertTrue(script.contains("--env \"HOME=$ISOLATED_HOME\""))
    XCTAssertTrue(script.contains("isolated_env_prefix \"$CONTROL_EXECUTABLE\" protocol-version"))
    XCTAssertTrue(script.contains("isolated_env_prefix swift run --configuration release HermesReleaseAgentPreflight"))
  }

  func testApplicationSupportAuditLogUpdateAndRuntimeStateAreIsolated() throws {
    let script = try read("Scripts/m14_002_real_user_install_acceptance.sh")

    XCTAssertTrue(script.contains("HERMES_CONFIG_DIR=\"$RUNTIME_ROOT/HermesBridge\""))
    XCTAssertTrue(script.contains("RUNTIME_DATA_ROOT=\"$RUNTIME_ROOT/Runtime\""))
    XCTAssertTrue(script.contains("REQUEST_STATE_ROOT=\"$RUNTIME_ROOT/RequestState\""))
    XCTAssertTrue(script.contains("LOGS_ROOT=\"$RUNTIME_ROOT/Logs\""))
    XCTAssertTrue(script.contains("REAL_HERMES_CACHES=\"$HOME/Library/Caches/HermesBridge\""))
    XCTAssertTrue(script.contains("REAL_HERMES_LOGS=\"$HOME/Library/Logs/HermesBridge\""))
    XCTAssertTrue(script.contains(#""StandardOutPath": str(Path(logs) / "service.stdout.log")"#))
  }

  func testLifecycleInstallStateWriteIsNotUsedInRealHome() throws {
    let script = try read("Scripts/m14_002_real_user_install_acceptance.sh")
    let install = try extractFunction("install_app_and_service", from: script)
    let cleanup = try extractFunction("cleanup", from: script)

    XCTAssertFalse(install.contains("HermesBridgeServiceLifecycle"))
    XCTAssertFalse(install.contains("--install-user-service"))
    XCTAssertFalse(cleanup.contains("HermesBridgeServiceLifecycle"))
    XCTAssertFalse(cleanup.contains("purge"))
  }

  func testIntegritySnapshotDoesNotReadFileContentsAndRedactsHome() throws {
    let script = try read("Scripts/m14_002_real_user_install_acceptance.sh")
    let snapshot = try extractFunction("write_real_home_integrity_snapshot", from: script)

    XCTAssertTrue(snapshot.contains("os.lstat(path)"))
    XCTAssertTrue(snapshot.contains("path.relative_to(root).as_posix()"))
    XCTAssertTrue(snapshot.contains("category"))
    XCTAssertTrue(snapshot.contains("followlinks=False"))
    XCTAssertFalse(snapshot.contains("read_text"))
    XCTAssertFalse(snapshot.contains("read_bytes"))
    XCTAssertFalse(snapshot.contains("Data(contentsOf"))
    XCTAssertFalse(snapshot.contains("/Users/"))
  }

  func testDetectedRealHomeMutationForcesFail() throws {
    let script = try read("Scripts/m14_002_real_user_install_acceptance.sh")
    let finish = try extractFunction("finish_result", from: script)
    let compare = try extractFunction("set_real_home_modified_result", from: script)

    XCTAssertTrue(compare.contains("RESULT[REAL_HERMES_HOME_MODIFIED]=yes"))
    XCTAssertTrue(compare.contains("RESULT[REAL_HERMES_HOME_MODIFIED]=no"))
    XCTAssertTrue(finish.contains("REAL_HERMES_HOME_MODIFIED"))
    XCTAssertTrue(finish.contains("[[ \"${RESULT[$key]}\" == \"no\" ]] || pass=\"no\""))
  }

  func testUnchangedRealHomeSnapshotPermitsPass() throws {
    let script = try read("Scripts/m14_002_real_user_install_acceptance.sh")
    let compare = try extractFunction("set_real_home_modified_result", from: script)

    XCTAssertTrue(compare.contains("if compare_real_home_integrity_snapshot; then"))
    XCTAssertTrue(compare.contains("RESULT[REAL_HERMES_HOME_MODIFIED]=no"))
  }

  func testRealHomeMutationDiagnosticsAreMetadataOnly() throws {
    let script = try read("Scripts/m14_002_real_user_install_acceptance.sh")
    let compare = try extractFunction("compare_real_home_integrity_snapshot", from: script)
    let diagnostics = try extractFunction("emit_real_home_mutation_diagnostics", from: script)

    XCTAssertTrue(compare.contains("before_row[\"type\"]"))
    XCTAssertTrue(compare.contains("after_row[\"type\"]"))
    XCTAssertTrue(compare.contains("before_row[\"size\"]"))
    XCTAssertTrue(compare.contains("after_row[\"size\"]"))
    XCTAssertTrue(compare.contains("before_row[\"mtime_ns\"]"))
    XCTAssertTrue(compare.contains("after_row[\"mtime_ns\"]"))
    XCTAssertTrue(diagnostics.contains("relative_path={rel}"))
    XCTAssertTrue(diagnostics.contains("before_type={before_type} after_type={after_type}"))
    XCTAssertTrue(diagnostics.contains("before_size={before_size} after_size={after_size}"))
    XCTAssertTrue(diagnostics.contains("before_mtime_ns={before_mtime} after_mtime_ns={after_mtime}"))
    XCTAssertFalse(diagnostics.contains("/Users/"))
  }

  func testCleanupDoesNotModifyProtectedPreexistingUserState() throws {
    let script = try read("Scripts/m14_002_real_user_install_acceptance.sh")
    let cleanup = try extractFunction("cleanup", from: script)

    XCTAssertFalse(cleanup.contains("rm -rf \"$REAL_HERMES_HOME\""))
    XCTAssertFalse(cleanup.contains("rm -rf \"$BRIDGE_SUPPORT\""))
    XCTAssertFalse(cleanup.contains("rm -rf \"$REAL_HERMES_CACHES\""))
    XCTAssertFalse(cleanup.contains("rm -rf \"$REAL_HERMES_LOGS\""))
    XCTAssertTrue(cleanup.contains("set_real_home_modified_result"))
  }

  func testDocumentationExists() throws {
    let doc = try read("Docs/Release/M14_002RealUserInstallAcceptance.md")

    XCTAssertTrue(doc.contains("Prerequisites"))
    XCTAssertTrue(doc.contains("HERMES_REAL_USER_INSTALL_ACCEPTANCE=YES"))
    XCTAssertTrue(doc.contains("~/Applications/Hermes Bridge.app"))
    XCTAssertTrue(doc.contains("~/Library/LaunchAgents/com.hermes.bridge.plist"))
    XCTAssertTrue(doc.contains("Agent Unavailable"))
    XCTAssertTrue(doc.contains("Manual Recovery"))
  }

  func testQuiesceRequiresExactRootPID() throws {
    let harness = try QuiesceHarness(root: root)
    let missing = try harness.run(arguments: [])
    let nonNumeric = try harness.run(arguments: ["abc"])

    XCTAssertNotEqual(missing.status, 0)
    XCTAssertTrue(missing.stderr.contains("usage:"))
    XCTAssertNotEqual(nonNumeric.status, 0)
    XCTAssertTrue(nonNumeric.stderr.contains("root Hermes PID must be numeric"))
  }

  func testQuiesceRequiresCurrentUserOwnership() throws {
    let harness = try QuiesceHarness(root: root)
    let result = try harness.run(arguments: ["100"], environment: ["HERMES_TEST_ROOT_UID": "999"])

    XCTAssertNotEqual(result.status, 0)
    XCTAssertTrue(result.stderr.contains("root process is not owned by the current user"))
    XCTAssertEqual(try harness.killLog(), "")
  }

  func testQuiesceEnumeratesExactPGIDIncludesChildrenAndExcludesUnrelatedPGID() throws {
    let harness = try QuiesceHarness(root: root)
    let result = try harness.run(arguments: ["100"])

    XCTAssertEqual(result.status, 0)
    XCTAssertTrue(result.stdout.contains("100\t1\t700\tHermes"))
    XCTAssertTrue(result.stdout.contains("101\t100\t700\tHermes Helper"))
    XCTAssertFalse(result.stdout.contains("102\t1\t800"))
    XCTAssertEqual(try harness.acceptanceInvocations(), 1)
  }

  func testQuiesceRejectsAnotherUIDProcessGroupMember() throws {
    let harness = try QuiesceHarness(root: root)
    let result = try harness.run(arguments: ["100"], environment: ["HERMES_TEST_OTHER_UID_MEMBER": "YES"])

    XCTAssertNotEqual(result.status, 0)
    XCTAssertTrue(result.stderr.contains("process-group member 103 is not owned by the current user"))
    XCTAssertEqual(try harness.killLog(), "")
  }

  func testQuiesceRefusesIfRootExitsBeforeSuspension() throws {
    let harness = try QuiesceHarness(root: root)
    let result = try harness.run(arguments: ["100"], environment: ["HERMES_TEST_ROOT_GONE_AFTER_ENUM": "YES"])

    XCTAssertNotEqual(result.status, 0)
    XCTAssertTrue(result.stderr.contains("supplied root process exited before suspension"))
    XCTAssertEqual(try harness.killLog(), "")
  }

  func testQuiesceStopContSymmetryAndAcceptanceOnce() throws {
    let harness = try QuiesceHarness(root: root)
    let result = try harness.run(arguments: ["100"])
    let signals = try harness.killLog().split(separator: "\n").map(String.init)

    XCTAssertEqual(result.status, 0)
    XCTAssertEqual(signals, ["-STOP 100", "-STOP 101", "-CONT 100", "-CONT 101"])
    XCTAssertEqual(try harness.acceptanceInvocations(), 1)
  }

  func testQuiesceInterruptCleanupContinuesRecordedPids() throws {
    let harness = try QuiesceHarness(root: root)
    let result = try harness.run(arguments: ["100"], environment: ["HERMES_TEST_ACCEPTANCE_SLEEP": "YES"], interruptAfter: 0.5)
    let signals = try harness.killLog().split(separator: "\n").map(String.init)

    XCTAssertNotEqual(result.status, 0)
    XCTAssertTrue(signals.contains("-STOP 100"))
    XCTAssertTrue(signals.contains("-STOP 101"))
    XCTAssertTrue(signals.contains("-CONT 100"))
    XCTAssertTrue(signals.contains("-CONT 101"))
    XCTAssertEqual(try harness.acceptanceInvocations(), 1)
  }

  func testQuiesceDoesNotUseBroadPrivilegedCommands() throws {
    let script = try read("Scripts/m14_002_quiesce_real_hermes.zsh")

    XCTAssertFalse(script.contains("pkill"))
    XCTAssertFalse(script.contains("killall"))
    XCTAssertFalse(script.contains("sudo"))
    XCTAssertFalse(script.contains("\"-$"))
    XCTAssertTrue(script.contains("\"$KILL_BIN\" -STOP \"$pid\""))
    XCTAssertTrue(script.contains("\"$KILL_BIN\" -CONT \"$pid\""))
  }

  func testQuiescePropagatesFailExitCode() throws {
    let harness = try QuiesceHarness(root: root)
    let result = try harness.run(arguments: ["100"], environment: ["HERMES_TEST_ACCEPTANCE_EXIT": "1"])

    XCTAssertEqual(result.status, 1)
    XCTAssertEqual(try harness.acceptanceInvocations(), 1)
    XCTAssertTrue(try harness.killLog().contains("-CONT 100"))
  }

  func testQuiescePropagatesPassExitCode() throws {
    let harness = try QuiesceHarness(root: root)
    let result = try harness.run(arguments: ["100"], environment: ["HERMES_TEST_ACCEPTANCE_EXIT": "0"])

    XCTAssertEqual(result.status, 0)
    XCTAssertEqual(try harness.acceptanceInvocations(), 1)
    XCTAssertTrue(try harness.killLog().contains("-CONT 101"))
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

  private struct CommandResult {
    let status: Int32
    let stdout: String
    let stderr: String
  }

  private final class QuiesceHarness {
    let directory: URL
    let root: URL
    let ps: URL
    let kill: URL
    let acceptance: URL
    let killLogURL: URL
    let acceptanceLog: URL

    init(root: URL) throws {
      self.root = root
      directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("hermes-quiesce-tests-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      ps = directory.appendingPathComponent("ps")
      kill = directory.appendingPathComponent("kill")
      acceptance = directory.appendingPathComponent("acceptance.zsh")
      killLogURL = directory.appendingPathComponent("kill.log")
      acceptanceLog = directory.appendingPathComponent("acceptance.log")
      try writeExecutable(ps, contents: Self.fakePS)
      try writeExecutable(kill, contents: Self.fakeKill)
      try writeExecutable(acceptance, contents: Self.fakeAcceptance)
    }

    func run(
      arguments: [String],
      environment extraEnvironment: [String: String] = [:],
      interruptAfter: TimeInterval? = nil
    ) throws -> CommandResult {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/bin/zsh")
      process.arguments = [root.appendingPathComponent("Scripts/m14_002_quiesce_real_hermes.zsh").path] + arguments
      var environment = ProcessInfo.processInfo.environment
      environment["HERMES_M14_002_PS"] = ps.path
      environment["HERMES_M14_002_KILL"] = kill.path
      environment["HERMES_M14_002_ACCEPTANCE_SCRIPT"] = acceptance.path
      environment["HERMES_M14_002_CURRENT_UID"] = "501"
      environment["HERMES_QUIESCE_REAL_AGENT"] = "YES"
      environment["HERMES_TEST_KILL_LOG"] = killLogURL.path
      environment["HERMES_TEST_ACCEPTANCE_LOG"] = acceptanceLog.path
      environment["HERMES_TEST_ROOT_SEEN"] = directory.appendingPathComponent("root-seen").path
      for (key, value) in extraEnvironment {
        environment[key] = value
      }
      process.environment = environment

      let stdout = Pipe()
      let stderr = Pipe()
      process.standardOutput = stdout
      process.standardError = stderr
      try process.run()
      if let interruptAfter {
        Thread.sleep(forTimeInterval: interruptAfter)
        process.interrupt()
      }
      process.waitUntilExit()
      return CommandResult(
        status: process.terminationStatus,
        stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
        stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      )
    }

    func killLog() throws -> String {
      guard FileManager.default.fileExists(atPath: killLogURL.path) else { return "" }
      return try String(contentsOf: killLogURL, encoding: .utf8)
    }

    func acceptanceInvocations() throws -> Int {
      guard FileManager.default.fileExists(atPath: acceptanceLog.path) else { return 0 }
      return try String(contentsOf: acceptanceLog, encoding: .utf8)
        .split(separator: "\n")
        .count
    }

    private func writeExecutable(_ url: URL, contents: String) throws {
      try contents.write(to: url, atomically: true, encoding: .utf8)
      try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private static let fakePS = """
      #!/bin/zsh
      uid="${HERMES_TEST_CURRENT_UID:-501}"
      root_uid="${HERMES_TEST_ROOT_UID:-$uid}"
      if [[ "$*" == *" -p 100"* ]]; then
        if [[ "${HERMES_TEST_ROOT_GONE:-}" == "YES" ]]; then exit 0; fi
        if [[ "${HERMES_TEST_ROOT_GONE_AFTER_ENUM:-}" == "YES" && -f "$HERMES_TEST_ROOT_SEEN" ]]; then exit 0; fi
        print -r -- " 100 1 700 $root_uid /tmp/Hermes"
        print -r -- seen > "$HERMES_TEST_ROOT_SEEN"
        exit 0
      fi
      if [[ "$*" == *"-axo"* ]]; then
        print -r -- " 100 1 700 $uid /tmp/Hermes"
        print -r -- " 101 100 700 $uid /tmp/Hermes Helper"
        print -r -- " 102 1 800 $uid /tmp/Other"
        if [[ "${HERMES_TEST_OTHER_UID_MEMBER:-}" == "YES" ]]; then
          print -r -- " 103 100 700 999 /tmp/Intruder"
        fi
        exit 0
      fi
      exit 1
      """

    private static let fakeKill = """
      #!/bin/zsh
      print -r -- "$*" >> "$HERMES_TEST_KILL_LOG"
      exit 0
      """

    private static let fakeAcceptance = """
      #!/bin/zsh
      print -r -- "acceptance" >> "$HERMES_TEST_ACCEPTANCE_LOG"
      if [[ "${HERMES_TEST_ACCEPTANCE_SLEEP:-}" == "YES" ]]; then
        sleep 5
      fi
      exit "${HERMES_TEST_ACCEPTANCE_EXIT:-0}"
      """
  }
}
