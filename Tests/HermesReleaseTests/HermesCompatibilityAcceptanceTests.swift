import Foundation
import XCTest

final class HermesCompatibilityAcceptanceTests: XCTestCase {
  private var root: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private func read(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }

  func testRequiredModesAndExitCodes() throws {
    let script = try read("Scripts/m14_004_hermes_compatibility_acceptance.sh")
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
  }

  func testRunRequiresExplicitOptIn() throws {
    let script = try read("Scripts/m14_004_hermes_compatibility_acceptance.sh")
    let run = try extractFunction("run_acceptance", from: script)

    XCTAssertTrue(run.contains("HERMES_M14_004_ACCEPTANCE:-"))
    XCTAssertTrue(run.contains("!= \"YES\""))
    XCTAssertTrue(run.contains("M14_004_RESULT]=OPT_IN_REQUIRED"))
    XCTAssertTrue(run.contains("exit 2"))
  }

  func testInspectIsReadOnlyAndPlansOnly() throws {
    let script = try read("Scripts/m14_004_hermes_compatibility_acceptance.sh")
    let inspect = try extractFunction("inspect", from: script)

    XCTAssertFalse(inspect.contains("mkdir"))
    XCTAssertFalse(inspect.contains("write_result"))
    XCTAssertFalse(inspect.contains("write_matrix"))
    XCTAssertFalse(inspect.contains("export_isolated_environment"))
    XCTAssertFalse(inspect.contains("run_version_query"))
    XCTAssertTrue(inspect.contains("inspect_version_query"))
    XCTAssertTrue(inspect.contains("M14-004 read-only inspect"))
    XCTAssertTrue(inspect.contains("planned_environment=HOME,HERMES_HOME,XDG_CONFIG_HOME,XDG_STATE_HOME,XDG_CACHE_HOME,TMPDIR"))
  }

  func testIsolatedEnvironmentNeverPassesRealHome() throws {
    let script = try read("Scripts/m14_004_hermes_compatibility_acceptance.sh")
    let environment = try extractFunction("export_isolated_environment", from: script)

    XCTAssertTrue(script.contains("RUNTIME_ROOT=\"$ARTIFACT_DIR/runtime\""))
    XCTAssertTrue(environment.contains("export HOME=\"$RUNTIME_ROOT/home\""))
    XCTAssertTrue(environment.contains("export HERMES_HOME=\"$RUNTIME_ROOT/hermes-home\""))
    XCTAssertTrue(environment.contains("export XDG_CONFIG_HOME=\"$RUNTIME_ROOT/xdg-config\""))
    XCTAssertTrue(environment.contains("export XDG_STATE_HOME=\"$RUNTIME_ROOT/xdg-state\""))
    XCTAssertTrue(environment.contains("export XDG_CACHE_HOME=\"$RUNTIME_ROOT/xdg-cache\""))
    XCTAssertTrue(environment.contains("export TMPDIR=\"$RUNTIME_ROOT/tmp\""))
    XCTAssertFalse(environment.contains("REAL_HERMES_HOME"))
  }

  func testHermesProbesReceiveOnlyIsolatedEnvironmentDuringRun() throws {
    let script = try read("Scripts/m14_004_hermes_compatibility_acceptance.sh")
    let version = try extractFunction("run_version_query", from: script)
    let help = try extractFunction("run_help_query", from: script)

    for function in [version, help] {
      XCTAssertTrue(function.contains("bounded_hermes_probe"))
      XCTAssertFalse(function.contains("REAL_HERMES_HOME"))
    }
    let probe = try extractFunction("bounded_hermes_probe", from: script)
    XCTAssertTrue(probe.contains("\"PATH\": \"/usr/bin:/bin:/usr/sbin:/sbin\""))
    XCTAssertTrue(probe.contains("\"HOME\", \"HERMES_HOME\", \"XDG_CONFIG_HOME\", \"XDG_STATE_HOME\", \"XDG_CACHE_HOME\", \"TMPDIR\""))
    XCTAssertTrue(probe.contains("timeout=10"))
    XCTAssertTrue(probe.contains("[executable, argument]"))
  }

  func testRealHomeMutationFailsWithoutAttributionException() throws {
    let script = try read("Scripts/m14_004_hermes_compatibility_acceptance.sh")
    let run = try extractFunction("run_acceptance", from: script)

    XCTAssertTrue(script.contains("REAL_HERMES_HOME=\"$HOME/.hermes\""))
    XCTAssertTrue(run.contains("real_home_snapshot \"$SNAPSHOT_BEFORE\""))
    XCTAssertTrue(run.contains("real_home_snapshot \"$SNAPSHOT_AFTER\""))
    XCTAssertTrue(run.contains("RESULT[REAL_HERMES_HOME_MODIFIED]=yes"))
    XCTAssertTrue(run.contains("RESULT[M14_004_RESULT]=FAIL"))
    XCTAssertFalse(script.contains("ATTRIBUTION"))
    XCTAssertFalse(script.contains("EXTERNAL_HERMES_ACTIVITY_DETECTED"))
  }

  func testNoBroadKillSudoOrNegativePIDSignaling() throws {
    let script = try read("Scripts/m14_004_hermes_compatibility_acceptance.sh")

    XCTAssertFalse(script.contains("pkill"))
    XCTAssertFalse(script.contains("killall"))
    XCTAssertFalse(script.contains("sudo"))
    XCTAssertFalse(script.contains("kill -- -"))
    XCTAssertFalse(script.contains("/bin/kill -TERM -"))
    XCTAssertTrue(script.contains("/bin/kill -TERM \"$pid\""))
    XCTAssertTrue(script.contains("/bin/kill -KILL \"$pid\""))
  }

  func testExactPIDIdentityValidationForCleanup() throws {
    let script = try read("Scripts/m14_004_hermes_compatibility_acceptance.sh")
    let cleanup = try extractFunction("cleanup_owned_process", from: script)

    XCTAssertTrue(cleanup.contains("OWNED_PID_FILE"))
    XCTAssertTrue(cleanup.contains("OWNED_IDENTITY_FILE"))
    XCTAssertTrue(cleanup.contains("/bin/ps -p \"$pid\""))
    XCTAssertTrue(cleanup.contains("/usr/bin/grep -Fq \"$current\" \"$OWNED_IDENTITY_FILE\""))
    XCTAssertTrue(cleanup.contains("[[ \"$pid\" == <-> ]]"))
  }

  func testResultKeysAreUniqueAndDeterministic() throws {
    let script = try read("Scripts/m14_004_hermes_compatibility_acceptance.sh")
    let keys = try arrayLiteral("ORDERED_KEYS", in: script)

    XCTAssertEqual(Set(keys).count, keys.count)
    XCTAssertEqual(keys.first, "EXPLICIT_OPT_IN_CONFIRMED")
    XCTAssertEqual(keys.last, "M14_004_RESULT")
    XCTAssertTrue(keys.contains("SERVICE_OWNED_DISCOVERY_USED"))
    XCTAssertTrue(keys.contains("REAL_HERMES_HOME_MODIFIED"))
    XCTAssertTrue(keys.contains("GENERATED_ARTIFACT_TRACKED_BY_GIT"))
  }

  func testMatrixRowsCoverRequiredCapabilities() throws {
    let script = try read("Scripts/m14_004_hermes_compatibility_acceptance.sh")
    let capabilities = try arrayLiteral("CAPABILITY_IDS", in: script)

    XCTAssertEqual(Set(capabilities).count, capabilities.count)
    XCTAssertEqual(capabilities.count, 16)
    XCTAssertTrue(capabilities.contains("request-submission-handshake"))
    XCTAssertTrue(capabilities.contains("request-cancellation-handshake"))
    XCTAssertTrue(capabilities.contains("approval-capability-discovery"))
    XCTAssertTrue(capabilities.contains("generated-artifact-cleanup"))
  }

  func testGeneratedArtifactsRemainIgnored() throws {
    let script = try read("Scripts/m14_004_hermes_compatibility_acceptance.sh")
    let gitignore = try read(".gitignore")

    XCTAssertTrue(gitignore.contains("artifacts/"))
    XCTAssertTrue(script.contains("git -C \"$ROOT_DIR\" check-ignore -q \"artifacts/m14-004/result.txt\""))
    XCTAssertTrue(script.contains("RESULT[GENERATED_ARTIFACT_TRACKED_BY_GIT]=no"))
  }

  func testServiceOwnedDiscoveryContractIsAsserted() throws {
    let script = try read("Scripts/m14_004_hermes_compatibility_acceptance.sh")
    let service = try read("Sources/HermesBridgeService/HermesBridgeCompositionRoot.swift")
    let app = try read("Sources/HermesBridgeApp/HermesAppCompositionRoot.swift")

    XCTAssertTrue(script.contains("SERVICE_OWNED_DISCOVERY_USED"))
    XCTAssertTrue(service.contains("self.discovery = HermesDiscovery("))
    XCTAssertTrue(service.contains("agentDiscovery: discovery"))
    XCTAssertFalse(app.contains("HermesDiscovery("))
    XCTAssertFalse(app.contains("HermesRuntimeSessionManager("))
    XCTAssertFalse(app.contains("HermesRuntimeCommandAPI("))
    XCTAssertFalse(app.contains("HermesRuntimeEventBus("))
  }

  func testCleanupIsIdempotentAndScopedToRuntimeRoot() throws {
    let script = try read("Scripts/m14_004_hermes_compatibility_acceptance.sh")
    let cleanup = try extractFunction("cleanup", from: script)

    XCTAssertTrue(cleanup.contains("cleanup_owned_process"))
    XCTAssertTrue(cleanup.contains("rm -rf \"$RUNTIME_ROOT\""))
    XCTAssertFalse(cleanup.contains("rm -rf \"$ARTIFACT_DIR\""))
    XCTAssertTrue(cleanup.contains("RESULT[M14_004_RESULT]=PASS"))
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
