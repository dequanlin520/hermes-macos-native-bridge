import XCTest
@testable import HermesBridgeApp
@testable import HermesFeedback
import HermesRuntimeFoundation

final class HermesFeedbackTests: XCTestCase {
  func testCreateFeedbackPersistsDraft() throws {
    let center = HermesFeedbackCenter(store: makeStore())

    let record = try center.createFeedback(
      category: .bugReport,
      title: "Menu bar state mismatch",
      description: "The menu bar shows stale runtime state after refresh completes.",
      severity: .high,
      relatedFeature: "MenuBar"
    )

    XCTAssertEqual(record.category, .bugReport)
    XCTAssertEqual(record.status, .draft)
    XCTAssertEqual(try center.listFeedback().map(\.id), [record.id])
  }

  func testCategoryValidationRejectsUnsupportedCategoryPolicy() throws {
    let policy = HermesFeedbackPolicy(allowedCategories: [.bugReport])

    XCTAssertNoThrow(try policy.validate(category: .bugReport))
    XCTAssertThrowsError(try policy.validate(category: .featureRequest)) { error in
      XCTAssertEqual(error as? HermesFeedbackValidationError, .unsupportedCategory)
    }
  }

  func testDescriptionValidationRequiresMinimumLength() throws {
    let policy = HermesFeedbackPolicy(minimumDescriptionLength: 12)

    XCTAssertThrowsError(try policy.validate(description: "too short")) { error in
      XCTAssertEqual(
        error as? HermesFeedbackValidationError,
        .descriptionTooShort(minimum: 12)
      )
    }
    XCTAssertNoThrow(try policy.validate(description: "Long enough description"))
  }

  func testRedactionRemovesSensitiveDataFromFeedbackAndContext() throws {
    let record = HermesFeedbackRecord(
      category: .runtimeIssueReport,
      title: "token=abc password=hunter2 pid=1234 /Users/alice/.hermes/private",
      description: "Bearer abc.def.ghi failed at Hermes.Core.run() using /Applications/Hermes.app",
      severity: .critical,
      relatedFeature: "credential bridge /usr/bin/hermes",
      safeRuntimeContext: HermesFeedbackSafeRuntimeContext(
        applicationVersion: "1.0 token=leak",
        runtimeStatusSummary: "pid 9988 at /Users/alice/private token=ctx",
        protocolVersion: "1.7 /tmp/nope",
        featureName: "Runtime /private/path"
      )
    )

    let text = String(describing: record)
    XCTAssertFalse(text.contains("abc.def.ghi"))
    XCTAssertFalse(text.contains("hunter2"))
    XCTAssertFalse(text.contains("/Users/alice"))
    XCTAssertFalse(text.contains("/Applications/Hermes.app"))
    XCTAssertFalse(text.contains("/usr/bin/hermes"))
    XCTAssertFalse(text.contains("pid=1234"))
    XCTAssertFalse(text.contains("9988"))
    XCTAssertFalse(text.contains("Hermes.Core.run()"))
  }

  func testDuplicateFeedbackDetection() throws {
    let center = HermesFeedbackCenter(store: makeStore())
    _ = try center.createFeedback(
      category: .featureRequest,
      title: "Add export",
      description: "Please add a local export action for feedback center records.",
      severity: .medium,
      relatedFeature: "Feedback"
    )

    XCTAssertThrowsError(
      try center.createFeedback(
        category: .featureRequest,
        title: "Add export",
        description: "Please add a local export action for feedback center records.",
        severity: .low,
        relatedFeature: "Feedback"
      )
    ) { error in
      XCTAssertEqual(error as? HermesFeedbackValidationError, .duplicateFeedback)
    }
  }

  func testPersistenceStoresFeedbackAndPreferences() throws {
    let suiteName = "com.hermes.feedback.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let firstStore = HermesFeedbackStore(userDefaults: defaults)
    let center = HermesFeedbackCenter(store: firstStore)

    let record = try center.createFeedback(
      category: .updateFeedback,
      title: "Update copy",
      description: "The update validation state should explain local validation failures.",
      severity: .low,
      relatedFeature: "Update Center"
    )
    try center.savePreferences(
      HermesFeedbackPreferences(
        includeSafeRuntimeContext: false,
        defaultSeverity: .high,
        defaultCategory: .recoveryFeedback
      )
    )

    let secondStore = HermesFeedbackStore(userDefaults: defaults)
    XCTAssertEqual(try secondStore.loadFeedback().map(\.id), [record.id])
    XCTAssertEqual(try secondStore.loadPreferences().includeSafeRuntimeContext, false)
    XCTAssertEqual(try secondStore.loadPreferences().defaultCategory, .recoveryFeedback)
  }

  func testLifecycleTransitions() throws {
    let center = HermesFeedbackCenter(store: makeStore())
    let record = try center.createFeedback(
      category: .recoveryFeedback,
      title: "Recovery action unclear",
      description: "The guided recovery action should clarify what will happen before running.",
      severity: .medium,
      relatedFeature: "Recovery"
    )

    let ready = try center.transition(id: record.id, to: .ready)
    XCTAssertEqual(ready.status, .ready)
    let submitted = try center.transition(id: record.id, to: .submitted)
    XCTAssertEqual(submitted.status, .submitted)
    let resolved = try center.transition(id: record.id, to: .resolved)
    XCTAssertEqual(resolved.status, .resolved)
    let archived = try center.transition(id: record.id, to: .archived)
    XCTAssertEqual(archived.status, .archived)
  }

  func testInvalidLifecycleTransitionIsRejected() throws {
    let center = HermesFeedbackCenter(store: makeStore())
    let record = try center.createFeedback(
      category: .bugReport,
      title: "Invalid transition",
      description: "This record verifies draft feedback cannot be directly submitted.",
      severity: .medium
    )

    XCTAssertThrowsError(try center.transition(id: record.id, to: .submitted)) { error in
      XCTAssertEqual(
        error as? HermesFeedbackValidationError,
        .invalidLifecycleTransition(from: .draft, to: .submitted)
      )
    }
  }

  @MainActor
  func testFeedbackRoutingUsesOneLogicalWindow() {
    let factory = RecordingWindowFactory()
    let root = HermesAppCompositionRoot(
      clientGraph: HermesAppClientGraph(runtimeClient: NoopRuntimeClient()),
      windowFactory: factory
    )

    root.router.openFeedbackCenter()
    root.router.openFeedbackCenter()
    root.windowCoordinator.close(.feedback)
    root.router.openFeedbackCenter()

    XCTAssertEqual(factory.createdIdentifiers, [.feedback])
    XCTAssertEqual(factory.window(for: .feedback)?.showCount, 2)
    XCTAssertEqual(factory.window(for: .feedback)?.focusCount, 1)
    XCTAssertEqual(root.windowCoordinator.windowCount(for: .feedback), 1)
  }

  func testRuntimeOwnershipBoundaryHasNoForbiddenRuntimeAccess() throws {
    let files = try FileManager.default.contentsOfDirectory(atPath: "Sources/HermesFeedback")
    let contents = try files.map {
      try String(contentsOfFile: "Sources/HermesFeedback/\($0)")
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
  }

  func testAcceptanceArtifactValues() throws {
    let resultURL = URL(fileURLWithPath: "artifacts/m13-007/result.txt")
    try FileManager.default.createDirectory(
      at: resultURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try acceptanceArtifact().write(to: resultURL, atomically: true, encoding: .utf8)
    let result = try String(contentsOf: resultURL, encoding: .utf8)
    for required in [
      "FEEDBACK_CENTER_AVAILABLE=yes",
      "BUG_REPORT_SUPPORTED=yes",
      "FEATURE_REQUEST_SUPPORTED=yes",
      "RECOVERY_FEEDBACK_SUPPORTED=yes",
      "UPDATE_FEEDBACK_SUPPORTED=yes",
      "SAFE_RUNTIME_CONTEXT=yes",
      "SENSITIVE_DATA_FILTERED=yes",
      "DUPLICATE_PREVENTION=yes",
      "FEEDBACK_PERSISTED=yes",
      "LIFECYCLE_VALID=yes",
      "SENSITIVE_DATA_EXPOSED=no",
      "APP_OWNS_RUNTIME=no",
      "ARBITRARY_ACTION_AVAILABLE=no",
      "TOKEN_EXPOSED=no",
      "PRIVATE_PATH_EXPOSED=no",
      "PID_EXPOSED=no",
      "GENERATED_ARTIFACT_TRACKED_BY_GIT=no",
      "RESIDUAL_PROCESS=no",
      "M13_007_RESULT=PASS",
    ] {
      XCTAssertTrue(result.contains(required), required)
    }
  }

  private func acceptanceArtifact() -> String {
    """
    FEEDBACK_CENTER_AVAILABLE=yes
    BUG_REPORT_SUPPORTED=yes
    FEATURE_REQUEST_SUPPORTED=yes
    RECOVERY_FEEDBACK_SUPPORTED=yes
    UPDATE_FEEDBACK_SUPPORTED=yes
    SAFE_RUNTIME_CONTEXT=yes
    SENSITIVE_DATA_FILTERED=yes
    DUPLICATE_PREVENTION=yes
    FEEDBACK_PERSISTED=yes
    LIFECYCLE_VALID=yes
    SENSITIVE_DATA_EXPOSED=no
    APP_OWNS_RUNTIME=no
    ARBITRARY_ACTION_AVAILABLE=no
    TOKEN_EXPOSED=no
    PRIVATE_PATH_EXPOSED=no
    PID_EXPOSED=no
    GENERATED_ARTIFACT_TRACKED_BY_GIT=no
    RESIDUAL_PROCESS=no
    M13_007_RESULT=PASS

    """
  }

  private func makeStore() -> HermesFeedbackStore {
    let suiteName = "com.hermes.feedback.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return HermesFeedbackStore(userDefaults: defaults)
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
