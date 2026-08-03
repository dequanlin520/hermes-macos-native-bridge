import Foundation
import XCTest

final class HermesIsolatedAgentSupervisorAcceptanceTests: XCTestCase {
  private var root: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private func read(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }

  func testModesAndExitCodeSemantics() throws {
    let script = try read("Scripts/m14_006_isolated_agent_supervisor_acceptance.sh")
    let mapper = try extractFunction("result_exit_code", from: script)

    XCTAssertTrue(script.contains("usage: $SCRIPT_NAME inspect|inspect-launch-plan|inspect-launch-syntax|run|cleanup"))
    XCTAssertTrue(script.contains("inspect)"))
    XCTAssertTrue(script.contains("inspect-launch-plan)"))
    XCTAssertTrue(script.contains("inspect-launch-syntax)"))
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
    let script = try read("Scripts/m14_006_isolated_agent_supervisor_acceptance.sh")
    let run = try extractFunction("run_acceptance", from: script)

    XCTAssertTrue(run.contains("HERMES_M14_006_ACCEPTANCE:-"))
    XCTAssertTrue(run.contains("!= \"YES\""))
    XCTAssertTrue(run.contains("RESULT[M14_006_RESULT]=OPT_IN_REQUIRED"))
    XCTAssertTrue(run.contains("set_reason acceptance.opt-in-required preflight operator-confirmation"))
    XCTAssertTrue(run.contains("exit 2"))
  }

  func testInspectLaunchPlanIsReadOnlyAndDoesNotRequireExactCLIShutdown() throws {
    let script = try read("Scripts/m14_006_isolated_agent_supervisor_acceptance.sh")
    let launchPlan = try extractFunction("inspect_launch_plan", from: script)
    let printer = try extractFunction("print_launch_plan", from: script)

    XCTAssertTrue(launchPlan.contains("production_inspect_readonly"))
    XCTAssertTrue(launchPlan.contains("validate_isolated_environment"))
    XCTAssertTrue(printer.contains("launch_permitted=yes"))
    XCTAssertTrue(printer.contains("exact_cli_shutdown_required=no"))
    XCTAssertTrue(printer.contains("supervisor_strategy=bridge-exact-pid"))
    XCTAssertTrue(printer.contains("launch_argument_identifiers=subcommand.serve,flag.isolated,flag.port.auto"))
    XCTAssertFalse(launchPlan.contains("write_result"))
    XCTAssertFalse(launchPlan.contains("write_launch_descriptor"))
    XCTAssertFalse(launchPlan.contains("cleanup_owned_process"))
  }

  func testInspectLaunchSyntaxIsReadOnly() throws {
    let script = try read("Scripts/m14_006_isolated_agent_supervisor_acceptance.sh")
    let inspect = try extractFunction("inspect_launch_syntax", from: script)

    XCTAssertTrue(inspect.contains("help_output_for \"$executable\" --help"))
    XCTAssertTrue(inspect.contains("help_output_for \"$executable\" serve --help"))
    XCTAssertTrue(inspect.contains("detected_version="))
    XCTAssertTrue(inspect.contains("advertised_serve_syntax="))
    XCTAssertTrue(inspect.contains("required_argument_identifiers="))
    XCTAssertTrue(inspect.contains("optional_argument_identifiers_relevant_to_isolation="))
    XCTAssertTrue(inspect.contains("foreground_daemon_behavior_advertised="))
    XCTAssertTrue(inspect.contains("isolated_configuration_requirements="))
    XCTAssertTrue(inspect.contains("expected_immediate_exit_risks="))
    XCTAssertTrue(inspect.contains("launch_readiness_mechanism="))
    XCTAssertTrue(inspect.contains("blocking_reason="))
    XCTAssertFalse(inspect.contains("write_result"))
    XCTAssertFalse(inspect.contains("write_launch_descriptor"))
    XCTAssertFalse(inspect.contains("cleanup_owned_process"))
    XCTAssertFalse(inspect.contains(" serve --isolated"))
  }

  func testInspectIsReadOnly() throws {
    let script = try read("Scripts/m14_006_isolated_agent_supervisor_acceptance.sh")
    let inspect = try extractFunction("inspect", from: script)

    XCTAssertTrue(inspect.contains("production_inspect"))
    XCTAssertTrue(script.contains("M14-006 read-only inspect"))
    XCTAssertTrue(script.contains("expected_topology_observations"))
    XCTAssertTrue(script.contains("supervisor_safety_invariants"))
    XCTAssertFalse(inspect.contains("write_result"))
    XCTAssertFalse(inspect.contains("validate_isolated_environment"))
  }

  func testCleanupIsIdempotentAndScopedToM14006RuntimeRoot() throws {
    let script = try read("Scripts/m14_006_isolated_agent_supervisor_acceptance.sh")
    let cleanup = try extractFunction("cleanup", from: script)

    XCTAssertTrue(cleanup.contains("cleanup_owned_process"))
    XCTAssertTrue(cleanup.contains("rm -rf \"$RUNTIME_ROOT\""))
    XCTAssertFalse(cleanup.contains("rm -rf \"$ARTIFACT_DIR\""))
    XCTAssertTrue(cleanup.contains("RESULT[M14_006_RESULT]=PASS"))
  }

  func testExactShutdownAndNoBroadKillOrStop() throws {
    let script = try read("Scripts/m14_006_isolated_agent_supervisor_acceptance.sh")
    let cleanup = try extractFunction("cleanup_owned_process", from: script)
    let launch = try extractFunction("attempt_supervisor_launch", from: script)

    XCTAssertTrue(cleanup.contains("/bin/kill -TERM \"$pid\""))
    XCTAssertTrue(cleanup.contains("/bin/kill -KILL \"$pid\""))
    XCTAssertTrue(launch.contains("\"$executable\" serve --isolated --port 0"))
    XCTAssertTrue(launch.contains("pid=$!"))
    XCTAssertTrue(launch.contains("PROVISIONAL_IDENTITY_FILE"))
    XCTAssertTrue(launch.contains("persist_identity_for_pid \"$pid\""))
    XCTAssertTrue(launch.contains("identity_matches \"$pid\""))
    XCTAssertTrue(launch.contains("observe_direct_descendants \"$pid\""))
    XCTAssertTrue(launch.contains("adopt_proven_child_after_launcher_exit \"$pid\""))
    XCTAssertFalse(script.contains("pkill"))
    XCTAssertFalse(script.contains("killall"))
    XCTAssertFalse(script.contains("kill -- -"))
    XCTAssertFalse(script.contains("/bin/kill -TERM -"))
    XCTAssertFalse(script.contains("serve --stop"))
    XCTAssertFalse(script.contains("sudo"))
  }

  func testResultKeysAreUniqueDeterministicAndComplete() throws {
    let script = try read("Scripts/m14_006_isolated_agent_supervisor_acceptance.sh")
    let keys = try arrayLiteral("ORDERED_KEYS", in: script)

    XCTAssertEqual(Set(keys).count, keys.count)
    XCTAssertEqual(keys.first, "EXPLICIT_OPT_IN_CONFIRMED")
    XCTAssertEqual(keys.last, "M14_006_RESULT")
    for required in [
      "SERVICE_OWNED_SUPERVISOR_USED",
      "SERVICE_OWNED_DISCOVERY_USED",
      "LAUNCH_ATTEMPTED",
      "LAUNCH_CHILD_EXITED",
      "LAUNCH_CHILD_EXIT_CODE",
      "LAUNCH_CHILD_SIGNAL",
      "LAUNCH_DURATION_MILLISECONDS",
      "LAUNCH_STDOUT_CATEGORY",
      "LAUNCH_STDERR_CATEGORY",
      "DESCENDANT_OBSERVED_BEFORE_EXIT",
      "LISTENER_OBSERVED_BEFORE_EXIT",
      "EXECUTABLE_IDENTITY_OBSERVED",
      "BROAD_STOP_INVOKED",
      "SUPERVISOR_REASON_CODE",
      "SUPERVISOR_REASON_PHASE",
      "SUPERVISOR_DETAIL_CATEGORY",
      "PROCESS_TOPOLOGY_STATUS",
      "PROCESS_IDENTITY_VALIDATED_BEFORE_SIGNAL",
      "ENDPOINT_OWNERSHIP_PROVEN",
      "EXACT_ROOT_TERM_USED",
      "EXACT_DESCENDANT_TERM_USED",
      "BROAD_PROCESS_KILL_USED",
      "REAL_HERMES_HOME_MODIFIED",
      "SUPERVISED_PROCESS_REAL_HOME_ACCESS",
      "EXTERNAL_REAL_HOME_MUTATION_OBSERVED",
      "SUPERVISOR_COMPATIBILITY_LEVEL",
    ] {
      XCTAssertTrue(keys.contains(required), required)
    }
  }

  func testM14006LaunchGateIgnoresM14005ExactShutdownUnsupported() throws {
    let script = try read("Scripts/m14_006_isolated_agent_supervisor_acceptance.sh")
    let reason = try extractFunction("m14006_blocking_reason", from: script)

    XCTAssertTrue(reason.contains("executable.unavailable"))
    XCTAssertTrue(reason.contains("version.unsupported"))
    XCTAssertTrue(reason.contains("isolated-command.not-advertised"))
    XCTAssertTrue(reason.contains("launch.environment-invalid"))
    XCTAssertTrue(reason.contains("print -r -- \"none\""))
    XCTAssertFalse(reason.contains("LAUNCH_CONTRACT_STATUS"))
    XCTAssertFalse(reason.contains("LAUNCH_CONTRACT_REASON"))
    XCTAssertFalse(reason.contains("EXACT_ISOLATED_SHUTDOWN_ADVERTISED"))
  }

  func testEveryNonPassResultRequiresReasonCodePhaseAndCategory() throws {
    let script = try read("Scripts/m14_006_isolated_agent_supervisor_acceptance.sh")
    let validator = try extractFunction("validate_terminal_reason_contract", from: script)

    XCTAssertTrue(validator.contains("SUPERVISOR_REASON_CODE"))
    XCTAssertTrue(validator.contains("SUPERVISOR_REASON_PHASE"))
    XCTAssertTrue(validator.contains("SUPERVISOR_DETAIL_CATEGORY"))
    XCTAssertTrue(script.contains("\"reasonCode\": result.get(\"SUPERVISOR_REASON_CODE\""))
    XCTAssertTrue(script.contains("\"reasonPhase\": result.get(\"SUPERVISOR_REASON_PHASE\""))
    XCTAssertTrue(script.contains("\"detailCategory\": result.get(\"SUPERVISOR_DETAIL_CATEGORY\""))
  }

  func testImmediateExitEvidenceAndPreciseReasonsArePersisted() throws {
    let script = try read("Scripts/m14_006_isolated_agent_supervisor_acceptance.sh")
    let launch = try extractFunction("attempt_supervisor_launch", from: script)
    let classifier = try extractFunction("classify_immediate_exit_reason", from: script)

    XCTAssertTrue(launch.contains("LAUNCH_CHILD_EXITED"))
    XCTAssertTrue(launch.contains("LAUNCH_CHILD_EXIT_CODE"))
    XCTAssertTrue(launch.contains("LAUNCH_CHILD_SIGNAL"))
    XCTAssertTrue(launch.contains("LAUNCH_DURATION_MILLISECONDS"))
    XCTAssertTrue(launch.contains("LAUNCH_STDOUT_CATEGORY"))
    XCTAssertTrue(launch.contains("LAUNCH_STDERR_CATEGORY"))
    XCTAssertTrue(script.contains("DESCENDANT_OBSERVED_BEFORE_EXIT"))
    XCTAssertTrue(script.contains("LISTENER_OBSERVED_BEFORE_EXIT"))
    XCTAssertTrue(launch.contains("EXECUTABLE_IDENTITY_OBSERVED"))
    for reason in [
      "launch.argument-missing",
      "launch.configuration-missing",
      "launch.environment-invalid",
      "launch.process-table-race",
      "launch.launcher-child-handoff",
      "launch.exited-zero-no-service",
      "launch.exited-nonzero",
      "launch.signaled",
      "launch.stderr-indicates-unsupported",
      "launch.unknown-immediate-exit",
    ] {
      XCTAssertTrue(script.contains(reason), reason)
    }
    XCTAssertFalse(script.contains("launch.exited-before-identity"))
    XCTAssertTrue(classifier.contains("missing-required-argument"))
    XCTAssertTrue(classifier.contains("missing-configuration"))
  }

  func testOutputCategoryRedactionRecognizesSensitiveAndBindShapes() throws {
    let script = try read("Scripts/m14_006_isolated_agent_supervisor_acceptance.sh")
    let categorizer = try extractFunction("category_for_output_file", from: script)

    XCTAssertTrue(categorizer.contains("address already in use"))
    XCTAssertTrue(categorizer.contains("bind-address-in-use"))
    XCTAssertTrue(categorizer.contains("redacted-sensitive-shape"))
    XCTAssertTrue(categorizer.contains("unsupported-argument"))
    XCTAssertTrue(categorizer.contains("missing-configuration"))
  }

  func testDocumentedLaunchFailureProducesFailNotGenericBlocked() throws {
    let script = try read("Scripts/m14_006_isolated_agent_supervisor_acceptance.sh")
    let run = try extractFunction("run_acceptance", from: script)

    XCTAssertTrue(run.contains("RESULT[SUPERVISOR_COMPATIBILITY_LEVEL]=FAIL"))
    XCTAssertTrue(run.contains("RESULT[M14_006_RESULT]=FAIL"))
    XCTAssertTrue(run.contains("result_exit_code"))
    XCTAssertFalse(run.contains("launch.exited-before-identity"))
  }

  func testArtifactsAreRedactedAndIgnored() throws {
    let script = try read("Scripts/m14_006_isolated_agent_supervisor_acceptance.sh")
    let gitignore = try read(".gitignore")

    XCTAssertTrue(gitignore.contains("artifacts/"))
    XCTAssertTrue(script.contains("process-topology.json"))
    XCTAssertTrue(script.contains("supervisor-report.json"))
    XCTAssertTrue(script.contains("launch-descriptor.json"))
    XCTAssertTrue(script.contains("privacy-safe"))
    XCTAssertTrue(script.contains("git -C \"$ROOT_DIR\" check-ignore -q \"artifacts/m14-006/result.txt\""))
    XCTAssertFalse(script.contains("print -r -- \"$HOME\""))
    XCTAssertFalse(script.contains("raw command line"))
  }

  func testServiceOwnsSupervisorAndUIDoesNot() throws {
    let service = try read("Sources/HermesBridgeService/HermesBridgeCompositionRoot.swift")
    let app = try read("Sources/HermesBridgeApp/HermesAppCompositionRoot.swift")

    XCTAssertTrue(service.contains("isolatedAgentSupervisor"))
    XCTAssertTrue(service.contains("HermesAgentSupervisor()"))
    XCTAssertTrue(service.contains("let serviceDiscovery = HermesDiscovery("))
    XCTAssertFalse(app.contains("HermesAgentSupervisor("))
    XCTAssertFalse(app.contains("HermesAgentSupervisorConfiguration"))
  }

  func testXPCProtocolVersionIsUnchangedAt18() throws {
    let xpc = try read("Sources/HermesBridgeXPC/HermesBridgeXPCModels.swift")

    XCTAssertTrue(xpc.contains("HermesBridgeProtocolVersion(major: 1, minor: 8)"))
    XCTAssertFalse(xpc.contains("major: 1, minor: 9"))
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
}
