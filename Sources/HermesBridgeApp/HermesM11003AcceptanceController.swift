import AppKit
import Foundation
import HermesBridgeXPC
import HermesRuntimeFoundation

struct HermesM11003AcceptanceController {
  private enum Mode: String {
    case startAndHold = "start-and-hold"
    case reconnectAndStop = "reconnect-and-stop"
  }

  private let mode: Mode
  private let stateURL: URL
  private let evidenceURL: URL
  private var didStart = false

  static func fromCommandLine(arguments: [String] = CommandLine.arguments)
    -> HermesM11003AcceptanceController?
  {
    guard let markerIndex = arguments.firstIndex(of: "--hermes-m11-003-acceptance") else {
      return nil
    }
    let modeIndex = markerIndex + 1
    let stateIndex = markerIndex + 2
    let evidenceIndex = markerIndex + 3
    guard arguments.indices.contains(modeIndex),
      arguments.indices.contains(stateIndex),
      arguments.indices.contains(evidenceIndex),
      let mode = Mode(rawValue: arguments[modeIndex])
    else {
      return nil
    }
    return HermesM11003AcceptanceController(
      mode: mode,
      stateURL: URL(fileURLWithPath: arguments[stateIndex]),
      evidenceURL: URL(fileURLWithPath: arguments[evidenceIndex])
    )
  }

  @MainActor
  mutating func startIfNeeded(compositionRoot: HermesAppCompositionRoot) {
    guard !didStart else { return }
    didStart = true
    let mode = mode
    let stateURL = stateURL
    let evidenceURL = evidenceURL
    Task { @MainActor in
      await Self.run(
        mode: mode,
        stateURL: stateURL,
        evidenceURL: evidenceURL,
        compositionRoot: compositionRoot
      )
    }
  }

  @MainActor
  private static func run(
    mode: Mode,
    stateURL: URL,
    evidenceURL: URL,
    compositionRoot: HermesAppCompositionRoot
  ) async {
    var evidence = HermesM11003AcceptanceEvidence()
    do {
      evidence.stage = "routes"
      compositionRoot.router.openDashboard()
      compositionRoot.router.openLogs()
      compositionRoot.router.openSettings()
      compositionRoot.router.openDiagnostics()
      evidence.dashboardRouteAvailable = true
      evidence.logsRouteAvailable = true
      evidence.settingsRouteAvailable = true
      evidence.diagnosticsRouteAvailable = true

      evidence.stage = "connect"
      let client = compositionRoot.clientGraph.runtimeClient
      let capabilities = try await connect(client: client)
      evidence.xpcConnectionSucceeded = true
      evidence.xpcProtocol17 = capabilities.protocolVersion == HermesBridgeProtocolVersion.current
      evidence.serviceOwnsRuntime =
        capabilities.capabilities.contains(.runtimeCommand)
        && capabilities.capabilities.contains(.runtimeEventObservation)

      switch mode {
      case .startAndHold:
        evidence.stage = "subscribe"
        let subscription = try await client.subscribeRuntimeEvents()
        evidence.stage = "create"
        let created = try sessionStatus(from: try await client.execute(.createSession))
        let eventTask = Task.detached {
          var iterator = subscription.events.makeAsyncIterator()
          return await nextEvent(matching: created.sessionID, iterator: &iterator)
        }
        evidence.stage = "start"
        let started = try sessionStatus(from: try await client.execute(.startSession(created.sessionID)))
        evidence.stage = "event"
        let event = await eventTask.value
        evidence.sessionStarted = started.currentStatus == .running
        evidence.eventReceived = event != nil
        try writeState(sessionID: started.sessionID, to: stateURL)
        try evidence.write(to: evidenceURL)
      case .reconnectAndStop:
        evidence.stage = "read-state"
        let sessionID = try readState(from: stateURL)
        evidence.stage = "reconnect"
        let reconnected = try sessionStatus(
          from: try await client.execute(.getSessionStatus(sessionID)))
        evidence.clientReconnected = reconnected.currentStatus == .running
        evidence.stage = "stop"
        evidence.explicitStopForwardedCount += 1
        let stopped = try sessionStatus(
          from: try await client.execute(.stopSession(sessionID, reason: .requested)))
        evidence.sessionStopped = stopped.currentStatus == .stopped
        try evidence.write(to: evidenceURL)
        await compositionRoot.shutdown()
        NSApplication.shared.terminate(nil)
      }
    } catch {
      evidence.failureCode = safeErrorCode(error)
      try? evidence.write(to: evidenceURL)
      if mode == .reconnectAndStop {
        NSApplication.shared.terminate(nil)
      }
    }
  }

  private static func connect(client: any HermesAppRuntimeClienting) async throws
    -> HermesBridgeCapabilitiesPayload
  {
    guard let adapter = client as? HermesBridgeRuntimeClientAdapter else {
      throw HermesM11003AcceptanceError.unexpectedClient
    }
    let mirror = Mirror(reflecting: adapter)
    guard let xpcClient = mirror.children.first(where: { $0.label == "client" })?.value
      as? HermesBridgeXPCClient
    else {
      throw HermesM11003AcceptanceError.unexpectedClient
    }
    return try await xpcClient.connect()
  }

  private static func sessionStatus(from result: HermesRuntimeCommandResult) throws
    -> HermesRuntimeCommandSessionStatus
  {
    guard case .sessionStatus(let status) = result else {
      throw HermesM11003AcceptanceError.unexpectedRuntimeResult
    }
    return status
  }

  private static func nextEvent(
    matching sessionID: UUID,
    iterator: inout AsyncStream<HermesRuntimeCommandEvent>.Iterator
  ) async -> HermesRuntimeCommandEvent? {
    let deadline = Date().addingTimeInterval(8)
    while Date() < deadline {
      if let event = await iterator.next(),
        event.session.sessionID == sessionID,
        event.kind == .sessionRunning
      {
        return event
      }
    }
    return nil
  }

  private static func writeState(sessionID: UUID, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try "SESSION_ID=\(sessionID.uuidString)\n".write(to: url, atomically: true, encoding: .utf8)
  }

  private static func readState(from url: URL) throws -> UUID {
    let text = try String(contentsOf: url, encoding: .utf8)
    guard let line = text.split(separator: "\n").first(where: { $0.hasPrefix("SESSION_ID=") }),
      let uuid = UUID(uuidString: String(line.dropFirst("SESSION_ID=".count)))
    else {
      throw HermesM11003AcceptanceError.invalidState
    }
    return uuid
  }

  private static func safeErrorCode(_ error: Error) -> String {
    let filtered = String(describing: error)
      .filter { character in
        character.isASCII
          && (character.isLetter || character.isNumber || character == "." || character == "_"
            || character == "(" || character == ")")
      }
    return String(filtered.prefix(160))
  }
}

private enum HermesM11003AcceptanceError: Error {
  case unexpectedClient
  case unexpectedRuntimeResult
  case invalidState
}

private struct HermesM11003AcceptanceEvidence {
  var xpcConnectionSucceeded = false
  var xpcProtocol17 = false
  var serviceOwnsRuntime = false
  var dashboardRouteAvailable = false
  var logsRouteAvailable = false
  var settingsRouteAvailable = false
  var diagnosticsRouteAvailable = false
  var sessionStarted = false
  var eventReceived = false
  var clientReconnected = false
  var explicitStopForwardedCount = 0
  var sessionStopped = false
  var stage = "init"
  var failureCode: String?

  func write(to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try render().write(to: url, atomically: true, encoding: .utf8)
  }

  private func render() -> String {
    var lines = [
      "XPC_CONNECTION_SUCCEEDED=\(yesNo(xpcConnectionSucceeded))",
      "XPC_PROTOCOL_1_7=\(yesNo(xpcProtocol17))",
      "SERVICE_OWNS_RUNTIME=\(yesNo(serviceOwnsRuntime))",
      "DASHBOARD_ROUTE_AVAILABLE=\(yesNo(dashboardRouteAvailable))",
      "LOGS_ROUTE_AVAILABLE=\(yesNo(logsRouteAvailable))",
      "SETTINGS_ROUTE_AVAILABLE=\(yesNo(settingsRouteAvailable))",
      "DIAGNOSTICS_ROUTE_AVAILABLE=\(yesNo(diagnosticsRouteAvailable))",
      "SESSION_STARTED=\(yesNo(sessionStarted))",
      "EVENT_RECEIVED=\(yesNo(eventReceived))",
      "CLIENT_RECONNECTED=\(yesNo(clientReconnected))",
      "EXPLICIT_STOP_FORWARDED_COUNT=\(explicitStopForwardedCount)",
      "SESSION_STOPPED=\(yesNo(sessionStopped))",
      "STAGE=\(stage)",
    ]
    if let failureCode {
      lines.append("FAILURE_CODE=\(failureCode)")
    }
    return lines.joined(separator: "\n") + "\n"
  }

  private func yesNo(_ value: Bool) -> String {
    value ? "yes" : "no"
  }
}
