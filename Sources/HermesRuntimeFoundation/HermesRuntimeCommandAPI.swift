import Foundation

public protocol HermesRuntimeSessionManaging: Sendable {
  var eventBus: HermesRuntimeEventBus { get }

  @discardableResult
  func createSession() -> HermesRuntimeSessionSnapshot

  @discardableResult
  func startSession(_ sessionID: UUID) async throws -> HermesRuntimeSessionSnapshot

  func getSession(_ sessionID: UUID) throws -> HermesRuntimeSessionSnapshot

  @discardableResult
  func stopSession(
    _ sessionID: UUID,
    reason: HermesRuntimeSessionShutdownReason
  ) async throws -> HermesRuntimeSessionSnapshot
}

extension HermesRuntimeSessionManager: HermesRuntimeSessionManaging {}

public enum HermesRuntimeCommand: Equatable, Sendable {
  case createSession
  case startSession(UUID)
  case stopSession(UUID, reason: HermesRuntimeSessionShutdownReason = .requested)
  case getSessionStatus(UUID)
  case subscribeEvents
}

public enum HermesRuntimeCommandAPIError: Error, Equatable, Sendable, CustomStringConvertible {
  case sessionManager(HermesRuntimeSessionManagerError)
  case session(HermesRuntimeSessionErrorCode)
  case backendAdapter(HermesBackendAdapterError)
  case operationFailed(String)

  public var description: String {
    switch self {
    case .sessionManager(let error):
      return error.description
    case .session(let error):
      return error.description
    case .backendAdapter(let error):
      return error.description
    case .operationFailed(let message):
      return message
    }
  }

  static func wrapping(_ error: Error) -> HermesRuntimeCommandAPIError {
    if let error = error as? HermesRuntimeCommandAPIError {
      return error
    }
    if let error = error as? HermesRuntimeSessionManagerError {
      return .sessionManager(error)
    }
    if let error = error as? HermesRuntimeSessionErrorCode {
      return .session(error)
    }
    if let error = error as? HermesBackendAdapterError {
      return .backendAdapter(error)
    }
    return .operationFailed(HermesBackendAdapter.redactedMessage(for: error))
  }
}

public struct HermesRuntimeCommandSessionStatus: Equatable, Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  public let sessionID: UUID
  public let currentStatus: HermesRuntimeSessionStatus
  public let backendVersion: String?
  public let startTime: Date?
  public let capabilities: HermesRuntimeCapabilities?
  public let lastErrorMessage: String?
  public let shutdownReason: HermesRuntimeSessionShutdownReason?

  public init(snapshot: HermesRuntimeSessionSnapshot) {
    sessionID = snapshot.sessionID
    currentStatus = snapshot.currentStatus
    backendVersion = snapshot.backendIdentity?.semanticVersion
    startTime = snapshot.startTime
    capabilities = snapshot.capabilities
    lastErrorMessage = snapshot.lastError?.description
    shutdownReason = snapshot.shutdownReason
  }

  public var description: String {
    let versionDescription = backendVersion ?? "unknown"
    let errorDescription = lastErrorMessage ?? "none"
    let shutdownDescription = shutdownReason?.description ?? "none"
    return
      "HermesRuntimeCommandSessionStatus(sessionID: \(sessionID), version: \(versionDescription), status: \(currentStatus.rawValue), error: \(errorDescription), shutdown: \(shutdownDescription))"
  }

  public var debugDescription: String {
    description
  }
}

public struct HermesRuntimeCommandEvent: Equatable, Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  public let sequenceNumber: UInt64
  public let kind: HermesRuntimeEventKind
  public let session: HermesRuntimeCommandEventSession
  public let occurredAt: Date

  public init(event: HermesRuntimeEvent) {
    sequenceNumber = event.sequenceNumber
    kind = event.kind
    session = HermesRuntimeCommandEventSession(eventSession: event.session)
    occurredAt = event.occurredAt
  }

  public var description: String {
    "HermesRuntimeCommandEvent(sequence: \(sequenceNumber), kind: \(kind.rawValue), session: \(session))"
  }

  public var debugDescription: String {
    description
  }
}

public struct HermesRuntimeCommandEventSession: Equatable, Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  public let sessionID: UUID
  public let currentStatus: HermesRuntimeSessionStatus
  public let backendVersion: String?
  public let startTime: Date?
  public let capabilities: HermesRuntimeCapabilities?
  public let lastErrorMessage: String?
  public let shutdownReason: HermesRuntimeSessionShutdownReason?

  public init(eventSession: HermesRuntimeEventSessionSummary) {
    sessionID = eventSession.sessionID
    currentStatus = eventSession.currentStatus
    backendVersion = eventSession.backendVersion
    startTime = eventSession.startTime
    capabilities = eventSession.capabilities
    lastErrorMessage = eventSession.lastErrorMessage
    shutdownReason = eventSession.shutdownReason
  }

  public var description: String {
    let versionDescription = backendVersion ?? "unknown"
    let errorDescription = lastErrorMessage ?? "none"
    let shutdownDescription = shutdownReason?.description ?? "none"
    return
      "HermesRuntimeCommandEventSession(sessionID: \(sessionID), version: \(versionDescription), status: \(currentStatus.rawValue), error: \(errorDescription), shutdown: \(shutdownDescription))"
  }

  public var debugDescription: String {
    description
  }
}

public struct HermesRuntimeCommandEventSubscription: Sendable {
  public let id: UUID
  public let events: AsyncStream<HermesRuntimeCommandEvent>
}

public enum HermesRuntimeCommandResult: Sendable {
  case sessionStatus(HermesRuntimeCommandSessionStatus)
  case eventSubscription(HermesRuntimeCommandEventSubscription)
}

public final class HermesRuntimeCommandAPI: @unchecked Sendable {
  private let sessionManager: HermesRuntimeSessionManaging

  public init(sessionManager: HermesRuntimeSessionManaging) {
    self.sessionManager = sessionManager
  }

  @discardableResult
  public func execute(_ command: HermesRuntimeCommand) async throws -> HermesRuntimeCommandResult {
    switch command {
    case .createSession:
      return .sessionStatus(createSession())
    case .startSession(let sessionID):
      return .sessionStatus(try await startSession(sessionID))
    case .stopSession(let sessionID, let reason):
      return .sessionStatus(try await stopSession(sessionID, reason: reason))
    case .getSessionStatus(let sessionID):
      return .sessionStatus(try getSessionStatus(sessionID))
    case .subscribeEvents:
      return .eventSubscription(subscribeEvents())
    }
  }

  @discardableResult
  public func createSession() -> HermesRuntimeCommandSessionStatus {
    HermesRuntimeCommandSessionStatus(snapshot: sessionManager.createSession())
  }

  @discardableResult
  public func startSession(_ sessionID: UUID) async throws -> HermesRuntimeCommandSessionStatus {
    do {
      return HermesRuntimeCommandSessionStatus(snapshot: try await sessionManager.startSession(sessionID))
    } catch {
      throw HermesRuntimeCommandAPIError.wrapping(error)
    }
  }

  @discardableResult
  public func stopSession(
    _ sessionID: UUID,
    reason: HermesRuntimeSessionShutdownReason = .requested
  ) async throws -> HermesRuntimeCommandSessionStatus {
    do {
      return HermesRuntimeCommandSessionStatus(
        snapshot: try await sessionManager.stopSession(sessionID, reason: reason)
      )
    } catch {
      throw HermesRuntimeCommandAPIError.wrapping(error)
    }
  }

  public func getSessionStatus(_ sessionID: UUID) throws -> HermesRuntimeCommandSessionStatus {
    do {
      return HermesRuntimeCommandSessionStatus(snapshot: try sessionManager.getSession(sessionID))
    } catch {
      throw HermesRuntimeCommandAPIError.wrapping(error)
    }
  }

  public func subscribeEvents(
    bufferingPolicy: AsyncStream<HermesRuntimeCommandEvent>.Continuation.BufferingPolicy = .unbounded
  ) -> HermesRuntimeCommandEventSubscription {
    let sourceSubscription = sessionManager.eventBus.subscribe()
    let stream = AsyncStream<HermesRuntimeCommandEvent>(bufferingPolicy: bufferingPolicy) { continuation in
      let task = Task {
        var iterator = sourceSubscription.events.makeAsyncIterator()
        while let event = await iterator.next() {
          continuation.yield(HermesRuntimeCommandEvent(event: event))
        }
        continuation.finish()
      }
      continuation.onTermination = { [eventBus = sessionManager.eventBus] _ in
        task.cancel()
        eventBus.unsubscribe(sourceSubscription.id)
      }
    }
    return HermesRuntimeCommandEventSubscription(id: sourceSubscription.id, events: stream)
  }
}
