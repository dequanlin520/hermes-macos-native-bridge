import Foundation
import HermesRuntimeFoundation

public protocol HermesDashboardRuntimeCommandExecuting: Sendable {
  @discardableResult
  func execute(_ command: HermesRuntimeCommand) async throws -> HermesRuntimeCommandResult
}

extension HermesRuntimeCommandAPI: HermesDashboardRuntimeCommandExecuting {}

public enum HermesDashboardHealthState: String, Equatable, Sendable {
  case unavailable
  case healthy
  case degraded
  case failed
  case stopped
}

public struct HermesDashboardSessionSummary: Equatable, Sendable {
  public let status: HermesRuntimeSessionStatus
  public let startedAt: Date?
  public let shutdownReason: String?

  public init(status: HermesRuntimeCommandSessionStatus) {
    self.status = status.currentStatus
    self.startedAt = status.startTime
    self.shutdownReason = status.shutdownReason?.description
  }

  public init(eventSession: HermesRuntimeCommandEventSession) {
    self.status = eventSession.currentStatus
    self.startedAt = eventSession.startTime
    self.shutdownReason = eventSession.shutdownReason?.description
  }
}

public struct HermesDashboardBackendHealthSummary: Equatable, Sendable {
  public let healthState: HermesDashboardHealthState
  public let backendVersion: String?
  public let gatewayState: String?
  public let gatewayRunning: Bool?
  public let gatewayBusy: Bool?
  public let gatewayDrainable: Bool?
  public let activeAgentCount: Int?
  public let desktopContract: Int?

  public init(status: HermesRuntimeCommandSessionStatus) {
    let capabilities = status.capabilities
    self.healthState = Self.healthState(status: status.currentStatus, capabilities: capabilities)
    self.backendVersion = status.backendVersion.map(Self.safeToken)
    self.gatewayState = capabilities?.gatewayState.map(Self.safeToken)
    self.gatewayRunning = capabilities?.gatewayRunning
    self.gatewayBusy = capabilities?.gatewayBusy
    self.gatewayDrainable = capabilities?.gatewayDrainable
    self.activeAgentCount = capabilities?.activeAgents
    self.desktopContract = capabilities?.desktopContract
  }

  public init(eventSession: HermesRuntimeCommandEventSession) {
    let capabilities = eventSession.capabilities
    self.healthState = Self.healthState(status: eventSession.currentStatus, capabilities: capabilities)
    self.backendVersion = eventSession.backendVersion.map(Self.safeToken)
    self.gatewayState = capabilities?.gatewayState.map(Self.safeToken)
    self.gatewayRunning = capabilities?.gatewayRunning
    self.gatewayBusy = capabilities?.gatewayBusy
    self.gatewayDrainable = capabilities?.gatewayDrainable
    self.activeAgentCount = capabilities?.activeAgents
    self.desktopContract = capabilities?.desktopContract
  }

  private static func healthState(
    status: HermesRuntimeSessionStatus,
    capabilities: HermesRuntimeCapabilities?
  ) -> HermesDashboardHealthState {
    switch status {
    case .running:
      return capabilities?.gatewayRunning == false ? .degraded : .healthy
    case .degraded:
      return .degraded
    case .failed:
      return .failed
    case .created, .starting, .stopping, .stopped:
      return .stopped
    }
  }

  private static func safeToken(_ value: String) -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-")
    }
    return String(filtered.prefix(80))
  }
}

public struct HermesDashboardRuntimeEventViewState: Equatable, Identifiable, Sendable {
  public let id: UInt64
  public let kind: HermesRuntimeEventKind
  public let status: HermesRuntimeSessionStatus
  public let occurredAt: Date
  public let lastErrorMessage: String?

  public init(event: HermesRuntimeCommandEvent) {
    self.id = event.sequenceNumber
    self.kind = event.kind
    self.status = event.session.currentStatus
    self.occurredAt = event.occurredAt
    self.lastErrorMessage = event.session.lastErrorMessage.map(Self.safeText)
  }

  private static func safeText(_ value: String) -> String {
    HermesDashboardController.safeDisplayText(value, limit: 160)
  }
}

public struct HermesDashboardState: Equatable, Sendable {
  public var runtimeStatus: HermesRuntimeSessionStatus?
  public var sessionSummary: HermesDashboardSessionSummary?
  public var backendHealthSummary: HermesDashboardBackendHealthSummary?
  public var recentEvents: [HermesDashboardRuntimeEventViewState]
  public var lastErrorMessage: String?
  public var isLoading: Bool
  public var actionInFlight: Bool

  public init(
    runtimeStatus: HermesRuntimeSessionStatus? = nil,
    sessionSummary: HermesDashboardSessionSummary? = nil,
    backendHealthSummary: HermesDashboardBackendHealthSummary? = nil,
    recentEvents: [HermesDashboardRuntimeEventViewState] = [],
    lastErrorMessage: String? = nil,
    isLoading: Bool = false,
    actionInFlight: Bool = false
  ) {
    self.runtimeStatus = runtimeStatus
    self.sessionSummary = sessionSummary
    self.backendHealthSummary = backendHealthSummary
    self.recentEvents = Array(recentEvents.prefix(20))
    self.lastErrorMessage = lastErrorMessage
    self.isLoading = isLoading
    self.actionInFlight = actionInFlight
  }
}

public actor HermesDashboardController {
  private let commandAPI: HermesDashboardRuntimeCommandExecuting
  private var state: HermesDashboardState
  private var currentSessionID: UUID?
  private var eventTask: Task<Void, Never>?

  public init(commandAPI: HermesDashboardRuntimeCommandExecuting) {
    self.commandAPI = commandAPI
    self.state = HermesDashboardState()
  }

  deinit {
    eventTask?.cancel()
  }

  public func currentState() -> HermesDashboardState {
    state
  }

  public func startEventSubscription(
    onStateChange: (@Sendable (HermesDashboardState) async -> Void)? = nil
  ) async {
    guard eventTask == nil else { return }
    do {
      let result = try await commandAPI.execute(.subscribeEvents)
      guard case .eventSubscription(let subscription) = result else {
        applyError("Runtime event subscription returned an unexpected result")
        await onStateChange?(state)
        return
      }
      eventTask = Task { [weak self] in
        for await event in subscription.events {
          await self?.record(event: event, onStateChange: onStateChange)
        }
      }
    } catch {
      applyError(Self.safeErrorMessage(error))
      await onStateChange?(state)
    }
  }

  @discardableResult
  public func load() async -> HermesDashboardState {
    state.isLoading = true
    _ = await refreshStatus()
    state.isLoading = false
    return state
  }

  @discardableResult
  public func startHermes() async -> HermesDashboardState {
    await runAction {
      let sessionID: UUID
      if let existingSessionID = currentSessionID {
        sessionID = existingSessionID
      } else {
        let created = try await sessionStatus(from: commandAPI.execute(.createSession))
        currentSessionID = created.sessionID
        sessionID = created.sessionID
        apply(status: created)
      }
      let started = try await sessionStatus(from: commandAPI.execute(.startSession(sessionID)))
      apply(status: started)
    }
  }

  @discardableResult
  public func stopHermes() async -> HermesDashboardState {
    await runAction {
      guard let sessionID = currentSessionID else {
        applyError("No Hermes runtime session is active")
        return
      }
      let stopped = try await sessionStatus(
        from: commandAPI.execute(.stopSession(sessionID, reason: .requested))
      )
      apply(status: stopped)
    }
  }

  @discardableResult
  public func restartHermes() async -> HermesDashboardState {
    await runAction {
      if let sessionID = currentSessionID {
        let stopped = try await sessionStatus(
          from: commandAPI.execute(.stopSession(sessionID, reason: .requested))
        )
        apply(status: stopped)
      }

      let created = try await sessionStatus(from: commandAPI.execute(.createSession))
      currentSessionID = created.sessionID
      apply(status: created)

      let started = try await sessionStatus(from: commandAPI.execute(.startSession(created.sessionID)))
      apply(status: started)
    }
  }

  @discardableResult
  public func refreshStatus() async -> HermesDashboardState {
    await runAction {
      guard let sessionID = currentSessionID else {
        let created = try await sessionStatus(from: commandAPI.execute(.createSession))
        currentSessionID = created.sessionID
        apply(status: created)
        return
      }
      let refreshed = try await sessionStatus(from: commandAPI.execute(.getSessionStatus(sessionID)))
      apply(status: refreshed)
    }
  }

  public func cancel() {
    eventTask?.cancel()
    eventTask = nil
  }

  private func runAction(_ action: () async throws -> Void) async -> HermesDashboardState {
    state.actionInFlight = true
    state.lastErrorMessage = nil
    do {
      try await action()
    } catch {
      applyError(Self.safeErrorMessage(error))
    }
    state.actionInFlight = false
    return state
  }

  private func record(
    event: HermesRuntimeCommandEvent,
    onStateChange: (@Sendable (HermesDashboardState) async -> Void)?
  ) async {
    currentSessionID = event.session.sessionID
    state.runtimeStatus = event.session.currentStatus
    state.sessionSummary = HermesDashboardSessionSummary(eventSession: event.session)
    state.backendHealthSummary = HermesDashboardBackendHealthSummary(eventSession: event.session)
    state.lastErrorMessage = event.session.lastErrorMessage.map(Self.safeErrorMessage)
    state.recentEvents.insert(HermesDashboardRuntimeEventViewState(event: event), at: 0)
    state.recentEvents = Array(state.recentEvents.prefix(20))
    await onStateChange?(state)
  }

  private func apply(status: HermesRuntimeCommandSessionStatus) {
    currentSessionID = status.sessionID
    state.runtimeStatus = status.currentStatus
    state.sessionSummary = HermesDashboardSessionSummary(status: status)
    state.backendHealthSummary = HermesDashboardBackendHealthSummary(status: status)
    state.lastErrorMessage = status.lastErrorMessage.map(Self.safeErrorMessage)
  }

  private func applyError(_ message: String) {
    state.lastErrorMessage = Self.safeErrorMessage(message)
    state.backendHealthSummary = state.backendHealthSummary?.failed()
      ?? HermesDashboardBackendHealthSummary.failedUnavailable()
  }

  private func sessionStatus(
    from result: HermesRuntimeCommandResult
  ) throws -> HermesRuntimeCommandSessionStatus {
    guard case .sessionStatus(let status) = result else {
      throw HermesDashboardControllerError.unexpectedRuntimeResult
    }
    return status
  }

  static func safeErrorMessage(_ error: Error) -> String {
    safeErrorMessage(String(describing: error))
  }

  static func safeErrorMessage(_ value: String) -> String {
    safeDisplayText(value, limit: 180)
  }

  static func safeDisplayText(_ value: String, limit: Int) -> String {
    var sanitized = value
    for marker in ["token=", "X-Hermes-Session-Token=", "HERMES_DASHBOARD_SESSION_TOKEN="] {
      var searchStart = sanitized.startIndex
      while searchStart < sanitized.endIndex,
        let range = sanitized.range(of: marker, range: searchStart..<sanitized.endIndex)
      {
        let valueStart = range.upperBound
        let valueEnd = sanitized[valueStart...].firstIndex {
          $0 == "&" || $0 == " " || $0 == "\n" || $0 == "\t" || $0 == ")" || $0 == ","
        } ?? sanitized.endIndex
        sanitized.replaceSubrange(valueStart..<valueEnd, with: "<redacted>")
        searchStart = sanitized.index(valueStart, offsetBy: "<redacted>".count)
      }
    }
    if let regex = try? NSRegularExpression(pattern: #"/(?:Users|private|var|tmp)/[^\s,"')]+"#) {
      let range = NSRange(sanitized.startIndex..<sanitized.endIndex, in: sanitized)
      sanitized = regex.stringByReplacingMatches(
        in: sanitized,
        range: range,
        withTemplate: "<redacted-path>"
      )
    }
    return String(sanitized.prefix(limit))
  }
}

extension HermesDashboardBackendHealthSummary {
  static func unavailable() -> HermesDashboardBackendHealthSummary {
    HermesDashboardBackendHealthSummary(
      healthState: .unavailable,
      backendVersion: nil,
      gatewayState: nil,
      gatewayRunning: nil,
      gatewayBusy: nil,
      gatewayDrainable: nil,
      activeAgentCount: nil,
      desktopContract: nil
    )
  }

  static func failedUnavailable() -> HermesDashboardBackendHealthSummary {
    HermesDashboardBackendHealthSummary(
      healthState: .failed,
      backendVersion: nil,
      gatewayState: nil,
      gatewayRunning: nil,
      gatewayBusy: nil,
      gatewayDrainable: nil,
      activeAgentCount: nil,
      desktopContract: nil
    )
  }

  func failed() -> HermesDashboardBackendHealthSummary {
    HermesDashboardBackendHealthSummary(
      healthState: .failed,
      backendVersion: backendVersion,
      gatewayState: gatewayState,
      gatewayRunning: gatewayRunning,
      gatewayBusy: gatewayBusy,
      gatewayDrainable: gatewayDrainable,
      activeAgentCount: activeAgentCount,
      desktopContract: desktopContract
    )
  }

  private init(
    healthState: HermesDashboardHealthState,
    backendVersion: String?,
    gatewayState: String?,
    gatewayRunning: Bool?,
    gatewayBusy: Bool?,
    gatewayDrainable: Bool?,
    activeAgentCount: Int?,
    desktopContract: Int?
  ) {
    self.healthState = healthState
    self.backendVersion = backendVersion
    self.gatewayState = gatewayState
    self.gatewayRunning = gatewayRunning
    self.gatewayBusy = gatewayBusy
    self.gatewayDrainable = gatewayDrainable
    self.activeAgentCount = activeAgentCount
    self.desktopContract = desktopContract
  }
}

private enum HermesDashboardControllerError: Error, CustomStringConvertible {
  case unexpectedRuntimeResult

  var description: String {
    "Runtime command returned an unexpected result"
  }
}
