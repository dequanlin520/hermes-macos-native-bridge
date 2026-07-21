import Foundation

public enum HermesRuntimeSessionManagerError: Error, Equatable, Sendable, CustomStringConvertible {
  case sessionNotFound(UUID)
  case sessionNotStopped(UUID)

  public var description: String {
    switch self {
    case .sessionNotFound(let sessionID):
      return "Hermes runtime session \(sessionID) was not found"
    case .sessionNotStopped(let sessionID):
      return "Hermes runtime session \(sessionID) must be stopped before removal"
    }
  }
}

public final class HermesRuntimeSessionManager: @unchecked Sendable {
  public typealias BackendFactory = @Sendable () -> HermesBackendAdapting
  public typealias SessionIDFactory = @Sendable () -> UUID
  public typealias Clock = @Sendable () -> Date

  private let backendFactory: BackendFactory
  private let sessionIDFactory: SessionIDFactory
  private let clock: Clock
  public let eventBus: HermesRuntimeEventBus
  private let lock = NSLock()
  private var sessions: [UUID: HermesRuntimeSession] = [:]

  public init(
    backendFactory: @escaping BackendFactory,
    sessionIDFactory: @escaping SessionIDFactory = UUID.init,
    clock: @escaping Clock = Date.init,
    eventBus: HermesRuntimeEventBus = HermesRuntimeEventBus()
  ) {
    self.backendFactory = backendFactory
    self.sessionIDFactory = sessionIDFactory
    self.clock = clock
    self.eventBus = eventBus
  }

  @discardableResult
  public func createSession() -> HermesRuntimeSessionSnapshot {
    let sessionID = sessionIDFactory()
    let session = HermesRuntimeSession(
      sessionID: sessionID,
      backend: backendFactory(),
      clock: clock
    )
    lock.withLock {
      sessions[sessionID] = session
    }
    let snapshot = session.snapshot()
    publish(.sessionCreated, snapshot: snapshot)
    return snapshot
  }

  @discardableResult
  public func startSession(_ sessionID: UUID) async throws -> HermesRuntimeSessionSnapshot {
    let session = try session(for: sessionID)
    let beforeStart = session.snapshot()
    if beforeStart.currentStatus == .created {
      publish(.sessionStarting, snapshot: beforeStart, currentStatus: .starting)
    }

    do {
      let snapshot = try await session.start()
      if snapshot.currentStatus == .running {
        publish(.sessionRunning, snapshot: snapshot)
      } else if snapshot.currentStatus == .degraded {
        publish(.sessionHealthChanged, snapshot: snapshot)
      }
      return snapshot
    } catch {
      let snapshot = session.snapshot()
      if snapshot.currentStatus == .failed {
        publish(.sessionFailed, snapshot: snapshot)
      }
      throw error
    }
  }

  public func getSession(_ sessionID: UUID) throws -> HermesRuntimeSessionSnapshot {
    try session(for: sessionID).snapshot()
  }

  public func listSessions() -> [HermesRuntimeSessionSnapshot] {
    lock.withLock { Array(sessions.values) }
      .map { $0.snapshot() }
      .sorted { $0.sessionID.uuidString < $1.sessionID.uuidString }
  }

  @discardableResult
  public func refreshSessionStatus(_ sessionID: UUID) async throws -> HermesRuntimeSessionSnapshot {
    let session = try session(for: sessionID)
    do {
      let snapshot = try await session.refreshStatus()
      publish(.sessionHealthChanged, snapshot: snapshot)
      return snapshot
    } catch {
      let snapshot = session.snapshot()
      if snapshot.currentStatus == .degraded {
        publish(.sessionHealthChanged, snapshot: snapshot)
      } else if snapshot.currentStatus == .failed {
        publish(.sessionFailed, snapshot: snapshot)
      }
      throw error
    }
  }

  @discardableResult
  public func stopSession(
    _ sessionID: UUID,
    reason: HermesRuntimeSessionShutdownReason = .requested
  ) async throws -> HermesRuntimeSessionSnapshot {
    let session = try session(for: sessionID)
    let beforeStop = session.snapshot()
    switch beforeStop.currentStatus {
    case .running, .degraded, .starting, .stopping:
      publish(.sessionStopping, snapshot: beforeStop, currentStatus: .stopping)
    case .created, .failed, .stopped:
      break
    }

    do {
      let snapshot = try await session.stop(reason: reason)
      if snapshot.currentStatus == .stopped {
        publish(.sessionStopped, snapshot: snapshot)
      }
      return snapshot
    } catch {
      let snapshot = session.snapshot()
      if snapshot.currentStatus == .failed {
        publish(.sessionFailed, snapshot: snapshot)
      }
      throw error
    }
  }

  @discardableResult
  public func removeSession(_ sessionID: UUID) throws -> HermesRuntimeSessionSnapshot {
    let session = try session(for: sessionID)
    let snapshot = session.snapshot()
    guard snapshot.currentStatus == .stopped else {
      throw HermesRuntimeSessionManagerError.sessionNotStopped(sessionID)
    }
    _ = lock.withLock {
      sessions.removeValue(forKey: sessionID)
    }
    return snapshot
  }

  private func session(for sessionID: UUID) throws -> HermesRuntimeSession {
    guard let session = lock.withLock({ sessions[sessionID] }) else {
      throw HermesRuntimeSessionManagerError.sessionNotFound(sessionID)
    }
    return session
  }

  private func publish(
    _ kind: HermesRuntimeEventKind,
    snapshot: HermesRuntimeSessionSnapshot,
    currentStatus: HermesRuntimeSessionStatus? = nil
  ) {
    eventBus.publish(
      HermesRuntimeEvent(
        kind: kind,
        session: HermesRuntimeEventSessionSummary(
          snapshot: snapshot,
          currentStatus: currentStatus
        )
      )
    )
  }
}
