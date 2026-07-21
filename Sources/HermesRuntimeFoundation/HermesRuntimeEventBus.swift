import Foundation

public enum HermesRuntimeEventKind: String, Equatable, Sendable {
  case sessionCreated
  case sessionStarting
  case sessionRunning
  case sessionHealthChanged
  case sessionFailed
  case sessionStopping
  case sessionStopped
}

public struct HermesRuntimeEventSessionSummary: Equatable, Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  public let sessionID: UUID
  public let currentStatus: HermesRuntimeSessionStatus
  public let backendVersion: String?
  public let processID: Int32?
  public let startTime: Date?
  public let capabilities: HermesRuntimeCapabilities?
  public let lastErrorMessage: String?
  public let shutdownReason: HermesRuntimeSessionShutdownReason?

  public init(
    snapshot: HermesRuntimeSessionSnapshot,
    currentStatus: HermesRuntimeSessionStatus? = nil
  ) {
    sessionID = snapshot.sessionID
    self.currentStatus = currentStatus ?? snapshot.currentStatus
    backendVersion = snapshot.backendIdentity?.semanticVersion
    processID = snapshot.processIdentity?.pid
    startTime = snapshot.startTime
    capabilities = snapshot.capabilities
    lastErrorMessage = snapshot.lastError.map { Self.redact($0.description) }
    shutdownReason = snapshot.shutdownReason
  }

  public var description: String {
    let versionDescription = backendVersion ?? "unknown"
    let pidDescription = processID.map(String.init) ?? "none"
    let errorDescription = lastErrorMessage ?? "none"
    let shutdownDescription = shutdownReason?.description ?? "none"
    return
      "HermesRuntimeEventSessionSummary(sessionID: \(sessionID), version: \(versionDescription), pid: \(pidDescription), status: \(currentStatus.rawValue), error: \(errorDescription), shutdown: \(shutdownDescription))"
  }

  public var debugDescription: String {
    description
  }

  private static func redact(_ message: String) -> String {
    var sanitized = HermesBackendAdapter.redactedMessage(for: RuntimeEventRedactionError(message: message))

    let pathPattern = #"/(?:Users|private|var|tmp)/[^\s,"')]+"#
    if let regex = try? NSRegularExpression(pattern: pathPattern) {
      let range = NSRange(sanitized.startIndex..<sanitized.endIndex, in: sanitized)
      sanitized = regex.stringByReplacingMatches(
        in: sanitized,
        range: range,
        withTemplate: "<redacted-path>"
      )
    }

    return sanitized
  }
}

public struct HermesRuntimeEvent: Equatable, Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  public let sequenceNumber: UInt64
  public let kind: HermesRuntimeEventKind
  public let session: HermesRuntimeEventSessionSummary
  public let occurredAt: Date

  public init(
    sequenceNumber: UInt64 = 0,
    kind: HermesRuntimeEventKind,
    session: HermesRuntimeEventSessionSummary,
    occurredAt: Date = Date()
  ) {
    self.sequenceNumber = sequenceNumber
    self.kind = kind
    self.session = session
    self.occurredAt = occurredAt
  }

  public var description: String {
    "HermesRuntimeEvent(sequence: \(sequenceNumber), kind: \(kind.rawValue), session: \(session))"
  }

  public var debugDescription: String {
    description
  }

  fileprivate func sequenced(_ sequenceNumber: UInt64) -> HermesRuntimeEvent {
    HermesRuntimeEvent(
      sequenceNumber: sequenceNumber,
      kind: kind,
      session: session,
      occurredAt: occurredAt
    )
  }
}

public struct HermesRuntimeEventSubscription: Sendable {
  public let id: UUID
  public let events: AsyncStream<HermesRuntimeEvent>
}

public final class HermesRuntimeEventBus: @unchecked Sendable {
  public typealias SubscriptionIDFactory = @Sendable () -> UUID

  private let subscriptionIDFactory: SubscriptionIDFactory
  private let lock = NSLock()
  private var nextSequenceNumber: UInt64 = 0
  private var subscribers: [UUID: AsyncStream<HermesRuntimeEvent>.Continuation] = [:]

  public init(subscriptionIDFactory: @escaping SubscriptionIDFactory = UUID.init) {
    self.subscriptionIDFactory = subscriptionIDFactory
  }

  public func publish(_ event: HermesRuntimeEvent) {
    let delivery: (event: HermesRuntimeEvent, continuations: [AsyncStream<HermesRuntimeEvent>.Continuation]) =
      lock.withLock {
        nextSequenceNumber += 1
        return (event.sequenced(nextSequenceNumber), Array(subscribers.values))
      }

    for continuation in delivery.continuations {
      continuation.yield(delivery.event)
    }
  }

  public func subscribe(
    bufferingPolicy: AsyncStream<HermesRuntimeEvent>.Continuation.BufferingPolicy = .unbounded
  ) -> HermesRuntimeEventSubscription {
    let subscriptionID = subscriptionIDFactory()
    let stream = AsyncStream<HermesRuntimeEvent>(bufferingPolicy: bufferingPolicy) { continuation in
      lock.withLock {
        subscribers[subscriptionID] = continuation
      }
      continuation.onTermination = { [weak self] _ in
        self?.unsubscribe(subscriptionID)
      }
    }

    return HermesRuntimeEventSubscription(id: subscriptionID, events: stream)
  }

  public func unsubscribe(_ subscriptionID: UUID) {
    let continuation = lock.withLock {
      subscribers.removeValue(forKey: subscriptionID)
    }
    continuation?.finish()
  }

  func subscriberCount() -> Int {
    lock.withLock { subscribers.count }
  }
}

private struct RuntimeEventRedactionError: Error, CustomStringConvertible {
  let message: String

  var description: String {
    message
  }
}
