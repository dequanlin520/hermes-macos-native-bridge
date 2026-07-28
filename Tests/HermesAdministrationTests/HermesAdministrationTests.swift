import XCTest
@testable import HermesAdministration
@testable import HermesBridgeApp
import HermesPolicy
import HermesPrivacy
import HermesRuntimeFoundation
import HermesUpdate

final class HermesAdministrationTests: XCTestCase {
  func testAdminViewCreationBuildsSafeSnapshot() async throws {
    let center = makeCenter()

    let snapshot = await center.snapshot()

    XCTAssertEqual(snapshot.system.applicationVersion, "1.2.3")
    XCTAssertEqual(snapshot.system.protocolVersion, "1.0")
    XCTAssertEqual(snapshot.system.serviceAvailability, .available)
    XCTAssertEqual(snapshot.complianceState, .compliant)
    XCTAssertFalse(snapshot.appOwnsRuntime)
    XCTAssertFalse(snapshot.arbitraryActionAvailable)
    XCTAssertTrue(snapshot.auditReadOnly)
  }

  func testPolicySummaryCountsActiveAndDeniedPolicies() {
    let summary = HermesAdminPolicySummary(policies: [
      HermesPolicyDefinition(
        id: "enterprise.runtime",
        name: "Runtime",
        category: .runtimeOperationRestrictions,
        value: .decision(.deny),
        version: "3"
      ),
      HermesPolicyDefinition(
        id: "enterprise.updates",
        name: "Updates",
        category: .updatePolicy,
        value: .decision(.allow),
        version: "3"
      ),
    ])

    XCTAssertEqual(summary.activePolicies, 2)
    XCTAssertEqual(summary.deniedPolicies, 1)
    XCTAssertEqual(summary.policyVersion, "3")
    XCTAssertEqual(summary.policyIDs, ["enterprise.runtime", "enterprise.updates"])
  }

  func testPrivacySummaryCountsConsentState() {
    let summary = HermesAdminPrivacySummary(records: [
      HermesPrivacyConsentRecord(category: .diagnosticsCollection, status: .allowed),
      HermesPrivacyConsentRecord(category: .usageAnalytics, status: .denied),
      HermesPrivacyConsentRecord(category: .crashInformation, status: .unknown),
    ])

    XCTAssertEqual(summary.allowedConsentCount, 1)
    XCTAssertEqual(summary.deniedConsentCount, 2)
    XCTAssertEqual(summary.unknownConsentCount, 0)
    XCTAssertEqual(summary.privacyState, .compliant)
  }

  func testUpdateSummaryReportsAvailability() {
    let release = HermesUpdateReleaseMetadata(releaseID: "release-2", version: "2.0.0")
    let summary = HermesAdminUpdateSummary(
      snapshot: HermesUpdateSnapshot(
        state: .updateAvailable,
        current: HermesUpdateCurrentVersionInfo(appVersion: "1.0.0", serviceVersion: "1.0.0"),
        availableRelease: release,
        message: "A trusted update is available."
      )
    )

    XCTAssertEqual(summary.currentVersion, "1.0.0")
    XCTAssertEqual(summary.updateAvailability, .available)
    XCTAssertEqual(summary.availableVersion, "2.0.0")
  }

  func testAuditSummaryIsSanitizedAndReadOnly() async {
    let center = makeCenter(
      policyEvents: [
        HermesPolicyAuditEvent(
          policyID: "enterprise.token",
          oldValue: "token=abc pid=1234 /Users/alice/.hermes",
          newValue: "allow"
        )
      ],
      privacyEvents: [
        HermesPrivacyAuditEvent(
          category: .usageAnalytics,
          oldStatus: .denied,
          newStatus: .allowed
        )
      ]
    )

    let snapshot = await center.snapshot()
    let text = String(describing: snapshot.audit)

    XCTAssertEqual(snapshot.audit.recentEventCount, 2)
    XCTAssertTrue(snapshot.auditReadOnly)
    XCTAssertFalse(text.contains("abc"))
    XCTAssertFalse(text.contains("1234"))
    XCTAssertFalse(text.contains("/Users/alice"))
  }

  func testRedactionRemovesSensitiveDataFromDTOFields() {
    let system = HermesAdminSystemStatus(
      applicationVersion: "1.0 token=abc",
      protocolVersion: "pid=1234",
      serviceAvailability: .available
    )
    let update = HermesAdminUpdateSummary(
      currentVersion: "2.0 password=hunter2",
      updateAvailability: .available,
      availableVersion: "/Users/alice/private/build",
      statusMessage: "Bearer secret.value"
    )

    let text = "\(system) \(update)"

    XCTAssertFalse(text.contains("abc"))
    XCTAssertFalse(text.contains("hunter2"))
    XCTAssertFalse(text.contains("1234"))
    XCTAssertFalse(text.contains("/Users/alice"))
    XCTAssertFalse(text.contains("secret.value"))
  }

  func testPreferencesPersistOnlyAdminNamespace() throws {
    let suiteName = "com.hermes.admin.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let store = HermesAdminPreferenceStore(userDefaults: defaults)

    try store.savePreferences(HermesAdminPreferences(showComplianceStatus: false, visibleAuditLimit: 12))

    XCTAssertEqual(try store.loadPreferences().showComplianceStatus, false)
    XCTAssertEqual(try store.loadPreferences().visibleAuditLimit, 12)
    XCTAssertNotNil(defaults.data(forKey: "com.hermes.admin.v1.preferences"))
  }

  @MainActor
  func testAdministrationRoutingUsesOneLogicalWindow() {
    let factory = RecordingWindowFactory()
    let root = HermesAppCompositionRoot(
      clientGraph: HermesAppClientGraph(runtimeClient: NoopRuntimeClient()),
      windowFactory: factory
    )

    root.router.openAdministrationCenter()
    root.router.openAdministrationCenter()
    root.windowCoordinator.close(.administration)
    root.router.openAdministrationCenter()

    XCTAssertEqual(factory.createdIdentifiers, [.administration])
    XCTAssertEqual(factory.window(for: .administration)?.showCount, 2)
    XCTAssertEqual(factory.window(for: .administration)?.focusCount, 1)
    XCTAssertEqual(root.windowCoordinator.windowCount(for: .administration), 1)
  }

  func testRuntimeOwnershipBoundaryHasNoForbiddenRuntimeAccess() throws {
    let files = try FileManager.default.contentsOfDirectory(atPath: "Sources/HermesAdministration")
    let contents = try files.map {
      try String(contentsOfFile: "Sources/HermesAdministration/\($0)")
    }.joined(separator: "\n")

    XCTAssertFalse(contents.contains("HermesProcessSupervisor"))
    XCTAssertFalse(contents.contains("HermesBackendAdapter"))
    XCTAssertFalse(contents.contains("HermesProtocolClient"))
    XCTAssertFalse(contents.contains("HermesRuntimeCommandAPI"))
    XCTAssertFalse(contents.contains("Process("))
    XCTAssertFalse(contents.contains("sudo"))
    XCTAssertFalse(contents.contains("NSWorkspace.shared.open"))
    XCTAssertFalse(contents.contains("URLSession"))
    XCTAssertFalse(contents.contains("filesystem"))
    XCTAssertFalse(contents.contains("appOwnsRuntime: Bool { true }"))
    XCTAssertFalse(contents.contains("arbitraryActionAvailable: Bool { true }"))
  }

  func testAcceptanceArtifactValues() throws {
    let resultURL = URL(fileURLWithPath: "artifacts/m13-010/result.txt")
    let result = try String(contentsOf: resultURL, encoding: .utf8)
    for required in [
      "ADMIN_CENTER_AVAILABLE=yes",
      "SYSTEM_STATUS_AVAILABLE=yes",
      "POLICY_SUMMARY_AVAILABLE=yes",
      "PRIVACY_SUMMARY_AVAILABLE=yes",
      "UPDATE_SUMMARY_AVAILABLE=yes",
      "AUDIT_SUMMARY_AVAILABLE=yes",
      "SAFE_DTO_ONLY=yes",
      "AUDIT_READ_ONLY=yes",
      "SENSITIVE_DATA_EXPOSED=no",
      "APP_OWNS_RUNTIME=no",
      "ARBITRARY_ACTION_AVAILABLE=no",
      "TOKEN_EXPOSED=no",
      "PRIVATE_PATH_EXPOSED=no",
      "PID_EXPOSED=no",
      "GENERATED_ARTIFACT_TRACKED_BY_GIT=no",
      "RESIDUAL_PROCESS=no",
      "M13_010_RESULT=PASS",
    ] {
      XCTAssertTrue(result.contains(required), required)
    }
  }

  private func makeCenter(
    policyEvents: [HermesPolicyAuditEvent] = [],
    privacyEvents: [HermesPrivacyAuditEvent] = []
  ) -> HermesAdminCenter {
    HermesAdminCenter(
      inputs: HermesAdminCenterInputs(
        systemStatus: {
          HermesAdminSystemStatus(
            applicationVersion: "1.2.3",
            protocolVersion: "1.0",
            serviceAvailability: .available
          )
        },
        policies: {
          [
            HermesPolicyDefinition(
              id: "enterprise.runtime",
              name: "Runtime",
              category: .runtimeOperationRestrictions,
              value: .decision(.deny)
            )
          ]
        },
        privacyRecords: {
          HermesPrivacyConsentCategory.allCases.map {
            HermesPrivacyConsentRecord(category: $0, status: .denied)
          }
        },
        updateSnapshot: {
          HermesUpdateSnapshot(
            state: .upToDate,
            current: HermesUpdateCurrentVersionInfo(
              appVersion: "1.2.3",
              serviceVersion: "1.2.3",
              xpcProtocolVersion: "1.0"
            ),
            message: "Hermes Bridge is up to date."
          )
        },
        policyAuditEvents: {
          policyEvents
        },
        privacyAuditEvents: {
          privacyEvents
        }
      ),
      preferenceStore: InMemoryAdminPreferenceStore()
    )
  }
}

private final class InMemoryAdminPreferenceStore: HermesAdminPreferenceStoring, @unchecked Sendable {
  private var preferences = HermesAdminPreferences()

  func loadPreferences() throws -> HermesAdminPreferences {
    preferences
  }

  func savePreferences(_ preferences: HermesAdminPreferences) throws {
    self.preferences = preferences
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
