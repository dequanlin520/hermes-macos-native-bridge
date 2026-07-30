import Foundation
import XCTest

final class HermesDynamicEndpointAcceptanceTests: XCTestCase {
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
    let script = try read("Scripts/m14_007_dynamic_endpoint_readiness_acceptance.sh")
    let mapper = try extractFunction("result_exit_code", from: script)

    XCTAssertTrue(script.contains("usage: $SCRIPT_NAME inspect|inspect-readiness-plan|run|cleanup"))
    XCTAssertTrue(script.contains("inspect)"))
    XCTAssertTrue(script.contains("inspect-readiness-plan)"))
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
    let run = try extractFunction("run_acceptance", from: try read("Scripts/m14_007_dynamic_endpoint_readiness_acceptance.sh"))

    XCTAssertTrue(run.contains("HERMES_M14_007_ACCEPTANCE:-"))
    XCTAssertTrue(run.contains("!= \"YES\""))
    XCTAssertTrue(run.contains("RESULT[M14_007_RESULT]=OPT_IN_REQUIRED"))
    XCTAssertTrue(run.contains("exit 2"))
  }

  func testInspectIsReadOnly() throws {
    let script = try read("Scripts/m14_007_dynamic_endpoint_readiness_acceptance.sh")
    let inspect = try extractFunction("inspect", from: script)
    let plan = try extractFunction("inspect_readiness_plan", from: script)

    XCTAssertTrue(inspect.contains("M14-007 read-only inspect"))
    XCTAssertTrue(inspect.contains("dynamic_endpoint_strategy="))
    XCTAssertTrue(inspect.contains("socket_ownership_facility="))
    XCTAssertTrue(inspect.contains("expected_readiness_mechanism=http-loopback-api-status"))
    XCTAssertFalse(inspect.contains("write_result"))
    XCTAssertFalse(inspect.contains("serve --isolated"))
    XCTAssertTrue(plan.contains("M14-007 read-only readiness plan"))
    XCTAssertTrue(plan.contains("detected_hermes_version="))
    XCTAssertTrue(plan.contains("selected_readiness_mechanism=http-loopback-api-status"))
    XCTAssertTrue(plan.contains("route_command_category=status"))
    XCTAssertTrue(plan.contains("hermes_identity_criteria="))
    XCTAssertTrue(plan.contains("service_discovery_strategy=acceptance-scoped-ownership-proven-endpoint-only"))
    XCTAssertTrue(plan.contains("retry_timeout_policy="))
    XCTAssertTrue(plan.contains("blocking_reason="))
    XCTAssertFalse(plan.contains("write_result"))
    XCTAssertFalse(plan.contains("serve --isolated"))
  }

  func testExactShutdownAndNoBroadOperations() throws {
    let script = try read("Scripts/m14_007_dynamic_endpoint_readiness_acceptance.sh")
    let cleanup = try extractFunction("cleanup_owned_process", from: script)

    XCTAssertTrue(cleanup.contains("/bin/kill -TERM \"$pid\""))
    XCTAssertTrue(cleanup.contains("/bin/kill -KILL \"$pid\""))
    XCTAssertTrue(script.contains("\"$executable\" serve --isolated --port 0"))
    XCTAssertTrue(script.contains("/usr/sbin/lsof -nP -a -p \"$pid\""))
    XCTAssertFalse(script.contains("killall"))
    XCTAssertFalse(script.contains("serve --stop"))
    XCTAssertFalse(script.contains("sudo"))
    XCTAssertFalse(script.contains("/bin/kill -TERM -"))
  }

  func testResultKeysAreUniqueDeterministicAndComplete() throws {
    let script = try read("Scripts/m14_007_dynamic_endpoint_readiness_acceptance.sh")
    let keys = try arrayLiteral("ORDERED_KEYS", in: script)

    XCTAssertEqual(Set(keys).count, keys.count)
    XCTAssertEqual(keys.first, "EXPLICIT_OPT_IN_CONFIRMED")
    XCTAssertEqual(keys.last, "M14_007_RESULT")
    for required in [
      "SERVICE_OWNED_ENDPOINT_DISCOVERY_USED",
      "SERVICE_OWNED_HERMES_DISCOVERY_USED",
      "DYNAMIC_PORT_REQUESTED",
      "LISTENER_OWNERSHIP_STATUS",
      "LISTENER_OWNER_RELATIONSHIP",
      "STARTUP_OUTPUT_ENDPOINT_MATCH",
      "READINESS_PROBE_ROUTE_CATEGORY",
      "READINESS_HTTP_STATUS",
      "READINESS_RESPONSE_CATEGORY",
      "READINESS_ATTEMPT_COUNT",
      "READINESS_DURATION_MILLISECONDS",
      "HERMES_ENDPOINT_IDENTITY_PROVEN",
      "SERVICE_DISCOVERY_ATTEMPTED",
      "DISCOVERY_ENDPOINT_MATCH",
      "LISTENER_REMAINING_AFTER_SHUTDOWN",
      "BROAD_STOP_INVOKED",
      "BROAD_PROCESS_KILL_USED",
      "SUPERVISED_PROCESS_REAL_HOME_ACCESS",
    ] {
      XCTAssertTrue(keys.contains(required), required)
    }
  }

  func testDynamicNumericPortAbsentFromResultTxtAndRuntimeEvidenceSeparated() throws {
    let script = try read("Scripts/m14_007_dynamic_endpoint_readiness_acceptance.sh")

    XCTAssertTrue(script.contains("Dynamic endpoint leaked into deterministic result"))
    XCTAssertTrue(script.contains("Non-PASS result requires stable reason"))
    XCTAssertTrue(script.contains("endpoint-evidence.json"))
    XCTAssertTrue(script.contains("readiness-report.json"))
    XCTAssertTrue(script.contains("privacy-safe-runtime-port-may-appear-in-evidence-only"))
  }

  func testReadinessRequiresHermesSpecificStatusShape() throws {
    let probe = try extractFunction("probe_readiness", from: try read("Scripts/m14_007_dynamic_endpoint_readiness_acceptance.sh"))

    XCTAssertTrue(probe.contains("/api/status"))
    XCTAssertTrue(probe.contains("READINESS_PROBE_ATTEMPTED]=yes"))
    XCTAssertTrue(probe.contains("READINESS_PROBE_ROUTE_CATEGORY]=status"))
    XCTAssertTrue(probe.contains("READINESS_HTTP_STATUS"))
    XCTAssertTrue(probe.contains("READINESS_RESPONSE_CATEGORY"))
    XCTAssertTrue(probe.contains("READINESS_ATTEMPT_COUNT]=1"))
    XCTAssertTrue(probe.contains("READINESS_DURATION_MILLISECONDS"))
    XCTAssertTrue(probe.contains("\"version\""))
    XCTAssertTrue(probe.contains("\"auth_required\""))
    XCTAssertTrue(probe.contains("\"gateway_running\""))
    XCTAssertTrue(probe.contains("readiness.http-not-found"))
    XCTAssertTrue(probe.contains("readiness.http-unexpected-status"))
    XCTAssertTrue(probe.contains("readiness.response-empty"))
    XCTAssertTrue(probe.contains("readiness.response-malformed"))
    XCTAssertTrue(probe.contains("readiness.identity-unproven"))
    XCTAssertTrue(probe.contains("rm -f \"$body\""))
    XCTAssertFalse(probe.contains("status-response.json"))
  }

  func testProvenEndpointAlwaysEntersReadinessBeforeServiceDiscovery() throws {
    let run = try extractFunction("run_acceptance", from: try read("Scripts/m14_007_dynamic_endpoint_readiness_acceptance.sh"))

    XCTAssertTrue(run.contains("RESULT[LISTENER_DETECTED]"))
    XCTAssertTrue(run.contains("RESULT[LISTENER_ADDRESS_SCOPE]"))
    XCTAssertTrue(run.contains("RESULT[LISTENER_OWNERSHIP_STATUS]"))
    XCTAssertTrue(run.contains("RESULT[ENDPOINT_UNIQUE]"))
    XCTAssertTrue(run.contains("if probe_readiness \"$assigned_port\"; then"))
    XCTAssertTrue(run.contains("scoped_service_discovery_match \"$assigned_port\" \"$endpoint\""))
    XCTAssertLessThan(
      run.range(of: "if probe_readiness \"$assigned_port\"; then")!.lowerBound,
      run.range(of: "scoped_service_discovery_match \"$assigned_port\" \"$endpoint\"")!.lowerBound
    )
  }

  func testScopedServiceDiscoveryDoesNotGlobalScan() throws {
    let script = try read("Scripts/m14_007_dynamic_endpoint_readiness_acceptance.sh")
    let discovery = try extractFunction("scoped_service_discovery_match", from: script)

    XCTAssertTrue(discovery.contains("acceptance-scoped-endpoint-only"))
    XCTAssertTrue(discovery.contains("global_scan_used=no"))
    XCTAssertTrue(discovery.contains("RESULT[SERVICE_DISCOVERY_ATTEMPTED]=yes"))
    XCTAssertTrue(discovery.contains("RESULT[M14_007_REASON_CODE]=discovery.endpoint-mismatch"))
    XCTAssertFalse(discovery.contains("command -v hermes"))
    XCTAssertFalse(discovery.contains("lsof"))
  }

  func testCleanupKeysFinalizedAfterReadinessFailure() throws {
    let script = try read("Scripts/m14_007_dynamic_endpoint_readiness_acceptance.sh")
    let finalize = try extractFunction("finalize_cleanup_evidence", from: script)
    let run = try extractFunction("run_acceptance", from: script)

    XCTAssertTrue(finalize.contains("LISTENER_REMAINING_AFTER_SHUTDOWN"))
    XCTAssertTrue(finalize.contains("ACCEPTANCE_PROCESS_REMAINING"))
    XCTAssertTrue(finalize.contains("ORPHAN_PROCESS_FOUND"))
    XCTAssertTrue(finalize.contains("SUPERVISED_PROCESS_REAL_HOME_ACCESS]=no"))
    XCTAssertTrue(finalize.contains("ENVIRONMENT_RESTORED]=yes"))
    XCTAssertTrue(run.contains("finalize_cleanup_evidence"))
    XCTAssertTrue(run.contains("readiness.connection-failed"))
    XCTAssertTrue(run.contains("readiness.timeout"))
  }

  func testCleanupIsIdempotentAndScoped() throws {
    let cleanup = try extractFunction("cleanup", from: try read("Scripts/m14_007_dynamic_endpoint_readiness_acceptance.sh"))

    XCTAssertTrue(cleanup.contains("cleanup_owned_process"))
    XCTAssertTrue(cleanup.contains("rm -rf \"$RUNTIME_ROOT\""))
    XCTAssertFalse(cleanup.contains("rm -rf \"$ARTIFACT_DIR\""))
    XCTAssertTrue(cleanup.contains("RESULT[M14_007_RESULT]=PASS"))
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
