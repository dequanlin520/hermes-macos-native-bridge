import XCTest
@testable import HermesBridgeApp
@testable import HermesOperations
import HermesRuntimeFoundation

final class HermesOperationsTests: XCTestCase {
  func testOperationsCenterBuildsReadOnlySafeDTO() async {
    let snapshot = await makeCenter().snapshot()

    XCTAssertEqual(snapshot.runtime.state, .nominal)
    XCTAssertEqual(snapshot.events.state, .nominal)
    XCTAssertEqual(snapshot.release.state, .nominal)
    XCTAssertEqual(snapshot.governance.state, .nominal)
    XCTAssertEqual(snapshot.overallState, .nominal)
    XCTAssertTrue(snapshot.readOnly)
    XCTAssertFalse(snapshot.appOwnsRuntime)
    XCTAssertFalse(snapshot.processExecutionAvailable)
    XCTAssertFalse(snapshot.shellAvailable)
    XCTAssertFalse(snapshot.uploadAvailable)
    XCTAssertFalse(snapshot.filesystemScanAvailable)
    XCTAssertFalse(snapshot.sensitiveDataPersistenceAvailable)
  }

  func testAggregationDetectsAttentionRequiredOperations() async {
    let snapshot = await makeCenter(
      events: HermesEventOperationsProviderSnapshot(
        eventPipelineStatus: "degraded event pipeline",
        recentEventCount: 3,
        notificationStatus: "1 critical notification",
        recentEventSummaries: ["notification blocked", "event received", "event received"]
      )
    ).snapshot()

    XCTAssertEqual(snapshot.events.state, .attentionRequired)
    XCTAssertEqual(snapshot.events.summary, "3 recent events, notifications 1 critical notification")
    XCTAssertEqual(snapshot.overallState, .attentionRequired)
  }

  func testSummaryGenerationIncludesAllOperationalDomains() async {
    let snapshot = await makeCenter(
      runtime: HermesRuntimeOperationsProviderSnapshot(
        runtimeStatus: "runtime available",
        sessionStatus: "sessions available",
        backendStatus: "backend available",
        activeOperationCount: 2
      ),
      release: HermesReleaseOperationsProviderSnapshot(
        releaseStatus: "ready",
        currentVersion: "1.0.0",
        availableVersion: "1.0.1",
        releaseReadiness: "release ready"
      ),
      governance: HermesGovernanceOperationsProviderSnapshot(
        policyStatus: "4 policies",
        privacyStatus: "2 privacy records",
        auditStatus: "7 audit events",
        complianceStatus: "nominal"
      )
    ).snapshot()

    XCTAssertEqual(
      snapshot.runtime.summary,
      "2 active operations, runtime runtime available, sessions sessions available"
    )
    XCTAssertEqual(snapshot.release.summary, "current 1.0.0, available 1.0.1, status ready")
    XCTAssertEqual(
      snapshot.governance.summary,
      "policy 4 policies, privacy 2 privacy records, audit 7 audit events"
    )
  }

  func testRedactionRemovesSensitiveDataFromDTOFields() async {
    let snapshot = await makeCenter(
      runtime: HermesRuntimeOperationsProviderSnapshot(
        runtimeStatus: "runtime bearer secret.value",
        sessionStatus: "session path /Users/alice/.hermes",
        backendStatus: "password=hunter2",
        activeOperationCount: 1
      ),
      events: HermesEventOperationsProviderSnapshot(
        eventPipelineStatus: "token=event-token",
        recentEventCount: 1,
        notificationStatus: "private_key=abc123 pid=9876",
        recentEventSummaries: ["api_key=notify /Users/alice/private process id 4321"]
      ),
      release: HermesReleaseOperationsProviderSnapshot(
        releaseStatus: "credential=release",
        currentVersion: "1.0 token=abc",
        availableVersion: "2.0 secret=available",
        releaseReadiness: "secret=ready"
      ),
      governance: HermesGovernanceOperationsProviderSnapshot(
        policyStatus: "api_key=policy",
        privacyStatus: "bearer privacy.secret",
        auditStatus: "process id 4321",
        complianceStatus: "token=compliance"
      )
    ).snapshot()

    let text = String(describing: snapshot)

    XCTAssertFalse(text.contains("secret.value"))
    XCTAssertFalse(text.contains("hunter2"))
    XCTAssertFalse(text.contains("event-token"))
    XCTAssertFalse(text.contains("abc123"))
    XCTAssertFalse(text.contains("9876"))
    XCTAssertFalse(text.contains("4321"))
    XCTAssertFalse(text.contains("/Users/alice"))
    XCTAssertFalse(text.contains("privacy.secret"))
  }

  func testRuntimeOwnershipBoundaryHasNoForbiddenAccess() throws {
    let files = try FileManager.default.contentsOfDirectory(atPath: "Sources/HermesOperations")
    let contents = try files.map {
      try String(contentsOfFile: "Sources/HermesOperations/\($0)")
    }.joined(separator: "\n")

    XCTAssertFalse(contents.contains("HermesProcessSupervisor"))
    XCTAssertFalse(contents.contains("HermesBackendAdapter"))
    XCTAssertFalse(contents.contains("HermesProtocolClient"))
    XCTAssertFalse(contents.contains("HermesRuntimeCommandAPI"))
    XCTAssertFalse(contents.contains("Process("))
    XCTAssertFalse(contents.contains("sudo"))
    XCTAssertFalse(contents.contains("NSWorkspace.shared.open"))
    XCTAssertFalse(contents.contains("URLSession"))
    XCTAssertFalse(contents.contains("FileHandle"))
    XCTAssertFalse(contents.contains("contentsOfDirectory"))
    XCTAssertFalse(contents.contains("UserDefaults"))
    XCTAssertFalse(contents.contains("appOwnsRuntime: Bool { true }"))
    XCTAssertFalse(contents.contains("processExecutionAvailable: Bool { true }"))
    XCTAssertFalse(contents.contains("shellAvailable: Bool { true }"))
    XCTAssertFalse(contents.contains("uploadAvailable: Bool { true }"))
    XCTAssertFalse(contents.contains("filesystemScanAvailable: Bool { true }"))
    XCTAssertFalse(contents.contains("sensitiveDataPersistenceAvailable: Bool { true }"))
  }

  @MainActor
  func testOperationsRoutingUsesOneLogicalWindow() {
    let factory = RecordingWindowFactory()
    let root = HermesAppCompositionRoot(
      clientGraph: HermesAppClientGraph(runtimeClient: NoopRuntimeClient()),
      windowFactory: factory
    )

    root.router.openOperationsCenter()
    root.router.openOperationsCenter()
    root.windowCoordinator.close(.operations)
    root.router.openOperationsCenter()

    XCTAssertEqual(factory.createdIdentifiers, [.operations])
    XCTAssertEqual(factory.window(for: .operations)?.showCount, 2)
    XCTAssertEqual(factory.window(for: .operations)?.focusCount, 1)
    XCTAssertEqual(root.windowCoordinator.windowCount(for: .operations), 1)
  }

  func testAcceptanceArtifactValues() throws {
    let resultURL = URL(fileURLWithPath: "artifacts/m13-013/result.txt")
    let result = try String(contentsOf: resultURL, encoding: .utf8)
    for required in [
      "OPERATIONS_CENTER_AVAILABLE=yes",
      "RUNTIME_OPERATIONS_SUMMARY_AVAILABLE=yes",
      "EVENT_OPERATIONS_SUMMARY_AVAILABLE=yes",
      "RELEASE_OPERATIONS_SUMMARY_AVAILABLE=yes",
      "GOVERNANCE_OPERATIONS_SUMMARY_AVAILABLE=yes",
      "SAFE_DTO_ONLY=yes",
      "READ_ONLY=yes",
      "APP_OWNS_RUNTIME=no",
      "PROCESS_EXECUTION_AVAILABLE=no",
      "SHELL_AVAILABLE=no",
      "UPLOAD_AVAILABLE=no",
      "FILESYSTEM_SCAN_AVAILABLE=no",
      "SENSITIVE_DATA_PERSISTENCE_AVAILABLE=no",
      "TOKEN_EXPOSED=no",
      "PRIVATE_PATH_EXPOSED=no",
      "PID_EXPOSED=no",
      "GENERATED_ARTIFACT_TRACKED_BY_GIT=no",
      "RESIDUAL_PROCESS=no",
      "M13_013_RESULT=PASS",
    ] {
      XCTAssertTrue(result.contains(required), required)
    }
  }

  private func makeCenter(
    runtime: HermesRuntimeOperationsProviderSnapshot = HermesRuntimeOperationsProviderSnapshot(
      runtimeStatus: "runtime available",
      sessionStatus: "sessions available",
      backendStatus: "backend available",
      activeOperationCount: 0
    ),
    events: HermesEventOperationsProviderSnapshot = HermesEventOperationsProviderSnapshot(
      eventPipelineStatus: "events available",
      recentEventCount: 0,
      notificationStatus: "0 notifications",
      recentEventSummaries: []
    ),
    release: HermesReleaseOperationsProviderSnapshot = HermesReleaseOperationsProviderSnapshot(
      releaseStatus: "up to date",
      currentVersion: "1.0.0",
      releaseReadiness: "ready"
    ),
    governance: HermesGovernanceOperationsProviderSnapshot = HermesGovernanceOperationsProviderSnapshot(
      policyStatus: "policy nominal",
      privacyStatus: "privacy nominal",
      auditStatus: "audit nominal",
      complianceStatus: "compliance nominal"
    )
  ) -> HermesOperationsCenter {
    HermesOperationsCenter(
      inputs: HermesOperationsCenterInputs(
        runtimeOperations: {
          runtime
        },
        eventOperations: {
          events
        },
        releaseOperations: {
          release
        },
        governanceOperations: {
          governance
        }
      )
    )
  }
}

@MainActor
private final class RecordingWindowFactory: HermesNativeUIWindowFactory, @unchecked Sendable {
  private var windows: [HermesNativeUIWindowIdentifier: RecordingWindow] = [:]
  private(set) var createdIdentifiers: [HermesNativeUIWindowIdentifier] = []

  func makeWindow(
    for identifier: HermesNativeUIWindowIdentifier,
    clientGraph _: HermesAppClientGraph
  ) -> HermesNativeUIWindowControlling {
    let window = RecordingWindow(identifier: identifier)
    windows[identifier] = window
    createdIdentifiers.append(identifier)
    return window
  }

  func window(for identifier: HermesNativeUIWindowIdentifier) -> RecordingWindow? {
    windows[identifier]
  }
}

@MainActor
private final class RecordingWindow: HermesNativeUIWindowControlling {
  let identifier: HermesNativeUIWindowIdentifier
  private(set) var isOpen = false
  private(set) var showCount = 0
  private(set) var focusCount = 0

  init(identifier: HermesNativeUIWindowIdentifier) {
    self.identifier = identifier
  }

  func show() {
    isOpen = true
    showCount += 1
  }

  func focus() {
    focusCount += 1
  }

  func close() {
    isOpen = false
  }

  func cleanup() {
    isOpen = false
  }
}

private final class NoopRuntimeClient: HermesAppRuntimeClienting, @unchecked Sendable {
  func execute(_: HermesRuntimeCommand) async throws -> HermesRuntimeCommandResult {
    .sessionList([])
  }

  func subscribeRuntimeEvents() async throws -> HermesRuntimeCommandEventSubscription {
    HermesRuntimeCommandEventSubscription(id: UUID(), events: AsyncStream { $0.finish() })
  }

  func invalidate() async {}
}
