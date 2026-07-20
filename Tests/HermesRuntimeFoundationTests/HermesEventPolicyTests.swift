import Foundation
import XCTest

@testable import HermesRuntimeFoundation

final class HermesEventPolicyTests: XCTestCase {
  func testPolicyIDValidationSchemaAndCreateUpdateReload() async throws {
    XCTAssertTrue(HermesEventPolicyID.isValid("hepol_network"))
    XCTAssertThrowsError(try HermesEventPolicyID(rawValue: "bad"))
    let root = try temporaryDirectory()
    let store = try FileBackedHermesEventPolicyStore(root: root)
    let policy = try makePolicy(id: "hepol_network")
    let created = try await store.createPolicy(policy)
    XCTAssertEqual(created.revision, 1)
    await XCTAssertThrowsAsync(try await store.createPolicy(policy))
    var updated = created
    updated.enabled = false
    let saved = try await store.updatePolicy(updated, expectedRevision: 1)
    XCTAssertEqual(saved.revision, 2)
    await XCTAssertThrowsAsync(try await store.updatePolicy(saved, expectedRevision: 1))
    let reloaded = try FileBackedHermesEventPolicyStore(root: root)
    let reloadedIDs = try await reloaded.listPolicies().map { $0.id }
    XCTAssertEqual(reloadedIDs, [policy.id])
  }

  func testCorruptAndSymlinkStoreRejected() async throws {
    let root = try temporaryDirectory()
    try Data("{bad".utf8).write(
      to: root.appendingPathComponent(FileBackedHermesEventPolicyStore.storeFileName)
    )
    let store = try FileBackedHermesEventPolicyStore(root: root)
    await XCTAssertThrowsAsync(try await store.listPolicies())

    let parent = try temporaryDirectory()
    let real = parent.appendingPathComponent("real", isDirectory: true)
    let link = parent.appendingPathComponent("link", isDirectory: true)
    try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
    XCTAssertThrowsError(try FileBackedHermesEventPolicyStore(root: link))
  }

  func testConditionCatalogAndAndSemantics() async throws {
    let engine = try await makeEngine(
      policies: [
        makePolicy(
          id: "hepol_app",
          conditions: [
            .eventKindEquals(.applicationLaunched),
            .applicationBundleIdentifierEquals("com.example.Safe"),
          ])
      ])
    let match = await engine.engine.evaluate(
      try event(
        kind: .applicationLaunched,
        application: HermesSafeApplicationIdentity(
          bundleIdentifier: "com.example.Safe",
          localizedName: "Safe"
        )))
    let miss = await engine.engine.evaluate(
      try event(
        kind: .applicationLaunched,
        application: HermesSafeApplicationIdentity(
          bundleIdentifier: "com.example.Other",
          localizedName: "Other"
        )))
    XCTAssertEqual(match.map(\.decision), [.executed])
    XCTAssertEqual(miss.map(\.decision), [.notMatched])
  }

  func testNetworkServiceHealthAndTimeConditions() async throws {
    let policy = try makePolicy(
      id: "hepol_net",
      conditions: [
        .eventKindEquals(.networkAvailable),
        .networkAvailabilityEquals(.available),
        .networkInterfaceTypeEquals(.wifi),
        .expensiveNetworkEquals(false),
        .constrainedNetworkEquals(true),
        .boundedTimeWindow(startHour: 0, endHour: 23),
      ])
    let harness = try await makeEngine(policies: [policy])
    let matched = await harness.engine.evaluate(
      try event(
        kind: .networkAvailable,
        timestamp: Date(timeIntervalSince1970: 36_000),
        networkStatus: .available,
        networkInterface: .wifi,
        networkExpensive: false,
        networkConstrained: true
      ))
    XCTAssertEqual(matched.map(\.decision), [.executed])

    let health = try await makeEngine(
      policies: [
        makePolicy(
          id: "hepol_health",
          conditions: [
            .eventKindEquals(.bridgeServiceDegraded),
            .serviceHealthStateEquals(.degraded),
          ])
      ])
    let healthResult = await health.engine.evaluate(
      try event(kind: .bridgeServiceDegraded, serviceHealth: .degraded))
    XCTAssertEqual(healthResult.map(\.decision), [.executed])
  }

  func testDuplicateSuppressionCooldownAndRateLimits() async throws {
    let clock = TestClock(Date(timeIntervalSince1970: 1))
    let policy = try makePolicy(
      id: "hepol_limits",
      cooldownSeconds: 30,
      maximumExecutionsPerMinute: 1
    )
    let harness = try await makeEngine(policies: [policy], now: { clock.now })
    let firstEvent = try event(kind: .networkAvailable, networkStatus: .available)
    let first = await harness.engine.evaluate(firstEvent).map(\.decision)
    let duplicate = await harness.engine.evaluate(firstEvent).map(\.decision)
    clock.advance(10)
    let cooldown = await harness.engine.evaluate(
      try event(kind: .networkAvailable, networkStatus: .available)
    ).map(\.decision)
    clock.advance(30)
    let limited = await harness.engine.evaluate(
      try event(kind: .networkAvailable, networkStatus: .available)
    ).map(\.decision)
    XCTAssertEqual(first, [.executed])
    XCTAssertEqual(duplicate, [.blockedCooldown])
    XCTAssertEqual(cooldown, [.blockedCooldown])
    XCTAssertEqual(limited, [.blockedRateLimit])
  }

  func testPauseResumeEmergencyStopDryRunAndApprovalGate() async throws {
    let dryRun = try makePolicy(id: "hepol_dry", executionMode: .dryRun)
    let approval = try makePolicy(
      id: "hepol_approval",
      approvalRequirement: .requireUserApproval
    )
    let harness = try await makeEngine(policies: [dryRun, approval])
    let decisions = await harness.engine.evaluate(
      try event(kind: .networkAvailable, networkStatus: .available))
    XCTAssertEqual(Set(decisions.map(\.decision)), [.matchedDryRun, .blockedApprovalRequired])
    let submittedPrompts = await harness.submitter.submittedPrompts
    XCTAssertTrue(submittedPrompts.isEmpty)

    _ = try await harness.engine.pause()
    let paused = await harness.engine.evaluate(
      try event(kind: .networkAvailable, networkStatus: .available))
    XCTAssertTrue(paused.allSatisfy { $0.decision == .blockedGlobalPause })
    _ = try await harness.engine.resume()
    await harness.engine.emergencyStop()
    let stopped = await harness.engine.evaluate(
      try event(kind: .networkAvailable, networkStatus: .available))
    XCTAssertTrue(stopped.allSatisfy { $0.reasonCode == "emergency_stop" })
  }

  func testActionCatalogBindingValidationTemplatesNotificationAndAuditPrivacy() async throws {
    let bindingID = try HermesRequestBindingID(rawValue: "binding:v1:safe")
    let policy = try makePolicy(
      id: "hepol_actions",
      actions: [
        .recordAuditEvent(reasonCode: "audit_only"),
        .refreshBridgeHealth,
        .restartBridgeService,
        .submitApprovedBinding(
          bindingID: bindingID,
          prompt: try HermesEventPolicyPromptTemplate(
            reviewedStaticTemplate: "kind={{eventKind}} app={{applicationBundleIdentifier}}"
          )
        ),
        .createUserNotification(title: "Bridge", body: "Safe event"),
        .markPolicyAttentionRequired(reasonCode: "attention_required"),
      ])
    let harness = try await makeEngine(policies: [policy])
    let result = await harness.engine.evaluate(
      try event(
        kind: .networkAvailable,
        application: HermesSafeApplicationIdentity(
          bundleIdentifier: "com.example.Safe",
          localizedName: "Safe"
        ),
        networkStatus: .available
      ))
    XCTAssertEqual(result.map(\.decision), Array(repeating: .executed, count: 6))
    let refreshCount = await harness.service.refreshCount
    let restartCount = await harness.service.restartCount
    let sentCount = await harness.notifications.sentCount
    let submittedBindings = await harness.submitter.submittedBindings
    XCTAssertEqual(refreshCount, 1)
    XCTAssertEqual(restartCount, 1)
    XCTAssertEqual(sentCount, 1)
    XCTAssertEqual(submittedBindings, [bindingID])
    let audit = await harness.audit.events
    let encoded = try String(data: JSONEncoder().encode(audit), encoding: .utf8).unwrap()
    XCTAssertFalse(encoded.localizedCaseInsensitiveContains("kind=networkAvailable"))
    XCTAssertFalse(encoded.localizedCaseInsensitiveContains("Prompt"))
    XCTAssertFalse(encoded.contains("/Users/"))
    XCTAssertFalse(encoded.localizedCaseInsensitiveContains("clipboard"))
    XCTAssertFalse(encoded.localizedCaseInsensitiveContains("window"))
  }

  func testBindingUnavailableEventTriggerDisabledUnknownPlaceholderAndPromptBounds() async throws {
    let missing = try makePolicy(
      id: "hepol_missing",
      actions: [
        .submitApprovedBinding(
          bindingID: try HermesRequestBindingID(rawValue: "binding:v1:missing"),
          prompt: try HermesEventPolicyPromptTemplate(reviewedStaticTemplate: "{{eventKind}}")
        )
      ])
    let harness = try await makeEngine(policies: [missing])
    let unavailable = await harness.engine.evaluate(
      try event(kind: .networkAvailable, networkStatus: .available)
    ).map(\.decision)
    XCTAssertEqual(unavailable, [.blockedBindingUnavailable])
    XCTAssertThrowsError(
      try HermesEventPolicyPromptTemplate(reviewedStaticTemplate: "{{rawEvent}}"))
    XCTAssertThrowsError(
      try HermesEventPolicyPromptTemplate(
        reviewedStaticTemplate: String(repeating: "x", count: 20_000)))
  }

  func testCircuitBreakerManualResumeConcurrentIsolationAndDeterministicOrdering() async throws {
    let service = FakePolicyService(failRefresh: true)
    let policies = try [
      makePolicy(id: "hepol_a", actions: [.refreshBridgeHealth]),
      makePolicy(id: "hepol_b", actions: [.refreshBridgeHealth]),
      makePolicy(id: "hepol_c", actions: [.refreshBridgeHealth]),
    ]
    let harness = try await makeEngine(policies: policies, service: service)
    let result = await harness.engine.evaluate(
      try event(kind: .networkAvailable, networkStatus: .available))
    XCTAssertEqual(result.map(\.policyID.rawValue), ["hepol_a", "hepol_b", "hepol_c"])
    XCTAssertTrue(result.allSatisfy { $0.decision == .failedRedacted })
    let open = try await harness.engine.status().circuitBreakerOpen
    XCTAssertTrue(open)
    _ = try await harness.engine.resume()
    let closed = try await harness.engine.status().circuitBreakerOpen
    XCTAssertFalse(closed)

    let concurrent = try await makeEngine(
      policies: [makePolicy(id: "hepol_concurrent", cooldownSeconds: 1)]
    )
    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<8 {
        group.addTask {
          _ = await concurrent.engine.evaluate(
            try! event(kind: .networkAvailable, networkStatus: .available))
        }
      }
    }
    let recentCount = try await concurrent.engine.status().recentDecisions.count
    XCTAssertGreaterThanOrEqual(recentCount, 1)
  }

  private struct Harness {
    let engine: HermesEventPolicyEngine
    let submitter: FakeSubmitter
    let service: FakePolicyService
    let notifications: FakeNotifications
    let audit: InMemoryAuditStore
  }

  private func makeEngine(
    policies: [HermesEventPolicy],
    service: FakePolicyService = FakePolicyService(),
    now: @escaping @Sendable () -> Date = Date.init
  ) async throws -> Harness {
    let root = try temporaryDirectory()
    let store = try FileBackedHermesEventPolicyStore(root: root)
    for policy in policies {
      _ = try await store.createPolicy(policy)
    }
    let submitter = FakeSubmitter()
    let notifications = FakeNotifications()
    let audit = InMemoryAuditStore()
    let engine = HermesEventPolicyEngine(
      store: store,
      bindingDiscovery: FakeBindingDiscovery(),
      submitter: submitter,
      serviceManager: service,
      notificationSender: notifications,
      auditStore: audit,
      now: now
    )
    return Harness(
      engine: engine,
      submitter: submitter,
      service: service,
      notifications: notifications,
      audit: audit
    )
  }

  private func makePolicy(
    id: String,
    executionMode: HermesEventPolicyExecutionMode = .active,
    conditions: [HermesEventPolicyCondition] = [
      .eventKindEquals(.networkAvailable),
      .networkAvailabilityEquals(.available),
    ],
    actions: [HermesEventPolicyAction] = [.recordAuditEvent(reasonCode: "matched")],
    cooldownSeconds: TimeInterval = 0,
    maximumExecutionsPerMinute: Int = 6,
    approvalRequirement: HermesEventPolicyApprovalRequirement = .noApproval
  ) throws -> HermesEventPolicy {
    try HermesEventPolicy(
      id: HermesEventPolicyID(rawValue: id),
      executionMode: executionMode,
      conditions: conditions,
      actions: actions,
      cooldownSeconds: cooldownSeconds,
      maximumExecutionsPerMinute: maximumExecutionsPerMinute,
      approvalRequirement: approvalRequirement
    )
  }
}

private actor FakeSubmitter: HermesEventPolicyRequestSubmitting {
  private(set) var submittedBindings: [HermesRequestBindingID] = []
  private(set) var submittedPrompts: [String] = []

  func submit(bindingID: HermesRequestBindingID, prompt: String) async throws -> HermesRequestID {
    submittedBindings.append(bindingID)
    submittedPrompts.append(prompt)
    return try HermesRequestID.generate()
  }
}

private struct FakeBindingDiscovery: HermesEventPolicyBindingDiscovering {
  func listEnabledEventPolicyBindings() async throws -> [HermesEventPolicyBindingSummary] {
    [
      HermesEventPolicyBindingSummary(
        bindingID: try! HermesRequestBindingID(rawValue: "binding:v1:safe"),
        enabled: true,
        maximumPromptBytes: 128,
        approvalPolicy: "explicit",
        allowsEventTriggeredInvocation: true
      ),
      HermesEventPolicyBindingSummary(
        bindingID: try! HermesRequestBindingID(rawValue: "binding:v1:disabled-trigger"),
        enabled: true,
        maximumPromptBytes: 128,
        approvalPolicy: "explicit",
        allowsEventTriggeredInvocation: false
      ),
    ]
  }
}

private actor FakePolicyService: HermesEventPolicyServiceManaging {
  private let failRefresh: Bool
  private(set) var refreshCount = 0
  private(set) var restartCount = 0

  init(failRefresh: Bool = false) {
    self.failRefresh = failRefresh
  }

  func refreshBridgeHealth() async throws {
    refreshCount += 1
    if failRefresh {
      throw HermesEventPolicyError.persistenceFailed("fixture")
    }
  }

  func restartBridgeService() async throws {
    restartCount += 1
  }
}

private actor FakeNotifications: HermesEventPolicyNotificationSending {
  private(set) var sentCount = 0

  func createUserNotification(title _: String, body _: String) async throws {
    sentCount += 1
  }
}

private actor InMemoryAuditStore: HermesAuditStore {
  private(set) var events: [HermesAuditEvent] = []

  func append(_ event: HermesAuditEvent) async throws {
    events.append(event)
  }

  func query(_ query: HermesAuditQuery) async throws -> [HermesAuditEvent] {
    Array(events.filter(query.includes).prefix(query.limit))
  }
}

private final class TestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Date

  init(_ value: Date) {
    self.value = value
  }

  var now: Date {
    lock.withLock { value }
  }

  func advance(_ seconds: TimeInterval) {
    lock.withLock {
      value = value.addingTimeInterval(seconds)
    }
  }
}

private func event(
  kind: HermesSystemEventKind,
  timestamp: Date = Date(),
  application: HermesSafeApplicationIdentity? = nil,
  networkStatus: HermesNetworkStatusClassification? = nil,
  networkInterface: HermesNetworkInterfaceSummary? = nil,
  networkExpensive: Bool? = nil,
  networkConstrained: Bool? = nil,
  serviceHealth: HermesBridgeServiceHealthClassification? = nil
) throws -> HermesSystemEvent {
  try HermesSystemEvent(
    eventID: .generate(),
    kind: kind,
    source: .testFixture,
    timestamp: timestamp,
    application: application,
    networkStatus: networkStatus,
    networkInterface: networkInterface,
    networkExpensive: networkExpensive,
    networkConstrained: networkConstrained,
    serviceHealth: serviceHealth,
    reasonCode: "fixture"
  )
}

private func temporaryDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("HermesEventPolicyTests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

extension XCTestCase {
  fileprivate func XCTAssertThrowsAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async {
    do {
      _ = try await expression()
      XCTFail("Expected error", file: file, line: line)
    } catch {}
  }
}

extension Optional {
  fileprivate func unwrap(file: StaticString = #filePath, line: UInt = #line) throws -> Wrapped {
    guard let self else {
      XCTFail("Expected value", file: file, line: line)
      throw HermesEventPolicyError.invalidPolicy
    }
    return self
  }
}
