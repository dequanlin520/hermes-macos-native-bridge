import AppKit
import Foundation
import Network
import Security

public struct HermesSystemEventID: Codable, Equatable, Hashable, Sendable,
  CustomStringConvertible
{
  public static let prefix = "hsev_"
  public static let encodedRandomLength = 22
  public static let maximumLength = prefix.count + encodedRandomLength

  public let rawValue: String

  public static func generate() throws -> HermesSystemEventID {
    var bytes = [UInt8](repeating: 0, count: 16)
    let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    guard result == errSecSuccess else {
      throw HermesSystemEventError.identifierGenerationFailed
    }
    return try HermesSystemEventID(
      rawValue: prefix + Data(bytes).hermesSystemEventBase64URLEncodedString())
  }

  public init(rawValue: String) throws {
    guard Self.isValid(rawValue) else {
      throw HermesSystemEventError.invalidEventID
    }
    self.rawValue = rawValue
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    try self.init(rawValue: container.decode(String.self))
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  public var description: String { rawValue }

  public static func isValid(_ value: String) -> Bool {
    guard value.count == maximumLength, value.hasPrefix(prefix) else {
      return false
    }
    return value.dropFirst(prefix.count).allSatisfy {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_")
    }
  }
}

public enum HermesSystemEventKind: String, Codable, CaseIterable, Equatable, Sendable {
  case networkAvailable
  case networkUnavailable
  case networkInterfaceChanged
  case networkExpensiveChanged
  case networkConstrainedChanged
  case systemWillSleep
  case systemDidWake
  case screenDidSleep
  case screenDidWake
  case sessionLocked
  case sessionUnlocked
  case applicationLaunched
  case applicationTerminated
  case activeApplicationChanged
  case bridgeServiceHealthy
  case bridgeServiceDegraded
  case bridgeServiceUnavailable
}

public enum HermesSystemEventSource: String, Codable, CaseIterable, Equatable, Sendable {
  case networkPath
  case workspace
  case session
  case bridgeService
  case testFixture
}

public enum HermesNetworkStatusClassification: String, Codable, CaseIterable, Equatable, Sendable {
  case available
  case unavailable
  case unknown
}

public enum HermesNetworkInterfaceSummary: String, Codable, CaseIterable, Equatable, Sendable {
  case wiredEthernet
  case wifi
  case cellular
  case loopback
  case other
  case unavailable
  case unknown
}

public enum HermesBridgeServiceHealthClassification: String, Codable, CaseIterable, Equatable,
  Sendable
{
  case healthy
  case degraded
  case unavailable
}

public struct HermesSafeApplicationIdentity: Codable, Equatable, Sendable {
  public static let maximumBundleIdentifierCharacters = 160
  public static let maximumLocalizedNameCharacters = 80

  public let bundleIdentifier: String?
  public let localizedName: String?

  public init(bundleIdentifier: String?, localizedName: String?) {
    self.bundleIdentifier = bundleIdentifier.flatMap {
      Self.safeBundleIdentifier($0)
    }
    self.localizedName = localizedName.flatMap {
      Self.safeLocalizedName($0)
    }
  }

  public init(application: NSRunningApplication) {
    self.init(
      bundleIdentifier: application.bundleIdentifier,
      localizedName: application.localizedName
    )
  }

  private static func safeBundleIdentifier(_ value: String) -> String? {
    var filtered = ""
    for character in value {
      guard character.isASCII,
        character.isLetter || character.isNumber || character == "." || character == "-"
          || character == "_"
      else {
        break
      }
      filtered.append(character)
    }
    let bounded = String(filtered.prefix(maximumBundleIdentifierCharacters))
    return bounded.isEmpty ? nil : bounded
  }

  private static func safeLocalizedName(_ value: String) -> String? {
    let filtered = value.unicodeScalars.filter { scalar in
      scalar.value >= 0x20 && scalar.value != 0x7F
    }
    let bounded = String(String.UnicodeScalarView(filtered)).prefixString(
      maximumLocalizedNameCharacters)
    return bounded.isEmpty ? nil : bounded
  }
}

public struct HermesSystemEvent: Codable, Equatable, Sendable {
  public static let maximumReasonCodeCharacters = 64

  public let eventID: HermesSystemEventID
  public let kind: HermesSystemEventKind
  public let source: HermesSystemEventSource
  public let timestamp: Date
  public let application: HermesSafeApplicationIdentity?
  public let networkStatus: HermesNetworkStatusClassification?
  public let networkInterface: HermesNetworkInterfaceSummary?
  public let networkExpensive: Bool?
  public let networkConstrained: Bool?
  public let serviceHealth: HermesBridgeServiceHealthClassification?
  public let replayed: Bool
  public let coalesced: Bool
  public let reasonCode: String

  public init(
    eventID: HermesSystemEventID,
    kind: HermesSystemEventKind,
    source: HermesSystemEventSource,
    timestamp: Date = Date(),
    application: HermesSafeApplicationIdentity? = nil,
    networkStatus: HermesNetworkStatusClassification? = nil,
    networkInterface: HermesNetworkInterfaceSummary? = nil,
    networkExpensive: Bool? = nil,
    networkConstrained: Bool? = nil,
    serviceHealth: HermesBridgeServiceHealthClassification? = nil,
    replayed: Bool = false,
    coalesced: Bool = false,
    reasonCode: String
  ) throws {
    self.eventID = eventID
    self.kind = kind
    self.source = source
    self.timestamp = timestamp
    self.application = application
    self.networkStatus = networkStatus
    self.networkInterface = networkInterface
    self.networkExpensive = networkExpensive
    self.networkConstrained = networkConstrained
    self.serviceHealth = serviceHealth
    self.replayed = replayed
    self.coalesced = coalesced
    self.reasonCode = try Self.safeReasonCode(reasonCode)
  }

  public static func safeReasonCode(_ value: String) throws -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-")
    }
    guard !filtered.isEmpty, filtered.count <= maximumReasonCodeCharacters else {
      throw HermesSystemEventError.invalidReasonCode
    }
    return filtered
  }
}

public struct HermesSystemEventBatch: Codable, Equatable, Sendable {
  public static let maximumEventCount = 128
  public static let maximumEncodedBytes = 64 * 1024

  public let events: [HermesSystemEvent]
  public let newestEventOrdinal: UInt64
  public let replayed: Bool
  public let resyncRequired: Bool
  public let droppedEventReason: String?

  public init(
    events: [HermesSystemEvent],
    newestEventOrdinal: UInt64,
    replayed: Bool = false,
    resyncRequired: Bool = false,
    droppedEventReason: String? = nil
  ) throws {
    self.events = Array(events.prefix(Self.maximumEventCount))
    self.newestEventOrdinal = newestEventOrdinal
    self.replayed = replayed
    self.resyncRequired = resyncRequired
    self.droppedEventReason = try droppedEventReason.map(HermesSystemEvent.safeReasonCode)
    guard (try? JSONEncoder().encode(self).count) ?? Int.max <= Self.maximumEncodedBytes else {
      throw HermesSystemEventError.batchTooLarge
    }
  }
}

public struct HermesSystemEventSubscriptionID: Codable, Equatable, Hashable, Sendable,
  CustomStringConvertible
{
  public static let prefix = "ssub_"
  public let rawValue: String

  public init(rawValue: String) throws {
    guard rawValue.hasPrefix(Self.prefix), rawValue.count <= 80,
      rawValue.dropFirst(Self.prefix.count).allSatisfy({
        $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_")
      })
    else {
      throw HermesSystemEventError.invalidSubscriptionID
    }
    self.rawValue = rawValue
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    try self.init(rawValue: container.decode(String.self))
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  public var description: String { rawValue }
}

public struct HermesSystemEventMonitorStatus: Codable, Equatable, Sendable {
  public let started: Bool
  public let networkMonitorActive: Bool
  public let workspaceMonitorActive: Bool
  public let sessionMonitorActive: Bool
  public let activeSubscriptionCount: Int
  public let observedCursor: UInt64
  public let deliveredCursor: UInt64
  public let acknowledgedCursor: UInt64
  public let resyncRequired: Bool
  public let networkStatus: HermesNetworkStatusClassification
  public let serviceHealth: HermesBridgeServiceHealthClassification

  public init(
    started: Bool,
    networkMonitorActive: Bool,
    workspaceMonitorActive: Bool,
    sessionMonitorActive: Bool,
    activeSubscriptionCount: Int,
    observedCursor: UInt64,
    deliveredCursor: UInt64,
    acknowledgedCursor: UInt64,
    resyncRequired: Bool,
    networkStatus: HermesNetworkStatusClassification,
    serviceHealth: HermesBridgeServiceHealthClassification
  ) {
    self.started = started
    self.networkMonitorActive = networkMonitorActive
    self.workspaceMonitorActive = workspaceMonitorActive
    self.sessionMonitorActive = sessionMonitorActive
    self.activeSubscriptionCount = activeSubscriptionCount
    self.observedCursor = observedCursor
    self.deliveredCursor = deliveredCursor
    self.acknowledgedCursor = acknowledgedCursor
    self.resyncRequired = resyncRequired
    self.networkStatus = networkStatus
    self.serviceHealth = serviceHealth
  }
}

public enum HermesSystemEventError: Error, Equatable, Sendable {
  case identifierGenerationFailed
  case invalidEventID
  case invalidSubscriptionID
  case invalidReasonCode
  case batchTooLarge
}

public struct HermesNetworkPathState: Equatable, Sendable {
  public let status: HermesNetworkStatusClassification
  public let interface: HermesNetworkInterfaceSummary
  public let expensive: Bool
  public let constrained: Bool

  public init(
    status: HermesNetworkStatusClassification,
    interface: HermesNetworkInterfaceSummary,
    expensive: Bool,
    constrained: Bool
  ) {
    self.status = status
    self.interface = interface
    self.expensive = expensive
    self.constrained = constrained
  }

  public init(path: NWPath) {
    self.init(
      status: path.status == .satisfied ? .available : .unavailable,
      interface: Self.interfaceSummary(path),
      expensive: path.isExpensive,
      constrained: path.isConstrained
    )
  }

  private static func interfaceSummary(_ path: NWPath) -> HermesNetworkInterfaceSummary {
    guard path.status == .satisfied else {
      return .unavailable
    }
    if path.usesInterfaceType(.wiredEthernet) { return .wiredEthernet }
    if path.usesInterfaceType(.wifi) { return .wifi }
    if path.usesInterfaceType(.cellular) { return .cellular }
    if path.usesInterfaceType(.loopback) { return .loopback }
    if path.usesInterfaceType(.other) { return .other }
    return .unknown
  }
}

public final class HermesSystemNetworkMonitor: @unchecked Sendable {
  public typealias Handler = @Sendable (HermesNetworkPathState) async -> Void

  private let lock = NSLock()
  private let queue = DispatchQueue(label: "com.hermes.bridge.system-events.network")
  private let handler: Handler
  private var monitor: NWPathMonitor?
  private var started = false
  private var stoppedGeneration = 0
  private var lastState: HermesNetworkPathState?

  public init(handler: @escaping Handler) {
    self.handler = handler
  }

  public func start() {
    let generation: Int = lock.withLock {
      if started {
        return stoppedGeneration
      }
      started = true
      let next = stoppedGeneration + 1
      stoppedGeneration = next
      let monitor = NWPathMonitor()
      self.monitor = monitor
      monitor.pathUpdateHandler = { [weak self] path in
        self?.handle(path: path, generation: next)
      }
      monitor.start(queue: queue)
      return next
    }
    _ = generation
  }

  public func stop() {
    let existing = lock.withLock {
      started = false
      stoppedGeneration += 1
      lastState = nil
      let current = monitor
      monitor = nil
      return current
    }
    existing?.pathUpdateHandler = nil
    existing?.cancel()
  }

  private func handle(path: NWPath, generation: Int) {
    let state = HermesNetworkPathState(path: path)
    let shouldEmit = lock.withLock {
      guard started, generation == stoppedGeneration else {
        return false
      }
      guard lastState != state else {
        return false
      }
      lastState = state
      return true
    }
    guard shouldEmit else {
      return
    }
    Task {
      await handler(state)
    }
  }
}

public final class HermesSystemWorkspaceMonitor: @unchecked Sendable {
  public typealias Handler =
    @Sendable (HermesSystemEventKind, HermesSafeApplicationIdentity?)
    async -> Void

  private let lock = NSLock()
  private let handler: Handler
  private var observers: [NSObjectProtocol] = []
  private var distributedObservers: [NSObjectProtocol] = []
  private var started = false

  public init(handler: @escaping Handler) {
    self.handler = handler
  }

  public func start() {
    lock.withLock {
      guard !started else { return }
      started = true
      let center = NSWorkspace.shared.notificationCenter
      addWorkspaceObserver(center, name: NSWorkspace.didLaunchApplicationNotification) {
        [weak self] notification in
        self?.emit(.applicationLaunched, application: Self.application(from: notification))
      }
      addWorkspaceObserver(center, name: NSWorkspace.didTerminateApplicationNotification) {
        [weak self] notification in
        self?.emit(.applicationTerminated, application: Self.application(from: notification))
      }
      addWorkspaceObserver(center, name: NSWorkspace.didActivateApplicationNotification) {
        [weak self] notification in
        self?.emit(.activeApplicationChanged, application: Self.application(from: notification))
      }
      addWorkspaceObserver(center, name: NSWorkspace.willSleepNotification) { [weak self] _ in
        self?.emit(.systemWillSleep, application: nil)
      }
      addWorkspaceObserver(center, name: NSWorkspace.didWakeNotification) { [weak self] _ in
        self?.emit(.systemDidWake, application: nil)
      }
      addWorkspaceObserver(center, name: NSWorkspace.screensDidSleepNotification) {
        [weak self] _
        in
        self?.emit(.screenDidSleep, application: nil)
      }
      addWorkspaceObserver(center, name: NSWorkspace.screensDidWakeNotification) {
        [weak self] _
        in
        self?.emit(.screenDidWake, application: nil)
      }
      let distributed = DistributedNotificationCenter.default()
      addDistributedObserver(distributed, name: Notification.Name("com.apple.screenIsLocked")) {
        [weak self] _ in
        self?.emit(.sessionLocked, application: nil)
      }
      addDistributedObserver(distributed, name: Notification.Name("com.apple.screenIsUnlocked")) {
        [weak self] _ in
        self?.emit(.sessionUnlocked, application: nil)
      }
    }
  }

  public func stop() {
    let current = lock.withLock {
      started = false
      let workspace = observers
      let distributed = distributedObservers
      observers = []
      distributedObservers = []
      return (workspace, distributed)
    }
    let center = NSWorkspace.shared.notificationCenter
    current.0.forEach { center.removeObserver($0) }
    let distributed = DistributedNotificationCenter.default()
    current.1.forEach { distributed.removeObserver($0) }
  }

  private func addWorkspaceObserver(
    _ center: NotificationCenter,
    name: Notification.Name,
    using block: @escaping @Sendable (Notification) -> Void
  ) {
    let observer = center.addObserver(forName: name, object: nil, queue: nil, using: block)
    observers.append(observer)
  }

  private func addDistributedObserver(
    _ center: DistributedNotificationCenter,
    name: Notification.Name,
    using block: @escaping @Sendable (Notification) -> Void
  ) {
    let observer = center.addObserver(forName: name, object: nil, queue: nil, using: block)
    distributedObservers.append(observer)
  }

  private func emit(_ kind: HermesSystemEventKind, application: HermesSafeApplicationIdentity?) {
    let shouldEmit = lock.withLock { started }
    guard shouldEmit else {
      return
    }
    Task {
      await handler(kind, application)
    }
  }

  private static func application(from notification: Notification) -> HermesSafeApplicationIdentity?
  {
    guard
      let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
        as? NSRunningApplication
    else {
      return nil
    }
    return HermesSafeApplicationIdentity(application: application)
  }
}

extension String {
  fileprivate func prefixString(_ count: Int) -> String {
    String(prefix(count))
  }
}

extension Data {
  fileprivate func hermesSystemEventBase64URLEncodedString() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
