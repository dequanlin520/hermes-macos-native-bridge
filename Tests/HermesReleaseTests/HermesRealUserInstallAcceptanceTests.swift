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
    XCTAssertTrue(script.contains("[[ \"$(path_state \"$REAL_HERMES_HOME\")\" == \"$PRE_HERMES_HOME_STATE\" ]]"))
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

  func testDocumentationExists() throws {
    let doc = try read("Docs/Release/M14_002RealUserInstallAcceptance.md")

    XCTAssertTrue(doc.contains("Prerequisites"))
    XCTAssertTrue(doc.contains("HERMES_REAL_USER_INSTALL_ACCEPTANCE=YES"))
    XCTAssertTrue(doc.contains("~/Applications/Hermes Bridge.app"))
    XCTAssertTrue(doc.contains("~/Library/LaunchAgents/com.hermes.bridge.plist"))
    XCTAssertTrue(doc.contains("Agent Unavailable"))
    XCTAssertTrue(doc.contains("Manual Recovery"))
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
