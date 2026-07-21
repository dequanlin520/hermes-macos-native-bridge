import Foundation
import HermesRuntimeFoundation

public protocol HermesRuntimeCommandExecuting: Sendable {
  @discardableResult
  func execute(_ command: HermesRuntimeCommand) async throws -> HermesRuntimeCommandResult
}

extension HermesRuntimeCommandAPI: HermesRuntimeCommandExecuting {}

public enum HermesMenuBarHealthState: String, Equatable, Sendable {
  case unavailable
  case healthy
  case degraded
  case failed
  case stopped
}

public struct HermesMenuBarSessionSummary: Equatable, Sendable {
  public let status: HermesRuntimeSessionStatus
  public let backendVersion: String?
  public let startedAt: Date?
  public let shutdownReason: String?
  public let activeAgentCount: Int?
  public let gatewayState: String?

  public init(status: HermesRuntimeCommandSessionStatus) {
    self.status = status.currentStatus
    self.backendVersion = status.backendVersion.map(Self.safeToken)
    self.startedAt = status.startTime
    self.shutdownReason = status.shutdownReason?.description
    self.activeAgentCount = status.capabilities?.activeAgents
    self.gatewayState = status.capabilities?.gatewayState.map(Self.safeToken)
  }

  public init(eventSession: HermesRuntimeCommandEventSession) {
    self.status = eventSession.currentStatus
    self.backendVersion = eventSession.backendVersion.map(Self.safeToken)
    self.startedAt = eventSession.startTime
    self.shutdownReason = eventSession.shutdownReason?.description
    self.activeAgentCount = eventSession.capabilities?.activeAgents
    self.gatewayState = eventSession.capabilities?.gatewayState.map(Self.safeToken)
  }

  private static func safeToken(_ value: String) -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-")
    }
    return String(filtered.prefix(80))
  }
}

public struct HermesMenuBarRuntimeEventViewState: Equatable, Identifiable, Sendable {
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
    var sanitized = value
    if let regex = try? NSRegularExpression(pattern: #"/(?:Users|private|var|tmp)/[^\s,"')]+"#) {
      let range = NSRange(sanitized.startIndex..<sanitized.endIndex, in: sanitized)
      sanitized = regex.stringByReplacingMatches(
        in: sanitized,
        range: range,
        withTemplate: "<redacted-path>"
      )
    }
    return String(sanitized.prefix(160))
  }
}

public struct HermesMenuBarState: Equatable, Sendable {
  public var runtimeStatus: HermesRuntimeSessionStatus?
  public var sessionSummary: HermesMenuBarSessionSummary?
  public var healthState: HermesMenuBarHealthState
  public var recentEvents: [HermesMenuBarRuntimeEventViewState]
  public var lastErrorMessage: String?
  public var eventsViewOpenRequested: Bool
  public var actionInFlight: Bool

  public init(
    runtimeStatus: HermesRuntimeSessionStatus? = nil,
    sessionSummary: HermesMenuBarSessionSummary? = nil,
    healthState: HermesMenuBarHealthState = .unavailable,
    recentEvents: [HermesMenuBarRuntimeEventViewState] = [],
    lastErrorMessage: String? = nil,
    eventsViewOpenRequested: Bool = false,
    actionInFlight: Bool = false
  ) {
    self.runtimeStatus = runtimeStatus
    self.sessionSummary = sessionSummary
    self.healthState = healthState
    self.recentEvents = Array(recentEvents.prefix(10))
    self.lastErrorMessage = lastErrorMessage
    self.eventsViewOpenRequested = eventsViewOpenRequested
    self.actionInFlight = actionInFlight
  }
}

public actor HermesMenuBarController {
  private let commandAPI: HermesRuntimeCommandExecuting
  private var state: HermesMenuBarState
  private var currentSessionID: UUID?
  private var eventTask: Task<Void, Never>?

  public init(commandAPI: HermesRuntimeCommandExecuting) {
    self.commandAPI = commandAPI
    self.state = HermesMenuBarState()
  }

  deinit {
    eventTask?.cancel()
  }

  public func currentState() -> HermesMenuBarState {
    state
  }

  public func startEventSubscription(
    onStateChange: (@Sendable (HermesMenuBarState) async -> Void)? = nil
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
  public func startHermes() async -> HermesMenuBarState {
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
  public func stopHermes() async -> HermesMenuBarState {
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
  public func refreshStatus() async -> HermesMenuBarState {
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

  @discardableResult
  public func openEventsView() -> HermesMenuBarState {
    state.eventsViewOpenRequested = true
    return state
  }

  public func acknowledgeEventsViewRequest() {
    state.eventsViewOpenRequested = false
  }

  public func cancel() {
    eventTask?.cancel()
    eventTask = nil
  }

  private func runAction(_ action: () async throws -> Void) async -> HermesMenuBarState {
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
    onStateChange: (@Sendable (HermesMenuBarState) async -> Void)?
  ) async {
    currentSessionID = event.session.sessionID
    state.runtimeStatus = event.session.currentStatus
    state.sessionSummary = HermesMenuBarSessionSummary(eventSession: event.session)
    state.healthState = Self.healthState(for: event.session)
    state.lastErrorMessage = event.session.lastErrorMessage.map(Self.safeErrorMessage)
    state.recentEvents.insert(HermesMenuBarRuntimeEventViewState(event: event), at: 0)
    state.recentEvents = Array(state.recentEvents.prefix(10))
    await onStateChange?(state)
  }

  private func apply(status: HermesRuntimeCommandSessionStatus) {
    currentSessionID = status.sessionID
    state.runtimeStatus = status.currentStatus
    state.sessionSummary = HermesMenuBarSessionSummary(status: status)
    state.healthState = Self.healthState(for: status)
    state.lastErrorMessage = status.lastErrorMessage.map(Self.safeErrorMessage)
  }

  private func applyError(_ message: String) {
    state.lastErrorMessage = Self.safeErrorMessage(message)
    state.healthState = .failed
  }

  private func sessionStatus(
    from result: HermesRuntimeCommandResult
  ) throws -> HermesRuntimeCommandSessionStatus {
    guard case .sessionStatus(let status) = result else {
      throw HermesMenuBarControllerError.unexpectedRuntimeResult
    }
    return status
  }

  private static func healthState(
    for status: HermesRuntimeCommandSessionStatus
  ) -> HermesMenuBarHealthState {
    switch status.currentStatus {
    case .running:
      return status.capabilities?.gatewayRunning == false ? .degraded : .healthy
    case .degraded:
      return .degraded
    case .failed:
      return .failed
    case .stopped, .created, .starting, .stopping:
      return .stopped
    }
  }

  private static func healthState(
    for session: HermesRuntimeCommandEventSession
  ) -> HermesMenuBarHealthState {
    switch session.currentStatus {
    case .running:
      return session.capabilities?.gatewayRunning == false ? .degraded : .healthy
    case .degraded:
      return .degraded
    case .failed:
      return .failed
    case .stopped, .created, .starting, .stopping:
      return .stopped
    }
  }

  private static func safeErrorMessage(_ error: Error) -> String {
    safeErrorMessage(String(describing: error))
  }

  private static func safeErrorMessage(_ value: String) -> String {
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
    return String(sanitized.prefix(180))
  }
}

private enum HermesMenuBarControllerError: Error, CustomStringConvertible {
  case unexpectedRuntimeResult

  var description: String {
    "Runtime command returned an unexpected result"
  }
}
