import Foundation
import HermesRuntimeFoundation
import Security

public actor HermesBridgeSystemEventCoordinator: HermesBridgeRequestHandling {
  public static let maximumEventKindsPerSubscription = HermesSystemEventKind.allCases.count
  public static let maximumSubscriptions = 32
  public static let maximumPendingBatchesPerSubscription = 16
  public static let maximumPollingTimeoutMilliseconds = 2_000
  public static let defaultInactivityTimeout: TimeInterval = 30

  private struct Subscription {
    let id: HermesSystemEventSubscriptionID
    let kinds: Set<HermesSystemEventKind>
    var pending: [HermesBridgeSystemEventBatchPayload]
    var expiresAt: Date
    var observedCursor: UInt64
    var deliveredCursor: UInt64
    var acknowledgedCursor: UInt64
    var resyncRequired: Bool
  }

  private let inactivityTimeout: TimeInterval
  private let productionMonitorsEnabled: Bool
  private var eventHandler: (@Sendable (HermesSystemEvent) async -> Void)?
  private var networkMonitor: HermesSystemNetworkMonitor?
  private var workspaceMonitor: HermesSystemWorkspaceMonitor?
  private var subscriptions: [HermesSystemEventSubscriptionID: Subscription] = [:]
  private var monitorStarted = false
  private var networkMonitorActive = false
  private var workspaceMonitorActive = false
  private var sessionMonitorActive = false
  private var observedCursor: UInt64 = 0
  private var deliveredCursor: UInt64 = 0
  private var acknowledgedCursor: UInt64 = 0
  private var resyncRequired = false
  private var networkStatus: HermesNetworkStatusClassification = .unknown
  private var lastNetworkState: HermesNetworkPathState?
  private var serviceHealth: HermesBridgeServiceHealthClassification = .healthy

  public init(
    networkMonitor: HermesSystemNetworkMonitor? = nil,
    workspaceMonitor: HermesSystemWorkspaceMonitor? = nil,
    inactivityTimeout: TimeInterval = 30,
    productionMonitorsEnabled: Bool = true,
    eventHandler: (@Sendable (HermesSystemEvent) async -> Void)? = nil
  ) {
    self.networkMonitor = networkMonitor
    self.workspaceMonitor = workspaceMonitor
    self.inactivityTimeout = max(0.05, inactivityTimeout)
    self.productionMonitorsEnabled = productionMonitorsEnabled
    self.eventHandler = eventHandler
  }

  public func setNetworkMonitor(_ monitor: HermesSystemNetworkMonitor) {
    guard networkMonitor == nil else { return }
    networkMonitor = monitor
  }

  public func setWorkspaceMonitor(_ monitor: HermesSystemWorkspaceMonitor) {
    guard workspaceMonitor == nil else { return }
    workspaceMonitor = monitor
  }

  public func setEventHandler(_ handler: @escaping @Sendable (HermesSystemEvent) async -> Void) {
    guard eventHandler == nil else { return }
    eventHandler = handler
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

  public func createSubscription(kinds: [HermesSystemEventKind]) async throws
    -> HermesBridgeSystemEventSubscriptionPayload
  {
    expireInactiveSubscriptions(now: Date())
    guard !kinds.isEmpty, kinds.count <= Self.maximumEventKindsPerSubscription else {
      throw HermesBridgeXPCError.malformedPayload
    }
    let filtered = Set(kinds)
    guard filtered.count == kinds.count else {
      throw HermesBridgeXPCError.malformedPayload
    }
    guard subscriptions.count < Self.maximumSubscriptions else {
      throw HermesBridgeXPCError.serviceUnavailable
    }
    ensureMonitorsStarted()
    let id = try makeSubscriptionID()
    let expiresAt = Date().addingTimeInterval(inactivityTimeout)
    subscriptions[id] = Subscription(
      id: id,
      kinds: filtered,
      pending: [],
      expiresAt: expiresAt,
      observedCursor: 0,
      deliveredCursor: 0,
      acknowledgedCursor: 0,
      resyncRequired: false
    )
    return HermesBridgeSystemEventSubscriptionPayload(
      subscriptionID: id,
      kinds: kinds,
      expiresAt: expiresAt
    )
  }

  public func createSystemEventSubscription(kinds: [HermesSystemEventKind]) async throws
    -> HermesBridgeSystemEventSubscriptionPayload
  {
    try await createSubscription(kinds: kinds)
  }

  public func pollSubscription(
    subscriptionID: HermesSystemEventSubscriptionID,
    timeoutMilliseconds: Int
  ) async throws -> HermesBridgeSystemEventBatchPayload {
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

  public func pollSystemEventSubscription(
    subscriptionID: HermesSystemEventSubscriptionID,
    timeoutMilliseconds: Int
  ) async throws -> HermesBridgeSystemEventBatchPayload {
    try await pollSubscription(
      subscriptionID: subscriptionID,
      timeoutMilliseconds: timeoutMilliseconds
    )
  }

  public func acknowledgeBatch(
    subscriptionID: HermesSystemEventSubscriptionID,
    acknowledgedEventOrdinal: UInt64
  ) async throws -> HermesBridgeAcknowledgementPayload {
    guard var subscription = subscriptions[subscriptionID] else {
      throw HermesBridgeXPCError.subscriptionNotFound
    }
    guard subscription.expiresAt >= Date() else {
      subscriptions.removeValue(forKey: subscriptionID)
      throw HermesBridgeXPCError.subscriptionExpired
    }
    guard acknowledgedEventOrdinal <= subscription.deliveredCursor else {
      throw HermesBridgeXPCError.acknowledgementRejected
    }
    if acknowledgedEventOrdinal > subscription.acknowledgedCursor {
      subscription.acknowledgedCursor = acknowledgedEventOrdinal
      acknowledgedCursor = max(acknowledgedCursor, acknowledgedEventOrdinal)
    }
    subscription.expiresAt = Date().addingTimeInterval(inactivityTimeout)
    subscriptions[subscriptionID] = subscription
    return HermesBridgeAcknowledgementPayload(
      subscriptionID: subscriptionID.rawValue,
      acknowledgedEventID: subscription.acknowledgedCursor
    )
  }

  public func acknowledgeSystemEventBatch(
    subscriptionID: HermesSystemEventSubscriptionID,
    acknowledgedEventOrdinal: UInt64
  ) async throws -> HermesBridgeAcknowledgementPayload {
    try await acknowledgeBatch(
      subscriptionID: subscriptionID,
      acknowledgedEventOrdinal: acknowledgedEventOrdinal
    )
  }

  public func cancelSubscription(subscriptionID: HermesSystemEventSubscriptionID) async throws
    -> HermesBridgeSystemEventSubscriptionPayload
  {
    let existing = subscriptions.removeValue(forKey: subscriptionID)
    return HermesBridgeSystemEventSubscriptionPayload(
      subscriptionID: subscriptionID,
      kinds: existing?.kinds.sorted { $0.rawValue < $1.rawValue } ?? [],
      expiresAt: Date(),
      resyncRequired: existing?.resyncRequired ?? false
    )
  }

  public func cancelSystemEventSubscription(
    subscriptionID: HermesSystemEventSubscriptionID
  ) async throws -> HermesBridgeSystemEventSubscriptionPayload {
    try await cancelSubscription(subscriptionID: subscriptionID)
  }

  public func monitorStatus() async throws -> HermesBridgeSystemEventMonitorStatusPayload {
    expireInactiveSubscriptions(now: Date())
    return HermesBridgeSystemEventMonitorStatusPayload(
      status: HermesSystemEventMonitorStatus(
        started: monitorStarted,
        networkMonitorActive: networkMonitorActive,
        workspaceMonitorActive: workspaceMonitorActive,
        sessionMonitorActive: sessionMonitorActive,
        activeSubscriptionCount: subscriptions.count,
        observedCursor: observedCursor,
        deliveredCursor: deliveredCursor,
        acknowledgedCursor: acknowledgedCursor,
        resyncRequired: resyncRequired,
        networkStatus: networkStatus,
        serviceHealth: serviceHealth
      ))
  }

  public func systemEventMonitorStatus() async throws -> HermesBridgeSystemEventMonitorStatusPayload
  {
    try await monitorStatus()
  }

  public func ingestNetworkState(_ state: HermesNetworkPathState) async {
    let previousState = lastNetworkState
    guard previousState != state else {
      return
    }
    lastNetworkState = state
    networkStatus = state.status
    if previousState?.status != state.status {
      await ingest(
        kind: state.status == .available ? .networkAvailable : .networkUnavailable,
        networkStatus: state.status,
        networkInterface: state.interface,
        networkExpensive: state.expensive,
        networkConstrained: state.constrained,
        reasonCode: "network_availability_changed"
      )
    }
    if previousState?.interface != state.interface {
      await ingest(
        kind: .networkInterfaceChanged,
        networkStatus: state.status,
        networkInterface: state.interface,
        networkExpensive: state.expensive,
        networkConstrained: state.constrained,
        coalesced: true,
        reasonCode: "network_interface_changed"
      )
    }
    if previousState?.expensive != state.expensive {
      await ingest(
        kind: .networkExpensiveChanged,
        networkStatus: state.status,
        networkInterface: state.interface,
        networkExpensive: state.expensive,
        networkConstrained: state.constrained,
        coalesced: true,
        reasonCode: "network_expensive_changed"
      )
    }
    if previousState?.constrained != state.constrained {
      await ingest(
        kind: .networkConstrainedChanged,
        networkStatus: state.status,
        networkInterface: state.interface,
        networkExpensive: state.expensive,
        networkConstrained: state.constrained,
        coalesced: true,
        reasonCode: "network_constrained_changed"
      )
    }
  }

  public func ingestWorkspace(
    kind: HermesSystemEventKind,
    application: HermesSafeApplicationIdentity?
  ) async {
    await ingest(
      kind: kind,
      source: (kind == .sessionLocked || kind == .sessionUnlocked) ? .session : .workspace,
      application: application,
      reasonCode: kind.rawValue
    )
  }

  public func ingestServiceHealth(_ health: HermesBridgeServiceHealthClassification) async {
    guard health != serviceHealth else {
      return
    }
    serviceHealth = health
    let kind: HermesSystemEventKind =
      switch health {
      case .healthy: .bridgeServiceHealthy
      case .degraded: .bridgeServiceDegraded
      case .unavailable: .bridgeServiceUnavailable
      }
    await ingest(
      kind: kind,
      source: .bridgeService,
      serviceHealth: health,
      reasonCode: "service_health_transition"
    )
  }

  public func ingest(
    kind: HermesSystemEventKind,
    source: HermesSystemEventSource = .networkPath,
    application: HermesSafeApplicationIdentity? = nil,
    networkStatus: HermesNetworkStatusClassification? = nil,
    networkInterface: HermesNetworkInterfaceSummary? = nil,
    networkExpensive: Bool? = nil,
    networkConstrained: Bool? = nil,
    serviceHealth: HermesBridgeServiceHealthClassification? = nil,
    replayed: Bool = false,
    coalesced: Bool = false,
    reasonCode: String? = nil
  ) async {
    guard
      let event = try? HermesSystemEvent(
        eventID: HermesSystemEventID.generate(),
        kind: kind,
        source: source,
        application: application,
        networkStatus: networkStatus,
        networkInterface: networkInterface,
        networkExpensive: networkExpensive,
        networkConstrained: networkConstrained,
        serviceHealth: serviceHealth,
        replayed: replayed,
        coalesced: coalesced,
        reasonCode: reasonCode ?? kind.rawValue
      )
    else {
      return
    }
    observedCursor += 1
    for (id, subscription) in subscriptions where subscription.kinds.contains(kind) {
      append(event, ordinal: observedCursor, to: id)
    }
    if let eventHandler {
      await eventHandler(event)
    }
  }

  public func shutdown() async {
    subscriptions.removeAll()
    monitorStarted = false
    networkMonitorActive = false
    workspaceMonitorActive = false
    sessionMonitorActive = false
    networkMonitor?.stop()
    workspaceMonitor?.stop()
  }

  private func pollNow(
    _ subscriptionID: HermesSystemEventSubscriptionID
  ) throws -> HermesBridgeSystemEventBatchPayload? {
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
      subscription.deliveredCursor = max(subscription.deliveredCursor, payload.newestEventOrdinal)
      deliveredCursor = max(deliveredCursor, payload.newestEventOrdinal)
      subscriptions[subscriptionID] = subscription
      return payload
    }
    subscriptions[subscriptionID] = subscription
    return nil
  }

  private func emptyPollPayload(
    _ subscriptionID: HermesSystemEventSubscriptionID
  ) throws -> HermesBridgeSystemEventBatchPayload {
    guard let subscription = subscriptions[subscriptionID] else {
      throw HermesBridgeXPCError.subscriptionNotFound
    }
    return try HermesBridgeSystemEventBatchPayload(
      subscriptionID: subscriptionID,
      events: [],
      newestEventOrdinal: subscription.deliveredCursor,
      replayed: false,
      resyncRequired: subscription.resyncRequired
    )
  }

  private func append(
    _ event: HermesSystemEvent,
    ordinal: UInt64,
    to subscriptionID: HermesSystemEventSubscriptionID
  ) {
    guard var subscription = subscriptions[subscriptionID] else {
      return
    }
    if subscription.pending.count >= Self.maximumPendingBatchesPerSubscription {
      subscription.pending.removeAll()
      subscription.resyncRequired = true
      resyncRequired = true
      if let overflow = try? HermesBridgeSystemEventBatchPayload(
        subscriptionID: subscriptionID,
        events: [],
        newestEventOrdinal: max(subscription.observedCursor, ordinal),
        replayed: true,
        resyncRequired: true,
        droppedEventReason: "slow_consumer"
      ) {
        subscription.pending.append(overflow)
      }
    } else if let payload = try? HermesBridgeSystemEventBatchPayload(
      subscriptionID: subscriptionID,
      events: [event],
      newestEventOrdinal: ordinal,
      replayed: event.replayed,
      resyncRequired: subscription.resyncRequired
    ) {
      subscription.pending.append(payload)
    } else {
      subscription.resyncRequired = true
      resyncRequired = true
    }
    subscription.observedCursor = max(subscription.observedCursor, ordinal)
    subscriptions[subscriptionID] = subscription
  }

  private func ensureMonitorsStarted() {
    guard !monitorStarted else {
      return
    }
    monitorStarted = true
    guard productionMonitorsEnabled else {
      return
    }
    if networkMonitor == nil {
      networkMonitor = HermesSystemNetworkMonitor { [weak self] state in
        await self?.ingestNetworkState(state)
      }
    }
    if workspaceMonitor == nil {
      workspaceMonitor = HermesSystemWorkspaceMonitor { [weak self] kind, application in
        await self?.ingestWorkspace(kind: kind, application: application)
      }
    }
    networkMonitor?.start()
    workspaceMonitor?.start()
    networkMonitorActive = networkMonitor != nil
    workspaceMonitorActive = workspaceMonitor != nil
    sessionMonitorActive = workspaceMonitor != nil
  }

  private func expireInactiveSubscriptions(now: Date) {
    subscriptions = subscriptions.filter { _, subscription in
      subscription.expiresAt >= now
    }
  }

  private func makeSubscriptionID() throws -> HermesSystemEventSubscriptionID {
    var bytes = [UInt8](repeating: 0, count: 24)
    let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    guard result == errSecSuccess else {
      throw HermesBridgeXPCError.internalFailure
    }
    return try HermesSystemEventSubscriptionID(
      rawValue: HermesSystemEventSubscriptionID.prefix
        + Data(bytes).hermesBridgeSystemBase64URLEncodedString()
    )
  }
}

extension Data {
  fileprivate func hermesBridgeSystemBase64URLEncodedString() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
