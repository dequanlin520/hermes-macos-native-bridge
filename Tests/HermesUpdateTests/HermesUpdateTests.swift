import Foundation
@testable import HermesBridgeApp
import HermesBridgeXPC
import HermesRuntimeFoundation
@testable import HermesUpdate
import XCTest

final class HermesUpdateTests: XCTestCase {
  func testStateMachineUpToDateResult() async {
    let provider = RecordingUpdateProvider()
    provider.availableRelease = nil
    let coordinator = HermesUpdateCoordinator(provider: provider)

    let snapshot = await coordinator.checkForUpdate()

    XCTAssertEqual(snapshot.state, .upToDate)
  }

  func testUpdateAvailableAndValidationRequireConfirmation() async {
    let provider = RecordingUpdateProvider()
    let coordinator = HermesUpdateCoordinator(provider: provider)

    let checked = await coordinator.checkForUpdate()
    let validated = await coordinator.validateAvailableUpdate()

    XCTAssertEqual(checked.state, .updateAvailable)
    XCTAssertEqual(validated.state, .awaitingConfirmation)
    XCTAssertEqual(provider.activateCount, 0)
    XCTAssertEqual(validated.confirmation?.operation, .activateUpdate)
  }

  func testVersionOrderingRejectsDowngradeAndSameVersion() async throws {
    let current = HermesUpdateCurrentVersionInfo(appVersion: "1.0.0", serviceVersion: "2.0.0")
    XCTAssertThrowsError(
      try HermesUpdatePolicy.validate(
        release: HermesUpdateReleaseMetadata(releaseID: "same", version: "2.0.0"),
        current: current
      )
    )
    XCTAssertThrowsError(
      try HermesUpdatePolicy.validate(
        release: HermesUpdateReleaseMetadata(releaseID: "old", version: "1.9.9"),
        current: current
      )
    )
  }

  func testInvalidChecksumIncompatibleXPCSigningAndAcceptancePayloadRejected() {
    let current = HermesUpdateCurrentVersionInfo(appVersion: "1.0.0", serviceVersion: "1.0.0")
    let invalids = [
      HermesUpdateReleaseMetadata(releaseID: "checksum", version: "1.0.1", checksum: .invalid),
      HermesUpdateReleaseMetadata(releaseID: "xpc", version: "1.0.1", compatibleXPCMajor: 2),
      HermesUpdateReleaseMetadata(releaseID: "signing", version: "1.0.1", signing: .invalid),
      HermesUpdateReleaseMetadata(releaseID: "acceptance", version: "1.0.1", containsAcceptanceContent: true),
      HermesUpdateReleaseMetadata(releaseID: "test", version: "1.0.1", isProductionPayload: false),
    ]

    for release in invalids {
      XCTAssertThrowsError(try HermesUpdatePolicy.validate(release: release, current: current))
    }
  }

  func testActivationForwardedExactlyOnceAndReconnects() async {
    let provider = RecordingUpdateProvider()
    let coordinator = HermesUpdateCoordinator(provider: provider)
    _ = await coordinator.checkForUpdate()
    _ = await coordinator.validateAvailableUpdate()

    let completed = await coordinator.activateConfirmed()
    _ = await coordinator.activateConfirmed()

    XCTAssertEqual(completed.state, .completed)
    XCTAssertEqual(provider.activateCount, 1)
    XCTAssertEqual(provider.reconnectCount, 1)
    XCTAssertEqual(completed.current.serviceVersion, "1.1.0")
  }

  func testFailedActivationPreservesCurrentVersionAndCleansPartialStage() async {
    let provider = RecordingUpdateProvider()
    provider.activateError = HermesUpdateValidationError(.activationFailed, "activation_failed")
    let coordinator = HermesUpdateCoordinator(provider: provider)
    _ = await coordinator.checkForUpdate()
    _ = await coordinator.validateAvailableUpdate()

    let failed = await coordinator.activateConfirmed()

    XCTAssertEqual(failed.state, .failed)
    XCTAssertEqual(failed.current.serviceVersion, "1.0.0")
    XCTAssertEqual(provider.partialStageCleaned, true)
  }

  func testRollbackAvailabilityConfirmationForwardingAndReconnect() async {
    let provider = RecordingUpdateProvider()
    provider.current = HermesUpdateCurrentVersionInfo(
      appVersion: "1.0.0",
      serviceVersion: "1.1.0",
      rollbackAvailable: true
    )
    let coordinator = HermesUpdateCoordinator(provider: provider)

    let available = await coordinator.prepareRollback()
    let completed = await coordinator.rollbackConfirmed()
    _ = await coordinator.rollbackConfirmed()

    XCTAssertEqual(available.state, .rollbackAvailable)
    XCTAssertEqual(available.confirmation?.operation, .rollback)
    XCTAssertEqual(completed.state, .completed)
    XCTAssertEqual(completed.current.serviceVersion, "1.0.0")
    XCTAssertEqual(provider.rollbackCount, 1)
    XCTAssertEqual(provider.reconnectCount, 1)
  }

  @MainActor
  func testShowUpgradeRequiredRoutingAndOneLogicalUpdateWindow() {
    let factory = RecordingWindowFactory()
    let graph = HermesAppClientGraph(
      runtimeClient: AppRuntimeClientStub(),
      updateCoordinator: HermesUpdateCoordinator(provider: RecordingUpdateProvider())
    )
    let root = HermesAppCompositionRoot(clientGraph: graph, windowFactory: factory)

    root.router.openUpdateCenter()
    root.router.openUpdateCenter()

    XCTAssertEqual(factory.createdIdentifiers, [.update])
    XCTAssertEqual(factory.window(for: .update)?.focusCount, 1)
    XCTAssertEqual(root.windowCoordinator.windowCount(for: .update), 1)
  }

  @MainActor
  func testClosingUpdateWindowDoesNotCancelServiceTransaction() async {
    let provider = RecordingUpdateProvider()
    let coordinator = HermesUpdateCoordinator(provider: provider)
    let graph = HermesAppClientGraph(
      runtimeClient: AppRuntimeClientStub(),
      updateCoordinator: coordinator
    )
    let windowCoordinator = HermesWindowCoordinator(clientGraph: graph, windowFactory: RecordingWindowFactory())

    windowCoordinator.open(.update)
    windowCoordinator.close(.update)
    let snapshot = await coordinator.windowClosed()

    XCTAssertEqual(snapshot.state, .idle)
    XCTAssertEqual(provider.activateCount, 0)
  }

  func testSanitizedFailuresAndAuditEvents() async throws {
    let store = RecordingAuditStore()
    let audit = HermesUpdateAuditStoreRecorder(store: store)

    await audit.record(
      kind: .activationFailed,
      outcome: .failed,
      reasonCode: "activation_failed",
      metadata: ["targetVersion": "1.1.0", "unsafe_path": "/Users/example/private.pkg"]
    )

    XCTAssertEqual(store.events.count, 1)
    let encoded = String(data: try JSONEncoder().encode(store.events[0]), encoding: .utf8)!
    XCTAssertFalse(encoded.contains("/Users/"))
    XCTAssertFalse(encoded.localizedCaseInsensitiveContains("token"))
    XCTAssertFalse(encoded.localizedCaseInsensitiveContains("pid"))
  }

  func testArbitraryURLPathCommandCannotBeRepresentedAndAppOwnsNoInstallerRuntimeInternals() throws {
    let models = try String(contentsOfFile: "Sources/HermesUpdate/HermesUpdateModels.swift")
    let app = try String(contentsOfFile: "Sources/HermesBridgeApp/HermesAppCompositionRoot.swift")

    XCTAssertFalse(models.contains("URL"))
    XCTAssertFalse(models.localizedCaseInsensitiveContains("shell"))
    XCTAssertFalse(models.localizedCaseInsensitiveContains("command"))
    XCTAssertFalse(models.contains("packagePath"))
    XCTAssertFalse(app.contains("HermesBridgeServiceManager("))
    XCTAssertFalse(app.contains("HermesRuntimeSessionManager("))
    XCTAssertFalse(app.contains("HermesRuntimeEventBus("))
  }

  func testXPCUpdateEnvelopeRejectsMixedPayloads() async throws {
    let handler = RecordingXPCUpdateHandler()
    let dispatcher = HermesBridgeXPCRequestDispatcher(handler: handler)
    let request = HermesBridgeRequestEnvelope(
      correlationID: try HermesBridgeCorrelationID(rawValue: "m13-003"),
      operation: .activateUpdate,
      runtimeCommand: HermesBridgeRuntimeCommandPayload(kind: .listSessions),
      activateUpdate: HermesBridgeUpdateConfirmationPayload(
        releaseID: "release-b",
        operation: .activateUpdate
      )
    )
    let data = try JSONEncoder().encode(request)

    let response = try JSONDecoder().decode(
      HermesBridgeResponseEnvelope.self,
      from: await dispatcher.handle(data)
    )

    guard case .failure(let error) = response.result else {
      return XCTFail("Expected malformed payload failure")
    }
    XCTAssertEqual(error.code, .malformedPayload)
  }
}

private final class RecordingUpdateProvider: HermesUpdateProviding, @unchecked Sendable {
  var current = HermesUpdateCurrentVersionInfo(
    appVersion: "1.0.0",
    serviceVersion: "1.0.0",
    rollbackAvailable: false
  )
  var availableRelease: HermesUpdateReleaseMetadata? = HermesUpdateReleaseMetadata(
    releaseID: "release-b",
    version: "1.1.0"
  )
  var activateCount = 0
  var rollbackCount = 0
  var reconnectCount = 0
  var partialStageCleaned = true
  var activateError: Error?

  func currentVersionInfo() async throws -> HermesUpdateCurrentVersionInfo { current }
  func checkForUpdate() async throws -> HermesUpdateReleaseMetadata? { availableRelease }
  func validate(release _: HermesUpdateReleaseMetadata) async throws -> HermesUpdateValidationReport {
    HermesUpdateValidationReport()
  }
  func activate(releaseID _: String) async throws -> HermesUpdateActivationResult {
    activateCount += 1
    if let activateError { throw activateError }
    current = HermesUpdateCurrentVersionInfo(
      appVersion: "1.0.0",
      serviceVersion: "1.1.0",
      rollbackAvailable: true
    )
    return HermesUpdateActivationResult(
      activatedVersion: "1.1.0",
      rollbackAvailable: true,
      partialStageCleaned: partialStageCleaned
    )
  }
  func rollback() async throws -> HermesUpdateRollbackResult {
    rollbackCount += 1
    current = HermesUpdateCurrentVersionInfo(
      appVersion: "1.0.0",
      serviceVersion: "1.0.0",
      rollbackAvailable: true
    )
    return HermesUpdateRollbackResult(activatedVersion: "1.0.0", rollbackAvailable: true)
  }
  func reconnectAndVerify() async throws -> Bool {
    reconnectCount += 1
    return true
  }
}

private final class RecordingAuditStore: HermesAuditStore, @unchecked Sendable {
  var events: [HermesAuditEvent] = []
  func append(_ event: HermesAuditEvent) async throws { events.append(event) }
  func query(_: HermesAuditQuery) async throws -> [HermesAuditEvent] { events }
}

private final class RecordingWindowFactory: HermesNativeUIWindowFactory, @unchecked Sendable {
  @MainActor private var windows: [HermesNativeUIWindowIdentifier: RecordingWindow] = [:]
  @MainActor private(set) var createdIdentifiers: [HermesNativeUIWindowIdentifier] = []

  @MainActor
  func makeWindow(
    for identifier: HermesNativeUIWindowIdentifier,
    clientGraph _: HermesAppClientGraph
  ) -> HermesNativeUIWindowControlling {
    let window = RecordingWindow(identifier: identifier)
    windows[identifier] = window
    createdIdentifiers.append(identifier)
    return window
  }

  @MainActor
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
  private(set) var cleanupCount = 0

  init(identifier: HermesNativeUIWindowIdentifier) {
    self.identifier = identifier
  }

  func show() { isOpen = true; showCount += 1 }
  func focus() { focusCount += 1 }
  func close() { isOpen = false; closeCount += 1 }
  func cleanup() { isOpen = false; cleanupCount += 1 }
}

private final class AppRuntimeClientStub: HermesAppRuntimeClienting, @unchecked Sendable {
  func execute(_ command: HermesRuntimeCommand) async throws -> HermesRuntimeCommandResult {
    switch command {
    case .listSessions:
      return .sessionList([])
    default:
      return .sessionStatus(
        HermesRuntimeCommandSessionStatus(
          sessionID: UUID(),
          currentStatus: .created,
          backendVersion: "1.0.0",
          startTime: nil,
          capabilities: nil,
          lastErrorMessage: nil,
          shutdownReason: nil
        ))
    }
  }
  func subscribeRuntimeEvents() async throws -> HermesRuntimeCommandEventSubscription {
    HermesRuntimeCommandEventSubscription(id: UUID(), events: AsyncStream { $0.finish() })
  }
  func invalidate() async {}
}

private final class RecordingXPCUpdateHandler: HermesBridgeRequestHandling, @unchecked Sendable {
  func submit(bindingID _: HermesRequestBindingID, prompt _: String) async throws -> HermesRequestID {
    throw HermesBridgeXPCError.unsupportedOperation
  }
  func status(requestID _: HermesRequestID) async throws -> HermesRequestRecord {
    throw HermesBridgeXPCError.unsupportedOperation
  }
  func cancel(requestID _: HermesRequestID) async throws -> HermesRequestRecord {
    throw HermesBridgeXPCError.unsupportedOperation
  }
  func respondToApproval(
    requestID _: HermesRequestID,
    decision _: HermesApprovalResponseDecision
  ) async throws -> HermesRequestRecord {
    throw HermesBridgeXPCError.unsupportedOperation
  }
  func updateStatus() async throws -> HermesBridgeUpdateStatusPayload {
    HermesBridgeUpdateStatusPayload(currentServiceVersion: "1.0.0", rollbackAvailable: false)
  }
  func checkForUpdate() async throws -> HermesBridgeUpdateStatusPayload {
    HermesBridgeUpdateStatusPayload(currentServiceVersion: "1.0.0", rollbackAvailable: false)
  }
  func validateUpdate(releaseID _: String) async throws -> HermesBridgeUpdateValidationReportPayload {
    HermesBridgeUpdateValidationReportPayload()
  }
  func activateUpdate(confirmation _: HermesBridgeUpdateConfirmationPayload) async throws
    -> HermesBridgeUpdateActivationResultPayload
  {
    HermesBridgeUpdateActivationResultPayload(activatedVersion: "1.1.0")
  }
  func rollbackUpdate(confirmation _: HermesBridgeUpdateConfirmationPayload) async throws
    -> HermesBridgeUpdateActivationResultPayload
  {
    HermesBridgeUpdateActivationResultPayload(activatedVersion: "1.0.0")
  }
}
