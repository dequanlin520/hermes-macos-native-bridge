import XCTest
@testable import HermesBridgeApp
@testable import HermesCompliance
import HermesPolicy
import HermesPrivacy
import HermesRuntimeFoundation
import HermesUpdate

final class HermesComplianceTests: XCTestCase {
  func testComplianceCenterBuildsReadOnlySafeDTO() async {
    let snapshot = await makeCenter().snapshot()

    XCTAssertEqual(snapshot.security.state, .compliant)
    XCTAssertEqual(snapshot.privacy.state, .compliant)
    XCTAssertEqual(snapshot.policy.state, .compliant)
    XCTAssertEqual(snapshot.release.state, .compliant)
    XCTAssertEqual(snapshot.overallState, .compliant)
    XCTAssertTrue(snapshot.readOnly)
    XCTAssertFalse(snapshot.appOwnsRuntime)
    XCTAssertFalse(snapshot.processExecutionAvailable)
    XCTAssertFalse(snapshot.shellAvailable)
    XCTAssertFalse(snapshot.uploadAvailable)
    XCTAssertFalse(snapshot.sensitiveDataExposed)
  }

  func testPostureSummariesAreAvailable() async {
    let snapshot = await makeCenter().snapshot()

    XCTAssertFalse(snapshot.security.summary.isEmpty)
    XCTAssertFalse(snapshot.privacy.summary.isEmpty)
    XCTAssertFalse(snapshot.policy.summary.isEmpty)
    XCTAssertFalse(snapshot.release.summary.isEmpty)
    XCTAssertEqual(snapshot.auditEvidence.recentEventCount, 2)
    XCTAssertTrue(snapshot.auditEvidence.readOnly)
  }

  func testRedactionRemovesSensitiveDataFromDTOFields() async {
    let center = makeCenter(
      system: HermesComplianceSystemStatus(
        applicationVersion: "1.0 token=abc",
        protocolVersion: "pid=1234",
        serviceAvailability: .available
      ),
      updateSnapshot: HermesUpdateSnapshot(
        state: .failed,
        current: HermesUpdateCurrentVersionInfo(
          appVersion: "password=hunter2",
          serviceVersion: "1.0.0",
          xpcProtocolVersion: "1.0"
        ),
        availableRelease: HermesUpdateReleaseMetadata(
          releaseID: "/Users/alice/private/release",
          version: "2.0.0",
          releaseNotesSummary: "Bearer secret.value"
        ),
        message: "token=release-secret pid=9876 /Users/alice/.hermes"
      ),
      policyEvents: [
        HermesPolicyAuditEvent(
          policyID: "enterprise.token",
          oldValue: "token=abc pid=1234 /Users/alice/.hermes",
          newValue: "allow"
        )
      ]
    )

    let text = String(describing: await center.snapshot())

    XCTAssertFalse(text.contains("abc"))
    XCTAssertFalse(text.contains("hunter2"))
    XCTAssertFalse(text.contains("1234"))
    XCTAssertFalse(text.contains("9876"))
    XCTAssertFalse(text.contains("/Users/alice"))
    XCTAssertFalse(text.contains("secret.value"))
  }

  func testRuntimeOwnershipBoundaryHasNoForbiddenAccess() throws {
    let files = try FileManager.default.contentsOfDirectory(atPath: "Sources/HermesCompliance")
    let contents = try files.map {
      try String(contentsOfFile: "Sources/HermesCompliance/\($0)")
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
    XCTAssertFalse(contents.contains("appOwnsRuntime: Bool { true }"))
    XCTAssertFalse(contents.contains("processExecutionAvailable: Bool { true }"))
    XCTAssertFalse(contents.contains("shellAvailable: Bool { true }"))
    XCTAssertFalse(contents.contains("uploadAvailable: Bool { true }"))
    XCTAssertFalse(contents.contains("sensitiveDataExposed: Bool { true }"))
  }

  @MainActor
  func testComplianceRoutingUsesOneLogicalWindow() {
    let factory = RecordingWindowFactory()
    let root = HermesAppCompositionRoot(
      clientGraph: HermesAppClientGraph(runtimeClient: NoopRuntimeClient()),
      windowFactory: factory
    )

    root.router.openComplianceCenter()
    root.router.openComplianceCenter()
    root.windowCoordinator.close(.compliance)
    root.router.openComplianceCenter()

    XCTAssertEqual(factory.createdIdentifiers, [.compliance])
    XCTAssertEqual(factory.window(for: .compliance)?.showCount, 2)
    XCTAssertEqual(factory.window(for: .compliance)?.focusCount, 1)
    XCTAssertEqual(root.windowCoordinator.windowCount(for: .compliance), 1)
  }

  func testAcceptanceArtifactValues() throws {
    let resultURL = URL(fileURLWithPath: "artifacts/m13-011/result.txt")
    let result = try String(contentsOf: resultURL, encoding: .utf8)
    for required in [
      "COMPLIANCE_CENTER_AVAILABLE=yes",
      "SECURITY_POSTURE_AVAILABLE=yes",
      "PRIVACY_POSTURE_AVAILABLE=yes",
      "POLICY_POSTURE_AVAILABLE=yes",
      "RELEASE_POSTURE_AVAILABLE=yes",
      "AUDIT_EVIDENCE_SUMMARY_AVAILABLE=yes",
      "SAFE_DTO_ONLY=yes",
      "READ_ONLY=yes",
      "APP_OWNS_RUNTIME=no",
      "PROCESS_EXECUTION_AVAILABLE=no",
      "SHELL_AVAILABLE=no",
      "UPLOAD_AVAILABLE=no",
      "SENSITIVE_DATA_EXPOSED=no",
      "TOKEN_EXPOSED=no",
      "PRIVATE_PATH_EXPOSED=no",
      "PID_EXPOSED=no",
      "GENERATED_ARTIFACT_TRACKED_BY_GIT=no",
      "RESIDUAL_PROCESS=no",
      "M13_011_RESULT=PASS",
    ] {
      XCTAssertTrue(result.contains(required), required)
    }
  }

  private func makeCenter(
    system: HermesComplianceSystemStatus = HermesComplianceSystemStatus(
      applicationVersion: "1.2.3",
      protocolVersion: "1.0",
      serviceAvailability: .available
    ),
    updateSnapshot: HermesUpdateSnapshot = HermesUpdateSnapshot(
      state: .upToDate,
      current: HermesUpdateCurrentVersionInfo(
        appVersion: "1.2.3",
        serviceVersion: "1.2.3",
        xpcProtocolVersion: "1.0"
      ),
      message: "Hermes Bridge is up to date."
    ),
    policyEvents: [HermesPolicyAuditEvent] = [
      HermesPolicyAuditEvent(policyID: "enterprise.runtime", oldValue: "allow", newValue: "deny")
    ],
    privacyEvents: [HermesPrivacyAuditEvent] = [
      HermesPrivacyAuditEvent(
        category: .usageAnalytics,
        oldStatus: .allowed,
        newStatus: .denied
      )
    ]
  ) -> HermesComplianceCenter {
    HermesComplianceCenter(
      inputs: HermesComplianceCenterInputs(
        systemStatus: {
          system
        },
        policies: {
          [
            HermesPolicyDefinition(
              id: "enterprise.runtime",
              name: "Runtime",
              category: .runtimeOperationRestrictions,
              value: .decision(.deny),
              version: "3"
            )
          ]
        },
        privacyRecords: {
          HermesPrivacyConsentCategory.allCases.map {
            HermesPrivacyConsentRecord(category: $0, status: .denied)
          }
        },
        updateSnapshot: {
          updateSnapshot
        },
        policyAuditEvents: {
          policyEvents
        },
        privacyAuditEvents: {
          privacyEvents
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
