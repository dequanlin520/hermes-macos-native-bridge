import XCTest
@testable import HermesAnalytics
@testable import HermesBridgeApp
import HermesRuntimeFoundation

final class HermesAnalyticsTests: XCTestCase {
  func testAnalyticsCenterBuildsReadOnlySafeDTO() async {
    let snapshot = await makeCenter().snapshot()

    XCTAssertEqual(snapshot.runtime.state, .stable)
    XCTAssertEqual(snapshot.operations.state, .stable)
    XCTAssertEqual(snapshot.governance.state, .stable)
    XCTAssertEqual(snapshot.overallState, .stable)
    XCTAssertTrue(snapshot.readOnly)
    XCTAssertFalse(snapshot.appOwnsRuntime)
    XCTAssertFalse(snapshot.processExecutionAvailable)
    XCTAssertFalse(snapshot.shellAvailable)
    XCTAssertFalse(snapshot.uploadAvailable)
    XCTAssertFalse(snapshot.filesystemScanAvailable)
  }

  func testReadOnlyBehaviorIsExposedByCenterAndSnapshot() async {
    let center = makeCenter()
    let snapshot = await center.snapshot()

    XCTAssertTrue(center.readOnly)
    XCTAssertFalse(center.appOwnsRuntime)
    XCTAssertFalse(center.processExecutionAvailable)
    XCTAssertFalse(center.shellAvailable)
    XCTAssertFalse(center.uploadAvailable)
    XCTAssertFalse(center.filesystemScanAvailable)
    XCTAssertTrue(snapshot.readOnly)
  }

  func testSummaryAggregationDetectsUnreliableOperations() async {
    let snapshot = await makeCenter(
      operations: HermesOperationsAnalyticsProviderSnapshot(
        errorTrendSummary: "failed update trend",
        recoveryTrendSummary: "recovery blocked",
        notificationTrendSummary: "1 critical notification",
        updateReliabilitySummary: "unreliable"
      )
    ).snapshot()

    XCTAssertEqual(snapshot.operations.state, .unreliable)
    XCTAssertEqual(snapshot.overallState, .unreliable)
    XCTAssertEqual(
      snapshot.operations.summary,
      "errors failed update trend, recovery recovery blocked, notifications 1 critical notification, updates unreliable"
    )
  }

  func testSummaryGenerationIncludesAllAnalyticsDomains() async {
    let snapshot = await makeCenter(
      runtime: HermesRuntimeAnalyticsProviderSnapshot(
        uptimeSummary: "99.9 percent available",
        sessionStabilitySummary: "sessions stable",
        serviceAvailabilitySummary: "service available"
      ),
      governance: HermesGovernanceAnalyticsProviderSnapshot(
        policyComplianceSummary: "4 policies compliant",
        privacyPostureTrend: "2 records stable",
        auditCoverageSummary: "7 audit events"
      )
    ).snapshot()

    XCTAssertEqual(
      snapshot.runtime.summary,
      "uptime 99.9 percent available, sessions sessions stable, service service available"
    )
    XCTAssertEqual(
      snapshot.governance.summary,
      "policy 4 policies compliant, privacy 2 records stable, audit 7 audit events"
    )
  }

  func testRedactionRemovesSensitiveDataFromDTOFields() async {
    let snapshot = await makeCenter(
      runtime: HermesRuntimeAnalyticsProviderSnapshot(
        uptimeSummary: "uptime bearer secret.value",
        sessionStabilitySummary: "session path /Users/alice/.hermes",
        serviceAvailabilitySummary: "password=hunter2"
      ),
      operations: HermesOperationsAnalyticsProviderSnapshot(
        errorTrendSummary: "token=event-token",
        recoveryTrendSummary: "private_key=abc123 pid=9876",
        notificationTrendSummary: "api_key=notify /Users/alice/private",
        updateReliabilitySummary: "credential=release"
      ),
      governance: HermesGovernanceAnalyticsProviderSnapshot(
        policyComplianceSummary: "api_key=policy",
        privacyPostureTrend: "bearer privacy.secret",
        auditCoverageSummary: "process id 4321"
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

  func testRuntimeBoundaryHasNoForbiddenAccess() throws {
    let files = try FileManager.default.contentsOfDirectory(atPath: "Sources/HermesAnalytics")
    let contents = try files.map {
      try String(contentsOfFile: "Sources/HermesAnalytics/\($0)")
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
  }

  @MainActor
  func testAnalyticsRoutingUsesOneLogicalWindow() {
    let factory = RecordingWindowFactory()
    let root = HermesAppCompositionRoot(
      clientGraph: HermesAppClientGraph(runtimeClient: NoopRuntimeClient()),
      windowFactory: factory
    )

    root.router.openAnalyticsCenter()
    root.router.openAnalyticsCenter()
    root.windowCoordinator.close(.analytics)
    root.router.openAnalyticsCenter()

    XCTAssertEqual(factory.createdIdentifiers, [.analytics])
    XCTAssertEqual(factory.window(for: .analytics)?.showCount, 2)
    XCTAssertEqual(factory.window(for: .analytics)?.focusCount, 1)
    XCTAssertEqual(root.windowCoordinator.windowCount(for: .analytics), 1)
  }

  func testAcceptanceArtifactValues() throws {
    let resultURL = URL(fileURLWithPath: "artifacts/m13-014/result.txt")
    let result = try String(contentsOf: resultURL, encoding: .utf8)
    for required in [
      "ANALYTICS_CENTER_AVAILABLE=yes",
      "RUNTIME_ANALYTICS_SUMMARY_AVAILABLE=yes",
      "OPERATIONS_ANALYTICS_SUMMARY_AVAILABLE=yes",
      "GOVERNANCE_ANALYTICS_SUMMARY_AVAILABLE=yes",
      "SAFE_DTO_ONLY=yes",
      "READ_ONLY=yes",
      "APP_OWNS_RUNTIME=no",
      "PROCESS_EXECUTION_AVAILABLE=no",
      "SHELL_AVAILABLE=no",
      "UPLOAD_AVAILABLE=no",
      "FILESYSTEM_SCAN_AVAILABLE=no",
      "TOKEN_EXPOSED=no",
      "PRIVATE_PATH_EXPOSED=no",
      "PID_EXPOSED=no",
      "GENERATED_ARTIFACT_TRACKED_BY_GIT=no",
      "RESIDUAL_PROCESS=no",
      "M13_014_RESULT=PASS",
    ] {
      XCTAssertTrue(result.contains(required), required)
    }
  }

  private func makeCenter(
    runtime: HermesRuntimeAnalyticsProviderSnapshot = HermesRuntimeAnalyticsProviderSnapshot(
      uptimeSummary: "available",
      sessionStabilitySummary: "sessions stable",
      serviceAvailabilitySummary: "service available"
    ),
    operations: HermesOperationsAnalyticsProviderSnapshot = HermesOperationsAnalyticsProviderSnapshot(
      errorTrendSummary: "0 high severity notifications",
      recoveryTrendSummary: "idle",
      notificationTrendSummary: "0 notifications",
      updateReliabilitySummary: "up to date"
    ),
    governance: HermesGovernanceAnalyticsProviderSnapshot = HermesGovernanceAnalyticsProviderSnapshot(
      policyComplianceSummary: "policy stable",
      privacyPostureTrend: "privacy stable",
      auditCoverageSummary: "audit covered"
    )
  ) -> HermesAnalyticsCenter {
    HermesAnalyticsCenter(
      inputs: HermesAnalyticsCenterInputs(
        runtimeAnalytics: {
          runtime
        },
        operationsAnalytics: {
          operations
        },
        governanceAnalytics: {
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
