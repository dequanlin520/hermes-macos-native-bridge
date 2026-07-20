import Foundation
import HermesRuntimeFoundation
import Security

public actor HermesBridgeFileIntegrationCoordinator: HermesBridgeRequestHandling {
  public static let maximumRootsPerSubscription = 8
  public static let maximumPendingBatchesPerSubscription = 16
  public static let maximumPollingTimeoutMilliseconds = 2_000
  public static let defaultInactivityTimeout: TimeInterval = 30

  private struct Subscription {
    let id: HermesBridgeFileEventSubscriptionID
    let rootIDs: Set<HermesAuthorizedRootID>
    var pending: [HermesBridgeFileEventBatchPayload]
    var expiresAt: Date
    var observedCursor: UInt64
    var deliveredCursor: UInt64
    var acknowledgedCursor: UInt64
    var rescanRequired: Bool
  }

  private let registry: HermesAuthorizedRootRegistry
  private let inactivityTimeout: TimeInterval
  private var monitor: HermesFSEventsMonitor?
  private var monitorStarted = false
  private var subscriptions: [HermesBridgeFileEventSubscriptionID: Subscription] = [:]
  private var observedCursor: UInt64 = 0
  private var deliveredCursor: UInt64 = 0
  private var acknowledgedCursor: UInt64 = 0
  private var rescanRequired = false

  public init(
    registry: HermesAuthorizedRootRegistry,
    monitor: HermesFSEventsMonitor? = nil,
    inactivityTimeout: TimeInterval = 30
  ) {
    self.registry = registry
    self.inactivityTimeout = max(0.05, inactivityTimeout)
    self.monitor = monitor
  }

  public func setMonitor(_ monitor: HermesFSEventsMonitor) {
    guard self.monitor == nil else {
      return
    }
    self.monitor = monitor
  }

  public nonisolated func submit(
    bindingID _: HermesRequestBindingID,
    prompt _: String
  ) async throws -> HermesRequestID {
    throw HermesBridgeXPCError.unsupportedCapability
  }

  public nonisolated func status(requestID _: HermesRequestID) async throws -> HermesRequestRecord {
    throw HermesBridgeXPCError.unsupportedCapability
  }

  public nonisolated func cancel(requestID _: HermesRequestID) async throws -> HermesRequestRecord {
    throw HermesBridgeXPCError.unsupportedCapability
  }

  public nonisolated func respondToApproval(
    requestID _: HermesRequestID,
    decision _: HermesApprovalResponseDecision
  ) async throws -> HermesRequestRecord {
    throw HermesBridgeXPCError.unsupportedCapability
  }

  public func listAuthorizedRoots() async throws -> HermesBridgeAuthorizedRootListPayload {
    let roots = try await registry.listRoots()
    return HermesBridgeAuthorizedRootListPayload(roots: roots.map(summary))
  }

  public func registerAuthorizedRoot(
    displayName: String,
    bookmarkData: Data
  ) async throws -> HermesBridgeAuthorizedRootPayload {
    let record = try await registry.registerBookmark(
      displayName: displayName,
      bookmarkData: bookmarkData,
      createdAt: Date()
    )
    return HermesBridgeAuthorizedRootPayload(root: summary(record))
  }

  public func refreshAuthorizedRoot(
    rootID: HermesAuthorizedRootID,
    bookmarkData: Data,
    expectedRevision: Int?
  ) async throws -> HermesBridgeAuthorizedRootPayload {
    let record = try await registry.reactivateRoot(
      rootID,
      freshBookmarkData: bookmarkData,
      expectedRevision: expectedRevision,
      updatedAt: Date()
    )
    return HermesBridgeAuthorizedRootPayload(root: summary(record))
  }

  public func deactivateAuthorizedRoot(
    rootID: HermesAuthorizedRootID,
    expectedRevision: Int?
  ) async throws -> HermesBridgeAuthorizedRootPayload {
    let record = try await registry.deactivateRoot(
      rootID,
      expectedRevision: expectedRevision,
      updatedAt: Date()
    )
    for (id, subscription) in subscriptions where subscription.rootIDs.contains(rootID) {
      subscriptions[id]?.rescanRequired = true
    }
    return HermesBridgeAuthorizedRootPayload(root: summary(record))
  }

  public func reactivateAuthorizedRoot(
    rootID: HermesAuthorizedRootID,
    bookmarkData: Data,
    expectedRevision: Int?
  ) async throws -> HermesBridgeAuthorizedRootPayload {
    let record = try await registry.reactivateRoot(
      rootID,
      freshBookmarkData: bookmarkData,
      expectedRevision: expectedRevision,
      updatedAt: Date()
    )
    return HermesBridgeAuthorizedRootPayload(root: summary(record))
  }

  public func removeAuthorizedRoot(
    rootID: HermesAuthorizedRootID,
    expectedRevision: Int?
  ) async throws -> HermesBridgeAuthorizedRootPayload {
    let record = try await registry.readRoot(rootID)
    try await registry.removeRoot(rootID, expectedRevision: expectedRevision)
    for (id, subscription) in subscriptions where subscription.rootIDs.contains(rootID) {
      subscriptions[id]?.rescanRequired = true
    }
    return HermesBridgeAuthorizedRootPayload(root: summary(record))
  }

  public func authorizedRootStatus(rootID: HermesAuthorizedRootID) async throws
    -> HermesBridgeAuthorizedRootStatusPayload
  {
    let record = try await registry.readRoot(rootID)
    return HermesBridgeAuthorizedRootStatusPayload(root: summary(record))
  }

  public func resolveAuthorizedRoot(rootID: HermesAuthorizedRootID) async throws
    -> HermesBridgeAuthorizedRootResolutionPayload
  {
    let record = try await registry.readRoot(rootID)
    let resolution = try await registry.resolveRoot(rootID)
    return HermesBridgeAuthorizedRootResolutionPayload(
      rootID: rootID,
      resolution: resolution,
      expectedResolvedRootURL: record.resolvedRootURL
    )
  }

  public func createFileEventSubscription(rootIDs: [HermesAuthorizedRootID]) async throws
    -> HermesBridgeFileEventSubscriptionPayload
  {
    expireInactiveSubscriptions(now: Date())
    guard !rootIDs.isEmpty, rootIDs.count <= Self.maximumRootsPerSubscription else {
      throw HermesBridgeXPCError.malformedPayload
    }
    var checked: [HermesAuthorizedRootID] = []
    for rootID in rootIDs {
      let record = try await registry.readRoot(rootID)
      guard record.state == .active else {
        throw HermesBridgeXPCError.rootInactive
      }
      checked.append(record.rootID)
    }
    try await ensureMonitorStarted()
    let id = try makeSubscriptionID()
    let expiresAt = Date().addingTimeInterval(inactivityTimeout)
    subscriptions[id] = Subscription(
      id: id,
      rootIDs: Set(checked),
      pending: [],
      expiresAt: expiresAt,
      observedCursor: 0,
      deliveredCursor: 0,
      acknowledgedCursor: 0,
      rescanRequired: false
    )
    return HermesBridgeFileEventSubscriptionPayload(
      subscriptionID: id,
      rootIDs: checked,
      expiresAt: expiresAt
    )
  }

  public func pollFileEventSubscription(
    subscriptionID: HermesBridgeFileEventSubscriptionID,
    timeoutMilliseconds: Int
  ) async throws -> HermesBridgeFileEventBatchPayload {
    let timeout = min(max(timeoutMilliseconds, 0), Self.maximumPollingTimeoutMilliseconds)
    let deadline = Date().addingTimeInterval(TimeInterval(timeout) / 1_000)
    while true {
      if let payload = try pollNow(subscriptionID) {
        return payload
      }
      if Date() >= deadline {
        return try emptyPollPayload(subscriptionID)
      }
      try await Task.sleep(nanoseconds: 25_000_000)
    }
  }

  public func acknowledgeFileEventBatch(
    subscriptionID: HermesBridgeFileEventSubscriptionID,
    acknowledgedEventID: UInt64
  ) async throws -> HermesBridgeAcknowledgementPayload {
    guard var subscription = subscriptions[subscriptionID] else {
      throw HermesBridgeXPCError.subscriptionNotFound
    }
    guard subscription.expiresAt >= Date() else {
      subscriptions.removeValue(forKey: subscriptionID)
      throw HermesBridgeXPCError.subscriptionExpired
    }
    guard acknowledgedEventID <= subscription.deliveredCursor else {
      throw HermesBridgeXPCError.acknowledgementRejected
    }
    if acknowledgedEventID > subscription.acknowledgedCursor {
      subscription.acknowledgedCursor = acknowledgedEventID
      acknowledgedCursor = max(acknowledgedCursor, acknowledgedEventID)
    }
    subscription.expiresAt = Date().addingTimeInterval(inactivityTimeout)
    subscriptions[subscriptionID] = subscription
    return HermesBridgeAcknowledgementPayload(
      subscriptionID: subscriptionID,
      acknowledgedEventID: subscription.acknowledgedCursor
    )
  }

  public func cancelFileEventSubscription(
    subscriptionID: HermesBridgeFileEventSubscriptionID
  ) async throws -> HermesBridgeFileEventSubscriptionPayload {
    let existing = subscriptions.removeValue(forKey: subscriptionID)
    let rootIDs = Array(existing?.rootIDs ?? [])
    return HermesBridgeFileEventSubscriptionPayload(
      subscriptionID: subscriptionID,
      rootIDs: rootIDs,
      expiresAt: Date(),
      rescanRequired: existing?.rescanRequired ?? false
    )
  }

  public func fileEventMonitorStatus() async throws -> HermesBridgeFileEventMonitorStatusPayload {
    expireInactiveSubscriptions(now: Date())
    return HermesBridgeFileEventMonitorStatusPayload(
      activeSubscriptionCount: subscriptions.count,
      observedCursor: observedCursor,
      deliveredCursor: deliveredCursor,
      acknowledgedCursor: acknowledgedCursor,
      rescanRequired: rescanRequired
    )
  }

  public func ingest(batch: HermesFileEventBatch) async {
    observedCursor = max(observedCursor, batch.newestEventID)
    rescanRequired = rescanRequired || batch.rescanRequired
    for (id, subscription) in subscriptions where subscription.rootIDs.contains(batch.rootID) {
      do {
        let payload = try Self.payload(subscriptionID: id, batch: batch)
        append(payload, to: id)
      } catch {
        subscriptions[id]?.rescanRequired = true
      }
    }
  }

  public func shutdown() async {
    subscriptions.removeAll()
    monitorStarted = false
    try? await monitor?.stop()
  }

  private func pollNow(
    _ subscriptionID: HermesBridgeFileEventSubscriptionID
  ) throws -> HermesBridgeFileEventBatchPayload? {
    guard var subscription = subscriptions[subscriptionID] else {
      throw HermesBridgeXPCError.subscriptionNotFound
    }
    guard subscription.expiresAt >= Date() else {
      subscriptions.removeValue(forKey: subscriptionID)
      throw HermesBridgeXPCError.subscriptionExpired
    }
    subscription.expiresAt = Date().addingTimeInterval(inactivityTimeout)
    if !subscription.pending.isEmpty {
      let payload = subscription.pending.removeFirst()
      subscription.deliveredCursor = max(subscription.deliveredCursor, payload.newestEventID)
      deliveredCursor = max(deliveredCursor, payload.newestEventID)
      subscriptions[subscriptionID] = subscription
      return payload
    }
    subscriptions[subscriptionID] = subscription
    return nil
  }

  private func emptyPollPayload(
    _ subscriptionID: HermesBridgeFileEventSubscriptionID
  ) throws -> HermesBridgeFileEventBatchPayload {
    guard let subscription = subscriptions[subscriptionID] else {
      throw HermesBridgeXPCError.subscriptionNotFound
    }
    guard let rootID = subscription.rootIDs.sorted(by: { $0.rawValue < $1.rawValue }).first else {
      throw HermesBridgeXPCError.subscriptionNotFound
    }
    return try HermesBridgeFileEventBatchPayload(
      subscriptionID: subscriptionID,
      rootID: rootID,
      events: [],
      newestEventID: subscription.deliveredCursor,
      replayed: false,
      rescanRequired: subscription.rescanRequired
    )
  }

  private func append(
    _ payload: HermesBridgeFileEventBatchPayload,
    to subscriptionID: HermesBridgeFileEventSubscriptionID
  ) {
    guard var subscription = subscriptions[subscriptionID] else {
      return
    }
    if subscription.pending.count >= Self.maximumPendingBatchesPerSubscription {
      subscription.pending.removeAll()
      subscription.rescanRequired = true
      rescanRequired = true
      if let overflow = try? HermesBridgeFileEventBatchPayload(
        subscriptionID: subscriptionID,
        rootID: try! HermesAuthorizedRootID(rawValue: payload.rootID),
        events: [],
        newestEventID: max(subscription.observedCursor, payload.newestEventID),
        replayed: true,
        rescanRequired: true,
        droppedEventReason: .userDropped
      ) {
        subscription.pending.append(overflow)
      }
    } else {
      subscription.pending.append(payload)
    }
    subscription.observedCursor = max(subscription.observedCursor, payload.newestEventID)
    subscriptions[subscriptionID] = subscription
  }

  private func ensureMonitorStarted() async throws {
    guard let monitor, !monitorStarted else {
      return
    }
    let records = try await registry.listRoots()
    try await monitor.start(records: records)
    monitorStarted = true
  }

  private func expireInactiveSubscriptions(now: Date) {
    subscriptions = subscriptions.filter { _, subscription in
      subscription.expiresAt >= now
    }
  }

  private func summary(_ record: HermesAuthorizedRootRecord) -> HermesBridgeAuthorizedRootSummary {
    HermesBridgeAuthorizedRootSummary(
      record: record,
      securityScopeStatus: .unavailable
    )
  }

  private func makeSubscriptionID() throws -> HermesBridgeFileEventSubscriptionID {
    var bytes = [UInt8](repeating: 0, count: 24)
    let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    guard result == errSecSuccess else {
      throw HermesBridgeXPCError.internalFailure
    }
    return try HermesBridgeFileEventSubscriptionID(
      rawValue: HermesBridgeFileEventSubscriptionID.prefix
        + Data(bytes).hermesBridgeBase64URLEncodedString()
    )
  }

  private static func payload(
    subscriptionID: HermesBridgeFileEventSubscriptionID,
    batch: HermesFileEventBatch
  ) throws -> HermesBridgeFileEventBatchPayload {
    let summaries = batch.events.map {
      HermesBridgeFileEventSummary(event: $0, replayed: batch.replayed)
    }
    return try HermesBridgeFileEventBatchPayload(
      subscriptionID: subscriptionID,
      rootID: batch.rootID,
      events: summaries,
      newestEventID: batch.newestEventID,
      replayed: batch.replayed,
      historyDone: batch.events.contains { $0.kind == .historyDone },
      rescanRequired: batch.rescanRequired,
      droppedEventReason: batch.droppedEventReason
    )
  }
}

extension Data {
  fileprivate func hermesBridgeBase64URLEncodedString() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
