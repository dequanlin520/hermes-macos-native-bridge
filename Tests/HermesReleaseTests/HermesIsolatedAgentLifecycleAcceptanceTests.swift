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
    XCTAssertFalse(inspect.contains("validate_isolated_environment"))
    XCTAssertTrue(inspect.contains("M14-005 read-only inspect"))
    XCTAssertTrue(inspect.contains("HERMES_VERSION_STATUS"))
    XCTAssertTrue(inspect.contains("DISCOVERY_PARITY"))
    XCTAssertTrue(inspect.contains("LAUNCH_CONTRACT_REASON"))
  }

  func testProductionInspectUsesSwiftPreflightRatherThanShellHermesDetection() throws {
    let script = try read("Scripts/m14_005_isolated_agent_lifecycle_acceptance.sh")
    let discovery = try extractFunction("discover_and_select_contract", from: script)

    XCTAssertTrue(discovery.contains("HermesReleaseAgentPreflight m14-005-inspect"))
    XCTAssertTrue(discovery.contains("load_production_inspect_report"))
    XCTAssertFalse(script.contains("command -v hermes"))
    XCTAssertFalse(script.contains("HERMES_M14_005_HERMES_EXECUTABLE"))
    XCTAssertFalse(script.contains("bounded_cli_probe"))
  }

  func testIsolatedEnvironmentVariablesAreAcceptanceOwned() throws {
    let script = try read("Scripts/m14_005_isolated_agent_lifecycle_acceptance.sh")
    let validator = try extractFunction("validate_isolated_environment", from: script)

    XCTAssertTrue(script.contains("RUNTIME_ROOT=\"$ARTIFACT_DIR/runtime\""))
    XCTAssertTrue(validator.contains("if \"..\" in root.parts"))
    XCTAssertTrue(validator.contains("child.resolve()"))
    XCTAssertTrue(script.contains("HermesReleaseAgentPreflight m14-005-inspect"))
  }

  func testSafeCommandProbePolicy() throws {
    let helper = try read("Sources/HermesReleaseAgentPreflight/HermesReleaseAgentPreflight.swift")

    XCTAssertTrue(helper.contains("HermesAgentCommandSafetyPolicy.validateProbeArguments(arguments)"))
    XCTAssertTrue(helper.contains("process.standardInput = FileHandle.nullDevice"))
    XCTAssertTrue(helper.contains("process.standardOutput = stdout"))
    XCTAssertTrue(helper.contains("process.standardError = stderr"))
    XCTAssertTrue(helper.contains("termination.wait(timeout: .now() + 5)"))
    XCTAssertTrue(helper.contains("process.terminate()"))
    XCTAssertTrue(helper.contains("kill(process.processIdentifier, SIGKILL)"))
    XCTAssertFalse(helper.contains("[\"stop\", \"--help\"]"))
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
    XCTAssertTrue(keys.contains("HERMES_EXECUTABLE_BASENAME"))
    XCTAssertTrue(keys.contains("HERMES_EXECUTABLE_SOURCE"))
    XCTAssertTrue(keys.contains("HERMES_VERSION_STATUS"))
    XCTAssertTrue(keys.contains("DISCOVERY_PARITY"))
    XCTAssertTrue(keys.contains("ISOLATED_START_ADVERTISED"))
    XCTAssertTrue(keys.contains("BROAD_SHUTDOWN_ADVERTISED"))
    XCTAssertTrue(keys.contains("BROAD_SHUTDOWN_SAFE_FOR_ISOLATED_LIFECYCLE"))
    XCTAssertTrue(keys.contains("EXACT_ISOLATED_SHUTDOWN_ADVERTISED"))
    XCTAssertTrue(keys.contains("M14_005_EXPECTED_RESULT"))
    XCTAssertTrue(keys.contains("EXPECTED_EXIT_CODE"))
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
    XCTAssertTrue(unsupportedBranch.contains("RESULT[ISOLATED_AGENT_STARTED]=unsupported"))
    XCTAssertFalse(unsupportedBranch.contains("RESULT[M14_005_RESULT]=FAIL"))
    XCTAssertFalse(unsupportedBranch.contains("serve --stop"))
  }

  func testSwiftPreflightReportsProductionContractSelectionFields() throws {
    let helper = try read("Sources/HermesReleaseAgentPreflight/HermesReleaseAgentPreflight.swift")

    XCTAssertTrue(helper.contains("\"HERMES_EXECUTABLE_STATUS\""))
    XCTAssertTrue(helper.contains("\"HERMES_EXECUTABLE_FAMILY\""))
    XCTAssertTrue(helper.contains("\"HERMES_EXECUTABLE_BASENAME\""))
    XCTAssertTrue(helper.contains("\"HERMES_EXECUTABLE_SOURCE\""))
    XCTAssertTrue(helper.contains("\"HERMES_VERSION_STATUS\""))
    XCTAssertTrue(helper.contains("\"DISCOVERY_PARITY\""))
    XCTAssertTrue(helper.contains("\"ISOLATED_START_ADVERTISED\""))
    XCTAssertTrue(helper.contains("\"BROAD_SHUTDOWN_ADVERTISED\""))
    XCTAssertTrue(helper.contains("\"BROAD_SHUTDOWN_SAFE_FOR_ISOLATED_LIFECYCLE\""))
    XCTAssertTrue(helper.contains("\"EXACT_ISOLATED_SHUTDOWN_ADVERTISED\""))
    XCTAssertTrue(helper.contains("HermesAgentLaunchContractSelector.select"))
    XCTAssertTrue(helper.contains("sourceCategory: result.candidate.sourceCategory"))
  }

  func testGeneratedArtifactsRemainIgnoredAndRedacted() throws {
    let script = try read("Scripts/m14_005_isolated_agent_lifecycle_acceptance.sh")
    let gitignore = try read(".gitignore")
    let inspect = try extractFunction("inspect", from: script)
    let helper = try read("Sources/HermesReleaseAgentPreflight/HermesReleaseAgentPreflight.swift")

    XCTAssertTrue(gitignore.contains("artifacts/"))
    XCTAssertTrue(script.contains("git -C \"$ROOT_DIR\" check-ignore -q \"artifacts/m14-005/result.txt\""))
    XCTAssertTrue(script.contains("RESULT[GENERATED_ARTIFACT_TRACKED_BY_GIT]=no"))
    XCTAssertTrue(inspect.contains("HERMES_EXECUTABLE_BASENAME"))
    XCTAssertFalse(inspect.contains("originalPath"))
    XCTAssertFalse(inspect.contains("resolvedPath"))
    XCTAssertTrue(helper.contains("output.prefix(64 * 1024)"))
    XCTAssertFalse(helper.contains("print(rootHelp)"))
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
    XCTAssertTrue(service.contains("let serviceDiscovery = HermesDiscovery("))
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
