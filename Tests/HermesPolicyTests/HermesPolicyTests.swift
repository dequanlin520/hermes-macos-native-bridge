import XCTest
@testable import HermesBridgeApp
@testable import HermesPolicy
import HermesRuntimeFoundation

final class HermesPolicyTests: XCTestCase {
  func testDefaultPoliciesAreCreatedDenied() throws {
    let center = HermesPolicyCenter(store: makeStore())

    let policies = try center.listPolicies()

    XCTAssertEqual(policies.count, HermesPolicyCategory.allCases.count)
    XCTAssertTrue(policies.allSatisfy { $0.value == .decision(.deny) })
    XCTAssertTrue(center.denyByDefault)
    XCTAssertFalse(center.appOwnsRuntime)
  }

  func testPolicyCreationPersistsDefinition() throws {
    let center = HermesPolicyCenter(store: makeStore())
    let policy = HermesPolicyDefinition(
      id: "enterprise.notifications",
      name: "Enterprise Notifications",
      category: .notificationPolicy,
      value: .decision(.allow),
      source: .managedProfile,
      version: "2"
    )

    let saved = try center.savePolicy(policy)

    XCTAssertEqual(saved.id, "enterprise.notifications")
    XCTAssertEqual(saved.value, .decision(.allow))
    XCTAssertEqual(try center.listPolicies().first { $0.id == saved.id }?.source, .managedProfile)
  }

  func testPolicyEvaluationSupportsAllow() throws {
    let center = HermesPolicyCenter(store: makeStore())
    _ = try center.savePolicy(
      HermesPolicyDefinition(
        id: "enterprise.updates",
        name: "Enterprise Updates",
        category: .updatePolicy,
        value: .decision(.allow)
      )
    )

    let result = try center.evaluate(policyID: "enterprise.updates")

    XCTAssertEqual(result.decision, .allow)
    XCTAssertEqual(result.policyID, "enterprise.updates")
  }

  func testUnknownPolicyDeniesByDefault() throws {
    let center = HermesPolicyCenter(store: makeStore())

    let result = try center.evaluate(policyID: "missing.policy")

    XCTAssertEqual(result.decision, .deny)
    XCTAssertEqual(result.source, .defaultPolicy)
    XCTAssertEqual(result.reason, "unknown policy")
  }

  func testConfirmationRequiredEvaluation() throws {
    let center = HermesPolicyCenter(store: makeStore())
    _ = try center.savePolicy(
      HermesPolicyDefinition(
        id: "enterprise.runtime.confirm",
        name: "Runtime Confirmation",
        category: .runtimeOperationRestrictions,
        value: .decision(.requireConfirmation)
      )
    )

    let result = try center.evaluate(policyID: "enterprise.runtime.confirm")

    XCTAssertEqual(result.decision, .requireConfirmation)
  }

  func testPersistenceStoresDefinitionsEvaluationsAndPreferences() throws {
    let suiteName = "com.hermes.policy.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let firstStore = HermesPolicyStore(userDefaults: defaults)
    let center = HermesPolicyCenter(store: firstStore)

    _ = try center.savePolicy(
      HermesPolicyDefinition(
        id: "enterprise.retention",
        name: "Retention",
        category: .retentionPolicy,
        value: .decision(.deny)
      )
    )
    _ = try center.evaluate(policyID: "enterprise.retention")
    try center.savePreferences(
      HermesPolicyPreferences(showManagedPolicyMetadata: false, recordLocalEvaluationResults: true)
    )

    let secondStore = HermesPolicyStore(userDefaults: defaults)
    XCTAssertEqual(
      try secondStore.loadPolicyDefinitions().first { $0.id == "enterprise.retention" }?.value,
      .decision(.deny)
    )
    XCTAssertEqual(try secondStore.loadEvaluationResults().first?.policyID, "enterprise.retention")
    XCTAssertEqual(try secondStore.loadPreferences().showManagedPolicyMetadata, false)
  }

  func testPolicyChangeCreatesSanitizedAuditEvent() throws {
    let center = HermesPolicyCenter(store: makeStore())

    _ = try center.savePolicy(
      HermesPolicyDefinition(
        id: "enterprise.privacy",
        name: "Privacy",
        category: .privacyPolicy,
        value: .decision(.allow)
      )
    )

    let events = try center.loadAuditEvents()
    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(events[0].policyID, "enterprise.privacy")
    XCTAssertEqual(events[0].oldValue, "missing")
    XCTAssertEqual(events[0].newValue, "allow")
    let auditText = String(describing: events[0])
    XCTAssertFalse(auditText.contains("token="))
    XCTAssertFalse(auditText.contains("/Users/"))
    XCTAssertFalse(auditText.contains("pid=123"))
  }

  func testRedactionRemovesSensitiveData() throws {
    let text = HermesPolicyRedactor.safeText(
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

  func testSensitivePolicyMetadataIsRejected() throws {
    let evaluator = HermesPolicyEvaluator()
    let policy = HermesPolicyDefinition(
      id: "enterprise.token",
      name: "Token Capture",
      category: .privacyPolicy,
      value: .text("token=abc")
    )

    XCTAssertThrowsError(try evaluator.validate(policy)) { error in
      guard case HermesPolicyValidationError.sensitivePolicyMetadataRejected = error else {
        return XCTFail("expected sensitive metadata rejection")
      }
    }
  }

  @MainActor
  func testPolicyRoutingUsesOneLogicalWindow() {
    let factory = RecordingWindowFactory()
    let root = HermesAppCompositionRoot(
      clientGraph: HermesAppClientGraph(runtimeClient: NoopRuntimeClient()),
      windowFactory: factory
    )

    root.router.openPolicyCenter()
    root.router.openPolicyCenter()
    root.windowCoordinator.close(.policy)
    root.router.openPolicyCenter()

    XCTAssertEqual(factory.createdIdentifiers, [.policy])
    XCTAssertEqual(factory.window(for: .policy)?.showCount, 2)
    XCTAssertEqual(factory.window(for: .policy)?.focusCount, 1)
    XCTAssertEqual(root.windowCoordinator.windowCount(for: .policy), 1)
  }

  func testRuntimeOwnershipBoundaryHasNoForbiddenRuntimeAccess() throws {
    let files = try FileManager.default.contentsOfDirectory(atPath: "Sources/HermesPolicy")
    let contents = try files.map {
      try String(contentsOfFile: "Sources/HermesPolicy/\($0)")
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
    XCTAssertFalse(contents.contains("automaticUploadAllowed: Bool { true }"))
    XCTAssertFalse(contents.contains("arbitraryActionAllowed: Bool { true }"))
    XCTAssertFalse(contents.contains("appOwnsRuntime: Bool { true }"))
  }

  func testAcceptanceArtifactValues() throws {
    let resultURL = URL(fileURLWithPath: "artifacts/m13-009/result.txt")
    let result = try String(contentsOf: resultURL, encoding: .utf8)
    for required in [
      "POLICY_CENTER_AVAILABLE=yes",
      "POLICY_MODEL_AVAILABLE=yes",
      "POLICY_EVALUATION_AVAILABLE=yes",
      "DENY_BY_DEFAULT=yes",
      "AUDIT_RECORDED=yes",
      "POLICY_PERSISTED=yes",
      "SENSITIVE_DATA_EXPOSED=no",
      "APP_OWNS_RUNTIME=no",
      "ARBITRARY_ACTION_AVAILABLE=no",
      "TOKEN_EXPOSED=no",
      "PRIVATE_PATH_EXPOSED=no",
      "PID_EXPOSED=no",
      "GENERATED_ARTIFACT_TRACKED_BY_GIT=no",
      "RESIDUAL_PROCESS=no",
      "M13_009_RESULT=PASS",
    ] {
      XCTAssertTrue(result.contains(required), required)
    }
  }

  private func makeStore() -> HermesPolicyStore {
    let suiteName = "com.hermes.policy.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return HermesPolicyStore(userDefaults: defaults)
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
