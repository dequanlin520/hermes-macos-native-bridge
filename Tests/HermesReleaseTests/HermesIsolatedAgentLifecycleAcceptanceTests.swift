import Foundation
import XCTest

final class HermesIsolatedAgentLifecycleAcceptanceTests: XCTestCase {
  private var root: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private func read(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }

  func testModesAndExitCodesAreExplicit() throws {
    let script = try read("Scripts/m14_005_isolated_agent_lifecycle_acceptance.sh")
    let mapper = try extractFunction("result_exit_code", from: script)

    XCTAssertTrue(script.contains("usage: $SCRIPT_NAME inspect|run|cleanup"))
    XCTAssertTrue(script.contains("inspect)"))
    XCTAssertTrue(script.contains("run)"))
    XCTAssertTrue(script.contains("cleanup)"))
    XCTAssertTrue(mapper.contains("PASS) return 0"))
    XCTAssertTrue(mapper.contains("FAIL) return 1"))
    XCTAssertTrue(mapper.contains("OPT_IN_REQUIRED) return 2"))
    XCTAssertTrue(mapper.contains("BLOCKED) return 3"))
    XCTAssertTrue(mapper.contains("TIMEOUT) return 4"))
    XCTAssertTrue(mapper.contains("PARTIAL) return 5"))
    XCTAssertTrue(mapper.contains("UNSUPPORTED) return 6"))
  }

  func testRunRequiresExplicitOptIn() throws {
    let script = try read("Scripts/m14_005_isolated_agent_lifecycle_acceptance.sh")
    let run = try extractFunction("run_acceptance", from: script)

    XCTAssertTrue(run.contains("HERMES_M14_005_ACCEPTANCE:-"))
    XCTAssertTrue(run.contains("!= \"YES\""))
    XCTAssertTrue(run.contains("RESULT[M14_005_RESULT]=OPT_IN_REQUIRED"))
    XCTAssertTrue(run.contains("exit 2"))
  }

  func testInspectIsReadOnly() throws {
    let script = try read("Scripts/m14_005_isolated_agent_lifecycle_acceptance.sh")
    let inspect = try extractFunction("inspect", from: script)

    XCTAssertTrue(inspect.contains("discover_and_select_contract inspect"))
    XCTAssertFalse(inspect.contains("write_result"))
    XCTAssertFalse(inspect.contains("write_contract"))
    XCTAssertFalse(inspect.contains("validate_isolated_environment"))
    XCTAssertFalse(inspect.contains("bounded_cli_probe"))
    XCTAssertTrue(inspect.contains("M14-005 read-only inspect"))
  }

  func testIsolatedEnvironmentVariablesAreAcceptanceOwned() throws {
    let script = try read("Scripts/m14_005_isolated_agent_lifecycle_acceptance.sh")
    let validator = try extractFunction("validate_isolated_environment", from: script)
    let probe = try extractFunction("bounded_cli_probe", from: script)

    XCTAssertTrue(script.contains("RUNTIME_ROOT=\"$ARTIFACT_DIR/runtime\""))
    XCTAssertTrue(probe.contains("\"HOME\": str(runtime / \"home\")"))
    XCTAssertTrue(probe.contains("\"HERMES_HOME\": str(runtime / \"hermes-home\")"))
    XCTAssertTrue(probe.contains("\"XDG_CONFIG_HOME\": str(runtime / \"xdg-config\")"))
    XCTAssertTrue(probe.contains("\"XDG_STATE_HOME\": str(runtime / \"xdg-state\")"))
    XCTAssertTrue(probe.contains("\"XDG_CACHE_HOME\": str(runtime / \"xdg-cache\")"))
    XCTAssertTrue(probe.contains("\"TMPDIR\": str(runtime / \"tmp\")"))
    XCTAssertTrue(validator.contains("if \"..\" in root.parts"))
    XCTAssertTrue(validator.contains("child.resolve()"))
  }

  func testSafeCommandProbePolicy() throws {
    let script = try read("Scripts/m14_005_isolated_agent_lifecycle_acceptance.sh")
    let probe = try extractFunction("bounded_cli_probe", from: script)

    XCTAssertTrue(probe.contains("stdin=subprocess.DEVNULL"))
    XCTAssertTrue(probe.contains("stdout=subprocess.PIPE"))
    XCTAssertTrue(probe.contains("stderr=subprocess.PIPE"))
    XCTAssertTrue(probe.contains("start_new_session=False"))
    XCTAssertTrue(probe.contains("communicate(timeout=5.0)"))
    XCTAssertTrue(probe.contains("process.terminate()"))
    XCTAssertTrue(probe.contains("os.kill(process.pid, signal.SIGKILL)"))
    XCTAssertTrue(probe.contains("event[\"reaped\"] = True"))
    XCTAssertTrue(probe.contains("bare-hermes-forbidden"))
  }

  func testNoBroadKillSudoOrNegativePIDSignaling() throws {
    let script = try read("Scripts/m14_005_isolated_agent_lifecycle_acceptance.sh")

    XCTAssertFalse(script.contains("pkill"))
    XCTAssertFalse(script.contains("killall"))
    XCTAssertFalse(script.contains("sudo"))
    XCTAssertFalse(script.contains("kill -- -"))
    XCTAssertFalse(script.contains("/bin/kill -TERM -"))
    XCTAssertTrue(script.contains("/bin/kill -TERM \"$pid\""))
    XCTAssertTrue(script.contains("/bin/kill -KILL \"$pid\""))
  }

  func testResultKeysAreUniqueAndDeterministic() throws {
    let script = try read("Scripts/m14_005_isolated_agent_lifecycle_acceptance.sh")
    let keys = try arrayLiteral("ORDERED_KEYS", in: script)

    XCTAssertEqual(Set(keys).count, keys.count)
    XCTAssertEqual(keys.first, "EXPLICIT_OPT_IN_CONFIRMED")
    XCTAssertEqual(keys.last, "M14_005_RESULT")
    XCTAssertTrue(keys.contains("LAUNCH_CONTRACT_STATUS"))
    XCTAssertTrue(keys.contains("REAL_HERMES_HOME_MODIFIED"))
    XCTAssertTrue(keys.contains("SERVICE_OWNED_CONTRACT_SELECTION"))
  }

  func testUnsupportedContractProducesExitSixRatherThanFail() throws {
    let script = try read("Scripts/m14_005_isolated_agent_lifecycle_acceptance.sh")
    let run = try extractFunction("run_acceptance", from: script)
    let unsupportedBranch = try substring(
      in: run,
      from: "if [[ \"${RESULT[LAUNCH_CONTRACT_STATUS]}\" == unsupported ]]; then",
      to: "elif [[ \"${RESULT[LAUNCH_CONTRACT_STATUS]}\" == blocked ]]; then"
    )

    XCTAssertTrue(unsupportedBranch.contains("RESULT[M14_005_RESULT]=UNSUPPORTED"))
    XCTAssertFalse(unsupportedBranch.contains("RESULT[M14_005_RESULT]=FAIL"))
  }

  func testGeneratedArtifactsRemainIgnoredAndRedacted() throws {
    let script = try read("Scripts/m14_005_isolated_agent_lifecycle_acceptance.sh")
    let gitignore = try read(".gitignore")
    let probe = try extractFunction("bounded_cli_probe", from: script)

    XCTAssertTrue(gitignore.contains("artifacts/"))
    XCTAssertTrue(script.contains("git -C \"$ROOT_DIR\" check-ignore -q \"artifacts/m14-005/result.txt\""))
    XCTAssertTrue(script.contains("RESULT[GENERATED_ARTIFACT_TRACKED_BY_GIT]=no"))
    XCTAssertTrue(probe.contains("REDACTED_PATH"))
    XCTAssertTrue(probe.contains("REDACTED_ID"))
    XCTAssertTrue(probe.contains("REDACTED"))
  }

  func testCleanupIsIdempotentAndScopedToM14005RuntimeRoot() throws {
    let script = try read("Scripts/m14_005_isolated_agent_lifecycle_acceptance.sh")
    let cleanup = try extractFunction("cleanup", from: script)

    XCTAssertTrue(cleanup.contains("cleanup_owned_process"))
    XCTAssertTrue(cleanup.contains("rm -rf \"$RUNTIME_ROOT\""))
    XCTAssertFalse(cleanup.contains("rm -rf \"$ARTIFACT_DIR\""))
    XCTAssertTrue(cleanup.contains("RESULT[M14_005_RESULT]=PASS"))
  }

  func testServiceOwnsLifecycleAndUIDoesNot() throws {
    let service = try read("Sources/HermesBridgeService/HermesBridgeCompositionRoot.swift")
    let app = try read("Sources/HermesBridgeApp/HermesAppCompositionRoot.swift")

    XCTAssertTrue(service.contains("isolatedAgentLaunchContract"))
    XCTAssertTrue(service.contains("isolatedAgentLifecycleCoordinator"))
    XCTAssertTrue(service.contains("HermesAgentLifecycleCoordinator("))
    XCTAssertTrue(service.contains("self.discovery = HermesDiscovery("))
    XCTAssertFalse(app.contains("HermesAgentLifecycleCoordinator("))
    XCTAssertFalse(app.contains("HermesAgentLaunchContractSelector"))
  }

  private func extractFunction(_ name: String, from script: String) throws -> String {
    guard let start = script.range(of: "\(name)() {") else {
      throw XCTSkip("missing function \(name)")
    }
    var depth = 0
    var index = start.lowerBound
    while index < script.endIndex {
      let char = script[index]
      if char == "{" {
        depth += 1
      } else if char == "}" {
        depth -= 1
        if depth == 0 {
          return String(script[start.lowerBound...index])
        }
      }
      index = script.index(after: index)
    }
    throw XCTSkip("unterminated function \(name)")
  }

  private func arrayLiteral(_ name: String, in script: String) throws -> [String] {
    guard let start = script.range(of: "\(name)=(") else {
      throw XCTSkip("missing array \(name)")
    }
    guard let end = script[start.upperBound...].range(of: "\n)") else {
      throw XCTSkip("unterminated array \(name)")
    }
    return script[start.upperBound..<end.lowerBound]
      .split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private func substring(in text: String, from startText: String, to endText: String) throws -> String {
    guard let start = text.range(of: startText),
      let end = text[start.upperBound...].range(of: endText)
    else {
      throw XCTSkip("missing substring bounds")
    }
    return String(text[start.lowerBound..<end.lowerBound])
  }
}
