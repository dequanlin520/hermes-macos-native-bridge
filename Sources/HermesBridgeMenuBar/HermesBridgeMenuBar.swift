import AppKit
import Foundation
import HermesBridgeControlCore
import HermesBridgeServiceManager
import HermesBridgeXPC
import HermesRuntimeFoundation

public enum HermesBridgeMenuBarServiceStatus: String, Codable, Equatable, Sendable {
  case loading
  case unavailable
  case installedStopped
  case runningHealthy
  case runningUnhealthy
  case protocolIncompatible
}

public struct HermesBridgeMenuBarRequestSummary: Codable, Equatable, Sendable {
  public let requestID: String
  public let bindingID: String
  public let lifecycleState: String
  public let resultAvailable: Bool
  public let failureCode: String?

  public init(summary: HermesBridgeRequestSummary) {
    self.requestID = Self.safeID(summary.requestID)
    self.bindingID = Self.safeID(summary.bindingID)
    self.lifecycleState = Self.safeToken(summary.lifecycleState)
    self.resultAvailable = summary.resultAvailable
    self.failureCode = summary.failureCode.map(Self.safeToken)
  }

  public init(
    requestID: String,
    bindingID: String,
    lifecycleState: String,
    resultAvailable: Bool,
    failureCode: String? = nil
  ) {
    self.requestID = Self.safeID(requestID)
    self.bindingID = Self.safeID(bindingID)
    self.lifecycleState = Self.safeToken(lifecycleState)
    self.resultAvailable = resultAvailable
    self.failureCode = failureCode.map(Self.safeToken)
  }

  private static func safeID(_ value: String) -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == ":" || $0 == "." || $0 == "_" || $0 == "-")
    }
    return String(filtered.prefix(128))
  }

  private static func safeToken(_ value: String) -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-")
    }
    return String(filtered.prefix(64))
  }
}

public struct HermesBridgeMenuBarState: Codable, Equatable, Sendable {
  public var serviceStatus: HermesBridgeMenuBarServiceStatus
  public var installed: Bool
  public var running: Bool
  public var healthy: Bool
  public var protocolCompatible: Bool
  public var protocolVersion: String?
  public var capabilities: [String]
  public var enabledBindingCount: Int
  public var recentRequests: [HermesBridgeMenuBarRequestSummary]
  public var permissionChecks: [HermesMenuBarPermissionCheckViewState]
  public var auditIntegrity: HermesMenuBarAuditIntegrityViewState?
  public var recentAuditEvents: [HermesMenuBarAuditEventViewState]
  public var lastActionMessage: String?

  public init(
    serviceStatus: HermesBridgeMenuBarServiceStatus = .loading,
    installed: Bool = false,
    running: Bool = false,
    healthy: Bool = false,
    protocolCompatible: Bool = false,
    protocolVersion: String? = nil,
    capabilities: [String] = [],
    enabledBindingCount: Int = 0,
    recentRequests: [HermesBridgeMenuBarRequestSummary] = [],
    permissionChecks: [HermesMenuBarPermissionCheckViewState] = [],
    auditIntegrity: HermesMenuBarAuditIntegrityViewState? = nil,
    recentAuditEvents: [HermesMenuBarAuditEventViewState] = [],
    lastActionMessage: String? = nil
  ) {
    self.serviceStatus = serviceStatus
    self.installed = installed
    self.running = running
    self.healthy = healthy
    self.protocolCompatible = protocolCompatible
    self.protocolVersion = protocolVersion
    self.capabilities = capabilities.sorted()
    self.enabledBindingCount = min(
      max(0, enabledBindingCount), HermesBridgeBindingSummary.maximumCount)
    self.recentRequests = Array(recentRequests.prefix(8))
    self.permissionChecks = Array(permissionChecks.prefix(HermesPermissionKind.allCases.count))
    self.auditIntegrity = auditIntegrity
    self.recentAuditEvents = Array(recentAuditEvents.prefix(20))
    self.lastActionMessage = lastActionMessage.map { String($0.prefix(120)) }
  }
}

public struct HermesMenuBarPermissionCheckViewState: Codable, Equatable, Sendable,
  Identifiable
{
  public let id: String
  public let kind: String
  public let state: String
  public let detailCode: String
  public let remediationCode: String?

  public init(check: HermesPermissionCheck) {
    self.id = check.kind.rawValue
    self.kind = check.kind.rawValue
    self.state = check.state.rawValue
    self.detailCode = check.detailCode
    self.remediationCode = check.remediationCode?.rawValue
  }
}

public struct HermesMenuBarAuditEventViewState: Codable, Equatable, Sendable,
  Identifiable
{
  public let id: String
  public let timestamp: Date
  public let kind: String
  public let actor: String
  public let outcome: String
  public let reasonCode: String
  public let correlationID: String?

  public init(event: HermesAuditEvent) {
    self.id = event.eventID.rawValue
    self.timestamp = event.timestamp
    self.kind = event.kind.rawValue
    self.actor = event.actor.rawValue
    self.outcome = event.outcome.rawValue
    self.reasonCode = event.reasonCode
    self.correlationID = event.correlationID
  }
}

public struct HermesMenuBarAuditIntegrityViewState: Codable, Equatable, Sendable {
  public let state: String
  public let verifiedSegmentCount: Int
  public let verifiedEventCount: Int
  public let issueCodes: [String]
  public let verifiedAt: Date
  public let signingAvailable: Bool
  public let activeFingerprintPrefix: String?
  public let accessPolicyState: String?
  public let signingRequiredPolicy: String?
  public let nonInteractiveSigningProven: Bool
  public let rotationTransactionState: String?
  public let recoveryRequired: String?

  public init(
    report: HermesAuditVerificationReport,
    signingStatus: HermesAuditSigningStatus? = nil,
    operationalStatus: HermesAuditSigningOperationalStatus? = nil
  ) {
    self.state = report.state.rawValue
    self.verifiedSegmentCount = report.verifiedSegmentCount
    self.verifiedEventCount = report.verifiedEventCount
    self.issueCodes = report.issueCodes.map(\.rawValue)
    self.verifiedAt = report.verifiedAt
    self.signingAvailable = signingStatus?.signingAvailable ?? false
    self.activeFingerprintPrefix = signingStatus?.activeFingerprintPrefix
    self.accessPolicyState = operationalStatus?.accessPolicyState.rawValue
    self.signingRequiredPolicy = operationalStatus?.signingRequiredPolicy.rawValue
    self.nonInteractiveSigningProven = operationalStatus?.nonInteractiveSigningProven ?? false
    self.rotationTransactionState = operationalStatus?.rotationTransactionState?.rawValue
    self.recoveryRequired = operationalStatus?.recoveryRequired?.rawValue
  }
}

public struct HermesBridgeMenuBarActionResult: Codable, Equatable, Sendable {
  public let succeeded: Bool
  public let safeMessage: String

  public init(succeeded: Bool, safeMessage: String) {
    self.succeeded = succeeded
    self.safeMessage = String(safeMessage.prefix(120))
  }
}

public enum HermesAuthorizedRootLoadingState: String, Codable, Equatable, Sendable {
  case loading
  case loaded
  case unavailable
  case failed
}

public enum HermesAuthorizedRootSecurityScopeState: String, Codable, Equatable, Sendable {
  case ordinaryBookmarkCreated
  case securityScopedBookmarkCreated
  case securityScopeStarted
  case securityScopeUnavailable
  case staleBookmark
  case rejected
}

public enum HermesAuthorizedRootMonitorState: String, Codable, Equatable, Sendable {
  case active
  case inactive
  case unavailable
}

public struct HermesAuthorizedRootActionAvailability: Codable, Equatable, Sendable {
  public let canRefreshAuthorization: Bool
  public let canActivate: Bool
  public let canDeactivate: Bool
  public let canRemove: Bool

  public init(
    canRefreshAuthorization: Bool,
    canActivate: Bool,
    canDeactivate: Bool,
    canRemove: Bool
  ) {
    self.canRefreshAuthorization = canRefreshAuthorization
    self.canActivate = canActivate
    self.canDeactivate = canDeactivate
    self.canRemove = canRemove
  }
}

public struct HermesAuthorizedRootViewState: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let rootID: String
  public let displayName: String
  public let active: Bool
  public let staleAuthorization: Bool
  public let securityScopeState: HermesAuthorizedRootSecurityScopeState
  public let monitorState: HermesAuthorizedRootMonitorState
  public let lastObservedEventID: UInt64
  public let rescanRequired: Bool
  public let actionAvailability: HermesAuthorizedRootActionAvailability
  public let revision: Int

  public init(
    summary: HermesBridgeAuthorizedRootSummary,
    monitorStatus: HermesBridgeFileEventMonitorStatusPayload?
  ) {
    let monitorActive = (monitorStatus?.activeSubscriptionCount ?? 0) > 0
    self.id = Self.safeID(summary.rootID)
    self.rootID = Self.safeID(summary.rootID)
    self.displayName = Self.safeText(summary.displayName, maximumCharacters: 80)
    self.active = summary.active
    self.staleAuthorization = summary.staleAuthorization
    if summary.staleAuthorization {
      self.securityScopeState = .staleBookmark
    } else {
      self.securityScopeState =
        summary.securityScopeStatus == .available
        ? .securityScopeStarted : .securityScopeUnavailable
    }
    self.monitorState = monitorStatus == nil ? .unavailable : (monitorActive ? .active : .inactive)
    self.lastObservedEventID = summary.lastObservedEventID
    self.rescanRequired = monitorStatus?.rescanRequired ?? false
    self.actionAvailability = HermesAuthorizedRootActionAvailability(
      canRefreshAuthorization: true,
      canActivate: !summary.active,
      canDeactivate: summary.active,
      canRemove: true
    )
    self.revision = max(0, summary.revision)
  }

  public init(
    rootID: String,
    displayName: String,
    active: Bool,
    staleAuthorization: Bool,
    securityScopeState: HermesAuthorizedRootSecurityScopeState,
    monitorState: HermesAuthorizedRootMonitorState,
    lastObservedEventID: UInt64,
    rescanRequired: Bool,
    actionAvailability: HermesAuthorizedRootActionAvailability,
    revision: Int
  ) {
    self.id = Self.safeID(rootID)
    self.rootID = Self.safeID(rootID)
    self.displayName = Self.safeText(displayName, maximumCharacters: 80)
    self.active = active
    self.staleAuthorization = staleAuthorization
    self.securityScopeState = securityScopeState
    self.monitorState = monitorState
    self.lastObservedEventID = lastObservedEventID
    self.rescanRequired = rescanRequired
    self.actionAvailability = actionAvailability
    self.revision = max(0, revision)
  }

  private static func safeID(_ value: String) -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-")
    }
    return String(filtered.prefix(HermesAuthorizedRootID.maximumLength))
  }

  private static func safeText(_ value: String, maximumCharacters: Int) -> String {
    let filtered = value.unicodeScalars.filter { scalar in
      scalar.value >= 0x20 && scalar.value != 0x7F
    }
    return String(String(String.UnicodeScalarView(filtered)).prefix(maximumCharacters))
  }
}

public struct HermesAuthorizedRootActionResult: Codable, Equatable, Sendable {
  public let succeeded: Bool
  public let safeCode: String
  public let safeMessage: String
  public let updatedRoot: HermesAuthorizedRootViewState?

  public init(
    succeeded: Bool,
    safeCode: String,
    safeMessage: String,
    updatedRoot: HermesAuthorizedRootViewState? = nil
  ) {
    self.succeeded = succeeded
    self.safeCode = Self.safeToken(safeCode)
    self.safeMessage = Self.safeText(safeMessage, maximumCharacters: 160)
    self.updatedRoot = updatedRoot
  }

  private static func safeToken(_ value: String) -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-")
    }
    return String(filtered.prefix(64))
  }

  private static func safeText(_ value: String, maximumCharacters: Int) -> String {
    let filtered = value.unicodeScalars.filter { scalar in
      scalar.value >= 0x20 && scalar.value != 0x7F
    }
    return String(String(String.UnicodeScalarView(filtered)).prefix(maximumCharacters))
  }
}

public enum HermesAuthorizedRootPanelResult: Equatable, Sendable {
  case selected(URL)
  case cancelled
}

public protocol HermesAuthorizedRootPanelSelecting: Sendable {
  @MainActor func selectNewDirectory() async -> HermesAuthorizedRootPanelResult
  @MainActor func selectReplacementDirectory(for rootID: String) async
    -> HermesAuthorizedRootPanelResult
}

public struct HermesAuthorizedRootOpenPanelConfiguration: Equatable, Sendable {
  public let canChooseDirectories: Bool
  public let canChooseFiles: Bool
  public let allowsMultipleSelection: Bool
  public let canCreateDirectories: Bool
  public let resolvesAliases: Bool
  public let prompt: String
  public let title: String
  public let message: String

  public static func newDirectory() -> HermesAuthorizedRootOpenPanelConfiguration {
    HermesAuthorizedRootOpenPanelConfiguration(
      canChooseDirectories: true,
      canChooseFiles: false,
      allowsMultipleSelection: false,
      canCreateDirectories: false,
      resolvesAliases: true,
      prompt: NSLocalizedString("Add Folder", comment: "Authorized root add prompt"),
      title: NSLocalizedString("Choose Authorized Folder", comment: "Authorized root add title"),
      message: NSLocalizedString(
        "Choose one folder for Hermes Bridge to authorize.",
        comment: "Authorized root add message"
      )
    )
  }

  public static func replacementDirectory(rootID _: String)
    -> HermesAuthorizedRootOpenPanelConfiguration
  {
    HermesAuthorizedRootOpenPanelConfiguration(
      canChooseDirectories: true,
      canChooseFiles: false,
      allowsMultipleSelection: false,
      canCreateDirectories: false,
      resolvesAliases: true,
      prompt: NSLocalizedString("Refresh Authorization", comment: "Authorized root refresh prompt"),
      title: NSLocalizedString(
        "Refresh Authorized Folder",
        comment: "Authorized root refresh title"
      ),
      message: NSLocalizedString(
        "Choose the same folder again to refresh authorization.",
        comment: "Authorized root refresh message"
      )
    )
  }
}

public final class NSOpenPanelHermesAuthorizedRootSelector: HermesAuthorizedRootPanelSelecting,
  @unchecked Sendable
{
  public init() {}

  @MainActor
  public func selectNewDirectory() async -> HermesAuthorizedRootPanelResult {
    await runPanel(configuration: .newDirectory())
  }

  @MainActor
  public func selectReplacementDirectory(for rootID: String) async
    -> HermesAuthorizedRootPanelResult
  {
    await runPanel(configuration: .replacementDirectory(rootID: rootID))
  }

  @MainActor
  private func runPanel(configuration: HermesAuthorizedRootOpenPanelConfiguration) async
    -> HermesAuthorizedRootPanelResult
  {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = configuration.canChooseDirectories
    panel.canChooseFiles = configuration.canChooseFiles
    panel.allowsMultipleSelection = configuration.allowsMultipleSelection
    panel.canCreateDirectories = configuration.canCreateDirectories
    panel.resolvesAliases = configuration.resolvesAliases
    panel.prompt = configuration.prompt
    panel.title = configuration.title
    panel.message = configuration.message
    let response = await panel.begin()
    guard response == .OK, let url = panel.urls.first else {
      return .cancelled
    }
    return .selected(url)
  }
}

public protocol HermesAuthorizedRootBookmarkCreating: Sendable {
  func createBookmark(for url: URL) throws -> HermesAuthorizedRootBookmarkCreation
}

public protocol HermesSecurityScopedResourceAccessing: Sendable {
  func startAccessing(_ url: URL) -> Bool
  func stopAccessing(_ url: URL)
}

public struct ProductionHermesSecurityScopedResourceAccessor:
  HermesSecurityScopedResourceAccessing
{
  public init() {}

  public func startAccessing(_ url: URL) -> Bool {
    url.startAccessingSecurityScopedResource()
  }

  public func stopAccessing(_ url: URL) {
    url.stopAccessingSecurityScopedResource()
  }
}

public struct HermesAuthorizedRootBookmarkCreation: Equatable, Sendable {
  public let bookmarkData: Data
  public let displayName: String
  public let securityScopeState: HermesAuthorizedRootSecurityScopeState

  public init(
    bookmarkData: Data,
    displayName: String,
    securityScopeState: HermesAuthorizedRootSecurityScopeState
  ) {
    self.bookmarkData = bookmarkData
    self.displayName = displayName
    self.securityScopeState = securityScopeState
  }
}

public struct ProductionHermesAuthorizedRootBookmarkCreator:
  HermesAuthorizedRootBookmarkCreating
{
  private let accessor: any HermesSecurityScopedResourceAccessing

  public init(
    accessor: any HermesSecurityScopedResourceAccessing =
      ProductionHermesSecurityScopedResourceAccessor()
  ) {
    self.accessor = accessor
  }

  public func createBookmark(for url: URL) throws -> HermesAuthorizedRootBookmarkCreation {
    let standardized = url.standardizedFileURL
    let resolved = standardized.resolvingSymlinksInPath()
    guard resolved.path != "/" else {
      throw HermesBridgeXPCError.invalidBookmark
    }
    let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
      .resolvingSymlinksInPath()
    guard resolved.path != home.path else {
      throw HermesBridgeXPCError.invalidBookmark
    }
    guard !Self.isSymlink(standardized.path) else {
      throw HermesBridgeXPCError.invalidBookmark
    }
    var isDirectory = ObjCBool(false)
    guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      throw HermesBridgeXPCError.invalidBookmark
    }

    let scopeStarted = accessor.startAccessing(resolved)
    defer {
      if scopeStarted {
        accessor.stopAccessing(resolved)
      }
    }

    let securityScopedData = try? resolved.bookmarkData(
      options: [.withSecurityScope],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
    let state: HermesAuthorizedRootSecurityScopeState
    let bookmarkData: Data
    if let securityScopedData {
      bookmarkData = securityScopedData
      state = scopeStarted ? .securityScopeStarted : .securityScopedBookmarkCreated
    } else {
      bookmarkData = try resolved.bookmarkData(
        options: [],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      state = scopeStarted ? .securityScopeStarted : .ordinaryBookmarkCreated
    }
    guard bookmarkData.count <= HermesBridgeRegisterAuthorizedRootPayload.maximumBookmarkBytes
    else {
      throw HermesBridgeXPCError.bookmarkTooLarge
    }
    return HermesAuthorizedRootBookmarkCreation(
      bookmarkData: bookmarkData,
      displayName: resolved.lastPathComponent.isEmpty
        ? "Authorized Folder" : resolved.lastPathComponent,
      securityScopeState: state
    )
  }

  private static func isSymlink(_ path: String) -> Bool {
    (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil
  }
}

public protocol HermesBridgeMenuBarServiceManaging: Sendable {
  func status() async -> HermesBridgeServiceStatus
  func start() async -> HermesBridgeMenuBarActionResult
  func restart() async -> HermesBridgeMenuBarActionResult
}

public protocol HermesBridgeMenuBarXPCClient: Sendable {
  func protocolVersion() async throws -> HermesBridgeProtocolVersionPayload
  func capabilities() async throws -> HermesBridgeCapabilitiesPayload
  func listEnabledBindings() async throws -> HermesBridgeBindingListPayload
  func close() async
}

public protocol HermesBridgeMenuBarRequestListing: Sendable {
  func recentRequests() async throws -> [HermesBridgeMenuBarRequestSummary]
}

public protocol HermesBridgeMenuBarDoctorRunning: Sendable {
  func runDoctor() async -> HermesBridgeMenuBarActionResult
}

public protocol HermesBridgeMenuBarPermissionViewing: Sendable {
  func viewPermissions() async -> [HermesMenuBarPermissionCheckViewState]
  func openSettings(remediationCode: HermesPermissionRemediationCode) async
    -> HermesBridgeMenuBarActionResult
}

public protocol HermesBridgeMenuBarAuditViewing: Sendable {
  func recentAuditEvents() async throws -> [HermesMenuBarAuditEventViewState]
  func integrityStatus() async throws -> HermesMenuBarAuditIntegrityViewState
  func exportAudit(to outputDirectory: URL) async -> HermesBridgeMenuBarActionResult
}

extension HermesBridgeMenuBarAuditViewing {
  public func integrityStatus() async throws -> HermesMenuBarAuditIntegrityViewState {
    HermesMenuBarAuditIntegrityViewState(
      report: HermesAuditVerificationReport(
        state: .signatureUnavailable,
        verifiedSegmentCount: 0,
        verifiedEventCount: 0,
        issueCodes: [.signatureUnavailable]
      ))
  }
}

public protocol HermesAuthorizedRootAppClient: Sendable {
  func listRoots() async throws -> HermesBridgeAuthorizedRootListPayload
  func registerBookmark(displayName: String, bookmarkData: Data) async throws
    -> HermesBridgeAuthorizedRootPayload
  func refreshBookmark(rootID: String, bookmarkData: Data, expectedRevision: Int?) async throws
    -> HermesBridgeAuthorizedRootPayload
  func deactivate(rootID: String, expectedRevision: Int?) async throws
    -> HermesBridgeAuthorizedRootPayload
  func reactivate(rootID: String, bookmarkData: Data, expectedRevision: Int?) async throws
    -> HermesBridgeAuthorizedRootPayload
  func remove(rootID: String, expectedRevision: Int?) async throws
    -> HermesBridgeAuthorizedRootPayload
  func rootStatus(rootID: String) async throws -> HermesBridgeAuthorizedRootStatusPayload
  func monitorStatus() async throws -> HermesBridgeFileEventMonitorStatusPayload
}

public struct HermesAuthorizedRootManagementState: Codable, Equatable, Sendable {
  public var loadingState: HermesAuthorizedRootLoadingState
  public var roots: [HermesAuthorizedRootViewState]
  public var lastAction: HermesAuthorizedRootActionResult?
  public var addInProgress: Bool
  public var safeMessage: String?

  public init(
    loadingState: HermesAuthorizedRootLoadingState = .loading,
    roots: [HermesAuthorizedRootViewState] = [],
    lastAction: HermesAuthorizedRootActionResult? = nil,
    addInProgress: Bool = false,
    safeMessage: String? = nil
  ) {
    self.loadingState = loadingState
    self.roots = Array(roots.prefix(HermesBridgeAuthorizedRootListPayload.maximumRootCount))
    self.lastAction = lastAction
    self.addInProgress = addInProgress
    self.safeMessage = safeMessage.map { String($0.prefix(160)) }
  }
}

public actor HermesAuthorizedRootManagementViewModel {
  private let panelSelector: any HermesAuthorizedRootPanelSelecting
  private let bookmarkCreator: any HermesAuthorizedRootBookmarkCreating
  private let client: any HermesAuthorizedRootAppClient
  private var refreshTask: Task<Void, Never>?
  private var mutationTasks: [Task<Void, Never>] = []
  private var addTaskActive = false
  public private(set) var state = HermesAuthorizedRootManagementState()

  public init(
    panelSelector: any HermesAuthorizedRootPanelSelecting,
    bookmarkCreator: any HermesAuthorizedRootBookmarkCreating,
    client: any HermesAuthorizedRootAppClient
  ) {
    self.panelSelector = panelSelector
    self.bookmarkCreator = bookmarkCreator
    self.client = client
  }

  public func load() async {
    await refresh()
  }

  public func refresh() async {
    refreshTask?.cancel()
    let task = Task { await self.performRefresh() }
    refreshTask = task
    await task.value
  }

  public func cancelTasks() {
    refreshTask?.cancel()
    refreshTask = nil
    mutationTasks.forEach { $0.cancel() }
    mutationTasks.removeAll()
    addTaskActive = false
  }

  public func addFolder() async -> HermesAuthorizedRootActionResult {
    guard !addTaskActive else {
      let result = HermesAuthorizedRootActionResult(
        succeeded: false,
        safeCode: "add_in_progress",
        safeMessage: "Add Folder is already in progress."
      )
      state.lastAction = result
      return result
    }
    addTaskActive = true
    state.addInProgress = true
    defer {
      addTaskActive = false
      state.addInProgress = false
    }
    let selection = await panelSelector.selectNewDirectory()
    guard case .selected(let url) = selection else {
      let result = HermesAuthorizedRootActionResult(
        succeeded: true,
        safeCode: "cancelled",
        safeMessage: "Folder selection cancelled."
      )
      state.lastAction = result
      return result
    }
    do {
      let bookmark = try bookmarkCreator.createBookmark(for: url)
      let payload = try await client.registerBookmark(
        displayName: bookmark.displayName,
        bookmarkData: bookmark.bookmarkData
      )
      let viewState = HermesAuthorizedRootViewState(
        summary: payload.root,
        monitorStatus: try? await client.monitorStatus()
      )
      await refresh()
      let result = HermesAuthorizedRootActionResult(
        succeeded: true,
        safeCode: bookmark.securityScopeState.rawValue,
        safeMessage: "Folder authorization registered.",
        updatedRoot: viewState
      )
      state.lastAction = result
      return result
    } catch {
      let result = actionResult(for: error)
      state.lastAction = result
      return result
    }
  }

  public func refreshAuthorization(rootID: String, expectedRevision: Int?) async
    -> HermesAuthorizedRootActionResult
  {
    let selection = await panelSelector.selectReplacementDirectory(for: rootID)
    guard case .selected(let url) = selection else {
      let result = HermesAuthorizedRootActionResult(
        succeeded: true,
        safeCode: "cancelled",
        safeMessage: "Authorization refresh cancelled."
      )
      state.lastAction = result
      return result
    }
    do {
      let bookmark = try bookmarkCreator.createBookmark(for: url)
      let payload = try await client.refreshBookmark(
        rootID: rootID,
        bookmarkData: bookmark.bookmarkData,
        expectedRevision: expectedRevision
      )
      let viewState = HermesAuthorizedRootViewState(
        summary: payload.root,
        monitorStatus: try? await client.monitorStatus()
      )
      await refresh()
      let result = HermesAuthorizedRootActionResult(
        succeeded: true,
        safeCode: bookmark.securityScopeState.rawValue,
        safeMessage: "Folder authorization refreshed.",
        updatedRoot: viewState
      )
      state.lastAction = result
      return result
    } catch {
      let result = actionResult(for: error)
      state.lastAction = result
      return result
    }
  }

  public func deactivate(rootID: String, expectedRevision: Int?) async
    -> HermesAuthorizedRootActionResult
  {
    await mutateAndRefresh(
      successCode: "deactivated",
      successMessage: "Folder authorization deactivated."
    ) {
      try await self.client.deactivate(rootID: rootID, expectedRevision: expectedRevision)
    }
  }

  public func reactivate(rootID: String, expectedRevision: Int?) async
    -> HermesAuthorizedRootActionResult
  {
    let selection = await panelSelector.selectReplacementDirectory(for: rootID)
    guard case .selected(let url) = selection else {
      let result = HermesAuthorizedRootActionResult(
        succeeded: true,
        safeCode: "cancelled",
        safeMessage: "Reactivation cancelled."
      )
      state.lastAction = result
      return result
    }
    do {
      let bookmark = try bookmarkCreator.createBookmark(for: url)
      let payload = try await client.reactivate(
        rootID: rootID,
        bookmarkData: bookmark.bookmarkData,
        expectedRevision: expectedRevision
      )
      let viewState = HermesAuthorizedRootViewState(
        summary: payload.root,
        monitorStatus: try? await client.monitorStatus()
      )
      await refresh()
      let result = HermesAuthorizedRootActionResult(
        succeeded: true,
        safeCode: bookmark.securityScopeState.rawValue,
        safeMessage: "Folder authorization reactivated.",
        updatedRoot: viewState
      )
      state.lastAction = result
      return result
    } catch {
      let result = actionResult(for: error)
      state.lastAction = result
      return result
    }
  }

  public func remove(rootID: String, expectedRevision: Int?, confirmed: Bool) async
    -> HermesAuthorizedRootActionResult
  {
    guard confirmed else {
      let result = HermesAuthorizedRootActionResult(
        succeeded: false,
        safeCode: "confirmation_required",
        safeMessage: "Removal requires confirmation."
      )
      state.lastAction = result
      return result
    }
    return await mutateAndRefresh(
      successCode: "removed",
      successMessage: "Folder authorization removed."
    ) {
      try await self.client.remove(rootID: rootID, expectedRevision: expectedRevision)
    }
  }

  private func performRefresh() async {
    if Task.isCancelled { return }
    state.loadingState = .loading
    do {
      let rootsPayload = try await client.listRoots()
      let monitor = try? await client.monitorStatus()
      let roots = rootsPayload.roots.map {
        HermesAuthorizedRootViewState(summary: $0, monitorStatus: monitor)
      }
      if Task.isCancelled { return }
      state.loadingState = .loaded
      state.roots = roots
      state.safeMessage = nil
    } catch let error as HermesBridgeXPCClientError {
      state.loadingState = loadingState(for: error)
      state.safeMessage = safeMessage(for: error)
    } catch {
      state.loadingState = .failed
      state.safeMessage = "Authorized folders could not be loaded."
    }
  }

  private func mutateAndRefresh(
    successCode: String,
    successMessage: String,
    operation: @escaping @Sendable () async throws -> HermesBridgeAuthorizedRootPayload
  ) async -> HermesAuthorizedRootActionResult {
    do {
      let payload = try await operation()
      let viewState = HermesAuthorizedRootViewState(
        summary: payload.root,
        monitorStatus: try? await client.monitorStatus()
      )
      await refresh()
      let result = HermesAuthorizedRootActionResult(
        succeeded: true,
        safeCode: successCode,
        safeMessage: successMessage,
        updatedRoot: viewState
      )
      state.lastAction = result
      return result
    } catch {
      let result = actionResult(for: error)
      state.lastAction = result
      return result
    }
  }

  private func actionResult(for error: Error) -> HermesAuthorizedRootActionResult {
    if let xpcError = error as? HermesBridgeXPCClientError {
      return HermesAuthorizedRootActionResult(
        succeeded: false,
        safeCode: safeCode(for: xpcError),
        safeMessage: safeMessage(for: xpcError)
      )
    }
    if let bridgeError = error as? HermesBridgeXPCError {
      return HermesAuthorizedRootActionResult(
        succeeded: false,
        safeCode: bridgeError.rawValue,
        safeMessage: safeMessage(for: .service(bridgeError))
      )
    }
    return HermesAuthorizedRootActionResult(
      succeeded: false,
      safeCode: "failed",
      safeMessage: "Authorized folder action failed."
    )
  }

  private func loadingState(for error: HermesBridgeXPCClientError)
    -> HermesAuthorizedRootLoadingState
  {
    switch error {
    case .service(.serviceUnavailable), .invalidated, .interrupted, .timedOut:
      return .unavailable
    case .service(.unsupportedCapability), .protocolNegotiationFailed:
      return .unavailable
    default:
      return .failed
    }
  }

  private func safeCode(for error: HermesBridgeXPCClientError) -> String {
    switch error {
    case .service(let code):
      return code.rawValue
    case .timedOut:
      return "timed_out"
    case .interrupted:
      return "interrupted"
    case .invalidated:
      return "invalidated"
    case .responseDecodingFailure:
      return "response_decoding_failure"
    case .protocolNegotiationFailed:
      return "protocol_negotiation_failed"
    }
  }

  private func safeMessage(for error: HermesBridgeXPCClientError) -> String {
    switch error {
    case .service(.unsupportedCapability):
      return "Authorized folder management is not supported by this Bridge service."
    case .service(.duplicateAuthorizedRoot):
      return "That folder is already authorized."
    case .service(.bookmarkTooLarge):
      return "The folder authorization bookmark is too large."
    case .service(.invalidBookmark):
      return "The selected folder could not be authorized."
    case .service(.staleAuthorization):
      return "Folder authorization is stale and must be refreshed."
    case .service(.securityScopeUnavailable):
      return "Security-scoped access was unavailable in this runtime."
    case .service(.rootNotFound):
      return "The authorized folder was not found."
    case .service(.rootInactive):
      return "The authorized folder is inactive."
    case .service(.serviceUnavailable), .timedOut, .interrupted, .invalidated:
      return "The Bridge service is unavailable."
    default:
      return "Authorized folder action failed."
    }
  }
}

public struct HermesBridgeMenuBarEnvironment: Sendable {
  public let serviceManager: any HermesBridgeMenuBarServiceManaging
  public let xpcClient: any HermesBridgeMenuBarXPCClient
  public let requestLister: any HermesBridgeMenuBarRequestListing
  public let doctor: any HermesBridgeMenuBarDoctorRunning
  public let permissions: any HermesBridgeMenuBarPermissionViewing
  public let audit: any HermesBridgeMenuBarAuditViewing

  public init(
    serviceManager: any HermesBridgeMenuBarServiceManaging,
    xpcClient: any HermesBridgeMenuBarXPCClient,
    requestLister: any HermesBridgeMenuBarRequestListing,
    doctor: any HermesBridgeMenuBarDoctorRunning,
    permissions: any HermesBridgeMenuBarPermissionViewing = NoopMenuBarPermissionViewer(),
    audit: any HermesBridgeMenuBarAuditViewing = NoopMenuBarAuditViewer()
  ) {
    self.serviceManager = serviceManager
    self.xpcClient = xpcClient
    self.requestLister = requestLister
    self.doctor = doctor
    self.permissions = permissions
    self.audit = audit
  }

  public static func production() -> HermesBridgeMenuBarEnvironment {
    let layout = HermesBridgeInstallationLayout.production()
    return HermesBridgeMenuBarEnvironment(
      serviceManager: ProductionMenuBarServiceManager(layout: layout),
      xpcClient: ProductionMenuBarXPCClient(layout: layout),
      requestLister: ProductionMenuBarRequestLister(layout: layout),
      doctor: ProductionMenuBarDoctor(layout: layout),
      permissions: ProductionMenuBarPermissionViewer(layout: layout),
      audit: ProductionMenuBarAuditViewer(layout: layout)
    )
  }
}

public actor HermesBridgeMenuBarViewModel {
  private let environment: HermesBridgeMenuBarEnvironment
  private var refreshTask: Task<Void, Never>?
  public private(set) var state = HermesBridgeMenuBarState()

  public init(environment: HermesBridgeMenuBarEnvironment) {
    self.environment = environment
  }

  public func load() async {
    await refresh()
  }

  public func refresh() async {
    refreshTask?.cancel()
    let task = Task { await self.performRefresh() }
    refreshTask = task
    await task.value
  }

  public func cancelRefresh() {
    refreshTask?.cancel()
    refreshTask = nil
  }

  public func startService() async -> HermesBridgeMenuBarActionResult {
    let result = await environment.serviceManager.start()
    await refresh()
    state.lastActionMessage = result.safeMessage
    return result
  }

  public func restartService() async -> HermesBridgeMenuBarActionResult {
    let result = await environment.serviceManager.restart()
    await refresh()
    state.lastActionMessage = result.safeMessage
    return result
  }

  public func runDoctor() async -> HermesBridgeMenuBarActionResult {
    let result = await environment.doctor.runDoctor()
    state.lastActionMessage = result.safeMessage
    return result
  }

  public func viewPermissions() async -> [HermesMenuBarPermissionCheckViewState] {
    let checks = await environment.permissions.viewPermissions()
    state.permissionChecks = checks
    return checks
  }

  public func openSettings(
    remediationCode: HermesPermissionRemediationCode
  ) async -> HermesBridgeMenuBarActionResult {
    let result = await environment.permissions.openSettings(remediationCode: remediationCode)
    state.lastActionMessage = result.safeMessage
    return result
  }

  public func latestAuditEvents() async -> [HermesMenuBarAuditEventViewState] {
    do {
      let events = try await environment.audit.recentAuditEvents()
      state.recentAuditEvents = events
      state.auditIntegrity = try? await environment.audit.integrityStatus()
      return events
    } catch {
      state.lastActionMessage = "audit unavailable"
      return []
    }
  }

  public func exportAudit(to outputDirectory: URL) async -> HermesBridgeMenuBarActionResult {
    let result = await environment.audit.exportAudit(to: outputDirectory)
    state.lastActionMessage = result.safeMessage
    return result
  }

  private func performRefresh() async {
    if Task.isCancelled { return }
    let serviceStatus = await environment.serviceManager.status()
    var next = HermesBridgeMenuBarState(
      serviceStatus: menuStatus(for: serviceStatus),
      installed: serviceStatus != .notInstalled,
      running: [.starting, .runningHealthy, .runningUnhealthy].contains(serviceStatus),
      healthy: serviceStatus == .runningHealthy
    )
    guard next.running else {
      state = next
      return
    }
    do {
      let version = try await environment.xpcClient.protocolVersion()
      let capabilities = try await environment.xpcClient.capabilities()
      let compatible = version.version.major == HermesBridgeProtocolVersion.current.major
      let bindings =
        capabilities.capabilities.contains(.bindingDiscovery)
        ? (try? await environment.xpcClient.listEnabledBindings().bindings) ?? [] : []
      let requests = (try? await environment.requestLister.recentRequests()) ?? []
      next.protocolCompatible = compatible
      next.serviceStatus = compatible ? next.serviceStatus : .protocolIncompatible
      next.protocolVersion = version.version.description
      next.capabilities = capabilities.capabilities.map(\.rawValue).sorted()
      next.enabledBindingCount = bindings.count
      next.recentRequests = Array(requests.prefix(8))
      state = next
    } catch {
      next.serviceStatus = .unavailable
      state = next
    }
  }

  private func menuStatus(for status: HermesBridgeServiceStatus) -> HermesBridgeMenuBarServiceStatus
  {
    switch status {
    case .notInstalled:
      return .unavailable
    case .installedStopped, .rollbackAvailable, .upgradePending, .invalidInstallation:
      return .installedStopped
    case .starting:
      return .loading
    case .runningHealthy:
      return .runningHealthy
    case .runningUnhealthy:
      return .runningUnhealthy
    }
  }
}

public final class ProductionMenuBarServiceManager: HermesBridgeMenuBarServiceManaging,
  @unchecked Sendable
{
  private let manager: HermesBridgeServiceManager

  public init(layout: HermesBridgeInstallationLayout) {
    self.manager = HermesBridgeServiceManager(layout: layout)
  }

  public func status() async -> HermesBridgeServiceStatus {
    await manager.status()
  }

  public func start() async -> HermesBridgeMenuBarActionResult {
    do {
      try manager.bootstrap()
      return HermesBridgeMenuBarActionResult(succeeded: true, safeMessage: "start requested")
    } catch {
      return HermesBridgeMenuBarActionResult(succeeded: false, safeMessage: "start failed")
    }
  }

  public func restart() async -> HermesBridgeMenuBarActionResult {
    do {
      let health = try await manager.restart()
      return HermesBridgeMenuBarActionResult(
        succeeded: health.isHealthy,
        safeMessage: health.isHealthy ? "restart completed" : "restart unhealthy"
      )
    } catch {
      return HermesBridgeMenuBarActionResult(succeeded: false, safeMessage: "restart failed")
    }
  }
}

public actor ProductionMenuBarXPCClient: HermesBridgeMenuBarXPCClient {
  private let client: HermesBridgeXPCClient

  public init(layout: HermesBridgeInstallationLayout, timeout: TimeInterval = 5) {
    let name = try! HermesBridgeMachServiceName(layout.machService)
    self.client = HermesBridgeXPCClient(machServiceName: name, timeout: timeout)
  }

  public func protocolVersion() async throws -> HermesBridgeProtocolVersionPayload {
    try await client.protocolVersion()
  }

  public func capabilities() async throws -> HermesBridgeCapabilitiesPayload {
    try await client.capabilities()
  }

  public func listEnabledBindings() async throws -> HermesBridgeBindingListPayload {
    try await client.listEnabledBindings()
  }

  public func close() async {
    await client.close()
  }
}

public actor ProductionAuthorizedRootAppClient: HermesAuthorizedRootAppClient {
  private let client: HermesBridgeXPCClient

  public init(layout: HermesBridgeInstallationLayout, timeout: TimeInterval = 5) {
    let name = try! HermesBridgeMachServiceName(layout.machService)
    self.client = HermesBridgeXPCClient(machServiceName: name, timeout: timeout)
  }

  public func listRoots() async throws -> HermesBridgeAuthorizedRootListPayload {
    try await client.listAuthorizedRoots()
  }

  public func registerBookmark(displayName: String, bookmarkData: Data) async throws
    -> HermesBridgeAuthorizedRootPayload
  {
    try await client.registerAuthorizedRoot(displayName: displayName, bookmarkData: bookmarkData)
  }

  public func refreshBookmark(rootID: String, bookmarkData: Data, expectedRevision: Int?)
    async throws
    -> HermesBridgeAuthorizedRootPayload
  {
    try await client.refreshAuthorizedRoot(
      rootID: try Self.parseRootID(rootID),
      bookmarkData: bookmarkData,
      expectedRevision: expectedRevision
    )
  }

  public func deactivate(rootID: String, expectedRevision: Int?) async throws
    -> HermesBridgeAuthorizedRootPayload
  {
    try await client.deactivateAuthorizedRoot(
      rootID: try Self.parseRootID(rootID),
      expectedRevision: expectedRevision
    )
  }

  public func reactivate(rootID: String, bookmarkData: Data, expectedRevision: Int?) async throws
    -> HermesBridgeAuthorizedRootPayload
  {
    try await client.reactivateAuthorizedRoot(
      rootID: try Self.parseRootID(rootID),
      bookmarkData: bookmarkData,
      expectedRevision: expectedRevision
    )
  }

  public func remove(rootID: String, expectedRevision: Int?) async throws
    -> HermesBridgeAuthorizedRootPayload
  {
    try await client.removeAuthorizedRoot(
      rootID: try Self.parseRootID(rootID),
      expectedRevision: expectedRevision
    )
  }

  public func rootStatus(rootID: String) async throws -> HermesBridgeAuthorizedRootStatusPayload {
    try await client.authorizedRootStatus(rootID: try Self.parseRootID(rootID))
  }

  public func monitorStatus() async throws -> HermesBridgeFileEventMonitorStatusPayload {
    try await client.fileEventMonitorStatus()
  }

  private static func parseRootID(_ value: String) throws -> HermesAuthorizedRootID {
    do {
      return try HermesAuthorizedRootID(rawValue: value)
    } catch {
      throw HermesBridgeXPCClientError.service(.rootNotFound)
    }
  }
}

public struct ProductionMenuBarRequestLister: HermesBridgeMenuBarRequestListing {
  private let lister: HermesBridgeRequestListing

  public init(layout: HermesBridgeInstallationLayout) {
    self.lister = ProductionRequestLister(layout: layout)
  }

  public func recentRequests() async throws -> [HermesBridgeMenuBarRequestSummary] {
    try await lister.listRequests().prefix(8).map(HermesBridgeMenuBarRequestSummary.init(summary:))
  }
}

public struct ProductionMenuBarDoctor: HermesBridgeMenuBarDoctorRunning {
  private let layout: HermesBridgeInstallationLayout
  private let doctor = ProductionDoctorChecker()

  public init(layout: HermesBridgeInstallationLayout) {
    self.layout = layout
  }

  public func runDoctor() async -> HermesBridgeMenuBarActionResult {
    let report = await doctor.report(layout: layout, timeout: 5)
    return HermesBridgeMenuBarActionResult(
      succeeded: report.overallStatus != .fail,
      safeMessage: "doctor \(report.overallStatus.rawValue)"
    )
  }
}

public struct NoopMenuBarPermissionViewer: HermesBridgeMenuBarPermissionViewing {
  public init() {}

  public func viewPermissions() async -> [HermesMenuBarPermissionCheckViewState] {
    []
  }

  public func openSettings(remediationCode _: HermesPermissionRemediationCode) async
    -> HermesBridgeMenuBarActionResult
  {
    HermesBridgeMenuBarActionResult(succeeded: false, safeMessage: "settings unavailable")
  }
}

public struct ProductionMenuBarPermissionViewer: HermesBridgeMenuBarPermissionViewing {
  private let layout: HermesBridgeInstallationLayout
  private let doctor = ProductionDoctorChecker()

  public init(layout: HermesBridgeInstallationLayout) {
    self.layout = layout
  }

  public func viewPermissions() async -> [HermesMenuBarPermissionCheckViewState] {
    let report = await doctor.report(layout: layout, timeout: 5)
    return report.permissions.checks.map(HermesMenuBarPermissionCheckViewState.init(check:))
  }

  @MainActor
  public func openSettings(remediationCode: HermesPermissionRemediationCode) async
    -> HermesBridgeMenuBarActionResult
  {
    guard let url = HermesSystemSettingsRemediationURL.url(for: remediationCode) else {
      return HermesBridgeMenuBarActionResult(
        succeeded: false,
        safeMessage: "settings pane unavailable"
      )
    }
    let opened = NSWorkspace.shared.open(url)
    return HermesBridgeMenuBarActionResult(
      succeeded: opened,
      safeMessage: opened ? "settings opened" : "settings unavailable"
    )
  }
}

public struct NoopMenuBarAuditViewer: HermesBridgeMenuBarAuditViewing {
  public init() {}

  public func recentAuditEvents() async throws -> [HermesMenuBarAuditEventViewState] {
    []
  }

  public func integrityStatus() async throws -> HermesMenuBarAuditIntegrityViewState {
    HermesMenuBarAuditIntegrityViewState(
      report: HermesAuditVerificationReport(
        state: .verifiedUnsigned,
        verifiedSegmentCount: 0,
        verifiedEventCount: 0,
        issueCodes: []
      ))
  }

  public func exportAudit(to _: URL) async -> HermesBridgeMenuBarActionResult {
    HermesBridgeMenuBarActionResult(succeeded: false, safeMessage: "audit export unavailable")
  }
}

public struct ProductionMenuBarAuditViewer: HermesBridgeMenuBarAuditViewing {
  private let layout: HermesBridgeInstallationLayout

  public init(layout: HermesBridgeInstallationLayout) {
    self.layout = layout
  }

  public func recentAuditEvents() async throws -> [HermesMenuBarAuditEventViewState] {
    let store = try auditStore()
    let events = try await store.query(try HermesAuditQuery(limit: 20))
    return events.map(HermesMenuBarAuditEventViewState.init(event:))
  }

  public func integrityStatus() async throws -> HermesMenuBarAuditIntegrityViewState {
    let auditRoot = layout.logsRoot.appendingPathComponent("Audit", isDirectory: true)
    let anchors = (try? HermesAuditPublicTrustAnchorStore(root: auditRoot).load()) ?? []
    let report = try HermesAuditIntegrityVerifier(
      root: auditRoot,
      trustAnchors: anchors
    ).verify()
    return HermesMenuBarAuditIntegrityViewState(
      report: report,
      signingStatus: HermesAuditPublicTrustAnchorStore(root: auditRoot).status(),
      operationalStatus: HermesAuditKeychainSetupCoordinator(auditRoot: auditRoot).status()
    )
  }

  public func exportAudit(to outputDirectory: URL) async -> HermesBridgeMenuBarActionResult {
    do {
      let store = try auditStore()
      let manifest = try await HermesAuditExporter(store: store).export(
        HermesAuditExportRequest(
          query: try HermesAuditQuery(limit: 500),
          outputDirectory: outputDirectory,
          format: .jsonl
        ))
      return HermesBridgeMenuBarActionResult(
        succeeded: true,
        safeMessage: "audit exported \(manifest.eventCount)"
      )
    } catch {
      return HermesBridgeMenuBarActionResult(
        succeeded: false,
        safeMessage: "audit export failed"
      )
    }
  }

  private func auditStore() throws -> FileBackedHermesAuditStore {
    let auditRoot = layout.logsRoot.appendingPathComponent("Audit", isDirectory: true)
    return try FileBackedHermesAuditStore(
      configuration: HermesAuditStoreConfiguration(
        root: auditRoot
      ),
      signingProvider: Self.signingProvider(auditRoot: auditRoot)
    )
  }

  private static func signingProvider(auditRoot: URL) -> any HermesAuditManifestSigningProvider {
    guard let active = try? HermesAuditPublicTrustAnchorStore(root: auditRoot).activeAnchor(),
      let signer = try? HermesAuditSigningKeyManager().lookup(
        signerID: active.signerID,
        keyGenerationID: active.keyGenerationID
      )
    else { return HermesUnsignedAuditManifestSigningProvider() }
    return signer
  }
}
