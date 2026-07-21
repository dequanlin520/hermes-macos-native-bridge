import Foundation

public enum HermesRuntimeSessionStatus: String, Equatable, Sendable {
  case created
  case starting
  case running
  case degraded
  case stopping
  case stopped
  case failed
}

public enum HermesRuntimeSessionShutdownReason: Equatable, Sendable, CustomStringConvertible {
  case requested
  case startupFailed
  case shutdownFailed

  public var description: String {
    switch self {
    case .requested:
      return "requested"
    case .startupFailed:
      return "startup failed"
    case .shutdownFailed:
      return "shutdown failed"
    }
  }
}

public struct HermesRuntimeSessionError: Equatable, Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  public let message: String

  public init(message: String) {
    self.message = Self.redact(message)
  }

  public init(_ error: Error) {
    message = Self.redact(String(describing: error))
  }

  public var description: String {
    message
  }

  public var debugDescription: String {
    description
  }

  private static func redact(_ message: String) -> String {
    HermesBackendAdapter.redactedMessage(for: RuntimeSessionRedactionError(message: message))
  }
}

public struct HermesRuntimeBackendIdentity: Equatable, Sendable, CustomStringConvertible {
  public let executablePath: String
  public let semanticVersion: String
  public let displayVersion: String
  public let installationMethod: String?
  public let releaseDate: String?
  public let desktopContract: Int?

  public init(
    executablePath: String,
    semanticVersion: String,
    displayVersion: String,
    installationMethod: String?,
    releaseDate: String?,
    desktopContract: Int?
  ) {
    self.executablePath = executablePath
    self.semanticVersion = semanticVersion
    self.displayVersion = displayVersion
    self.installationMethod = installationMethod
    self.releaseDate = releaseDate
    self.desktopContract = desktopContract
  }

  init(discovery: HermesDiscoveryResult, status: HermesBackendStatus) {
    self.init(
      executablePath: discovery.candidate.resolvedPath,
      semanticVersion: discovery.versionInfo.semanticVersion,
      displayVersion: discovery.versionInfo.displayVersion,
      installationMethod: discovery.versionInfo.installationMethod,
      releaseDate: status.releaseDate,
      desktopContract: status.desktopContract
    )
  }

  public var description: String {
    "HermesRuntimeBackendIdentity(version: \(semanticVersion), executable: \(executablePath))"
  }
}

public struct HermesRuntimeCapabilities: Equatable, Sendable {
  public let authMode: HermesBackendAuthMode?
  public let desktopContract: Int?
  public let gatewayRunning: Bool?
  public let gatewayState: String?
  public let gatewayBusy: Bool?
  public let gatewayDrainable: Bool?
  public let activeAgents: Int?

  public init(
    authMode: HermesBackendAuthMode?,
    desktopContract: Int?,
    gatewayRunning: Bool?,
    gatewayState: String?,
    gatewayBusy: Bool?,
    gatewayDrainable: Bool?,
    activeAgents: Int?
  ) {
    self.authMode = authMode
    self.desktopContract = desktopContract
    self.gatewayRunning = gatewayRunning
    self.gatewayState = gatewayState
    self.gatewayBusy = gatewayBusy
    self.gatewayDrainable = gatewayDrainable
    self.activeAgents = activeAgents
  }

  init(status: HermesBackendStatus) {
    self.init(
      authMode: status.authMode,
      desktopContract: status.desktopContract,
      gatewayRunning: status.gatewayRunning,
      gatewayState: status.gatewayState,
      gatewayBusy: status.gatewayBusy,
      gatewayDrainable: status.gatewayDrainable,
      activeAgents: status.activeAgents
    )
  }
}

public struct HermesRuntimeSessionSnapshot: Equatable, Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  public let sessionID: UUID
  public let backendIdentity: HermesRuntimeBackendIdentity?
  public let processIdentity: HermesProcessIdentity?
  public let startTime: Date?
  public let currentStatus: HermesRuntimeSessionStatus
  public let capabilities: HermesRuntimeCapabilities?
  public let lastError: HermesRuntimeSessionError?
  public let shutdownReason: HermesRuntimeSessionShutdownReason?

  public var description: String {
    let pidDescription = processIdentity.map { String($0.pid) } ?? "none"
    let backendDescription = backendIdentity?.semanticVersion ?? "unknown"
    let errorDescription = lastError?.description ?? "none"
    let shutdownDescription = shutdownReason?.description ?? "none"
    return
      "HermesRuntimeSessionSnapshot(sessionID: \(sessionID), backend: \(backendDescription), pid: \(pidDescription), status: \(currentStatus.rawValue), error: \(errorDescription), shutdown: \(shutdownDescription))"
  }

  public var debugDescription: String {
    description
  }
}

public enum HermesRuntimeSessionErrorCode: Error, Equatable, Sendable, CustomStringConvertible {
  case invalidTransition(from: HermesRuntimeSessionStatus, operation: String)
  case sessionNotStopped(UUID)

  public var description: String {
    switch self {
    case .invalidTransition(let status, let operation):
      return "cannot \(operation) Hermes runtime session while \(status.rawValue)"
    case .sessionNotStopped(let sessionID):
      return "Hermes runtime session \(sessionID) must be stopped before removal"
    }
  }
}

public final class HermesRuntimeSession: @unchecked Sendable {
  public let sessionID: UUID

  private let backend: HermesBackendAdapting
  private let clock: @Sendable () -> Date
  private let lock = NSLock()
  private var storage: HermesRuntimeSessionSnapshot

  public init(
    sessionID: UUID = UUID(),
    backend: HermesBackendAdapting,
    clock: @escaping @Sendable () -> Date = Date.init
  ) {
    self.sessionID = sessionID
    self.backend = backend
    self.clock = clock
    storage = HermesRuntimeSessionSnapshot(
      sessionID: sessionID,
      backendIdentity: nil,
      processIdentity: nil,
      startTime: nil,
      currentStatus: .created,
      capabilities: nil,
      lastError: nil,
      shutdownReason: nil
    )
  }

  public func snapshot() -> HermesRuntimeSessionSnapshot {
    lock.withLock { storage }
  }

  @discardableResult
  public func start() async throws -> HermesRuntimeSessionSnapshot {
    let startTime = clock()
    try lock.withLock {
      switch storage.currentStatus {
      case .created:
        storage = replacing(status: .starting, startTime: startTime)
      case .running, .degraded:
        return
      case .starting, .stopping, .stopped, .failed:
        throw HermesRuntimeSessionErrorCode.invalidTransition(
          from: storage.currentStatus,
          operation: "start"
        )
      }
    }

    do {
      let result = try await backend.start()
      return lock.withLock {
        storage = HermesRuntimeSessionSnapshot(
          sessionID: sessionID,
          backendIdentity: HermesRuntimeBackendIdentity(
            discovery: result.discovery,
            status: result.initialStatus
          ),
          processIdentity: result.launch.identity,
          startTime: startTime,
          currentStatus: Self.runtimeStatus(for: result.initialStatus),
          capabilities: HermesRuntimeCapabilities(status: result.initialStatus),
          lastError: nil,
          shutdownReason: nil
        )
        return storage
      }
    } catch {
      let sessionError = HermesRuntimeSessionError(error)
      lock.withLock {
        storage = HermesRuntimeSessionSnapshot(
          sessionID: sessionID,
          backendIdentity: storage.backendIdentity,
          processIdentity: storage.processIdentity,
          startTime: startTime,
          currentStatus: .failed,
          capabilities: storage.capabilities,
          lastError: sessionError,
          shutdownReason: .startupFailed
        )
      }
      throw error
    }
  }

  @discardableResult
  public func refreshStatus() async throws -> HermesRuntimeSessionSnapshot {
    try lock.withLock {
      switch storage.currentStatus {
      case .running, .degraded:
        return
      case .created, .starting, .stopping, .stopped, .failed:
        throw HermesRuntimeSessionErrorCode.invalidTransition(
          from: storage.currentStatus,
          operation: "refresh"
        )
      }
    }

    do {
      let health = try await backend.health()
      return lock.withLock {
        storage = HermesRuntimeSessionSnapshot(
          sessionID: sessionID,
          backendIdentity: storage.backendIdentity,
          processIdentity: processIdentity(from: health.processState) ?? storage.processIdentity,
          startTime: storage.startTime,
          currentStatus: Self.runtimeStatus(for: health),
          capabilities: HermesRuntimeCapabilities(status: health.status),
          lastError: nil,
          shutdownReason: nil
        )
        return storage
      }
    } catch {
      let sessionError = HermesRuntimeSessionError(error)
      lock.withLock {
        storage = HermesRuntimeSessionSnapshot(
          sessionID: sessionID,
          backendIdentity: storage.backendIdentity,
          processIdentity: storage.processIdentity,
          startTime: storage.startTime,
          currentStatus: .degraded,
          capabilities: storage.capabilities,
          lastError: sessionError,
          shutdownReason: storage.shutdownReason
        )
      }
      throw error
    }
  }

  @discardableResult
  public func stop(
    reason: HermesRuntimeSessionShutdownReason = .requested
  ) async throws -> HermesRuntimeSessionSnapshot {
    let shouldStopBackend: Bool = lock.withLock {
      switch storage.currentStatus {
      case .stopped:
        return false
      case .created, .failed:
        storage = replacing(status: .stopped, shutdownReason: reason)
        return false
      case .running, .degraded, .starting, .stopping:
        storage = replacing(status: .stopping)
        return true
      }
    }

    guard shouldStopBackend else {
      return snapshot()
    }

    do {
      _ = try await backend.stop()
      return lock.withLock {
        storage = HermesRuntimeSessionSnapshot(
          sessionID: sessionID,
          backendIdentity: storage.backendIdentity,
          processIdentity: storage.processIdentity,
          startTime: storage.startTime,
          currentStatus: .stopped,
          capabilities: storage.capabilities,
          lastError: nil,
          shutdownReason: reason
        )
        return storage
      }
    } catch {
      let sessionError = HermesRuntimeSessionError(error)
      lock.withLock {
        storage = HermesRuntimeSessionSnapshot(
          sessionID: sessionID,
          backendIdentity: storage.backendIdentity,
          processIdentity: storage.processIdentity,
          startTime: storage.startTime,
          currentStatus: .failed,
          capabilities: storage.capabilities,
          lastError: sessionError,
          shutdownReason: .shutdownFailed
        )
      }
      throw error
    }
  }

  private func replacing(
    status: HermesRuntimeSessionStatus,
    startTime: Date? = nil,
    shutdownReason: HermesRuntimeSessionShutdownReason? = nil
  ) -> HermesRuntimeSessionSnapshot {
    HermesRuntimeSessionSnapshot(
      sessionID: sessionID,
      backendIdentity: storage.backendIdentity,
      processIdentity: storage.processIdentity,
      startTime: startTime ?? storage.startTime,
      currentStatus: status,
      capabilities: storage.capabilities,
      lastError: storage.lastError,
      shutdownReason: shutdownReason ?? storage.shutdownReason
    )
  }

  private static func runtimeStatus(for status: HermesBackendStatus) -> HermesRuntimeSessionStatus {
    if status.gatewayRunning == false {
      return .degraded
    }
    return .running
  }

  private static func runtimeStatus(
    for health: HermesBackendHealthSnapshot
  ) -> HermesRuntimeSessionStatus {
    if case .failed = health.processState {
      return .degraded
    }
    if case .failed = health.protocolState {
      return .degraded
    }
    return runtimeStatus(for: health.status)
  }

  private func processIdentity(from state: HermesProcessState) -> HermesProcessIdentity? {
    switch state {
    case .ready(let identity), .stopping(let identity):
      return identity
    case .idle, .starting, .exited, .failed:
      return nil
    }
  }
}

private struct RuntimeSessionRedactionError: Error, CustomStringConvertible {
  let message: String

  var description: String {
    message
  }
}
