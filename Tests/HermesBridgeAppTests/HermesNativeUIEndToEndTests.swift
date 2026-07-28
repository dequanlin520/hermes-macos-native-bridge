import Darwin
import Foundation
@testable import HermesBridgeApp
@testable import HermesBridgeService
@testable import HermesBridgeXPC
import HermesRuntimeFoundation
import HermesSettings
import XCTest

@MainActor
final class HermesNativeUIEndToEndTests: XCTestCase {
  func testM11002NativeUIEndToEndAcceptance() async throws {
    let harness = try M11002AcceptanceHarness()
    defer { harness.cleanup() }

    var result = M11002Result()
    do {
      let evidence = try await harness.runEndToEnd()
      result.xpcProtocol17 = evidence.protocolVersion.isCompatible(
        with: HermesBridgeProtocolVersion(major: 1, minor: 7)
      )
      result.appOwnsConcreteRuntime = try Self.appOwnsConcreteRuntime()
      result.serviceOwnsRuntime = evidence.serviceOwnsRuntime
      result.dashboardRoute = evidence.window.dashboard
      result.logsRoute = evidence.window.logs
      result.settingsRoute = evidence.window.settings
      result.diagnosticsRoute = evidence.window.diagnostics
      result.repeatedOpenFocuses = evidence.window.repeatedOpenFocuses
      result.commandCrossedXPC = evidence.commandCrossedXPC
      result.eventCrossedXPC = evidence.eventCrossedXPC
      result.sessionStarted = evidence.sessionStarted
      result.runtimeSurvivedUIExit = evidence.runtimeSurvivedUIExit
      result.clientReconnected = evidence.clientReconnected
      result.explicitStopForwardedOnce = evidence.explicitStopForwardedOnce
      result.sessionStopped = evidence.sessionStopped
      result.tokenExposed = evidence.redaction.tokenExposed
      result.privatePathExposed = evidence.redaction.privatePathExposed
      result.pidExposed = evidence.redaction.pidExposed
      result.residualProcess = harness.hasResidualProcess()
      try result.write()

      let resultContents = try String(contentsOf: M11002Result.resultURL)
      XCTAssertTrue(result.isPassing, resultContents)
    } catch {
      result.residualProcess = harness.hasResidualProcess()
      try? result.write()
      throw error
    }
  }

  func testServiceOwnedRuntimeIdentity() throws {
    let harness = try M11002AcceptanceHarness()
    defer { harness.cleanup() }
    let service = try harness.makeServiceRoot()

    XCTAssertTrue(type(of: service.runtimeEventBus) == HermesRuntimeEventBus.self)
    XCTAssertTrue(type(of: service.runtimeSessionManager) == HermesRuntimeSessionManager.self)
    XCTAssertTrue(type(of: service.runtimeCommandAPI) == HermesRuntimeCommandAPI.self)
  }

  func testUIClientInvalidationDoesNotStopSessionAndReconnectObservesExistingRuntime() async throws {
    let harness = try M11002AcceptanceHarness()
    defer { harness.cleanup() }
    let service = try harness.makeServiceRoot()
    let first = harness.makeAppClient(service: service)
    let started = try await harness.startSession(using: first.runtimeClient)

    await first.shutdown()
    let survived = try await service.runtimeCommandAPI.execute(.getSessionStatus(started.sessionID))
    let second = harness.makeAppClient(service: service)
    let reconnected = try await second.runtimeClient.execute(.getSessionStatus(started.sessionID))
    _ = try await second.runtimeClient.execute(.stopSession(started.sessionID))

    XCTAssertEqual(survived.sessionStatus?.currentStatus, .running)
    XCTAssertEqual(reconnected.sessionStatus?.currentStatus, .running)
  }

  func testCommandXPCEventXPCOrderingAndExplicitStopForwarding() async throws {
    let harness = try M11002AcceptanceHarness()
    defer { harness.cleanup() }
    let service = try harness.makeServiceRoot()
    let graph = harness.makeAppClient(service: service)
    let subscription = try await graph.runtimeClient.subscribeRuntimeEvents()
    var iterator = subscription.events.makeAsyncIterator()
    let started = try await harness.startSession(using: graph.runtimeClient)
    let events = try await harness.collectEvents(count: 3, iterator: &iterator)

    _ = try await graph.runtimeClient.execute(.stopSession(started.sessionID))

    XCTAssertEqual(events.map(\.kind), [.sessionCreated, .sessionStarting, .sessionRunning])
    XCTAssertEqual(events.map(\.sequenceNumber), [1, 2, 3])
    XCTAssertEqual(harness.stopForwardCount(), 1)
  }

  func testWindowRouteUniquenessAndTypedIdentifiers() {
    let factory = M11002RecordingWindowFactory()
    let root = HermesAppCompositionRoot(
      clientGraph: HermesAppClientGraph(runtimeClient: M11002NoopRuntimeClient()),
      windowFactory: factory
    )

    root.router.openDashboard()
    root.router.openOnboarding()
    root.router.openLogs()
    root.router.openSettings()
    root.router.openDiagnostics()
    root.router.openUpdateCenter()
    root.router.openNotifications()
    root.router.openTimeline()
    root.router.openSearchCenter()
    root.windowCoordinator.open(.recovery)
    root.router.openDashboard()
    root.windowCoordinator.close(.logs)
    root.router.openLogs()

    XCTAssertEqual(Set(factory.createdIdentifiers), Set(HermesNativeUIWindowIdentifier.allCases))
    XCTAssertEqual(factory.window(for: .dashboard)?.focusCount, 1)
    XCTAssertEqual(factory.window(for: .logs)?.showCount, 2)
    XCTAssertEqual(
      HermesNativeUIWindowIdentifier.allCases.map(\.rawValue).filter {
        $0.hasPrefix("com.hermes.bridge.window.")
      }.count,
      10
    )
  }

  func testRedactionResultDoesNotExposeSentinels() throws {
    let text = M11002Result(
      tokenExposed: false,
      privatePathExposed: false,
      pidExposed: false
    ).render()

    XCTAssertFalse(text.contains(M11002AcceptanceHarness.sentinelToken))
    XCTAssertFalse(text.contains(M11002AcceptanceHarness.sentinelPrivatePath))
    XCTAssertFalse(text.contains(M11002AcceptanceHarness.sentinelPID))
  }

  func testCleanupAfterFailurePathLeavesNoResidualProcess() throws {
    let harness = try M11002AcceptanceHarness()
    let service = try harness.makeServiceRoot()
    service.xpcService.invalidate()
    harness.cleanup()

    XCTAssertFalse(harness.hasResidualProcess())
  }

  private static func appOwnsConcreteRuntime() throws -> Bool {
    let source = try String(
      contentsOfFile: "Sources/HermesBridgeApp/HermesAppCompositionRoot.swift",
      encoding: .utf8
    )
    return [
      "HermesRuntimeSessionManager(",
      "HermesRuntimeEventBus(",
      "HermesRuntimeCommandAPI(",
      "HermesProcessSupervisor(",
      "HermesBackendAdapter(",
      "HermesProtocolClient(",
    ].contains { source.contains($0) }
  }
}

private struct M11002Evidence {
  let protocolVersion: HermesBridgeProtocolVersion
  let serviceOwnsRuntime: Bool
  let window: M11002WindowEvidence
  let commandCrossedXPC: Bool
  let eventCrossedXPC: Bool
  let sessionStarted: Bool
  let runtimeSurvivedUIExit: Bool
  let clientReconnected: Bool
  let explicitStopForwardedOnce: Bool
  let sessionStopped: Bool
  let redaction: M11002RedactionEvidence
}

private struct M11002WindowEvidence {
  var dashboard = false
  var logs = false
  var settings = false
  var diagnostics = false
  var repeatedOpenFocuses = false
}

private struct M11002RedactionEvidence {
  var tokenExposed = true
  var privatePathExposed = true
  var pidExposed = true
}

private final class M11002AcceptanceHarness: @unchecked Sendable {
  static let sentinelToken = "m11-token-sentinel-should-not-escape"
  static let sentinelPrivatePath = "/Users/private/m11-002/secret/hermes"
  static let sentinelPID = "pid=424242"

  let root: URL
  let fakeBackend: URL
  let stopCountFile: URL
  private let commandLock = NSLock()
  private var runtimeCommandKinds: [HermesBridgeRuntimeCommandKind] = []
  private var serviceRoots: [HermesBridgeCompositionRoot] = []

  init() throws {
    self.root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("artifacts/m11-002/run-\(UUID().uuidString)", isDirectory: true)
    self.fakeBackend = root.appendingPathComponent("fake-hermes.py")
    self.stopCountFile = root.appendingPathComponent("stop-count.txt")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try writeFakeBackend()
  }

  func runEndToEnd() async throws -> M11002Evidence {
    let service = try makeServiceRoot()
    let firstGraph = makeAppClient(service: service)
    let window = await routeWindows(clientGraph: firstGraph)
    let capabilities = try await (firstGraph.runtimeClient as! HermesBridgeRuntimeClientAdapter)
      .protocolVersionForAcceptance()
    let subscription = try await firstGraph.runtimeClient.subscribeRuntimeEvents()
    var iterator = subscription.events.makeAsyncIterator()
    let started = try await startSession(using: firstGraph.runtimeClient)
    let running = try await firstGraph.runtimeClient.execute(.getSessionStatus(started.sessionID))
    let events = try await collectEvents(count: 3, iterator: &iterator)

    await firstGraph.shutdown()
    let survived = try await service.runtimeCommandAPI.execute(.getSessionStatus(started.sessionID))
    let secondGraph = makeAppClient(service: service)
    let reconnected = try await secondGraph.runtimeClient.execute(.getSessionStatus(started.sessionID))
    let stopped = try await secondGraph.runtimeClient.execute(.stopSession(started.sessionID))
    try await waitForStopForwardCount(1)
    await secondGraph.shutdown()

    let exposureText = [
      String(describing: running),
      events.map(String.init(describing:)).joined(separator: "\n"),
      String(describing: survived),
      String(describing: reconnected),
      String(describing: stopped),
    ].joined(separator: "\n")

    return M11002Evidence(
      protocolVersion: capabilities.version,
      serviceOwnsRuntime: type(of: service.runtimeSessionManager) == HermesRuntimeSessionManager.self
        && type(of: service.runtimeEventBus) == HermesRuntimeEventBus.self
        && type(of: service.runtimeCommandAPI) == HermesRuntimeCommandAPI.self,
      window: window,
      commandCrossedXPC: started.currentStatus == .running
        && runtimeCommandCount(.startSession) == 1,
      eventCrossedXPC: events.contains { $0.kind == .sessionRunning },
      sessionStarted: running.sessionStatus?.currentStatus == .running,
      runtimeSurvivedUIExit: survived.sessionStatus?.currentStatus == .running,
      clientReconnected: reconnected.sessionStatus?.currentStatus == .running,
      explicitStopForwardedOnce: stopForwardCount() == 1,
      sessionStopped: stopped.sessionStatus?.currentStatus == .stopped,
      redaction: M11002RedactionEvidence(
        tokenExposed: exposureText.contains(Self.sentinelToken),
        privatePathExposed: exposureText.contains(Self.sentinelPrivatePath),
        pidExposed: exposureText.contains(Self.sentinelPID) || exposureText.contains("424242")
      )
    )
  }

  func makeServiceRoot() throws -> HermesBridgeCompositionRoot {
    let serviceRoot = root.appendingPathComponent("service-\(UUID().uuidString)", isDirectory: true)
    let configuration = try HermesBridgeServiceConfiguration(
      machServiceName: "com.hermes.bridge.test.m11-002.\(UUID().uuidString)",
      runtimeRoot: serviceRoot.appendingPathComponent("Runtime", isDirectory: true),
      requestStateRoot: serviceRoot.appendingPathComponent("RequestState", isDirectory: true),
      allowlistedHermesExecutableCandidates: [fakeBackend],
      loopbackPortPolicy: HermesBridgeLoopbackPortPolicy(fixedPort: try Self.freePort()),
      timeouts: HermesBridgeServiceTimeouts(
        startup: 6,
        gracefulShutdown: 2,
        forcedShutdown: 2,
        gatewayReady: 4
      ),
      maximumConcurrentXPCRequests: 8,
      allowTestMachServiceName: true
    )
    let paths = try HermesBridgeServicePaths(
      runtimeRoot: configuration.runtimeRoot,
      requestStateRoot: configuration.requestStateRoot,
      logsRoot: serviceRoot.appendingPathComponent("Logs", isDirectory: true),
      temporaryRoot: serviceRoot.appendingPathComponent("Temporary", isDirectory: true)
    )
    let service = try HermesBridgeCompositionRoot(configuration: configuration, paths: paths)
    serviceRoots.append(service)
    return service
  }

  func makeAppClient(service: HermesBridgeCompositionRoot) -> HermesAppClientGraph {
    let client = HermesBridgeXPCClient(
      transport: M11002InProcessTransport(dispatcher: service.dispatcher, harness: self),
      timeout: 10
    )
    return HermesAppClientGraph(
      runtimeClient: HermesBridgeRuntimeClientAdapter(client: client, pollTimeoutMilliseconds: 50),
      settingsStore: M11002InMemorySettingsStore()
    )
  }

  func startSession(using client: any HermesAppRuntimeClienting) async throws
    -> HermesRuntimeCommandSessionStatus
  {
    let created = try await client.execute(.createSession).sessionStatus!
    return try await client.execute(.startSession(created.sessionID)).sessionStatus!
  }

  func collectEvents(
    count: Int,
    iterator: inout AsyncStream<HermesRuntimeCommandEvent>.Iterator
  ) async throws -> [HermesRuntimeCommandEvent] {
    var events: [HermesRuntimeCommandEvent] = []
    let deadline = Date().addingTimeInterval(6)
    while events.count < count && Date() < deadline {
      if let event = await iterator.next() {
        events.append(event)
      }
    }
    return events
  }

  @MainActor
  private func routeWindows(clientGraph: HermesAppClientGraph) -> M11002WindowEvidence {
    let factory = M11002RecordingWindowFactory()
    let root = HermesAppCompositionRoot(clientGraph: clientGraph, windowFactory: factory)
    root.router.openDashboard()
    root.router.openLogs()
    root.router.openSettings()
    root.router.openDiagnostics()
    root.router.openDashboard()
    root.windowCoordinator.close(.logs)
    root.router.openLogs()

    return M11002WindowEvidence(
      dashboard: factory.window(for: .dashboard)?.showCount == 1,
      logs: factory.window(for: .logs)?.showCount == 2,
      settings: factory.window(for: .settings)?.showCount == 1,
      diagnostics: factory.window(for: .diagnostics)?.showCount == 1,
      repeatedOpenFocuses: factory.createdIdentifiers.filter { $0 == .dashboard }.count == 1
        && factory.window(for: .dashboard)?.focusCount == 1
        && root.windowCoordinator.windowCount(for: .dashboard) == 1
    )
  }

  func stopForwardCount() -> Int {
    runtimeCommandCount(.stopSession)
  }

  func waitForStopForwardCount(_ expected: Int) async throws {
    let deadline = Date().addingTimeInterval(4)
    while Date() < deadline {
      if stopForwardCount() == expected { return }
      try await Task.sleep(nanoseconds: 50_000_000)
    }
  }

  func hasResidualProcess() -> Bool {
    shell(["/usr/bin/pgrep", "-fl", root.path]).trimmingCharacters(in: .whitespacesAndNewlines)
      .isEmpty == false
  }

  func cleanup() {
    for service in serviceRoots {
      service.xpcService.invalidate()
      if case .sessionList(let sessions) = try? awaitBlockingRuntimeList(service) {
        for session in sessions where session.currentStatus != .stopped {
          _ = try? awaitBlockingRuntimeStop(service, session.sessionID)
        }
      }
    }
    try? FileManager.default.removeItem(at: root)
  }

  private func awaitBlockingRuntimeList(_ service: HermesBridgeCompositionRoot) throws
    -> HermesRuntimeCommandResult
  {
    let semaphore = DispatchSemaphore(value: 0)
    let box = LockedBox<Result<HermesRuntimeCommandResult, Error>?>(nil)
    Task {
      do { box.set(.success(try await service.runtimeCommandAPI.execute(.listSessions))) }
      catch { box.set(.failure(error)) }
      semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 5)
    return try box.value!.get()
  }

  private func awaitBlockingRuntimeStop(_ service: HermesBridgeCompositionRoot, _ sessionID: UUID)
    throws -> HermesRuntimeCommandResult
  {
    let semaphore = DispatchSemaphore(value: 0)
    let box = LockedBox<Result<HermesRuntimeCommandResult, Error>?>(nil)
    Task {
      do { box.set(.success(try await service.runtimeCommandAPI.execute(.stopSession(sessionID)))) }
      catch { box.set(.failure(error)) }
      semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 5)
    return try box.value!.get()
  }

  private func writeFakeBackend() throws {
    let script = """
      #!/usr/bin/python3
      import argparse, asyncio, base64, hashlib, json, os, signal, struct
      from urllib.parse import parse_qs, urlparse
      import sys
      if sys.argv[1:] == ["--version"]:
        print("Hermes Agent v0.18.2")
        print("Install Method: m11-002-fixture")
        sys.exit(0)
      parser = argparse.ArgumentParser()
      parser.add_argument("--safe-mode", action="store_true")
      parser.add_argument("serve")
      parser.add_argument("--host", required=True)
      parser.add_argument("--port", required=True, type=int)
      parser.add_argument("--skip-build", action="store_true")
      parser.add_argument("--isolated", action="store_true")
      args = parser.parse_args()
      token = os.environ.get("HERMES_DASHBOARD_SESSION_TOKEN", "")
      stop_file = "\(stopCountFile.path)"
      async def read_req(r):
        data = await r.readuntil(b"\\r\\n\\r\\n")
        lines = data.decode("ascii", "replace").split("\\r\\n")
        method, target, _ = lines[0].split(" ", 2)
        headers = {}
        for line in lines[1:]:
          if ":" in line:
            k, v = line.split(":", 1); headers[k.lower()] = v.strip()
        return method, target, headers
      async def http(w, status, body=b""):
        reason = {200:"OK",403:"Forbidden",404:"Not Found"}.get(status,"Error")
        w.write((f"HTTP/1.1 {status} {reason}\\r\\nContent-Length: {len(body)}\\r\\nConnection: close\\r\\n\\r\\n").encode()+body)
        await w.drain(); w.close(); await w.wait_closed()
      async def frame(r):
        h = await r.readexactly(2); opcode = h[0] & 0x0f
        if opcode == 8: return None
        length = h[1] & 0x7f; masked = h[1] & 0x80
        if length == 126: length = struct.unpack("!H", await r.readexactly(2))[0]
        elif length == 127: length = struct.unpack("!Q", await r.readexactly(8))[0]
        mask = await r.readexactly(4) if masked else b"\\0\\0\\0\\0"
        data = await r.readexactly(length)
        if masked: data = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
        return data.decode()
      async def send(w, obj):
        data = json.dumps(obj).encode(); header = bytearray([0x81])
        if len(data) < 126: header.append(len(data))
        else: header.extend([126]); header.extend(struct.pack("!H", len(data)))
        w.write(bytes(header)+data); await w.drain()
      async def ws(r, w, target, headers):
        if parse_qs(urlparse(target).query).get("token", [""])[0] != token:
          return await http(w, 403, b"forbidden")
        key = headers.get("sec-websocket-key", "")
        accept = base64.b64encode(hashlib.sha1((key+"258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
        w.write(("HTTP/1.1 101 Switching Protocols\\r\\nUpgrade: websocket\\r\\nConnection: Upgrade\\r\\nSec-WebSocket-Accept: "+accept+"\\r\\n\\r\\n").encode()); await w.drain()
        await send(w, {"jsonrpc":"2.0","method":"event","params":{"type":"gateway.ready"}})
        while True:
          try:
            raw = await frame(r)
            if raw is None: break
            req = json.loads(raw)
          except Exception: break
          m = req.get("method"); rid = req.get("id")
          if m == "session.create":
            resp = {"jsonrpc":"2.0","id":rid,"result":{"session_id":"m11-session","stored_session_id":"stored-m11","message_count":0,"info":{"desktop_contract":3}}}
          elif m == "session.status":
            resp = {"jsonrpc":"2.0","id":rid,"result":{"output":"idle"}}
          elif m == "session.interrupt":
            resp = {"jsonrpc":"2.0","id":rid,"result":{"status":"interrupted"}}
          elif m == "prompt.submit":
            resp = {"jsonrpc":"2.0","id":rid,"result":{"status":"streaming"}}
          elif m == "approval.respond":
            resp = {"jsonrpc":"2.0","id":rid,"result":{"resolved":True}}
          else:
            resp = {"jsonrpc":"2.0","id":rid,"error":{"code":-32601,"message":"unknown"}}
          await send(w, resp)
        w.close()
      async def handle(r, w):
        try:
          method, target, headers = await read_req(r); path = urlparse(target).path
          if method == "GET" and path == "/api/status":
            return await http(w, 200, json.dumps({"version":"m11-fixture","auth_required":True,"auth_mode":"loopback_token","desktop_contract":3,"gateway_running":True,"gateway_state":"running"}).encode())
          if method == "GET" and path == "/api/ws": return await ws(r, w, target, headers)
          return await http(w, 404, b"not found")
        except Exception:
          try: w.close(); await w.wait_closed()
          except Exception: pass
      async def main():
        server = await asyncio.start_server(handle, "127.0.0.1", args.port)
        print("sentinels token=\(Self.sentinelToken) path=\(Self.sentinelPrivatePath) \(Self.sentinelPID)", flush=True)
        print(f"HERMES_BACKEND_READY port={args.port}", flush=True)
        stop = asyncio.Event()
        def on_term():
          with open(stop_file, "a") as f: f.write("stop\\n")
          stop.set()
        asyncio.get_running_loop().add_signal_handler(signal.SIGTERM, on_term)
        async with server: await stop.wait()
      asyncio.run(main())
      """
    try script.write(to: fakeBackend, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: NSNumber(value: Int16(0o700))],
      ofItemAtPath: fakeBackend.path
    )
  }

  private static func freePort() throws -> Int {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { throw NSError(domain: "M11002", code: 1) }
    defer { close(fd) }
    var address = sockaddr_in(
      sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
      sin_family: sa_family_t(AF_INET),
      sin_port: 0,
      sin_addr: in_addr(s_addr: inet_addr("127.0.0.1")),
      sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
    )
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard bound == 0 else { throw NSError(domain: "M11002", code: 2) }
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let named = withUnsafeMutablePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        getsockname(fd, $0, &length)
      }
    }
    guard named == 0 else { throw NSError(domain: "M11002", code: 3) }
    return Int(UInt16(bigEndian: address.sin_port))
  }

  private func shell(_ arguments: [String]) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: arguments[0])
    process.arguments = Array(arguments.dropFirst())
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    try? process.run()
    process.waitUntilExit()
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
  }

  fileprivate func recordRequest(_ requestData: Data) {
    guard
      let envelope = try? JSONDecoder().decode(HermesBridgeRequestEnvelope.self, from: requestData),
      envelope.operation == .runtimeCommand,
      let command = envelope.runtimeCommand
    else { return }
    commandLock.withLock {
      runtimeCommandKinds.append(command.kind)
    }
  }

  private func runtimeCommandCount(_ kind: HermesBridgeRuntimeCommandKind) -> Int {
    commandLock.withLock {
      runtimeCommandKinds.filter { $0 == kind }.count
    }
  }
}

private extension HermesRuntimeCommandResult {
  var sessionStatus: HermesRuntimeCommandSessionStatus? {
    if case .sessionStatus(let status) = self { return status }
    return nil
  }
}

private struct M11002InProcessTransport: HermesBridgeXPCTransport {
  let dispatcher: HermesBridgeXPCRequestDispatcher
  let harness: M11002AcceptanceHarness
  func send(_ requestData: Data) async throws -> Data {
    harness.recordRequest(requestData)
    return await dispatcher.handle(requestData)
  }
  func close() {}
}

private extension HermesBridgeRuntimeClientAdapter {
  func protocolVersionForAcceptance() async throws -> HermesBridgeProtocolVersionPayload {
    let mirror = Mirror(reflecting: self)
    guard let client = mirror.children.first(where: { $0.label == "client" })?.value
      as? HermesBridgeXPCClient
    else { throw HermesBridgeXPCClientError.responseDecodingFailure }
    return try await client.protocolVersion()
  }
}

private final class M11002RecordingWindowFactory: HermesNativeUIWindowFactory, @unchecked Sendable {
  @MainActor private var windows: [HermesNativeUIWindowIdentifier: M11002RecordingWindow] = [:]
  @MainActor private(set) var createdIdentifiers: [HermesNativeUIWindowIdentifier] = []

  @MainActor
  func makeWindow(
    for identifier: HermesNativeUIWindowIdentifier,
    clientGraph _: HermesAppClientGraph
  ) -> HermesNativeUIWindowControlling {
    let window = M11002RecordingWindow(identifier: identifier)
    windows[identifier] = window
    createdIdentifiers.append(identifier)
    return window
  }

  @MainActor
  func window(for identifier: HermesNativeUIWindowIdentifier) -> M11002RecordingWindow? {
    windows[identifier]
  }
}

@MainActor
private final class M11002RecordingWindow: HermesNativeUIWindowControlling {
  let identifier: HermesNativeUIWindowIdentifier
  private(set) var isOpen = false
  private(set) var showCount = 0
  private(set) var focusCount = 0
  private(set) var closeCount = 0

  init(identifier: HermesNativeUIWindowIdentifier) {
    self.identifier = identifier
  }

  func show() {
    isOpen = true
    showCount += 1
  }

  func focus() { focusCount += 1 }

  func close() {
    isOpen = false
    closeCount += 1
  }

  func cleanup() { isOpen = false }
}

private final class M11002NoopRuntimeClient: HermesAppRuntimeClienting, @unchecked Sendable {
  func execute(_ command: HermesRuntimeCommand) async throws -> HermesRuntimeCommandResult {
    switch command {
    case .createSession, .startSession, .stopSession, .getSessionStatus:
      return .sessionStatus(
        HermesRuntimeCommandSessionStatus(
          sessionID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
          currentStatus: .running,
          backendVersion: nil,
          startTime: nil,
          capabilities: nil,
          lastErrorMessage: nil,
          shutdownReason: nil
        ))
    case .listSessions:
      return .sessionList([])
    case .subscribeEvents:
      return .eventSubscription(try await subscribeRuntimeEvents())
    }
  }

  func subscribeRuntimeEvents() async throws -> HermesRuntimeCommandEventSubscription {
    HermesRuntimeCommandEventSubscription(id: UUID(), events: AsyncStream { $0.finish() })
  }

  func invalidate() async {}
}

private final class M11002InMemorySettingsStore: HermesConfigurationStoring, @unchecked Sendable {
  private var settings = HermesSettings.defaults
  func load() throws -> HermesSettings { settings }
  func save(_ settings: HermesSettings) throws { self.settings = settings }
}

private final class LockedBox<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: Value
  init(_ value: Value) { stored = value }
  var value: Value { lock.withLock { stored } }
  func set(_ value: Value) { lock.withLock { stored = value } }
}

private struct M11002Result {
  static let resultURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("artifacts/m11-002/result.txt")

  var xpcProtocol17 = false
  var appOwnsConcreteRuntime = true
  var serviceOwnsRuntime = false
  var dashboardRoute = false
  var logsRoute = false
  var settingsRoute = false
  var diagnosticsRoute = false
  var repeatedOpenFocuses = false
  var commandCrossedXPC = false
  var eventCrossedXPC = false
  var sessionStarted = false
  var runtimeSurvivedUIExit = false
  var clientReconnected = false
  var explicitStopForwardedOnce = false
  var sessionStopped = false
  var tokenExposed = false
  var privatePathExposed = false
  var pidExposed = false
  var residualProcess = true

  var isPassing: Bool {
    xpcProtocol17
      && !appOwnsConcreteRuntime
      && serviceOwnsRuntime
      && dashboardRoute
      && logsRoute
      && settingsRoute
      && diagnosticsRoute
      && repeatedOpenFocuses
      && commandCrossedXPC
      && eventCrossedXPC
      && sessionStarted
      && runtimeSurvivedUIExit
      && clientReconnected
      && explicitStopForwardedOnce
      && sessionStopped
      && !tokenExposed
      && !privatePathExposed
      && !pidExposed
      && !residualProcess
  }

  func write() throws {
    try FileManager.default.createDirectory(
      at: Self.resultURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try render().write(to: Self.resultURL, atomically: true, encoding: .utf8)
  }

  func render() -> String {
    [
      "XPC_PROTOCOL_1_7=\(yesNo(xpcProtocol17))",
      "APP_OWNS_CONCRETE_RUNTIME=\(yesNo(appOwnsConcreteRuntime))",
      "SERVICE_OWNS_RUNTIME=\(yesNo(serviceOwnsRuntime))",
      "DASHBOARD_ROUTE=\(yesNo(dashboardRoute))",
      "LOGS_ROUTE=\(yesNo(logsRoute))",
      "SETTINGS_ROUTE=\(yesNo(settingsRoute))",
      "DIAGNOSTICS_ROUTE=\(yesNo(diagnosticsRoute))",
      "REPEATED_OPEN_FOCUSES=\(yesNo(repeatedOpenFocuses))",
      "COMMAND_CROSSED_XPC=\(yesNo(commandCrossedXPC))",
      "EVENT_CROSSED_XPC=\(yesNo(eventCrossedXPC))",
      "SESSION_STARTED=\(yesNo(sessionStarted))",
      "RUNTIME_SURVIVED_UI_EXIT=\(yesNo(runtimeSurvivedUIExit))",
      "CLIENT_RECONNECTED=\(yesNo(clientReconnected))",
      "EXPLICIT_STOP_FORWARDED_ONCE=\(yesNo(explicitStopForwardedOnce))",
      "SESSION_STOPPED=\(yesNo(sessionStopped))",
      "TOKEN_EXPOSED=\(yesNo(tokenExposed))",
      "PRIVATE_PATH_EXPOSED=\(yesNo(privatePathExposed))",
      "PID_EXPOSED=\(yesNo(pidExposed))",
      "RESIDUAL_PROCESS=\(yesNo(residualProcess))",
      "M11_002_RESULT=\(isPassing ? "PASS" : "FAIL")",
    ].joined(separator: "\n") + "\n"
  }

  private func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }
}
