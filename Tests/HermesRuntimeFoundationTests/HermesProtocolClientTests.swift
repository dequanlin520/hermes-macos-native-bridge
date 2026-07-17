import Darwin
import Foundation
import XCTest

@testable import HermesRuntimeFoundation

final class HermesProtocolClientTests: XCTestCase {
  private var fixtures: [FixtureBackend] = []

  override func tearDown() async throws {
    for fixture in fixtures {
      fixture.stop()
    }
    fixtures.removeAll()
    XCTAssertFalse(hasResidualFixtureProcess())
  }

  func testSecureTokenGenerationAndRedaction() throws {
    let first = try HermesBackendSessionToken.generate()
    let second = try HermesBackendSessionToken.generate()

    XCTAssertNotEqual(first.rawValue, second.rawValue)
    XCTAssertGreaterThanOrEqual(first.rawValue.count, 40)
    XCTAssertFalse(String(describing: first).contains(first.rawValue))
    XCTAssertFalse(String(reflecting: first).contains(first.rawValue))
  }

  func testFixedLoopbackEndpointAndInvalidPortRejection() throws {
    let endpoint = try HermesBackendEndpoint(port: 19123)

    XCTAssertEqual(endpoint.statusURL.absoluteString, "http://127.0.0.1:19123/api/status")
    XCTAssertTrue(endpoint.description.contains("/api/status"))
    XCTAssertTrue(endpoint.description.contains("/api/ws"))
    XCTAssertFalse(endpoint.description.contains("token=" + fixtureToken.rawValue))

    XCTAssertThrowsError(try HermesBackendEndpoint(port: 0)) {
      XCTAssertEqual($0 as? HermesProtocolClientError, .invalidPort(0))
    }
  }

  func testStatusDecoding() async throws {
    let fixture = try startFixture()
    let client = try client(for: fixture)

    let status = try await client.fetchStatus()

    XCTAssertEqual(status.version, "0.18.2")
    XCTAssertEqual(status.authRequired, true)
    XCTAssertEqual(status.authMode, .loopbackToken)
    XCTAssertEqual(status.desktopContract, 3)
  }

  func testMalformedStatusResponse() async throws {
    let fixture = try startFixture(mode: "malformed-status")
    let client = try client(for: fixture)

    await XCTAssertThrowsAsyncError(try await client.fetchStatus()) {
      XCTAssertEqual($0 as? HermesProtocolClientError, .malformedStatus)
    }
  }

  func testAuthenticatedWebSocketSuccessAndGatewayReady() async throws {
    let fixture = try startFixture()
    let client = try client(for: fixture)

    try await client.connectAndWaitUntilReady(timeout: 2)

    XCTAssertEqual(client.state, .ready)
    await client.close()
  }

  func testAuthenticationRejection() async throws {
    let fixture = try startFixture()
    let endpoint = try HermesBackendEndpoint(port: fixture.port)
    let client = HermesProtocolClient(
      endpoint: endpoint,
      token: HermesBackendSessionToken(rawValue: "wrong-token"),
      requestTimeout: 0.2
    )

    await XCTAssertThrowsAsyncError(try await client.connectAndWaitUntilReady(timeout: 0.5))
    await client.close()
  }

  func testSessionCreation() async throws {
    let client = try await readyClient()

    let result = try await client.createSession()

    XCTAssertEqual(result.sessionID, "session-1")
    XCTAssertEqual(result.storedSessionID, "stored-1")
    XCTAssertEqual(result.desktopContract, 3)
    await client.close()
  }

  func testTextualSessionStatus() async throws {
    let client = try await readyClient()

    let status = try await client.sessionStatus(sessionID: "session-1")

    XCTAssertEqual(status.output, "idle")
    await client.close()
  }

  func testPromptSubmitFixtureEncoding() async throws {
    let client = try await readyClient()

    let result = try await client.submitPrompt(sessionID: "session-1", text: "hello fixture")

    XCTAssertEqual(result.status, "streaming")
    await client.close()
  }

  func testPromptLengthRejection() async throws {
    let client = try await readyClient()

    await XCTAssertThrowsAsyncError(
      try await client.submitPrompt(
        sessionID: "session-1", text: String(repeating: "A", count: 70_000))
    ) {
      XCTAssertEqual($0 as? HermesProtocolClientError, .promptTooLong(maximumBytes: 65_536))
    }
    await client.close()
  }

  func testCooperativeInterrupt() async throws {
    let client = try await readyClient()

    let result = try await client.interruptSession(sessionID: "session-1")

    XCTAssertEqual(result.status, "interrupted")
    await client.close()
  }

  func testApprovalRequestDecodingAndResponseEncoding() async throws {
    let fixture = try startFixture(mode: "approval-after-create")
    let client = try client(for: fixture)
    var iterator = client.events.makeAsyncIterator()
    try await client.connectAndWaitUntilReady(timeout: 2)
    _ = try await client.createSession()

    var event = await iterator.next()
    if case .gatewayReady = event {
      event = await iterator.next()
    }
    guard case .approvalRequest(let request) = event else {
      return XCTFail("expected approval request, got \(String(describing: event))")
    }
    XCTAssertEqual(request.sessionID, "session-1")
    XCTAssertEqual(request.approvalID, "approval-1")
    XCTAssertEqual(request.prompt, "Allow fixture action?")

    let response = try await client.respondToApproval(sessionID: "session-1", decision: .approve)
    XCTAssertTrue(response.resolved)
    await client.close()
  }

  func testJSONRPCErrorMapping() async throws {
    let client = try await readyClient()

    await XCTAssertThrowsAsyncError(
      try await client.submitPrompt(sessionID: "session-1", text: "rpc-error")
    ) {
      XCTAssertEqual(
        $0 as? HermesProtocolClientError,
        .rpcError(code: -32602, message: "fixture invalid params")
      )
    }
    await client.close()
  }

  func testOutOfOrderResponseCorrelation() async throws {
    let client = try await readyClient()

    async let first = client.submitPrompt(sessionID: "session-1", text: "out-of-order-a")
    try await Task.sleep(nanoseconds: 50_000_000)
    async let second = client.submitPrompt(sessionID: "session-1", text: "out-of-order-b")
    let results = try await (first.status, second.status)

    XCTAssertEqual(results.0, "streaming-a")
    XCTAssertEqual(results.1, "streaming-b")
    await client.close()
  }

  func testRequestTimeout() async throws {
    let fixture = try startFixture()
    let endpoint = try HermesBackendEndpoint(port: fixture.port)
    let client = HermesProtocolClient(
      endpoint: endpoint,
      token: fixtureToken,
      requestTimeout: 0.2
    )
    try await client.connectAndWaitUntilReady(timeout: 2)

    await XCTAssertThrowsAsyncError(
      try await client.submitPrompt(sessionID: "session-1", text: "timeout")
    ) {
      XCTAssertEqual($0 as? HermesProtocolClientError, .requestTimedOut)
    }
    await client.close()
  }

  func testConnectionLossFailsPendingRequests() async throws {
    let client = try await readyClient()

    await XCTAssertThrowsAsyncError(
      try await client.submitPrompt(sessionID: "session-1", text: "close-pending")
    )
    await client.close()
  }

  func testRepeatedCloseIsIdempotent() async throws {
    let client = try await readyClient()

    await client.close()
    await client.close()

    XCTAssertEqual(client.state, .closed)
  }

  func testNoResidualFixtureProcess() async throws {
    let fixture = try startFixture()
    let client = try client(for: fixture)
    try await client.connectAndWaitUntilReady(timeout: 2)
    await client.close()
    fixture.stop()

    XCTAssertFalse(hasResidualFixtureProcess())
  }

  private var fixtureToken: HermesBackendSessionToken {
    HermesBackendSessionToken(rawValue: "fixture-token")
  }

  private func readyClient() async throws -> HermesProtocolClient {
    let fixture = try startFixture()
    let client = try client(for: fixture)
    try await client.connectAndWaitUntilReady(timeout: 2)
    return client
  }

  private func client(for fixture: FixtureBackend) throws -> HermesProtocolClient {
    HermesProtocolClient(
      endpoint: try HermesBackendEndpoint(port: fixture.port),
      token: fixtureToken,
      requestTimeout: 1
    )
  }

  private func startFixture(mode: String = "normal") throws -> FixtureBackend {
    let fixture = try FixtureBackend(token: fixtureToken.rawValue, mode: mode)
    fixtures.append(fixture)
    return fixture
  }

  private func hasResidualFixtureProcess() -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-axo", "pid=,command="]
    let pipe = Pipe()
    process.standardOutput = pipe
    do {
      try process.run()
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      let fixturePath = FixtureBackend.scriptURL.path
      return String(data: data, encoding: .utf8)?
        .components(separatedBy: .newlines)
        .contains { $0.contains(fixturePath) } ?? false
    } catch {
      return false
    }
  }
}

private final class FixtureBackend {
  static let scriptURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/hermes_fixture_backend.py")

  let process: Process
  let port: Int
  private let termination = DispatchSemaphore(value: 0)

  init(token: String, mode: String) throws {
    process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = [Self.scriptURL.path, "--token", token, "--mode", mode]
    process.terminationHandler = { [termination] _ in
      termination.signal()
    }

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    try process.run()

    let deadline = Date().addingTimeInterval(3)
    var readyData = Data()
    while Date() < deadline {
      readyData.append(stdout.fileHandleForReading.availableData)
      if let text = String(data: readyData, encoding: .utf8),
        let line = text.components(separatedBy: .newlines).first(where: {
          $0.hasPrefix("READY port=")
        }),
        let parsedPort = Int(line.replacingOccurrences(of: "READY port=", with: ""))
      {
        port = parsedPort
        return
      }
      if !process.isRunning {
        break
      }
      Thread.sleep(forTimeInterval: 0.01)
    }

    let errorText = String(data: stderr.fileHandleForReading.availableData, encoding: .utf8) ?? ""
    process.terminate()
    throw NSError(
      domain: "FixtureBackend",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: "fixture failed to start: \(errorText)"]
    )
  }

  func stop() {
    if process.isRunning {
      process.terminate()
      if termination.wait(timeout: .now() + 2) != .success, process.isRunning {
        kill(process.processIdentifier, SIGKILL)
        _ = termination.wait(timeout: .now() + 2)
      }
      return
    }
    _ = termination.wait(timeout: .now())
  }
}

private func XCTAssertThrowsAsyncError<T>(
  _ expression: @autoclosure () async throws -> T,
  _ errorHandler: (Error) -> Void = { _ in },
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  do {
    _ = try await expression()
    XCTFail("expected async error", file: file, line: line)
  } catch {
    errorHandler(error)
  }
}
