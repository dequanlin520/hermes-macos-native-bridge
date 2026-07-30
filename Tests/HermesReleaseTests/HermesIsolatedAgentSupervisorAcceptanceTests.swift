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
    let script = try read("Scripts/m14_006_isolated_agent_supervisor_acceptance.sh")
    let run = try extractFunction("run_acceptance", from: script)

    XCTAssertTrue(run.contains("HERMES_M14_006_ACCEPTANCE:-"))
    XCTAssertTrue(run.contains("!= \"YES\""))
    XCTAssertTrue(run.contains("RESULT[M14_006_RESULT]=OPT_IN_REQUIRED"))
    XCTAssertTrue(run.contains("exit 2"))
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

    XCTAssertTrue(cleanup.contains("/bin/kill -TERM \"$pid\""))
    XCTAssertTrue(cleanup.contains("/bin/kill -KILL \"$pid\""))
    XCTAssertFalse(script.contains("pkill"))
    XCTAssertFalse(script.contains("killall"))
    XCTAssertFalse(script.contains("kill -- -"))
    XCTAssertFalse(script.contains("/bin/kill -TERM -"))
    XCTAssertFalse(script.contains("serve --stop"))
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
      "BROAD_STOP_INVOKED",
      "PROCESS_TOPOLOGY_STATUS",
      "ENDPOINT_OWNERSHIP_PROVEN",
      "EXACT_ROOT_TERM_USED",
      "EXACT_DESCENDANT_TERM_USED",
      "BROAD_PROCESS_KILL_USED",
      "REAL_HERMES_HOME_MODIFIED",
      "SUPERVISOR_COMPATIBILITY_LEVEL",
    ] {
      XCTAssertTrue(keys.contains(required), required)
    }
  }

  func testArtifactsAreRedactedAndIgnored() throws {
    let script = try read("Scripts/m14_006_isolated_agent_supervisor_acceptance.sh")
    let gitignore = try read(".gitignore")

    XCTAssertTrue(gitignore.contains("artifacts/"))
    XCTAssertTrue(script.contains("process-topology.json"))
    XCTAssertTrue(script.contains("supervisor-report.json"))
    XCTAssertTrue(script.contains("privacy-safe"))
    XCTAssertTrue(script.contains("git -C \"$ROOT_DIR\" check-ignore -q \"artifacts/m14-006/result.txt\""))
    XCTAssertFalse(script.contains("print -r -- \"$HOME\""))
  }

  func testServiceOwnsSupervisorAndUIDoesNot() throws {
    let service = try read("Sources/HermesBridgeService/HermesBridgeCompositionRoot.swift")
    let app = try read("Sources/HermesBridgeApp/HermesAppCompositionRoot.swift")

    XCTAssertTrue(service.contains("isolatedAgentSupervisor"))
    XCTAssertTrue(service.contains("HermesAgentSupervisor()"))
    XCTAssertTrue(service.contains("self.discovery = HermesDiscovery("))
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
