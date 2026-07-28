import XCTest
@testable import HermesBridgeApp
@testable import HermesHealth
import HermesRuntimeFoundation

final class HermesHealthTests: XCTestCase {
  func testHealthCenterBuildsReadOnlySafeDTO() async {
    let snapshot = await makeCenter().snapshot()

    XCTAssertEqual(snapshot.system.state, .healthy)
    XCTAssertEqual(snapshot.runtime.state, .healthy)
    XCTAssertEqual(snapshot.operational.state, .healthy)
    XCTAssertEqual(snapshot.compliance.state, .healthy)
    XCTAssertEqual(snapshot.overallState, .healthy)
    XCTAssertTrue(snapshot.readOnly)
    XCTAssertFalse(snapshot.appOwnsRuntime)
    XCTAssertFalse(snapshot.automaticRepairAvailable)
    XCTAssertFalse(snapshot.processExecutionAvailable)
    XCTAssertFalse(snapshot.shellAvailable)
    XCTAssertFalse(snapshot.uploadAvailable)
    XCTAssertFalse(snapshot.filesystemScanAvailable)
  }

  func testSummaryGenerationDetectsDegradedOperationalHealth() async {
    let snapshot = await makeCenter(
      operational: HermesHealthOperationalProviderSnapshot(
        recentFailures: ["updateFailed validation failed"],
        recoveryStatus: "actionAvailable",
        updateStatus: "failed",
        notificationStatus: "1 critical notification"
      )
    ).snapshot()

    XCTAssertEqual(snapshot.operational.state, .degraded)
    XCTAssertEqual(snapshot.operational.recentFailuresSummary, "1 recent failures")
    XCTAssertEqual(snapshot.overallState, .degraded)
  }

  func testRedactionRemovesSensitiveDataFromDTOFields() async {
    let snapshot = await makeCenter(
      system: HermesHealthSystemProviderSnapshot(
        applicationAvailability: .available,
        serviceAvailability: .available,
        xpcConnectivity: .connected,
        applicationVersion: "1.0 token=abc",
        protocolVersion: "pid=1234"
      ),
      runtime: HermesHealthRuntimeProviderSnapshot(
        runtimeStatusSummary: "backend bearer secret.value",
        sessionAvailabilitySummary: "session path /Users/alice/.hermes",
        backendAvailabilitySummary: "password=hunter2"
      ),
      operational: HermesHealthOperationalProviderSnapshot(
        recentFailures: ["private_key=abc123 pid=9876 /Users/alice/private"],
        recoveryStatus: "token=recovery",
        updateStatus: "credential=update",
        notificationStatus: "secret=notify"
      ),
      compliance: HermesHealthComplianceProviderSnapshot(
        policyStatus: "api_key=policy",
        privacyStatus: "bearer privacy.secret",
        auditStatus: "process id 4321"
      )
    ).snapshot()

    let text = String(describing: snapshot)

    XCTAssertFalse(text.contains("abc123"))
    XCTAssertFalse(text.contains("hunter2"))
    XCTAssertFalse(text.contains("1234"))
    XCTAssertFalse(text.contains("9876"))
    XCTAssertFalse(text.contains("4321"))
    XCTAssertFalse(text.contains("/Users/alice"))
    XCTAssertFalse(text.contains("secret.value"))
    XCTAssertFalse(text.contains("privacy.secret"))
  }

  func testRuntimeOwnershipBoundaryHasNoForbiddenAccess() throws {
    let files = try FileManager.default.contentsOfDirectory(atPath: "Sources/HermesHealth")
    let contents = try files.map {
      try String(contentsOfFile: "Sources/HermesHealth/\($0)")
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
    XCTAssertFalse(contents.contains("appOwnsRuntime: Bool { true }"))
    XCTAssertFalse(contents.contains("automaticRepairAvailable: Bool { true }"))
    XCTAssertFalse(contents.contains("processExecutionAvailable: Bool { true }"))
    XCTAssertFalse(contents.contains("shellAvailable: Bool { true }"))
    XCTAssertFalse(contents.contains("uploadAvailable: Bool { true }"))
    XCTAssertFalse(contents.contains("filesystemScanAvailable: Bool { true }"))
  }

  @MainActor
  func testHealthRoutingUsesOneLogicalWindow() {
    let factory = RecordingWindowFactory()
    let root = HermesAppCompositionRoot(
      clientGraph: HermesAppClientGraph(runtimeClient: NoopRuntimeClient()),
      windowFactory: factory
    )

    root.router.openHealthCenter()
    root.router.openHealthCenter()
    root.windowCoordinator.close(.health)
    root.router.openHealthCenter()

    XCTAssertEqual(factory.createdIdentifiers, [.health])
    XCTAssertEqual(factory.window(for: .health)?.showCount, 2)
    XCTAssertEqual(factory.window(for: .health)?.focusCount, 1)
    XCTAssertEqual(root.windowCoordinator.windowCount(for: .health), 1)
  }

  func testAcceptanceArtifactValues() throws {
    let resultURL = URL(fileURLWithPath: "artifacts/m13-012/result.txt")
    let result = try String(contentsOf: resultURL, encoding: .utf8)
    for required in [
      "HEALTH_CENTER_AVAILABLE=yes",
      "SYSTEM_HEALTH_AVAILABLE=yes",
      "RUNTIME_HEALTH_AVAILABLE=yes",
      "OPERATIONAL_HEALTH_AVAILABLE=yes",
      "COMPLIANCE_HEALTH_AVAILABLE=yes",
      "SAFE_DTO_ONLY=yes",
      "READ_ONLY=yes",
      "APP_OWNS_RUNTIME=no",
      "AUTOMATIC_REPAIR_AVAILABLE=no",
      "PROCESS_EXECUTION_AVAILABLE=no",
      "SHELL_AVAILABLE=no",
      "UPLOAD_AVAILABLE=no",
      "FILESYSTEM_SCAN_AVAILABLE=no",
      "TOKEN_EXPOSED=no",
      "PRIVATE_PATH_EXPOSED=no",
      "PID_EXPOSED=no",
      "GENERATED_ARTIFACT_TRACKED_BY_GIT=no",
      "RESIDUAL_PROCESS=no",
      "M13_012_RESULT=PASS",
    ] {
      XCTAssertTrue(result.contains(required), required)
    }
  }

  private func makeCenter(
    system: HermesHealthSystemProviderSnapshot = HermesHealthSystemProviderSnapshot(
      applicationAvailability: .available,
      serviceAvailability: .available,
      xpcConnectivity: .connected,
      applicationVersion: "1.2.3",
      protocolVersion: "1.0"
    ),
    runtime: HermesHealthRuntimeProviderSnapshot = HermesHealthRuntimeProviderSnapshot(
      runtimeStatusSummary: "runtime available",
      sessionAvailabilitySummary: "sessions available",
      backendAvailabilitySummary: "backend available"
    ),
    operational: HermesHealthOperationalProviderSnapshot = HermesHealthOperationalProviderSnapshot(
      recentFailures: [],
      recoveryStatus: "idle",
      updateStatus: "upToDate",
      notificationStatus: "0 notifications"
    ),
    compliance: HermesHealthComplianceProviderSnapshot = HermesHealthComplianceProviderSnapshot(
      policyStatus: "compliant",
      privacyStatus: "compliant",
      auditStatus: "2 audit events"
    )
  ) -> HermesHealthCenter {
    HermesHealthCenter(
      inputs: HermesHealthCenterInputs(
        systemHealth: {
          system
        },
        runtimeHealth: {
          runtime
        },
        operationalHealth: {
          operational
        },
        complianceHealth: {
          compliance
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
