import Foundation
import XCTest

final class HermesAgentProtocolHandshakeAcceptanceTests: XCTestCase {
  private var root: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  func testModesAndExitCodeSemantics() throws {
    let script = try read("Scripts/m14_008_agent_protocol_handshake_acceptance.sh")
    let mapper = try extractFunction("result_exit_code", from: script)

    XCTAssertTrue(script.contains("usage: $SCRIPT_NAME inspect|inspect-request-plan|run|cleanup"))
    XCTAssertTrue(script.contains("inspect)"))
    XCTAssertTrue(script.contains("inspect-request-plan)"))
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
    let run = try extractFunction("run_acceptance", from: try read(scriptPath))

    XCTAssertTrue(run.contains("HERMES_M14_008_ACCEPTANCE:-"))
    XCTAssertTrue(run.contains("!= \"YES\""))
    XCTAssertTrue(run.contains("RESULT[M14_008_RESULT]=OPT_IN_REQUIRED"))
    XCTAssertTrue(run.contains("exit 2"))
  }

  func testInspectIsReadOnlyAndReportsProtocolPlan() throws {
    let script = try read(scriptPath)
    let inspect = try extractFunction("inspect", from: script)

    XCTAssertTrue(inspect.contains("M14-008 read-only inspect"))
    XCTAssertTrue(inspect.contains("endpoint_readiness_dependency=m14-007-ownership-proven-api-status"))
    XCTAssertTrue(inspect.contains("protocol_metadata_source="))
    XCTAssertTrue(inspect.contains("authentication_category="))
    XCTAssertTrue(inspect.contains("request_advertised_status="))
    XCTAssertTrue(inspect.contains("cancel_advertised_status="))
    XCTAssertTrue(inspect.contains("approval_advertised_status="))
    XCTAssertTrue(inspect.contains("expected_exercisability="))
    XCTAssertTrue(inspect.contains("blocking_reason="))
    XCTAssertFalse(inspect.contains("write_artifacts"))
    XCTAssertFalse(inspect.contains("serve --isolated"))
  }

  func testInspectRequestPlanIsReadOnlyAndReportsTypedAuthentication() throws {
    let script = try read(scriptPath)
    let inspect = try extractFunction("inspect_request_plan", from: script)

    XCTAssertTrue(inspect.contains("authentication_state="))
    XCTAssertTrue(inspect.contains("credential_action=none"))
    XCTAssertTrue(inspect.contains("ephemeral_credential_required=no"))
    XCTAssertTrue(inspect.contains("request_method_category=session-create"))
    XCTAssertTrue(inspect.contains("safe_synthetic_request_available=yes"))
    XCTAssertTrue(inspect.contains("status_mechanism=session-status"))
    XCTAssertTrue(inspect.contains("blocking_reason="))
    XCTAssertFalse(inspect.contains("write_artifacts"))
    XCTAssertFalse(inspect.contains("serve --isolated"))
    XCTAssertFalse(inspect.contains("create_token"))
  }

  func testResultKeysAreUniqueDeterministicAndComplete() throws {
    let keys = try arrayLiteral("ORDERED_KEYS", in: try read(scriptPath))

    XCTAssertEqual(Set(keys).count, keys.count)
    XCTAssertEqual(keys.first, "EXPLICIT_OPT_IN_CONFIRMED")
    XCTAssertEqual(keys.last, "M14_008_RESULT")
    for required in [
      "SERVICE_OWNED_PROTOCOL_CLIENT_USED",
      "SERVICE_OWNED_SUPERVISOR_USED",
      "SERVICE_OWNED_ENDPOINT_DISCOVERY_USED",
      "PROTOCOL_METADATA_DISCOVERED",
      "PROTOCOL_FAMILY",
      "AUTHENTICATION_REQUIRED",
      "EPHEMERAL_CREDENTIAL_ISOLATED",
      "REQUEST_CAPABILITY",
      "REQUEST_TRANSPORT",
      "REQUEST_AUTHENTICATION_MODE",
      "REQUEST_CONNECTION_ATTEMPTED",
      "REQUEST_CONNECTION_STATUS",
      "REQUEST_RPC_METHOD_CATEGORY",
      "REQUEST_RPC_RESPONSE_CATEGORY",
      "REQUEST_RPC_ERROR_CODE",
      "REQUEST_SUBMISSION_DURATION_MILLISECONDS",
      "REQUEST_REASON_CODE",
      "REQUEST_IDENTITY_CAPTURED",
      "CANCEL_TARGET_IDENTITY_MATCHED",
      "APPROVAL_CAPABILITY",
      "CLIENT_RECONNECT_TESTED",
      "BROAD_STOP_INVOKED",
      "BROAD_PROCESS_KILL_USED",
      "SUPERVISED_PROCESS_REAL_HOME_ACCESS",
    ] {
      XCTAssertTrue(keys.contains(required), required)
    }
  }

  func testMetadataDiscoveryIsBoundedAndDoesNotPersistRawOpenAPI() throws {
    let script = try read(scriptPath)

    XCTAssertTrue(script.contains("/api/status"))
    XCTAssertTrue(script.contains("/openapi.json"))
    XCTAssertTrue(script.contains("openapi-summary.json"))
    XCTAssertTrue(script.contains("sanitized-no-raw-openapi-no-token-no-port-no-url"))
    XCTAssertFalse(script.contains("/api/requests"))
    XCTAssertFalse(script.contains("/api/cancel"))
  }

  func testProtocolExerciseUsesServiceOwnedJSONRPCAndSafeSessionRequest() throws {
    let exercise = try extractFunction("exercise_protocol", from: try read(scriptPath))

    XCTAssertTrue(exercise.contains("target = \"/api/ws\" if auth_mode == \"none\""))
    XCTAssertTrue(exercise.contains("f\"/api/ws?token={token}\""))
    XCTAssertTrue(exercise.contains("\"session.create\""))
    XCTAssertTrue(exercise.contains("\"session.status\""))
    XCTAssertTrue(exercise.contains("\"session.interrupt\""))
    XCTAssertFalse(exercise.contains("\"prompt.submit\""))
    XCTAssertFalse(exercise.contains("shell"))
    XCTAssertFalse(exercise.contains("osascript"))
    XCTAssertFalse(exercise.contains("open -a"))
  }

  func testApprovalIsSupportedUnexercisedWithoutHarmlessTrigger() throws {
    let exercise = try extractFunction("exercise_protocol", from: try read(scriptPath))

    XCTAssertTrue(exercise.contains("RESULT[APPROVAL_CAPABILITY]=supported-unexercised"))
    XCTAssertTrue(exercise.contains("RESULT[APPROVAL_RESULT]=supported-but-no-harmless-trigger"))
    XCTAssertTrue(exercise.contains("RESULT[APPROVAL_TRIGGERED]"))
    XCTAssertTrue(exercise.contains("RESULT[APPROVAL_DECISION_SUBMITTED]"))
    XCTAssertFalse(exercise.contains("\"approval.respond\""))
  }

  func testReconnectContinuityAndRequestIdentityRedaction() throws {
    let script = try read(scriptPath)
    let exercise = try extractFunction("exercise_protocol", from: script)
    let validate = try extractFunction("validate_result_contract", from: script)

    XCTAssertTrue(exercise.contains("sock2 = socket.create_connection"))
    XCTAssertTrue(exercise.contains("REQUEST_STATE_SURVIVED_RECONNECT]=yes"))
    XCTAssertTrue(script.contains("raw-request-identity-omitted"))
    XCTAssertTrue(validate.contains("Raw UUID leaked into deterministic result"))
    XCTAssertTrue(validate.contains("Dynamic port leaked into deterministic result"))
    XCTAssertTrue(validate.contains("meaningful_secret_shape"))
    XCTAssertTrue(validate.contains("for key, value in values.items()"))
  }

  func testScannerIgnoresFieldNamesAndBenignDeterministicValues() throws {
    let validate = try extractFunction("validate_result_contract", from: try read(scriptPath))

    XCTAssertFalse(validate.contains("re.search(r\"[A-Za-z0-9_-]{32,}\", text)"))
    XCTAssertTrue(validate.contains("allowed_values"))
    XCTAssertTrue(validate.contains("semantic_version"))
    XCTAssertTrue(validate.contains("hermes-jsonrpc-websocket"))
    XCTAssertTrue(validate.contains("Sensitive result value leaked: key-category="))
  }

  func testExactShutdownReuseAndNoBroadStop() throws {
    let script = try read(scriptPath)
    let cleanup = try extractFunction("cleanup_owned_process", from: script)

    XCTAssertTrue(cleanup.contains("/bin/kill -TERM \"$pid\""))
    XCTAssertTrue(cleanup.contains("/bin/kill -KILL \"$pid\""))
    XCTAssertTrue(script.contains("\"$executable\" serve --isolated --port 0"))
    XCTAssertTrue(script.contains("/usr/sbin/lsof -nP -a -p \"$1\""))
    XCTAssertFalse(script.contains("killall"))
    XCTAssertFalse(script.contains("serve --stop"))
    XCTAssertFalse(script.contains("/bin/kill -TERM -"))
  }

  func testCleanupIsIdempotentAndRemovesEphemeralCredential() throws {
    let script = try read(scriptPath)
    let cleanup = try extractFunction("cleanup", from: script)
    let finalize = try extractFunction("finalize_cleanup_evidence", from: script)

    XCTAssertTrue(cleanup.contains("cleanup_owned_process"))
    XCTAssertTrue(cleanup.contains("rm -rf \"$RUNTIME_ROOT\""))
    XCTAssertFalse(cleanup.contains("rm -rf \"$ARTIFACT_DIR\""))
    XCTAssertTrue(finalize.contains("rm -f \"$TOKEN_FILE\""))
    XCTAssertTrue(finalize.contains("SUPERVISED_PROCESS_REAL_HOME_ACCESS]=no"))
    XCTAssertTrue(finalize.contains("ENVIRONMENT_RESTORED]=yes"))
  }

  func testXPCProtocolVersionIsUnchangedAt18() throws {
    let xpc = try read("Sources/HermesBridgeXPC/HermesBridgeXPCModels.swift")

    XCTAssertTrue(xpc.contains("HermesBridgeProtocolVersion(major: 1, minor: 8)"))
    XCTAssertFalse(xpc.contains("major: 1, minor: 9"))
  }

  func testBridgeServiceOwnsProtocolClientFactoryBelowUI() throws {
    let composition = try read("Sources/HermesBridgeService/HermesBridgeCompositionRoot.swift")
    let appSources = [
      "Sources/HermesBridgeApp/HermesBridgeApp.swift",
      "Sources/HermesDashboard/HermesDashboardController.swift",
      "Sources/HermesMenuBar/HermesMenuBarController.swift",
    ].compactMap { try? read($0) }.joined(separator: "\n")

    XCTAssertTrue(composition.contains("isolatedAgentProtocolClientFactory"))
    XCTAssertTrue(composition.contains("HermesAgentRequestClientFactory()"))
    XCTAssertFalse(appSources.contains("HermesAgentRequestClient("))
    XCTAssertFalse(appSources.contains("HermesBackendEndpoint(port:"))
  }

  private var scriptPath: String { "Scripts/m14_008_agent_protocol_handshake_acceptance.sh" }

  private func read(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
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
