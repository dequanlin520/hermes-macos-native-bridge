import Foundation
import HermesRuntimeFoundation
import XCTest

@testable import HermesAppIntents
@testable import HermesBridgeXPC

final class HermesAppIntentsTests: XCTestCase {
  override func tearDown() async throws {
    await HermesAppIntentDependencyProvider.shared.resetTestingOverrides()
  }

  func testBindingEntityIdentifierAndDisplay() throws {
    let entity = try HermesAppIntentBindingEntity(
      id: try bindingID().rawValue,
      displayName: "Daily Status",
      safeDescription: "Allowed summary request"
    )

    XCTAssertEqual(entity.id, "binding:v1:daily.status")
    XCTAssertTrue(entity.description.contains("Daily Status"))
    XCTAssertFalse(entity.description.contains("executable"))
  }

  func testDisabledBindingOmitted() async throws {
    let enabled = HermesAppIntentBindingDefinition(
      id: try bindingID(),
      enabled: true,
      displayName: "Enabled",
      safeDescription: "Enabled binding"
    )
    let disabled = HermesAppIntentBindingDefinition(
      id: try HermesRequestBindingID(rawValue: "binding:v1:disabled.binding"),
      enabled: false,
      displayName: "Disabled",
      safeDescription: "Disabled binding"
    )
    await installFake(bindings: [enabled, disabled])

    let suggestions = try await HermesAppIntentBindingQuery().suggestedEntities()

    XCTAssertEqual(suggestions.map(\.id), [enabled.id.rawValue])
  }

  func testRequestEntityRedaction() throws {
    let entity = try HermesAppIntentRequestEntity(
      id: requestID().rawValue,
      lifecycleState: "running",
      cancellationRequested: false,
      resultAvailable: true,
      failureCode: "safe_code"
    )

    XCTAssertFalse(entity.description.contains("prompt"))
    XCTAssertFalse(entity.description.contains("token"))
    XCTAssertFalse(entity.description.contains("result body"))
    XCTAssertFalse(entity.description.contains("/Users/"))
  }

  func testSubmitValidationRejectsEmptyPrompt() async throws {
    let fake = FakeAppIntentClient()
    let operations = HermesAppIntentOperations(client: fake)

    await assertThrowsAsyncError(
      try await operations.submit(bindingID: bindingID().rawValue, prompt: "")
    ) {
      XCTAssertEqual($0 as? HermesAppIntentError, .oversizedPrompt)
    }
  }

  func testPromptSizeRejection() async throws {
    let fake = FakeAppIntentClient()
    let operations = HermesAppIntentOperations(client: fake)
    let prompt = String(repeating: "x", count: HermesAppIntentOperations.maximumPromptBytes + 1)

    await assertThrowsAsyncError(
      try await operations.submit(bindingID: bindingID().rawValue, prompt: prompt)
    ) {
      XCTAssertEqual($0 as? HermesAppIntentError, .oversizedPrompt)
    }
  }

  func testSubmitDispatchesExactlyOnce() async throws {
    let fake = FakeAppIntentClient()
    let operations = HermesAppIntentOperations(client: fake)

    _ = try await operations.submit(bindingID: bindingID().rawValue, prompt: "hello")

    XCTAssertEqual(fake.submitCount, 1)
    XCTAssertEqual(fake.submittedPrompts, ["hello"])
  }

  func testSubmitReturnsRequestIDWithoutCompletionWait() async throws {
    let fake = FakeAppIntentClient()
    fake.blockCompletion = true
    let operations = HermesAppIntentOperations(client: fake)

    let entity = try await operations.submit(bindingID: bindingID().rawValue, prompt: "hello")

    XCTAssertEqual(entity.id, requestID().rawValue)
    XCTAssertEqual(entity.lifecycleState, "accepted")
    XCTAssertFalse(fake.completionWaited)
  }

  func testSubmitErrorMapping() async throws {
    let fake = FakeAppIntentClient()
    fake.submitError = HermesAppIntentError.invalidBinding
    let operations = HermesAppIntentOperations(client: fake)

    await assertThrowsAsyncError(
      try await operations.submit(bindingID: bindingID().rawValue, prompt: "hello")
    ) {
      XCTAssertEqual($0 as? HermesAppIntentError, .invalidBinding)
    }
  }

  func testStatusDispatch() async throws {
    let fake = FakeAppIntentClient()
    let operations = HermesAppIntentOperations(client: fake)

    let entity = try await operations.status(requestID: requestID().rawValue)

    XCTAssertEqual(fake.statusCount, 1)
    XCTAssertEqual(entity.lifecycleState, "running")
  }

  func testStatusSafeOutput() async throws {
    let fake = FakeAppIntentClient()
    fake.statusValue = HermesAppIntentRequestStatus(
      requestID: requestID().rawValue,
      lifecycleState: .failed,
      cancellationRequested: false,
      resultAvailable: true,
      failureCode: "safe_failure",
      failureRetryable: true
    )
    let operations = HermesAppIntentOperations(client: fake)

    let entity = try await operations.status(requestID: requestID().rawValue)

    XCTAssertEqual(entity.failureCode, "safe_failure")
    XCTAssertFalse(String(describing: entity).contains("backend"))
  }

  func testCancelDispatch() async throws {
    let fake = FakeAppIntentClient()
    let operations = HermesAppIntentOperations(client: fake)

    let entity = try await operations.cancel(requestID: requestID().rawValue)

    XCTAssertEqual(fake.cancelCount, 1)
    XCTAssertEqual(entity.lifecycleState, "cancelled")
  }

  func testRepeatedCancelHandling() async throws {
    let fake = FakeAppIntentClient()
    let operations = HermesAppIntentOperations(client: fake)

    let first = try await operations.cancel(requestID: requestID().rawValue)
    let second = try await operations.cancel(requestID: requestID().rawValue)

    XCTAssertEqual(first.lifecycleState, "cancelled")
    XCTAssertEqual(second.lifecycleState, "cancelled")
    XCTAssertEqual(fake.cancelCount, 2)
  }

  func testApprovalAllowDecision() async throws {
    let fake = FakeAppIntentClient()
    let operations = HermesAppIntentOperations(client: fake)

    _ = try await operations.respondToApproval(
      requestID: requestID().rawValue,
      decision: .allow
    )

    XCTAssertEqual(fake.approvalDecisions, [.allow])
  }

  func testApprovalDenyDecision() async throws {
    let fake = FakeAppIntentClient()
    let operations = HermesAppIntentOperations(client: fake)

    _ = try await operations.respondToApproval(
      requestID: requestID().rawValue,
      decision: .deny
    )

    XCTAssertEqual(fake.approvalDecisions, [.deny])
  }

  func testInvalidApprovalDecisionCannotBeConstructed() {
    XCTAssertNil(HermesAppIntentApprovalDecision(rawValue: "maybe"))
  }

  func testHealthAvailable() async throws {
    let fake = FakeAppIntentClient()
    let health = try await HermesAppIntentOperations(client: fake).health()

    XCTAssertTrue(health.available)
    XCTAssertTrue(health.compatible)
    XCTAssertEqual(health.protocolVersion, "1.0")
  }

  func testHealthUnavailable() async throws {
    let fake = FakeAppIntentClient()
    fake.healthError = HermesAppIntentError.serviceUnavailable

    await assertThrowsAsyncError(try await HermesAppIntentOperations(client: fake).health()) {
      XCTAssertEqual($0 as? HermesAppIntentError, .serviceUnavailable)
    }
  }

  func testProtocolIncompatibleMapping() {
    XCTAssertEqual(
      HermesAppIntentXPCClient.map(
        HermesBridgeXPCClientError.service(.unsupportedProtocolVersion)),
      .protocolIncompatible
    )
  }

  func testServiceUnavailableMapping() {
    XCTAssertEqual(
      HermesAppIntentXPCClient.map(HermesBridgeXPCClientError.interrupted), .serviceUnavailable)
  }

  func testRequestNotFoundMapping() {
    XCTAssertEqual(
      HermesAppIntentXPCClient.map(HermesBridgeXPCClientError.service(.requestNotFound)),
      .requestNotFound
    )
  }

  func testPromptAbsentFromReturnedEntity() throws {
    let entity = HermesAppIntentRequestEntity(requestID: requestID())

    XCTAssertFalse(String(describing: entity).contains("hello private prompt"))
  }

  func testBackendTokenAbsent() throws {
    let entity = HermesAppIntentRequestEntity(requestID: requestID())

    XCTAssertFalse(String(describing: entity).localizedCaseInsensitiveContains("token"))
  }

  func testRawResultBodyAbsent() throws {
    let entity = try HermesAppIntentRequestEntity(
      id: requestID().rawValue,
      lifecycleState: "completed",
      resultAvailable: true
    )

    XCTAssertFalse(String(describing: entity).contains("raw result"))
  }

  func testPrivatePathAbsent() throws {
    let entity = HermesAppIntentRequestEntity(requestID: requestID())

    XCTAssertFalse(String(describing: entity).contains("/Users/"))
  }

  func testAppShortcutDefinitionsCompile() {
    XCTAssertEqual(HermesAppShortcutsProvider.appShortcuts.count, 5)
  }

  func testIntentTitlesAndDescriptionsAreNonempty() {
    XCTAssertFalse(String(describing: SubmitHermesRequestIntent.title).isEmpty)
    XCTAssertFalse(String(describing: CheckHermesRequestStatusIntent.title).isEmpty)
    XCTAssertFalse(String(describing: CancelHermesRequestIntent.title).isEmpty)
    XCTAssertFalse(String(describing: RespondToHermesApprovalIntent.title).isEmpty)
    XCTAssertFalse(String(describing: CheckHermesBridgeHealthIntent.title).isEmpty)
    XCTAssertFalse(String(describing: SubmitHermesRequestIntent.description).isEmpty)
    XCTAssertFalse(String(describing: CheckHermesBridgeHealthIntent.description).isEmpty)
  }

  func testNoRealHermesProcessLaunched() async throws {
    let fake = FakeAppIntentClient()

    _ = try await HermesAppIntentOperations(client: fake).submit(
      bindingID: bindingID().rawValue,
      prompt: "hello"
    )

    XCTAssertFalse(fake.launchedRealHermes)
  }

  func testNoPermanentLaunchAgentModification() async throws {
    let fake = FakeAppIntentClient()

    _ = try await HermesAppIntentOperations(client: fake).health()

    XCTAssertFalse(fake.modifiedLaunchAgent)
  }

  func testFakeXPCRoundTripThroughAdapter() async throws {
    let payload = HermesBridgeRequestStatusPayload(
      record: try requestRecord(state: .running, resultAvailable: false)
    )
    let client = HermesAppIntentXPCClient(
      client: HermesBridgeXPCClient(
        transport: FakeXPCTransport(
          result: .success(.status(payload))
        )
      )
    )

    let status = try await client.status(requestID: requestID())

    XCTAssertEqual(status.lifecycleState, .running)
  }

  func testConcurrentIntentCallsRemainIsolated() async throws {
    let fake = FakeAppIntentClient()
    let operations = HermesAppIntentOperations(client: fake)

    async let first = operations.submit(bindingID: bindingID().rawValue, prompt: "one")
    async let second = operations.submit(bindingID: bindingID().rawValue, prompt: "two")
    let results = try await [first.id, second.id]

    XCTAssertEqual(results.count, 2)
    XCTAssertEqual(fake.submittedPrompts.sorted(), ["one", "two"])
  }

  private func installFake(bindings: [HermesAppIntentBindingDefinition] = []) async {
    await HermesAppIntentDependencyProvider.shared.replaceForTesting(
      clientFactory: FakeClientFactory(client: FakeAppIntentClient()),
      bindingProvider: HermesAppIntentStaticBindingProvider(bindings: bindings)
    )
  }
}

private final class FakeAppIntentClient: @unchecked Sendable, HermesAppIntentClient {
  private let lock = NSLock()
  private var submitCountStorage = 0
  private var statusCountStorage = 0
  private var cancelCountStorage = 0
  private var submittedPromptsStorage: [String] = []
  private var approvalDecisionsStorage: [HermesAppIntentApprovalDecision] = []
  private var submitErrorStorage: Error?
  private var healthErrorStorage: Error?
  private var blockCompletionStorage = false
  private var completionWaitedStorage = false
  private var launchedRealHermesStorage = false
  private var modifiedLaunchAgentStorage = false
  private var statusValueStorage = HermesAppIntentRequestStatus(
    requestID: try! HermesRequestID(
      rawValue: "hrq_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    ).rawValue,
    lifecycleState: .running,
    cancellationRequested: false,
    resultAvailable: false
  )

  var submitCount: Int { lock.withLock { submitCountStorage } }
  var statusCount: Int { lock.withLock { statusCountStorage } }
  var cancelCount: Int { lock.withLock { cancelCountStorage } }
  var submittedPrompts: [String] { lock.withLock { submittedPromptsStorage } }
  var approvalDecisions: [HermesAppIntentApprovalDecision] {
    lock.withLock { approvalDecisionsStorage }
  }
  var completionWaited: Bool { lock.withLock { completionWaitedStorage } }
  var launchedRealHermes: Bool { lock.withLock { launchedRealHermesStorage } }
  var modifiedLaunchAgent: Bool { lock.withLock { modifiedLaunchAgentStorage } }

  var submitError: Error? {
    get { lock.withLock { submitErrorStorage } }
    set { lock.withLock { submitErrorStorage = newValue } }
  }

  var healthError: Error? {
    get { lock.withLock { healthErrorStorage } }
    set { lock.withLock { healthErrorStorage = newValue } }
  }

  var blockCompletion: Bool {
    get { lock.withLock { blockCompletionStorage } }
    set { lock.withLock { blockCompletionStorage = newValue } }
  }

  var statusValue: HermesAppIntentRequestStatus {
    get { lock.withLock { statusValueStorage } }
    set { lock.withLock { statusValueStorage = newValue } }
  }

  func submit(bindingID _: HermesRequestBindingID, prompt: String) async throws -> HermesRequestID {
    let error = lock.withLock {
      submitCountStorage += 1
      submittedPromptsStorage.append(prompt)
      return submitErrorStorage
    }
    if let error {
      throw error
    }
    return try HermesRequestID(rawValue: "hrq_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
  }

  func status(requestID _: HermesRequestID) async throws -> HermesAppIntentRequestStatus {
    lock.withLock {
      statusCountStorage += 1
      return statusValueStorage
    }
  }

  func cancel(requestID: HermesRequestID) async throws -> HermesAppIntentRequestStatus {
    lock.withLock {
      cancelCountStorage += 1
    }
    return HermesAppIntentRequestStatus(
      requestID: requestID.rawValue,
      lifecycleState: .cancelled,
      cancellationRequested: true,
      resultAvailable: false
    )
  }

  func respondToApproval(
    requestID: HermesRequestID,
    decision: HermesAppIntentApprovalDecision
  ) async throws -> HermesAppIntentRequestStatus {
    lock.withLock {
      approvalDecisionsStorage.append(decision)
    }
    return HermesAppIntentRequestStatus(
      requestID: requestID.rawValue,
      lifecycleState: .running,
      cancellationRequested: false,
      resultAvailable: false
    )
  }

  func health() async throws -> HermesAppIntentHealthStatus {
    if let healthError = lock.withLock({ healthErrorStorage }) {
      throw healthError
    }
    return HermesAppIntentHealthStatus(
      available: true,
      compatible: true,
      protocolVersion: "1.0",
      supportedCapabilities: ["protocolVersion", "submitRequest"]
    )
  }
}

private struct FakeClientFactory: HermesAppIntentClientFactory {
  let client: any HermesAppIntentClient

  func makeClient() async throws -> any HermesAppIntentClient {
    client
  }
}

private struct FakeXPCTransport: HermesBridgeXPCTransport {
  let result: HermesBridgeResponseResult

  func send(_ requestData: Data) async throws -> Data {
    let request = try JSONDecoder().decode(HermesBridgeRequestEnvelope.self, from: requestData)
    let response = HermesBridgeResponseEnvelope(
      correlationID: request.correlationID,
      result: result
    )
    return try JSONEncoder().encode(response)
  }

  func close() {}
}

private func bindingID() throws -> HermesRequestBindingID {
  try HermesRequestBindingID(rawValue: "binding:v1:daily.status")
}

private func requestID() -> HermesRequestID {
  try! HermesRequestID(rawValue: "hrq_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
}

private func requestRecord(
  state: HermesRequestLifecycleState,
  resultAvailable: Bool
) throws -> HermesRequestRecord {
  try HermesRequestRecord(
    requestID: requestID(),
    bindingID: bindingID(),
    lifecycleState: state,
    createdAt: Date(),
    updatedAt: Date(),
    result: resultAvailable
      ? HermesRequestResultMetadata(
        availability: .available,
        completedAt: Date(),
        contentClass: .redacted,
        redactedSummary: "available",
        bridgeOwnedResultLocator: "bridge-result:v1:test"
      ) : nil
  )
}

private func assertThrowsAsyncError<T>(
  _ expression: @autoclosure () async throws -> T,
  _ errorHandler: (Error) -> Void = { _ in }
) async {
  do {
    _ = try await expression()
    XCTFail("expected error")
  } catch {
    errorHandler(error)
  }
}
