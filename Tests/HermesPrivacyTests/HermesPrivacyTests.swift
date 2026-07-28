import XCTest
@testable import HermesBridgeApp
@testable import HermesPrivacy
import HermesRuntimeFoundation

final class HermesPrivacyTests: XCTestCase {
  func testDefaultConsentStateIsDenied() throws {
    let center = HermesPrivacyCenter(store: makeStore())

    let records = try center.listConsentRecords()

    XCTAssertEqual(records.count, HermesPrivacyConsentCategory.allCases.count)
    XCTAssertTrue(records.allSatisfy { $0.status == .denied })
    XCTAssertTrue(center.denyByDefault)
    XCTAssertTrue(center.explicitConsentRequired)
  }

  func testConsentUpdatePersistsAllowedStatus() throws {
    let center = HermesPrivacyCenter(store: makeStore())

    let updated = try center.updateConsent(
      category: .diagnosticsCollection,
      status: .allowed,
      source: .privacyCenter
    )

    XCTAssertEqual(updated.status, .allowed)
    XCTAssertEqual(updated.source, .privacyCenter)
    XCTAssertEqual(try center.status(for: .diagnosticsCollection), .allowed)
  }

  func testUnknownStatusIsPersistedAsDenied() throws {
    let center = HermesPrivacyCenter(store: makeStore())

    let updated = try center.updateConsent(
      category: .usageAnalytics,
      status: .unknown,
      source: .privacyCenter
    )

    XCTAssertEqual(updated.status, .denied)
    XCTAssertEqual(try center.status(for: .usageAnalytics), .denied)
  }

  func testPersistenceStoresConsentAndPreferences() throws {
    let suiteName = "com.hermes.privacy.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let firstStore = HermesPrivacyStore(userDefaults: defaults)
    let center = HermesPrivacyCenter(store: firstStore)

    let updated = try center.updateConsent(
      category: .crashInformation,
      status: .allowed,
      source: .settings
    )
    try center.savePreferences(
      HermesPrivacyPreferences(showPrivacyReminders: false, retainLocalHistory: true)
    )

    let secondStore = HermesPrivacyStore(userDefaults: defaults)
    XCTAssertEqual(try secondStore.loadConsentRecords().first?.id, updated.id)
    XCTAssertEqual(
      try secondStore.loadConsentRecords().first { $0.category == .crashInformation }?.status,
      .allowed
    )
    XCTAssertEqual(try secondStore.loadPreferences().showPrivacyReminders, false)
    XCTAssertEqual(try secondStore.loadPreferences().retainLocalHistory, true)
  }

  func testConsentChangeCreatesSanitizedAuditEvent() throws {
    let center = HermesPrivacyCenter(store: makeStore())

    _ = try center.updateConsent(
      category: .updateCheckMetadata,
      status: .allowed,
      source: .privacyCenter
    )

    let events = try center.loadAuditEvents()
    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(events[0].category, .updateCheckMetadata)
    XCTAssertEqual(events[0].oldStatus, .denied)
    XCTAssertEqual(events[0].newStatus, .allowed)
    let auditText = String(describing: events[0])
    XCTAssertFalse(auditText.contains("token"))
    XCTAssertFalse(auditText.contains("/Users/"))
    XCTAssertFalse(auditText.contains("pid"))
  }

  func testSensitiveCategoryRejection() throws {
    let policy = HermesPrivacyPolicy()

    XCTAssertThrowsError(try policy.category(from: "tokenCollection")) { error in
      XCTAssertEqual(
        error as? HermesPrivacyValidationError,
        .sensitiveCategoryRejected("tokenCollection")
      )
    }
    XCTAssertThrowsError(try policy.category(from: "privatePathUpload")) { error in
      XCTAssertEqual(
        error as? HermesPrivacyValidationError,
        .sensitiveCategoryRejected("privatePathUpload")
      )
    }
  }

  func testRedactionRemovesSensitiveData() throws {
    let text = HermesPrivacyRedactor.safeText(
      "token=abc password=hunter2 pid=1234 /Users/alice/.hermes Bearer secret.value"
    )

    XCTAssertFalse(text.contains("abc"))
    XCTAssertFalse(text.contains("hunter2"))
    XCTAssertFalse(text.contains("1234"))
    XCTAssertFalse(text.contains("/Users/alice"))
    XCTAssertFalse(text.contains("secret.value"))
    XCTAssertTrue(text.contains("<redacted>"))
    XCTAssertTrue(text.contains("<redacted-path>"))
  }

  @MainActor
  func testPrivacyRoutingUsesOneLogicalWindow() {
    let factory = RecordingWindowFactory()
    let root = HermesAppCompositionRoot(
      clientGraph: HermesAppClientGraph(runtimeClient: NoopRuntimeClient()),
      windowFactory: factory
    )

    root.router.openPrivacyCenter()
    root.router.openPrivacyCenter()
    root.windowCoordinator.close(.privacy)
    root.router.openPrivacyCenter()

    XCTAssertEqual(factory.createdIdentifiers, [.privacy])
    XCTAssertEqual(factory.window(for: .privacy)?.showCount, 2)
    XCTAssertEqual(factory.window(for: .privacy)?.focusCount, 1)
    XCTAssertEqual(root.windowCoordinator.windowCount(for: .privacy), 1)
  }

  func testRuntimeOwnershipBoundaryHasNoForbiddenRuntimeAccess() throws {
    let files = try FileManager.default.contentsOfDirectory(atPath: "Sources/HermesPrivacy")
    let contents = try files.map {
      try String(contentsOfFile: "Sources/HermesPrivacy/\($0)")
    }.joined(separator: "\n")

    XCTAssertFalse(contents.contains("HermesProcessSupervisor"))
    XCTAssertFalse(contents.contains("HermesBackendAdapter"))
    XCTAssertFalse(contents.contains("HermesProtocolClient"))
    XCTAssertFalse(contents.contains("HermesRuntimeCommandAPI"))
    XCTAssertFalse(contents.contains("HermesBridgeXPC"))
    XCTAssertFalse(contents.contains("Process("))
    XCTAssertFalse(contents.contains("sudo"))
    XCTAssertFalse(contents.contains("NSWorkspace.shared.open"))
    XCTAssertFalse(contents.contains("URLSession"))
    XCTAssertFalse(contents.contains("shell"))
    XCTAssertFalse(contents.contains("automaticUploadAllowed: Bool { true }"))
    XCTAssertFalse(contents.contains("arbitraryActionAllowed: Bool { true }"))
    XCTAssertFalse(contents.contains("appOwnsRuntime: Bool { true }"))
  }

  func testAcceptanceArtifactValues() throws {
    let resultURL = URL(fileURLWithPath: "artifacts/m13-008/result.txt")
    let result = try String(contentsOf: resultURL, encoding: .utf8)
    for required in [
      "PRIVACY_CENTER_AVAILABLE=yes",
      "CONSENT_MODEL_AVAILABLE=yes",
      "DENY_BY_DEFAULT=yes",
      "EXPLICIT_CONSENT_REQUIRED=yes",
      "CONSENT_PERSISTED=yes",
      "AUDIT_RECORDED=yes",
      "SENSITIVE_CATEGORY_REJECTED=yes",
      "SENSITIVE_DATA_EXPOSED=no",
      "APP_OWNS_RUNTIME=no",
      "ARBITRARY_ACTION_AVAILABLE=no",
      "AUTO_UPLOAD_AVAILABLE=no",
      "TOKEN_EXPOSED=no",
      "PRIVATE_PATH_EXPOSED=no",
      "PID_EXPOSED=no",
      "GENERATED_ARTIFACT_TRACKED_BY_GIT=no",
      "RESIDUAL_PROCESS=no",
      "M13_008_RESULT=PASS",
    ] {
      XCTAssertTrue(result.contains(required), required)
    }
  }

  private func makeStore() -> HermesPrivacyStore {
    let suiteName = "com.hermes.privacy.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return HermesPrivacyStore(userDefaults: defaults)
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
  private(set) var closeCount = 0

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
    closeCount += 1
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
