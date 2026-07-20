import HermesBridgeControlCore
import HermesBridgeMenuBar
import HermesBridgeServiceManager
import HermesBridgeXPC
import HermesRuntimeFoundation
import XCTest

final class HermesBridgeMenuBarTests: XCTestCase {
  func testInitialLoadingState() async {
    let viewModel = HermesBridgeMenuBarViewModel(environment: .fake(serviceStatus: .starting))

    let state = await viewModel.state
    XCTAssertEqual(state.serviceStatus, .loading)
  }

  func testHealthyState() async throws {
    let viewModel = HermesBridgeMenuBarViewModel(environment: .fake(serviceStatus: .runningHealthy))

    await viewModel.load()
    let state = await viewModel.state

    XCTAssertEqual(state.serviceStatus, .runningHealthy)
    XCTAssertTrue(state.healthy)
    XCTAssertTrue(state.protocolCompatible)
    XCTAssertEqual(state.enabledBindingCount, 1)
    XCTAssertTrue(state.capabilities.contains("bindingDiscovery"))
  }

  func testUnavailableState() async {
    let viewModel = HermesBridgeMenuBarViewModel(environment: .fake(serviceStatus: .notInstalled))

    await viewModel.load()
    let state = await viewModel.state

    XCTAssertEqual(state.serviceStatus, .unavailable)
    XCTAssertFalse(state.running)
  }

  func testProtocolIncompatibleState() async {
    let viewModel = HermesBridgeMenuBarViewModel(
      environment: .fake(serviceStatus: .runningHealthy, version: .init(major: 2, minor: 0))
    )

    await viewModel.load()

    let state = await viewModel.state
    XCTAssertEqual(state.serviceStatus, .protocolIncompatible)
  }

  func testStartRestartDoctorActions() async {
    let service = FakeServiceManager(status: .installedStopped)
    let doctor = FakeDoctor()
    let viewModel = HermesBridgeMenuBarViewModel(
      environment: .fake(service: service, doctor: doctor)
    )

    let start = await viewModel.startService()
    let restart = await viewModel.restartService()
    let doctorResult = await viewModel.runDoctor()

    XCTAssertTrue(start.succeeded)
    XCTAssertTrue(restart.succeeded)
    XCTAssertTrue(doctorResult.succeeded)
    let startCount = await service.startCount
    let restartCount = await service.restartCount
    let doctorCount = await doctor.count
    XCTAssertEqual(startCount, 1)
    XCTAssertEqual(restartCount, 1)
    XCTAssertEqual(doctorCount, 1)
  }

  func testRefreshCancellation() async {
    let viewModel = HermesBridgeMenuBarViewModel(environment: .fake(serviceStatus: .runningHealthy))

    await viewModel.refresh()
    await viewModel.cancelRefresh()

    let state = await viewModel.state
    XCTAssertEqual(state.serviceStatus, .runningHealthy)
  }

  func testRecentRequestRedactionAndNoResultBody() async {
    let viewModel = HermesBridgeMenuBarViewModel(environment: .fake(serviceStatus: .runningHealthy))

    await viewModel.load()
    let rendered = String(describing: await viewModel.state.recentRequests)

    XCTAssertFalse(rendered.contains("secret prompt"))
    XCTAssertFalse(rendered.contains("backend-token"))
    XCTAssertFalse(rendered.contains("raw result body"))
    XCTAssertFalse(rendered.contains("/Users/"))
  }

  func testAuthorizedRootPanelConfigurationIsDirectoryOnlySingleSelection() {
    let add = HermesAuthorizedRootOpenPanelConfiguration.newDirectory()
    let refresh = HermesAuthorizedRootOpenPanelConfiguration.replacementDirectory(
      rootID: "hroot_test")

    XCTAssertTrue(add.canChooseDirectories)
    XCTAssertFalse(add.canChooseFiles)
    XCTAssertFalse(add.allowsMultipleSelection)
    XCTAssertFalse(add.canCreateDirectories)
    XCTAssertTrue(add.resolvesAliases)
    XCTAssertTrue(refresh.canChooseDirectories)
    XCTAssertFalse(refresh.allowsMultipleSelection)
  }

  func testAuthorizedRootPanelCancelIsNeutral() async {
    let viewModel = HermesAuthorizedRootManagementViewModel(
      panelSelector: FakeAuthorizedRootPanel(results: [.cancelled]),
      bookmarkCreator: FakeBookmarkCreator(),
      client: FakeAuthorizedRootClient()
    )

    let result = await viewModel.addFolder()

    XCTAssertTrue(result.succeeded)
    XCTAssertEqual(result.safeCode, "cancelled")
  }

  func testAuthorizedRootBookmarkRejectsRootHomeNonDirectoryAndSymlink() throws {
    let temp = try temporaryDirectory()
    let file = temp.appendingPathComponent("file.txt")
    try "sample".write(to: file, atomically: true, encoding: .utf8)
    let directory = temp.appendingPathComponent("target", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let symlink = temp.appendingPathComponent("linked", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: directory)
    let creator = ProductionHermesAuthorizedRootBookmarkCreator()

    XCTAssertThrowsError(
      try creator.createBookmark(for: URL(fileURLWithPath: "/", isDirectory: true)))
    XCTAssertThrowsError(
      try creator.createBookmark(for: FileManager.default.homeDirectoryForCurrentUser)
    )
    XCTAssertThrowsError(try creator.createBookmark(for: file))
    XCTAssertThrowsError(try creator.createBookmark(for: symlink))
  }

  func testAuthorizedRootBookmarkCreationAndBalancedSecurityScope() throws {
    let temp = try temporaryDirectory()
    let accessor = CountingSecurityScopeAccessor(startResult: true)
    let creator = ProductionHermesAuthorizedRootBookmarkCreator(accessor: accessor)

    let created = try creator.createBookmark(for: temp)

    XCTAssertFalse(created.bookmarkData.isEmpty)
    XCTAssertEqual(created.displayName, temp.lastPathComponent)
    XCTAssertEqual(created.securityScopeState, .securityScopeStarted)
    XCTAssertEqual(accessor.startCount, 1)
    XCTAssertEqual(accessor.stopCount, 1)
  }

  func testAuthorizedRootBookmarkSizeBoundBeforeRegistration() async {
    let viewModel = HermesAuthorizedRootManagementViewModel(
      panelSelector: FakeAuthorizedRootPanel(results: [.selected(URL(fileURLWithPath: "/tmp"))]),
      bookmarkCreator: FakeBookmarkCreator(
        bookmarkData: Data(
          repeating: 7,
          count: HermesBridgeRegisterAuthorizedRootPayload.maximumBookmarkBytes + 1
        )
      ),
      client: FakeAuthorizedRootClient()
    )

    let result = await viewModel.addFolder()

    XCTAssertFalse(result.succeeded)
    XCTAssertEqual(result.safeCode, "bookmarkTooLarge")
  }

  func testAuthorizedRootRegistrationDispatchAndMutationRefresh() async throws {
    let client = FakeAuthorizedRootClient()
    let viewModel = HermesAuthorizedRootManagementViewModel(
      panelSelector: FakeAuthorizedRootPanel(results: [.selected(URL(fileURLWithPath: "/tmp"))]),
      bookmarkCreator: FakeBookmarkCreator(bookmarkData: Data("bookmark-secret".utf8)),
      client: client
    )

    let result = await viewModel.addFolder()
    let registerCount = await client.registerCount
    let listCount = await client.listCount
    let rendered = String(describing: await viewModel.state)

    XCTAssertTrue(result.succeeded)
    XCTAssertEqual(registerCount, 1)
    XCTAssertGreaterThanOrEqual(listCount, 1)
    XCTAssertFalse(rendered.contains("bookmark-secret"))
    XCTAssertFalse(rendered.contains("/Users/"))
  }

  func testAuthorizedRootRefreshDeactivateReactivateAndRemoveDispatch() async {
    let client = FakeAuthorizedRootClient()
    let panel = FakeAuthorizedRootPanel(results: [
      .selected(URL(fileURLWithPath: "/tmp")),
      .selected(URL(fileURLWithPath: "/tmp")),
    ])
    let viewModel = HermesAuthorizedRootManagementViewModel(
      panelSelector: panel,
      bookmarkCreator: FakeBookmarkCreator(),
      client: client
    )
    let root = client.initialRoot

    _ = await viewModel.refreshAuthorization(rootID: root.rootID, expectedRevision: root.revision)
    _ = await viewModel.deactivate(rootID: root.rootID, expectedRevision: root.revision)
    _ = await viewModel.reactivate(rootID: root.rootID, expectedRevision: root.revision)
    let unconfirmed = await viewModel.remove(
      rootID: root.rootID,
      expectedRevision: root.revision,
      confirmed: false
    )
    _ = await viewModel.remove(
      rootID: root.rootID, expectedRevision: root.revision, confirmed: true)

    let refreshCount = await client.refreshCount
    let deactivateCount = await client.deactivateCount
    let reactivateCount = await client.reactivateCount
    let removeCount = await client.removeCount
    XCTAssertEqual(refreshCount, 1)
    XCTAssertEqual(deactivateCount, 1)
    XCTAssertEqual(reactivateCount, 1)
    XCTAssertEqual(removeCount, 1)
    XCTAssertFalse(unconfirmed.succeeded)
    XCTAssertEqual(unconfirmed.safeCode, "confirmation_required")
  }

  func testAuthorizedRootDuplicateStaleUnavailableUnsupportedAndMonitorStateMapping() async throws {
    let duplicateClient = FakeAuthorizedRootClient(
      registerError: .service(.duplicateAuthorizedRoot))
    let duplicateViewModel = HermesAuthorizedRootManagementViewModel(
      panelSelector: FakeAuthorizedRootPanel(results: [.selected(URL(fileURLWithPath: "/tmp"))]),
      bookmarkCreator: FakeBookmarkCreator(),
      client: duplicateClient
    )
    let duplicate = await duplicateViewModel.addFolder()
    XCTAssertEqual(duplicate.safeCode, "duplicateAuthorizedRoot")

    let stale = try FakeAuthorizedRootClient.summary(
      displayName: "Stale",
      active: true,
      stale: true,
      securityScopeStatus: .unavailable,
      lastObservedEventID: 44
    )
    let staleClient = FakeAuthorizedRootClient(
      roots: [stale],
      monitorStatus: HermesBridgeFileEventMonitorStatusPayload(
        activeSubscriptionCount: 0,
        observedCursor: 44,
        deliveredCursor: 44,
        acknowledgedCursor: 40,
        rescanRequired: true
      )
    )
    let staleViewModel = HermesAuthorizedRootManagementViewModel(
      panelSelector: FakeAuthorizedRootPanel(),
      bookmarkCreator: FakeBookmarkCreator(),
      client: staleClient
    )
    await staleViewModel.load()
    let loadedStaleState = await staleViewModel.state
    let staleState = try XCTUnwrap(loadedStaleState.roots.first)
    XCTAssertTrue(staleState.staleAuthorization)
    XCTAssertEqual(staleState.securityScopeState, .staleBookmark)
    XCTAssertEqual(staleState.monitorState, .inactive)
    XCTAssertTrue(staleState.rescanRequired)

    let unavailable = HermesAuthorizedRootViewState(summary: stale, monitorStatus: nil)
    XCTAssertEqual(unavailable.monitorState, .unavailable)

    let unsupported = HermesAuthorizedRootManagementViewModel(
      panelSelector: FakeAuthorizedRootPanel(),
      bookmarkCreator: FakeBookmarkCreator(),
      client: FakeAuthorizedRootClient(listError: .service(.unsupportedCapability))
    )
    await unsupported.load()
    let unsupportedState = await unsupported.state
    XCTAssertEqual(unsupportedState.loadingState, .unavailable)
  }

  func testAuthorizedRootRenderedStateOmitsAbsolutePathPromptTokenAndContent() throws {
    let root = HermesAuthorizedRootViewState(
      rootID: try HermesAuthorizedRootID.generate().rawValue,
      displayName: "Documents",
      active: true,
      staleAuthorization: false,
      securityScopeState: .securityScopeUnavailable,
      monitorState: .active,
      lastObservedEventID: 9,
      rescanRequired: false,
      actionAvailability: HermesAuthorizedRootActionAvailability(
        canRefreshAuthorization: true,
        canActivate: false,
        canDeactivate: true,
        canRemove: true
      ),
      revision: 1
    )

    let rendered = String(describing: root)

    XCTAssertFalse(rendered.contains("/Users/"))
    XCTAssertFalse(rendered.contains("bookmark"))
    XCTAssertFalse(rendered.contains("backend-token"))
    XCTAssertFalse(rendered.contains("Prompt"))
    XCTAssertFalse(rendered.contains("file-secret"))
  }

  func testAuthorizedRootAddActionSerializationAndTaskCancellation() async {
    let panel = DelayedAuthorizedRootPanel()
    let client = FakeAuthorizedRootClient()
    let viewModel = HermesAuthorizedRootManagementViewModel(
      panelSelector: panel,
      bookmarkCreator: FakeBookmarkCreator(),
      client: client
    )

    async let first = viewModel.addFolder()
    try? await Task.sleep(nanoseconds: 10_000_000)
    let second = await viewModel.addFolder()
    await viewModel.cancelTasks()
    panel.finish(with: .cancelled)
    _ = await first

    XCTAssertFalse(second.succeeded)
    XCTAssertEqual(second.safeCode, "add_in_progress")
    let cancelledState = await viewModel.state
    XCTAssertFalse(cancelledState.addInProgress)
  }

  func testExistingMenuBarControlsRemainAvailableWithoutRealHermesLaunch() async {
    let service = FakeServiceManager(status: .installedStopped)
    let viewModel = HermesBridgeMenuBarViewModel(
      environment: .fake(service: service, doctor: FakeDoctor())
    )

    _ = await viewModel.startService()
    _ = await viewModel.restartService()
    await viewModel.cancelRefresh()

    let startCount = await service.startCount
    let restartCount = await service.restartCount
    XCTAssertEqual(startCount, 1)
    XCTAssertEqual(restartCount, 1)
  }

  func testNoArbitraryPathFieldInAuthorizedRootSources() throws {
    let source = try String(
      contentsOfFile: "Sources/HermesBridgeMenuBar/HermesBridgeMenuBar.swift",
      encoding: .utf8
    )

    XCTAssertFalse(source.contains("TextField("))
    XCTAssertFalse(source.contains("registerAuthorizedRootPath"))
    XCTAssertFalse(source.contains("manualPath"))
  }

  private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("hermes-m5-003-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}

extension HermesBridgeMenuBarEnvironment {
  fileprivate static func fake(
    serviceStatus: HermesBridgeServiceStatus = .runningHealthy,
    version: HermesBridgeProtocolVersion = .current
  ) -> HermesBridgeMenuBarEnvironment {
    fake(service: FakeServiceManager(status: serviceStatus), xpc: FakeXPC(version: version))
  }

  fileprivate static func fake(
    service: FakeServiceManager = FakeServiceManager(status: .runningHealthy),
    xpc: FakeXPC = FakeXPC(),
    doctor: FakeDoctor = FakeDoctor()
  ) -> HermesBridgeMenuBarEnvironment {
    HermesBridgeMenuBarEnvironment(
      serviceManager: service,
      xpcClient: xpc,
      requestLister: FakeLister(),
      doctor: doctor
    )
  }
}

private actor FakeServiceManager: HermesBridgeMenuBarServiceManaging {
  private let statusValue: HermesBridgeServiceStatus
  private(set) var startCount = 0
  private(set) var restartCount = 0

  init(status: HermesBridgeServiceStatus) {
    self.statusValue = status
  }

  func status() async -> HermesBridgeServiceStatus {
    statusValue
  }

  func start() async -> HermesBridgeMenuBarActionResult {
    startCount += 1
    return HermesBridgeMenuBarActionResult(succeeded: true, safeMessage: "start requested")
  }

  func restart() async -> HermesBridgeMenuBarActionResult {
    restartCount += 1
    return HermesBridgeMenuBarActionResult(succeeded: true, safeMessage: "restart completed")
  }
}

private actor FakeXPC: HermesBridgeMenuBarXPCClient {
  private let version: HermesBridgeProtocolVersion

  init(version: HermesBridgeProtocolVersion = .current) {
    self.version = version
  }

  func protocolVersion() async throws -> HermesBridgeProtocolVersionPayload {
    HermesBridgeProtocolVersionPayload(version: version)
  }

  func capabilities() async throws -> HermesBridgeCapabilitiesPayload {
    HermesBridgeCapabilitiesPayload(capabilities: HermesBridgeCapability.allCases)
  }

  func listEnabledBindings() async throws -> HermesBridgeBindingListPayload {
    try HermesBridgeBindingListPayload(bindings: [
      HermesBridgeBindingSummary(
        bindingID: try HermesRequestBindingID(rawValue: "binding:v1:test"),
        localizedDisplayName: "Test",
        safeLocalizedDescription: "Safe",
        maximumPromptBytes: 128,
        approvalPolicy: "explicit",
        enabled: true
      )
    ])
  }

  func close() async {}
}

private struct FakeLister: HermesBridgeMenuBarRequestListing {
  func recentRequests() async throws -> [HermesBridgeMenuBarRequestSummary] {
    [
      HermesBridgeMenuBarRequestSummary(
        requestID: "hrq_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        bindingID: "binding:v1:test",
        lifecycleState: "completed",
        resultAvailable: true,
        failureCode: nil
      )
    ]
  }
}

private actor FakeDoctor: HermesBridgeMenuBarDoctorRunning {
  private(set) var count = 0

  func runDoctor() async -> HermesBridgeMenuBarActionResult {
    count += 1
    return HermesBridgeMenuBarActionResult(succeeded: true, safeMessage: "doctor pass")
  }
}

private final class FakeAuthorizedRootPanel: HermesAuthorizedRootPanelSelecting, @unchecked Sendable
{
  private var results: [HermesAuthorizedRootPanelResult]

  init(results: [HermesAuthorizedRootPanelResult] = [.cancelled]) {
    self.results = results
  }

  @MainActor
  func selectNewDirectory() async -> HermesAuthorizedRootPanelResult {
    next()
  }

  @MainActor
  func selectReplacementDirectory(for _: String) async
    -> HermesAuthorizedRootPanelResult
  {
    next()
  }

  private func next() -> HermesAuthorizedRootPanelResult {
    if results.isEmpty {
      return .cancelled
    }
    return results.removeFirst()
  }
}

private final class DelayedAuthorizedRootPanel: HermesAuthorizedRootPanelSelecting,
  @unchecked Sendable
{
  private var continuation: CheckedContinuation<HermesAuthorizedRootPanelResult, Never>?

  @MainActor
  func selectNewDirectory() async -> HermesAuthorizedRootPanelResult {
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  @MainActor
  func selectReplacementDirectory(for _: String) async
    -> HermesAuthorizedRootPanelResult
  {
    .cancelled
  }

  func finish(with result: HermesAuthorizedRootPanelResult) {
    continuation?.resume(returning: result)
    continuation = nil
  }

}

private struct FakeBookmarkCreator: HermesAuthorizedRootBookmarkCreating {
  let bookmarkData: Data
  let state: HermesAuthorizedRootSecurityScopeState

  init(
    bookmarkData: Data = Data("fake-bookmark".utf8),
    state: HermesAuthorizedRootSecurityScopeState = .ordinaryBookmarkCreated
  ) {
    self.bookmarkData = bookmarkData
    self.state = state
  }

  func createBookmark(for url: URL) throws -> HermesAuthorizedRootBookmarkCreation {
    guard bookmarkData.count <= HermesBridgeRegisterAuthorizedRootPayload.maximumBookmarkBytes
    else {
      throw HermesBridgeXPCError.bookmarkTooLarge
    }
    return HermesAuthorizedRootBookmarkCreation(
      bookmarkData: bookmarkData,
      displayName: url.lastPathComponent.isEmpty ? "Selected" : url.lastPathComponent,
      securityScopeState: state
    )
  }
}

private final class CountingSecurityScopeAccessor: HermesSecurityScopedResourceAccessing,
  @unchecked Sendable
{
  private let startResult: Bool
  private let lock = NSLock()
  private var starts = 0
  private var stops = 0

  init(startResult: Bool) {
    self.startResult = startResult
  }

  var startCount: Int { lock.withLock { starts } }
  var stopCount: Int { lock.withLock { stops } }

  func startAccessing(_: URL) -> Bool {
    lock.withLock {
      starts += 1
    }
    return startResult
  }

  func stopAccessing(_: URL) {
    lock.withLock {
      stops += 1
    }
  }
}

private actor FakeAuthorizedRootClient: HermesAuthorizedRootAppClient {
  private(set) var listCount = 0
  private(set) var registerCount = 0
  private(set) var refreshCount = 0
  private(set) var deactivateCount = 0
  private(set) var reactivateCount = 0
  private(set) var removeCount = 0

  let initialRoot: HermesAuthorizedRootViewState
  private var roots: [HermesBridgeAuthorizedRootSummary]
  private let monitor: HermesBridgeFileEventMonitorStatusPayload
  private let listError: HermesBridgeXPCClientError?
  private let registerError: HermesBridgeXPCClientError?

  init(
    roots: [HermesBridgeAuthorizedRootSummary]? = nil,
    monitorStatus: HermesBridgeFileEventMonitorStatusPayload =
      HermesBridgeFileEventMonitorStatusPayload(
        activeSubscriptionCount: 1,
        observedCursor: 12,
        deliveredCursor: 12,
        acknowledgedCursor: 10,
        rescanRequired: false
      ),
    listError: HermesBridgeXPCClientError? = nil,
    registerError: HermesBridgeXPCClientError? = nil
  ) {
    let summary = try! Self.summary(displayName: "Docs")
    self.roots = roots ?? [summary]
    self.monitor = monitorStatus
    self.listError = listError
    self.registerError = registerError
    self.initialRoot = HermesAuthorizedRootViewState(summary: summary, monitorStatus: monitorStatus)
  }

  func listRoots() async throws -> HermesBridgeAuthorizedRootListPayload {
    listCount += 1
    if let listError {
      throw listError
    }
    return HermesBridgeAuthorizedRootListPayload(roots: roots)
  }

  func registerBookmark(displayName: String, bookmarkData _: Data) async throws
    -> HermesBridgeAuthorizedRootPayload
  {
    registerCount += 1
    if let registerError {
      throw registerError
    }
    let summary = try Self.summary(displayName: displayName)
    roots.append(summary)
    return HermesBridgeAuthorizedRootPayload(root: summary)
  }

  func refreshBookmark(rootID: String, bookmarkData _: Data, expectedRevision _: Int?) async throws
    -> HermesBridgeAuthorizedRootPayload
  {
    refreshCount += 1
    return HermesBridgeAuthorizedRootPayload(
      root: try Self.summary(rootID: rootID, displayName: "Docs"))
  }

  func deactivate(rootID: String, expectedRevision _: Int?) async throws
    -> HermesBridgeAuthorizedRootPayload
  {
    deactivateCount += 1
    return HermesBridgeAuthorizedRootPayload(
      root: try Self.summary(rootID: rootID, displayName: "Docs", active: false)
    )
  }

  func reactivate(rootID: String, bookmarkData _: Data, expectedRevision _: Int?) async throws
    -> HermesBridgeAuthorizedRootPayload
  {
    reactivateCount += 1
    return HermesBridgeAuthorizedRootPayload(
      root: try Self.summary(rootID: rootID, displayName: "Docs"))
  }

  func remove(rootID: String, expectedRevision _: Int?) async throws
    -> HermesBridgeAuthorizedRootPayload
  {
    removeCount += 1
    roots.removeAll { $0.rootID == rootID }
    return HermesBridgeAuthorizedRootPayload(
      root: try Self.summary(rootID: rootID, displayName: "Docs"))
  }

  func rootStatus(rootID: String) async throws -> HermesBridgeAuthorizedRootStatusPayload {
    HermesBridgeAuthorizedRootStatusPayload(
      root: try Self.summary(rootID: rootID, displayName: "Docs")
    )
  }

  func monitorStatus() async throws -> HermesBridgeFileEventMonitorStatusPayload {
    monitor
  }

  static func summary(
    rootID: String = (try! HermesAuthorizedRootID.generate()).rawValue,
    displayName: String,
    active: Bool = true,
    stale: Bool = false,
    securityScopeStatus: HermesBridgeSecurityScopeStatus = .unavailable,
    lastObservedEventID: UInt64 = 12
  ) throws -> HermesBridgeAuthorizedRootSummary {
    let id = try HermesAuthorizedRootID(rawValue: rootID)
    let record = try HermesAuthorizedRootRecord(
      rootID: id,
      displayName: displayName,
      resolvedRootURL: FileManager.default.temporaryDirectory
        .appendingPathComponent(id.rawValue, isDirectory: true),
      bookmarkData: Data("bookmark".utf8),
      bookmarkCreatedAt: Date(),
      bookmarkUpdatedAt: Date(),
      bookmarkDataIsStale: stale,
      state: active ? .active : .inactive,
      lastObservedFSEventID: lastObservedEventID,
      revision: 1
    )
    return HermesBridgeAuthorizedRootSummary(
      record: record,
      securityScopeStatus: securityScopeStatus
    )
  }
}
