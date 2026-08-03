import XCTest
@testable import HermesAppIntents
@testable import HermesBridgeMenuBar
@testable import HermesRuntimeFoundation

final class HermesProductE2EAcceptanceTests: XCTestCase {
  private let resultKeys = [
    "EXPLICIT_OPT_IN_CONFIRMED",
    "USER_SCOPE_ONLY",
    "RELEASE_APP_BUILT",
    "APP_INSTALLED",
    "LAUNCH_AGENT_INSTALLED",
    "XPC_PROTOCOL_VERSION",
    "INITIAL_XPC_CONNECTED",
    "PRODUCT_CAPABILITY_SNAPSHOT_RECEIVED",
    "HERMES_EXECUTABLE_AVAILABLE",
    "HERMES_EXECUTABLE_FAMILY",
    "HERMES_EXECUTABLE_SOURCE",
    "HERMES_VERSION_STATUS",
    "HERMES_VERSION",
    "DISCOVERY_PARITY",
    "ISOLATED_AGENT_START_REQUESTED_THROUGH_SERVICE",
    "ISOLATED_AGENT_READY",
    "ENDPOINT_OWNERSHIP_PROVEN",
    "STATUS_VISIBLE_TO_CLIENT",
    "REQUEST_CAPABILITY",
    "REQUEST_CAPABILITY_REASON",
    "CANCEL_CAPABILITY",
    "CANCEL_CAPABILITY_REASON",
    "APPROVAL_CAPABILITY",
    "APPROVAL_CAPABILITY_REASON",
    "UNSUPPORTED_CONTROLS_DISABLED",
    "APP_EXIT_LEFT_RUNTIME_POLICY_CORRECT",
    "APP_RELAUNCHED",
    "APP_RECONNECTED",
    "SERVICE_RESTARTED",
    "APP_RECONNECTED_AFTER_SERVICE_RESTART",
    "STATUS_CONTINUITY_PROVEN",
    "ISOLATED_AGENT_STOPPED_THROUGH_SERVICE",
    "EXACT_PROCESS_IDENTITY_USED",
    "LISTENER_REMAINING_AFTER_SHUTDOWN",
    "ACCEPTANCE_PROCESS_REMAINING",
    "APP_TARGET_CLEANED",
    "LAUNCH_AGENT_TARGET_CLEANED",
    "SUPERVISED_PROCESS_REAL_HOME_ACCESS",
    "GENERATED_ARTIFACT_TRACKED_BY_GIT",
    "ENVIRONMENT_RESTORED",
    "RC_SCOPE_FROZEN",
    "M14_009_REASON_CODE",
    "M14_009_RESULT",
  ]

  func testAcceptanceScriptDefinesDeterministicResultKeysAndOptInGuard() throws {
    let script = try read("Scripts/m14_009_product_e2e_acceptance.sh")
    for key in resultKeys {
      XCTAssertTrue(script.contains(key), "missing \(key)")
    }
    XCTAssertTrue(script.contains("HERMES_M14_009_ACCEPTANCE=YES"))
    XCTAssertTrue(script.contains("inspect|run|cleanup"))
    XCTAssertTrue(script.contains("HermesReleaseAgentPreflight m14-009-inspect"))
    XCTAssertFalse(script.contains("safe_version()"))
    XCTAssertFalse(script.contains("hermes --version"))
    XCTAssertTrue(script.contains("transport.route-unsupported"))
    XCTAssertTrue(
      try read("Sources/HermesRuntimeFoundation/HermesProductCapabilities.swift")
        .contains("private-route.not-assumed")
    )
  }

  func testInspectUsesAuthoritativeProductSnapshotKeys() throws {
    let script = try read("Scripts/m14_009_product_e2e_acceptance.sh")
    let helper = try read("Sources/HermesReleaseAgentPreflight/HermesReleaseAgentPreflight.swift")

    for key in [
      "XPC_PROTOCOL_VERSION",
      "HERMES_EXECUTABLE_AVAILABLE",
      "HERMES_EXECUTABLE_FAMILY",
      "HERMES_EXECUTABLE_SOURCE",
      "HERMES_VERSION_STATUS",
      "HERMES_VERSION",
      "DISCOVERY_PARITY",
      "REQUEST_CAPABILITY",
      "REQUEST_CAPABILITY_REASON",
      "CANCEL_CAPABILITY",
      "CANCEL_CAPABILITY_REASON",
      "APPROVAL_CAPABILITY",
      "APPROVAL_CAPABILITY_REASON",
      "RC_SCOPE_STATUS",
      "M14_009_EXPECTED_RESULT",
    ] {
      XCTAssertTrue(helper.contains("\"\(key)\""), "missing \(key)")
    }
    XCTAssertTrue(helper.contains("HermesBridgeServiceConfiguration.productionDefault()"))
    XCTAssertTrue(helper.contains("HermesDiscovery("))
    XCTAssertTrue(helper.contains("HermesAgentVersionDescriptor(result: result, sourceCategory: \"PATH\")"))
    XCTAssertTrue(helper.contains("HermesProductCapabilitySnapshot.rc1("))
    XCTAssertTrue(script.contains("preflight_inspect"))
  }

  func testAcceptanceScriptDoesNotUsePrivateRoutesOrDirectHermesProtocolRequests() throws {
    let script = try read("Scripts/m14_009_product_e2e_acceptance.sh")
    XCTAssertFalse(script.contains("/api/ws"))
    XCTAssertFalse(script.contains("ws://"))
    XCTAssertFalse(script.contains("wss://"))
    XCTAssertFalse(script.contains("curl"))
    XCTAssertFalse(script.contains("nc "))
    XCTAssertFalse(script.contains("killall"))
    XCTAssertFalse(script.contains("pkill"))
  }

  func testMenuBarConsumesTypedSnapshotAndDisablesUnsupportedControls() {
    let snapshot = productSnapshot()
    let state = HermesBridgeMenuBarState(
      running: true,
      protocolCompatible: true,
      protocolVersion: "1.8",
      productCapabilitySnapshot: snapshot
    )

    XCTAssertEqual(state.productCapabilitySnapshot, snapshot)
    XCTAssertFalse(state.requestControl.enabled)
    XCTAssertFalse(state.cancelControl.enabled)
    XCTAssertFalse(state.approvalControl.enabled)
    XCTAssertEqual(state.requestControl.reasonCode, "transport.route-unsupported")
    XCTAssertEqual(state.cancelControl.reasonCode, "transport.route-unsupported")
    XCTAssertEqual(state.approvalControl.reasonCode, "transport.route-unsupported")
    XCTAssertEqual(state.productCapabilitySnapshot?.observedHermesVersion, "0.18.2")
  }

  func testAppIntentHealthReceivesTypedSnapshotVersion() async throws {
    let operations = HermesAppIntentOperations(client: UnsupportedRequestClient(snapshot: productSnapshot()))

    let health = try await operations.health()

    XCTAssertEqual(health.productCapabilitySnapshot?.observedHermesVersion, "0.18.2")
    XCTAssertEqual(
      health.productCapabilitySnapshot?.capability(.approvalResponse)?.observedHermesVersion,
      "0.18.2"
    )
  }

  func testAppIntentRequestOperationsFailWithTypedCapabilityReason() async throws {
    let operations = HermesAppIntentOperations(client: UnsupportedRequestClient(snapshot: productSnapshot()))

    await XCTAssertThrowsAsyncError(
      try await operations.submit(bindingID: "binding:v1:daily.status", prompt: "hello")
    ) { error in
      XCTAssertEqual(error as? HermesAppIntentError, .capabilityUnavailable("transport.route-unsupported"))
    }
    await XCTAssertThrowsAsyncError(
      try await operations.cancel(requestID: "hrq_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
    ) { error in
      XCTAssertEqual(error as? HermesAppIntentError, .capabilityUnavailable("transport.route-unsupported"))
    }
    await XCTAssertThrowsAsyncError(
      try await operations.respondToApproval(
        requestID: "hrq_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        decision: .allow
      )
    ) { error in
      XCTAssertEqual(error as? HermesAppIntentError, .capabilityUnavailable("transport.route-unsupported"))
    }
  }

  func testREADMEStatusAndRCScopeAreCurrentAndAligned() throws {
    let readme = try read("README.md")
    let rcScope = try read("Docs/Release/RC1Scope.md")
    let m14 = try read("Docs/Release/M14_009ProductE2EAcceptance.md")

    XCTAssertFalse(readme.contains("Pre-alpha. Technical validation has not started."))
    XCTAssertTrue(readme.contains("Release-candidate engineering validation in progress."))
    XCTAssertTrue(readme.contains("XPC 1.8"))
    XCTAssertTrue(readme.contains("Hermes Agent 0.18.2"))
    XCTAssertTrue(readme.contains("transport.route-unsupported"))
    XCTAssertTrue(readme.contains("Docs/Release/RC1Scope.md"))
    XCTAssertTrue(rcScope.contains("request submission for Hermes Agent 0.18.2"))
    XCTAssertTrue(rcScope.contains("arbitrary shell execution"))
    XCTAssertTrue(rcScope.contains("GUI Computer Use"))
    XCTAssertTrue(m14.contains("HermesProductCapabilitySnapshot"))
    XCTAssertTrue(m14.contains("XPC 1.8"))
  }

  func testGeneratedArtifactsAreIgnoredAndCleanupIsIdempotent() throws {
    let gitignore = try read(".gitignore")
    let script = try read("Scripts/m14_009_product_e2e_acceptance.sh")

    XCTAssertTrue(gitignore.contains("artifacts/"))
    XCTAssertTrue(script.contains("rm -rf \"$ARTIFACT_DIR/tmp\""))
    XCTAssertTrue(script.contains("cleanup)"))
  }

  func testRCScopeMatchesCapabilitySnapshotUnsupportedBoundary() throws {
    let rcScope = try read("Docs/Release/RC1Scope.md")
    let snapshot = productSnapshot()

    XCTAssertEqual(snapshot.capability(.requestSubmission)?.status, .unsupported)
    XCTAssertEqual(snapshot.capability(.requestCancellation)?.status, .unsupported)
    XCTAssertEqual(snapshot.capability(.approvalResponse)?.status, .unsupported)
    XCTAssertTrue(rcScope.contains("request submission for Hermes Agent 0.18.2"))
    XCTAssertTrue(rcScope.contains("request cancellation for Hermes Agent 0.18.2"))
    XCTAssertTrue(rcScope.contains("approval response for Hermes Agent 0.18.2"))
  }

  private func productSnapshot() -> HermesProductCapabilitySnapshot {
    HermesProductCapabilitySnapshot.rc1(
      xpcProtocolVersion: "1.8",
      bridgeServiceConnected: true,
      executableAvailable: true,
      observedHermesVersion: "0.18.2",
      compatibilityLevel: .partiallyCompatible,
      runtimeStatus: .ready,
      statusReady: true,
      endpointOwnershipProven: true,
      lifecycleExercised: true,
      controlledReconnectExercised: true,
      exactShutdownExercised: true
    )
  }

  private func read(_ relativePath: String) throws -> String {
    try String(contentsOfFile: repoRoot().appendingPathComponent(relativePath).path, encoding: .utf8)
  }

  private func repoRoot() -> URL {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<3 {
      url.deleteLastPathComponent()
    }
    return url
  }
}

private struct UnsupportedRequestClient: HermesAppIntentClient {
  let snapshot: HermesProductCapabilitySnapshot

  func listEnabledBindings() async throws -> [HermesAppIntentBindingDefinition] {
    [HermesAppIntentBindingDefinition(
      id: try HermesRequestBindingID(rawValue: "binding:v1:daily.status"),
      enabled: true,
      displayName: "Daily Status",
      safeDescription: "Fixture"
    )]
  }

  func submit(bindingID _: HermesRequestBindingID, prompt _: String) async throws
    -> HermesRequestID
  {
    XCTFail("submit transport must not be called when product capability is unsupported")
    return try HermesRequestID(rawValue: "hrq_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
  }

  func status(requestID _: HermesRequestID) async throws -> HermesAppIntentRequestStatus {
    XCTFail("status transport must not be called when product capability is unsupported")
    return HermesAppIntentRequestStatus(
      requestID: "hrq_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      lifecycleState: .unknown,
      cancellationRequested: false,
      resultAvailable: false
    )
  }

  func cancel(requestID _: HermesRequestID) async throws -> HermesAppIntentRequestStatus {
    XCTFail("cancel transport must not be called when product capability is unsupported")
    return HermesAppIntentRequestStatus(
      requestID: "hrq_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      lifecycleState: .unknown,
      cancellationRequested: false,
      resultAvailable: false
    )
  }

  func respondToApproval(
    requestID _: HermesRequestID,
    decision _: HermesAppIntentApprovalDecision
  ) async throws -> HermesAppIntentRequestStatus {
    XCTFail("approval transport must not be called when product capability is unsupported")
    return HermesAppIntentRequestStatus(
      requestID: "hrq_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      lifecycleState: .unknown,
      cancellationRequested: false,
      resultAvailable: false
    )
  }

  func health() async throws -> HermesAppIntentHealthStatus {
    HermesAppIntentHealthStatus(
      available: true,
      compatible: true,
      protocolVersion: "1.8",
      supportedCapabilities: [],
      productCapabilitySnapshot: snapshot
    )
  }
}

private func XCTAssertThrowsAsyncError<T>(
  _ expression: @autoclosure @escaping () async throws -> T,
  _ errorHandler: (Error) -> Void
) async {
  do {
    _ = try await expression()
    XCTFail("Expected error")
  } catch {
    errorHandler(error)
  }
}
