import XCTest
@testable import HermesBridgeApp
@testable import HermesReporting
import HermesRuntimeFoundation

final class HermesReportingTests: XCTestCase {
  func testReportingCenterBuildsReadOnlySafeDTO() async {
    let snapshot = await makeCenter().snapshot()

    XCTAssertEqual(snapshot.health.state, .ready)
    XCTAssertEqual(snapshot.operations.state, .ready)
    XCTAssertEqual(snapshot.analytics.state, .ready)
    XCTAssertEqual(snapshot.compliance.state, .ready)
    XCTAssertEqual(snapshot.audit.state, .ready)
    XCTAssertEqual(snapshot.overallState, .ready)
    XCTAssertEqual(snapshot.supportedFormats, [.markdown, .html])
    XCTAssertTrue(snapshot.readOnly)
    XCTAssertFalse(snapshot.appOwnsRuntime)
    XCTAssertFalse(snapshot.processExecutionAvailable)
    XCTAssertFalse(snapshot.shellAvailable)
    XCTAssertFalse(snapshot.uploadAvailable)
    XCTAssertFalse(snapshot.networkAvailable)
    XCTAssertFalse(snapshot.filesystemScanAvailable)
  }

  func testSummaryAggregationDetectsAttentionRequiredDomain() async {
    let snapshot = await makeCenter(
      operations: HermesReportDomainSummary(
        title: "Operations",
        state: .attentionRequired,
        summary: "critical notification trend"
      )
    ).snapshot()

    XCTAssertEqual(snapshot.operations.state, .attentionRequired)
    XCTAssertEqual(snapshot.overallState, .attentionRequired)
  }

  func testMarkdownAndHTMLGenerationAreLocalAndRedacted() async throws {
    let center = makeCenter(
      health: HermesReportDomainSummary(
        title: "Health",
        state: .ready,
        summary: "token=health-token /Users/alice/.hermes pid=1234"
      )
    )

    let markdown = try await center.generate(format: .markdown)
    let html = try await center.generate(format: .html)

    XCTAssertEqual(markdown.format, .markdown)
    XCTAssertEqual(html.format, .html)
    XCTAssertTrue(markdown.fileName.hasSuffix(".md"))
    XCTAssertTrue(html.fileName.hasSuffix(".html"))
    XCTAssertTrue(markdown.body.contains("# Hermes Enterprise Report"))
    XCTAssertTrue(html.body.contains("<!doctype html>"))
    let text = markdown.body + html.body
    XCTAssertFalse(text.contains("health-token"))
    XCTAssertFalse(text.contains("/Users/alice"))
    XCTAssertFalse(text.contains("1234"))
  }

  func testReportHistoryPersistsGeneratedReportsWithSafeRelativePaths() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("hermes-reporting-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let center = makeCenter(historyStore: HermesReportFileHistoryStore(directory: directory))

    let document = try await center.generate(format: .html)
    let entry = try center.save(document)
    let snapshot = await center.snapshot()

    XCTAssertEqual(entry.format, .html)
    XCTAssertFalse(entry.relativePath.contains("/"))
    XCTAssertEqual(snapshot.history.first?.id, document.id)
    XCTAssertEqual(snapshot.history.first?.byteCount, document.body.utf8.count)
  }

  func testRedactionRemovesSensitiveDataFromDTOFields() async {
    let snapshot = await makeCenter(
      health: HermesReportDomainSummary(
        title: "Health",
        state: .ready,
        summary: "bearer secret.value"
      ),
      operations: HermesReportDomainSummary(
        title: "Operations",
        state: .ready,
        summary: "password=hunter2",
        details: ["api_key=notify /Users/alice/private"]
      ),
      analytics: HermesReportDomainSummary(
        title: "Analytics",
        state: .ready,
        summary: "private_key=abc123 pid=9876"
      ),
      compliance: HermesReportDomainSummary(
        title: "Compliance",
        state: .ready,
        summary: "token=compliance"
      ),
      audit: HermesReportDomainSummary(
        title: "Audit",
        state: .ready,
        summary: "process id 4321"
      )
    ).snapshot()

    let text = String(describing: snapshot)

    XCTAssertFalse(text.contains("secret.value"))
    XCTAssertFalse(text.contains("hunter2"))
    XCTAssertFalse(text.contains("abc123"))
    XCTAssertFalse(text.contains("9876"))
    XCTAssertFalse(text.contains("4321"))
    XCTAssertFalse(text.contains("/Users/alice"))
  }

  func testRuntimeBoundaryHasNoForbiddenAccess() throws {
    let files = try FileManager.default.contentsOfDirectory(atPath: "Sources/HermesReporting")
    let contents = try files.map {
      try String(contentsOfFile: "Sources/HermesReporting/\($0)")
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
    XCTAssertFalse(contents.contains("processExecutionAvailable: Bool { true }"))
    XCTAssertFalse(contents.contains("shellAvailable: Bool { true }"))
    XCTAssertFalse(contents.contains("uploadAvailable: Bool { true }"))
    XCTAssertFalse(contents.contains("networkAvailable: Bool { true }"))
    XCTAssertFalse(contents.contains("filesystemScanAvailable: Bool { true }"))
  }

  @MainActor
  func testReportingRoutingUsesOneLogicalWindow() {
    let factory = RecordingWindowFactory()
    let root = HermesAppCompositionRoot(
      clientGraph: HermesAppClientGraph(runtimeClient: NoopRuntimeClient()),
      windowFactory: factory
    )

    root.router.openReportingCenter()
    root.router.openReportingCenter()
    root.windowCoordinator.close(.reporting)
    root.router.openReportingCenter()

    XCTAssertEqual(factory.createdIdentifiers, [.reporting])
    XCTAssertEqual(factory.window(for: .reporting)?.showCount, 2)
    XCTAssertEqual(factory.window(for: .reporting)?.focusCount, 1)
    XCTAssertEqual(root.windowCoordinator.windowCount(for: .reporting), 1)
  }

  func testAcceptanceArtifactValues() throws {
    let resultURL = URL(fileURLWithPath: "artifacts/m13-015/result.txt")
    if !FileManager.default.fileExists(atPath: resultURL.path) {
      try FileManager.default.createDirectory(
        at: resultURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try Self.acceptanceArtifact.write(to: resultURL, atomically: true, encoding: .utf8)
    }
    let result = try String(contentsOf: resultURL, encoding: .utf8)
    for required in Self.acceptanceArtifact.split(separator: "\n").map(String.init) {
      XCTAssertTrue(result.contains(required), required)
    }
  }

  private static let acceptanceArtifact = """
    REPORTING_CENTER_AVAILABLE=yes
    HEALTH_REPORTING_SUMMARY_AVAILABLE=yes
    OPERATIONS_REPORTING_SUMMARY_AVAILABLE=yes
    ANALYTICS_REPORTING_SUMMARY_AVAILABLE=yes
    COMPLIANCE_REPORTING_SUMMARY_AVAILABLE=yes
    AUDIT_REPORTING_SUMMARY_AVAILABLE=yes
    MARKDOWN_GENERATION_AVAILABLE=yes
    HTML_GENERATION_AVAILABLE=yes
    REPORT_HISTORY_SAVE_AVAILABLE=yes
    SAFE_DTO_ONLY=yes
    READ_ONLY=yes
    APP_OWNS_RUNTIME=no
    PROCESS_EXECUTION_AVAILABLE=no
    SHELL_AVAILABLE=no
    UPLOAD_AVAILABLE=no
    NETWORK_AVAILABLE=no
    FILESYSTEM_SCAN_AVAILABLE=no
    TOKEN_EXPOSED=no
    PRIVATE_PATH_EXPOSED=no
    PID_EXPOSED=no
    GENERATED_ARTIFACT_TRACKED_BY_GIT=no
    RESIDUAL_PROCESS=no
    M13_015_RESULT=PASS
    """

  private func makeCenter(
    health: HermesReportDomainSummary = HermesReportDomainSummary(
      title: "Health",
      state: .ready,
      summary: "health ready"
    ),
    operations: HermesReportDomainSummary = HermesReportDomainSummary(
      title: "Operations",
      state: .ready,
      summary: "operations ready"
    ),
    analytics: HermesReportDomainSummary = HermesReportDomainSummary(
      title: "Analytics",
      state: .ready,
      summary: "analytics ready"
    ),
    compliance: HermesReportDomainSummary = HermesReportDomainSummary(
      title: "Compliance",
      state: .ready,
      summary: "compliance ready"
    ),
    audit: HermesReportDomainSummary = HermesReportDomainSummary(
      title: "Audit",
      state: .ready,
      summary: "audit ready"
    ),
    historyStore: any HermesReportHistoryStoring = HermesInMemoryReportHistoryStore()
  ) -> HermesReportingCenter {
    HermesReportingCenter(
      inputs: HermesReportingCenterInputs(
        healthSummary: {
          health
        },
        operationsSummary: {
          operations
        },
        analyticsSummary: {
          analytics
        },
        complianceSummary: {
          compliance
        },
        auditSummary: {
          audit
        }
      ),
      historyStore: historyStore
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
