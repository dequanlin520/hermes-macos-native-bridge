import Foundation
import Security

public struct HermesBackendSessionToken: Equatable, Hashable, Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  static let byteCount = 32

  let rawValue: String

  public static func generate() throws -> HermesBackendSessionToken {
    var bytes = [UInt8](repeating: 0, count: byteCount)
    let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    guard result == errSecSuccess else {
      throw HermesProtocolClientError.tokenGenerationFailed
    }
    return HermesBackendSessionToken(rawValue: Data(bytes).base64URLEncodedString())
  }

  init(rawValue: String) {
    self.rawValue = rawValue
  }

  public var description: String {
    "<redacted HermesBackendSessionToken>"
  }

  public var debugDescription: String {
    description
  }
}

public struct HermesBackendEndpoint: Equatable, Sendable, CustomStringConvertible {
  public static let host = "127.0.0.1"
  public static let statusPath = "/api/status"
  public static let webSocketPath = "/api/ws"

  public let port: Int

  public init(port: Int) throws {
    guard (1...65535).contains(port) else {
      throw HermesProtocolClientError.invalidPort(port)
    }
    self.port = port
  }

  public var statusURL: URL {
    URL(string: "http://\(Self.host):\(port)\(Self.statusPath)")!
  }

  func webSocketURL(token: HermesBackendSessionToken) -> URL {
    var components = URLComponents()
    components.scheme = "ws"
    components.host = Self.host
    components.port = port
    components.path = Self.webSocketPath
    components.queryItems = [URLQueryItem(name: "token", value: token.rawValue)]
    return components.url!
  }

  public var description: String {
    "HermesBackendEndpoint(http://\(Self.host):\(port)\(Self.statusPath), ws://\(Self.host):\(port)\(Self.webSocketPath)?token=<redacted>)"
  }
}

public enum HermesBackendAuthMode: String, Decodable, Equatable, Sendable {
  case loopbackToken = "loopback_token"
  case oauthTicket = "oauth_ticket"
  case unknown

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let value = try container.decode(String.self)
    self = HermesBackendAuthMode(rawValue: value) ?? .unknown
  }
}

public struct HermesBackendStatus: Decodable, Equatable, Sendable {
  public let version: String
  public let releaseDate: String?
  public let authRequired: Bool?
  public let authMode: HermesBackendAuthMode?
  public let desktopContract: Int?
  public let gatewayRunning: Bool?
  public let gatewayState: String?
  public let activeAgents: Int?
  public let gatewayBusy: Bool?
  public let gatewayDrainable: Bool?

  enum CodingKeys: String, CodingKey {
    case version
    case releaseDate = "release_date"
    case authRequired = "auth_required"
    case authMode = "auth_mode"
    case desktopContract = "desktop_contract"
    case gatewayRunning = "gateway_running"
    case gatewayState = "gateway_state"
    case activeAgents = "active_agents"
    case gatewayBusy = "gateway_busy"
    case gatewayDrainable = "gateway_drainable"
  }
}

public enum HermesJSONRPCRequestID: Hashable, Codable, Sendable, CustomStringConvertible {
  case string(String)
  case integer(Int)

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let string = try? container.decode(String.self) {
      self = .string(string)
    } else {
      self = .integer(try container.decode(Int.self))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value):
      try container.encode(value)
    case .integer(let value):
      try container.encode(value)
    }
  }

  public var description: String {
    switch self {
    case .string(let value):
      return value
    case .integer(let value):
      return String(value)
    }
  }
}

public struct HermesJSONRPCError: Decodable, Error, Equatable, Sendable, CustomStringConvertible {
  public let code: Int
  public let message: String

  public var description: String {
    "JSON-RPC error \(code): \(message)"
  }
}

public enum HermesGatewayEvent: Equatable, Sendable {
  case gatewayReady
  case approvalRequest(HermesApprovalRequest)
  case backendEvent(HermesBackendEvent)
  case unknown(type: String?, metadata: [String: String])
}

public struct HermesBackendEvent: Equatable, Sendable {
  public let type: String
  public let sessionID: String?
  public let metadata: [String: String]
}

public struct HermesApprovalRequest: Equatable, Sendable {
  public let sessionID: String?
  public let approvalID: String?
  public let prompt: String?
  public let metadata: [String: String]
}

public enum HermesProtocolClientState: Equatable, Sendable {
  case disconnected
  case connecting
  case connected
  case ready
  case closing
  case closed
  case failed(HermesProtocolClientError)
}

public enum HermesApprovalDecision: String, Encodable, Equatable, Sendable {
  case approve
  case reject
}

public struct HermesSessionCreationResult: Decodable, Equatable, Sendable {
  public let sessionID: String
  public let storedSessionID: String?
  public let messageCount: Int?
  public let desktopContract: Int?

  enum CodingKeys: String, CodingKey {
    case sessionID = "session_id"
    case storedSessionID = "stored_session_id"
    case messageCount = "message_count"
    case desktopContract = "desktop_contract"
    case info
  }

  enum InfoCodingKeys: String, CodingKey {
    case desktopContract = "desktop_contract"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    sessionID = try container.decode(String.self, forKey: .sessionID)
    storedSessionID = try container.decodeIfPresent(String.self, forKey: .storedSessionID)
    messageCount = try container.decodeIfPresent(Int.self, forKey: .messageCount)
    if let value = try container.decodeIfPresent(Int.self, forKey: .desktopContract) {
      desktopContract = value
    } else if container.contains(.info) {
      let info = try container.nestedContainer(keyedBy: InfoCodingKeys.self, forKey: .info)
      desktopContract = try info.decodeIfPresent(Int.self, forKey: .desktopContract)
    } else {
      desktopContract = nil
    }
  }
}

public struct HermesPromptSubmissionResult: Decodable, Equatable, Sendable {
  public let status: String
}

public struct HermesSessionStatusResult: Decodable, Equatable, Sendable {
  public let output: String?
}

public struct HermesSessionInterruptResult: Decodable, Equatable, Sendable {
  public let status: String
}

public struct HermesApprovalResponseResult: Decodable, Equatable, Sendable {
  public let resolved: Bool
}

public enum HermesProtocolClientError: Error, Equatable, Sendable, CustomStringConvertible {
  case tokenGenerationFailed
  case invalidPort(Int)
  case invalidSessionID
  case promptTooLong(maximumBytes: Int)
  case payloadTooLarge(maximumBytes: Int)
  case tooManyPendingRequests(maximum: Int)
  case notConnected
  case notReady
  case malformedStatus
  case unexpectedHTTPStatus(Int)
  case webSocketClosed
  case requestTimedOut
  case responseIDMismatch
  case malformedFrame
  case rpcError(code: Int, message: String)
  case transport(String)

  public var description: String {
    switch self {
    case .tokenGenerationFailed:
      return "failed to generate Hermes backend session token"
    case .invalidPort(let port):
      return "invalid Hermes backend port \(port)"
    case .invalidSessionID:
      return "invalid Hermes session identifier"
    case .promptTooLong(let maximumBytes):
      return "prompt exceeds \(maximumBytes) bytes"
    case .payloadTooLarge(let maximumBytes):
      return "JSON payload exceeds \(maximumBytes) bytes"
    case .tooManyPendingRequests(let maximum):
      return "too many pending Hermes requests; maximum is \(maximum)"
    case .notConnected:
      return "Hermes protocol client is not connected"
    case .notReady:
      return "Hermes protocol client is not ready"
    case .malformedStatus:
      return "Hermes backend returned malformed status"
    case .unexpectedHTTPStatus(let status):
      return "Hermes backend returned HTTP \(status)"
    case .webSocketClosed:
      return "Hermes WebSocket closed"
    case .requestTimedOut:
      return "Hermes request timed out"
    case .responseIDMismatch:
      return "Hermes response ID mismatch"
    case .malformedFrame:
      return "Hermes backend returned a malformed JSON-RPC frame"
    case .rpcError(let code, let message):
      return "Hermes JSON-RPC error \(code): \(message)"
    case .transport(let message):
      return "Hermes transport error: \(message)"
    }
  }
}

public final class HermesProtocolClient: @unchecked Sendable {
  public let endpoint: HermesBackendEndpoint
  public let token: HermesBackendSessionToken
  public let maximumPayloadBytes: Int
  public let maximumPendingRequests: Int
  public let requestTimeout: TimeInterval

  private let session: URLSession
  private let decoder = JSONDecoder()
  private let encoder = JSONEncoder()
  private let lock = NSLock()
  private var webSocketTask: URLSessionWebSocketTask?
  private var pending: [HermesJSONRPCRequestID: PendingRequest] = [:]
  private var nextRequestNumber = 0
  private var eventContinuation: AsyncStream<HermesGatewayEvent>.Continuation?
  private var readyContinuation: CheckedContinuation<Void, Error>?
  private var closed = false
  private var storedState: HermesProtocolClientState = .disconnected

  public private(set) var state: HermesProtocolClientState {
    get { lock.withLock { storedState } }
    set { lock.withLock { storedState = newValue } }
  }

  public lazy var events: AsyncStream<HermesGatewayEvent> = {
    AsyncStream { continuation in
      self.lock.withLock {
        self.eventContinuation = continuation
      }
    }
  }()

  public init(
    endpoint: HermesBackendEndpoint,
    token: HermesBackendSessionToken,
    session: URLSession = .shared,
    maximumPayloadBytes: Int = 256 * 1024,
    maximumPendingRequests: Int = 32,
    requestTimeout: TimeInterval = 5
  ) {
    self.endpoint = endpoint
    self.token = token
    self.session = session
    self.maximumPayloadBytes = max(1024, maximumPayloadBytes)
    self.maximumPendingRequests = max(1, maximumPendingRequests)
    self.requestTimeout = max(0.001, requestTimeout)
  }

  public func fetchStatus() async throws -> HermesBackendStatus {
    var request = URLRequest(url: endpoint.statusURL)
    request.httpMethod = "GET"
    request.setValue(token.rawValue, forHTTPHeaderField: "X-Hermes-Session-Token")

    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw HermesProtocolClientError.transport(String(describing: error))
    }

    if let httpResponse = response as? HTTPURLResponse,
      !(200...299).contains(httpResponse.statusCode)
    {
      throw HermesProtocolClientError.unexpectedHTTPStatus(httpResponse.statusCode)
    }

    guard data.count <= maximumPayloadBytes else {
      throw HermesProtocolClientError.payloadTooLarge(maximumBytes: maximumPayloadBytes)
    }

    do {
      return try decoder.decode(HermesBackendStatus.self, from: data)
    } catch {
      throw HermesProtocolClientError.malformedStatus
    }
  }

  public func connectAndWaitUntilReady(timeout: TimeInterval = 5) async throws {
    try await connect()
    try await waitUntilReady(timeout: timeout)
  }

  public func connect() async throws {
    let task: URLSessionWebSocketTask = try lock.withLock {
      switch storedState {
      case .disconnected, .closed, .failed:
        storedState = .connecting
      case .connecting, .connected, .ready:
        throw HermesProtocolClientError.notConnected
      case .closing:
        throw HermesProtocolClientError.webSocketClosed
      }

      closed = false
      let task = session.webSocketTask(with: endpoint.webSocketURL(token: token))
      webSocketTask = task
      return task
    }

    task.resume()
    state = .connected
    Task { await self.receiveLoop() }
  }

  public func waitUntilReady(timeout: TimeInterval = 5) async throws {
    if state == .ready {
      return
    }

    try await withCheckedThrowingContinuation { continuation in
      let shouldScheduleTimeout: Bool = self.lock.withLock {
        if self.storedState == .ready {
          continuation.resume()
          return false
        } else if case .failed(let error) = self.storedState {
          continuation.resume(throwing: error)
          return false
        } else if self.closed {
          continuation.resume(throwing: HermesProtocolClientError.webSocketClosed)
          return false
        } else {
          self.readyContinuation = continuation
          return true
        }
      }
      if shouldScheduleTimeout {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(0.001, timeout)) {
          let continuationToResume: CheckedContinuation<Void, Error>? = self.lock.withLock {
            guard self.readyContinuation != nil, self.storedState != .ready else {
              return nil
            }
            let continuation = self.readyContinuation
            self.readyContinuation = nil
            return continuation
          }
          continuationToResume?.resume(throwing: HermesProtocolClientError.requestTimedOut)
        }
      }
    }
  }

  public func close() async {
    let pendingToFail: [PendingRequest] = lock.withLock {
      if closed {
        return []
      }
      closed = true
      storedState = .closing
      let values = Array(pending.values)
      pending.removeAll()
      return values
    }

    for request in pendingToFail {
      request.complete(.failure(HermesProtocolClientError.webSocketClosed))
    }

    webSocketTask?.cancel(with: .normalClosure, reason: nil)
    lock.withLock {
      storedState = .closed
      readyContinuation?.resume(throwing: HermesProtocolClientError.webSocketClosed)
      readyContinuation = nil
      eventContinuation?.finish()
    }
  }

  public func createSession() async throws -> HermesSessionCreationResult {
    try await sendTyped(method: "session.create", params: EmptyParams())
  }

  public func submitPrompt(sessionID: String, text: String) async throws
    -> HermesPromptSubmissionResult
  {
    try validate(sessionID: sessionID)
    guard text.utf8.count <= Limits.maximumPromptBytes else {
      throw HermesProtocolClientError.promptTooLong(maximumBytes: Limits.maximumPromptBytes)
    }
    return try await sendTyped(
      method: "prompt.submit",
      params: PromptSubmitParams(sessionID: sessionID, text: text)
    )
  }

  public func sessionStatus(sessionID: String) async throws -> HermesSessionStatusResult {
    try validate(sessionID: sessionID)
    return try await sendTyped(
      method: "session.status",
      params: SessionIDParams(sessionID: sessionID)
    )
  }

  public func interruptSession(sessionID: String) async throws -> HermesSessionInterruptResult {
    try validate(sessionID: sessionID)
    return try await sendTyped(
      method: "session.interrupt",
      params: SessionIDParams(sessionID: sessionID)
    )
  }

  public func respondToApproval(
    sessionID: String,
    decision: HermesApprovalDecision,
    all: Bool? = nil
  ) async throws -> HermesApprovalResponseResult {
    try validate(sessionID: sessionID)
    return try await sendTyped(
      method: "approval.respond",
      params: ApprovalRespondParams(sessionID: sessionID, choice: decision.rawValue, all: all)
    )
  }

  private func sendTyped<Params: Encodable, Result: Decodable & Sendable>(
    method: String,
    params: Params
  ) async throws -> Result {
    guard state == .ready else {
      throw HermesProtocolClientError.notReady
    }
    let requestID = try registerPendingRequest()
    let envelope = JSONRPCRequestEnvelope(id: requestID, method: method, params: params)
    let data: Data
    do {
      data = try encoder.encode(envelope)
    } catch {
      completePending(id: requestID, result: .failure(HermesProtocolClientError.malformedFrame))
      throw HermesProtocolClientError.malformedFrame
    }
    guard data.count <= maximumPayloadBytes else {
      completePending(
        id: requestID,
        result: .failure(
          HermesProtocolClientError.payloadTooLarge(maximumBytes: maximumPayloadBytes))
      )
      throw HermesProtocolClientError.payloadTooLarge(maximumBytes: maximumPayloadBytes)
    }
    guard let text = String(data: data, encoding: .utf8) else {
      completePending(id: requestID, result: .failure(HermesProtocolClientError.malformedFrame))
      throw HermesProtocolClientError.malformedFrame
    }
    guard let task = lock.withLock({ webSocketTask }) else {
      completePending(id: requestID, result: .failure(HermesProtocolClientError.notConnected))
      throw HermesProtocolClientError.notConnected
    }

    do {
      try await task.send(.string(text))
    } catch {
      completePending(
        id: requestID,
        result: .failure(HermesProtocolClientError.transport(String(describing: error))))
      throw HermesProtocolClientError.transport(String(describing: error))
    }

    return try await waitForResponse(id: requestID, as: Result.self)
  }

  private func registerPendingRequest() throws -> HermesJSONRPCRequestID {
    try lock.withLock {
      guard pending.count < maximumPendingRequests else {
        throw HermesProtocolClientError.tooManyPendingRequests(maximum: maximumPendingRequests)
      }
      nextRequestNumber += 1
      let id = HermesJSONRPCRequestID.string("bridge-\(nextRequestNumber)")
      pending[id] = PendingRequest()
      return id
    }
  }

  private func waitForResponse<Result: Decodable & Sendable>(
    id: HermesJSONRPCRequestID,
    as type: Result.Type
  ) async throws -> Result {
    let pendingRequest = lock.withLock { pending[id] }
    guard let pendingRequest else {
      throw HermesProtocolClientError.responseIDMismatch
    }

    let data = try await withThrowingTaskGroup(of: Data.self) { group in
      group.addTask {
        try await pendingRequest.value()
      }
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(self.requestTimeout * 1_000_000_000))
        self.completePending(id: id, result: .failure(HermesProtocolClientError.requestTimedOut))
        throw HermesProtocolClientError.requestTimedOut
      }
      let data = try await group.next()!
      group.cancelAll()
      return data
    }

    do {
      return try decoder.decode(type, from: data)
    } catch {
      throw HermesProtocolClientError.malformedFrame
    }
  }

  private func receiveLoop() async {
    while true {
      guard let task = lock.withLock({ webSocketTask }), !closed else {
        return
      }
      do {
        let message = try await task.receive()
        try handle(message: message)
      } catch {
        failConnection(HermesProtocolClientError.transport(String(describing: error)))
        return
      }
    }
  }

  private func handle(message: URLSessionWebSocketTask.Message) throws {
    let data: Data
    switch message {
    case .string(let text):
      guard let encoded = text.data(using: .utf8) else {
        throw HermesProtocolClientError.malformedFrame
      }
      data = encoded
    case .data(let received):
      data = received
    @unknown default:
      throw HermesProtocolClientError.malformedFrame
    }

    guard data.count <= maximumPayloadBytes else {
      throw HermesProtocolClientError.payloadTooLarge(maximumBytes: maximumPayloadBytes)
    }

    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw HermesProtocolClientError.malformedFrame
    }

    if object["id"] != nil {
      try handleResponse(data: data)
    } else if object["method"] as? String == "event" {
      try handleEventFrame(object)
    } else {
      eventContinuation?.yield(.unknown(type: object["method"] as? String, metadata: [:]))
    }
  }

  private func handleResponse(data: Data) throws {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      object["jsonrpc"] as? String == "2.0",
      let idValue = object["id"]
    else {
      throw HermesProtocolClientError.malformedFrame
    }

    let responseID: HermesJSONRPCRequestID
    if let stringID = idValue as? String {
      responseID = .string(stringID)
    } else if let integerID = idValue as? Int {
      responseID = .integer(integerID)
    } else {
      throw HermesProtocolClientError.malformedFrame
    }

    if let errorObject = object["error"] as? [String: Any] {
      let errorData = try JSONSerialization.data(withJSONObject: errorObject)
      let error = try decoder.decode(HermesJSONRPCError.self, from: errorData)
      completePending(
        id: responseID,
        result: .failure(
          HermesProtocolClientError.rpcError(code: error.code, message: error.message))
      )
      return
    }

    guard let resultObject = object["result"] else {
      completePending(id: responseID, result: .failure(HermesProtocolClientError.malformedFrame))
      return
    }

    let resultData = try JSONSerialization.data(
      withJSONObject: resultObject, options: [.fragmentsAllowed])
    completePending(id: responseID, result: .success(resultData))
  }

  private func handleEventFrame(_ object: [String: Any]) throws {
    guard let params = object["params"] as? [String: Any] else {
      eventContinuation?.yield(.unknown(type: nil, metadata: [:]))
      return
    }
    let type = params["type"] as? String
    let metadata = Self.boundedMetadata(from: params)

    switch type {
    case "gateway.ready":
      state = .ready
      lock.withLock {
        readyContinuation?.resume()
        readyContinuation = nil
      }
      eventContinuation?.yield(.gatewayReady)
    case "approval.request":
      eventContinuation?.yield(
        .approvalRequest(
          HermesApprovalRequest(
            sessionID: params["session_id"] as? String,
            approvalID: params["approval_id"] as? String,
            prompt: params["prompt"] as? String,
            metadata: metadata
          )))
    case .some(let eventType):
      eventContinuation?.yield(
        .backendEvent(
          HermesBackendEvent(
            type: eventType,
            sessionID: params["session_id"] as? String,
            metadata: metadata
          )))
    case .none:
      eventContinuation?.yield(.unknown(type: nil, metadata: metadata))
    }
  }

  private func completePending(
    id: HermesJSONRPCRequestID,
    result: Result<Data, HermesProtocolClientError>
  ) {
    let request = lock.withLock { pending.removeValue(forKey: id) }
    request?.complete(result)
  }

  private func failConnection(_ error: HermesProtocolClientError) {
    let pendingToFail: [PendingRequest] = lock.withLock {
      if closed {
        return []
      }
      storedState = .failed(error)
      let values = Array(pending.values)
      pending.removeAll()
      readyContinuation?.resume(throwing: error)
      readyContinuation = nil
      eventContinuation?.finish()
      return values
    }
    for request in pendingToFail {
      request.complete(.failure(error))
    }
  }

  private func validate(sessionID: String) throws {
    guard !sessionID.isEmpty,
      sessionID.utf8.count <= Limits.maximumSessionIDBytes,
      sessionID.range(of: #"^[A-Za-z0-9._:-]+$"#, options: .regularExpression) != nil
    else {
      throw HermesProtocolClientError.invalidSessionID
    }
  }

  private static func boundedMetadata(from params: [String: Any]) -> [String: String] {
    var metadata: [String: String] = [:]
    for (key, value) in params.sorted(by: { $0.key < $1.key }).prefix(16) {
      guard key != "type", key != "session_id" else {
        continue
      }
      let rendered: String
      if let string = value as? String {
        rendered = string
      } else {
        rendered = String(describing: value)
      }
      metadata[key] = String(rendered.prefix(512))
    }
    return metadata
  }
}

private enum Limits {
  static let maximumSessionIDBytes = 256
  static let maximumPromptBytes = 64 * 1024
}

private struct EmptyParams: Encodable {}

private struct SessionIDParams: Encodable {
  let sessionID: String

  enum CodingKeys: String, CodingKey {
    case sessionID = "session_id"
  }
}

private struct PromptSubmitParams: Encodable {
  let sessionID: String
  let text: String

  enum CodingKeys: String, CodingKey {
    case sessionID = "session_id"
    case text
  }
}

private struct ApprovalRespondParams: Encodable {
  let sessionID: String
  let choice: String
  let all: Bool?

  enum CodingKeys: String, CodingKey {
    case sessionID = "session_id"
    case choice
    case all
  }
}

private struct JSONRPCRequestEnvelope<Params: Encodable>: Encodable {
  let jsonrpc = "2.0"
  let id: HermesJSONRPCRequestID
  let method: String
  let params: Params
}

private final class PendingRequest: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Data, Error>?
  private var completed: Result<Data, HermesProtocolClientError>?

  func value() async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
      lock.withLock {
        if let completed {
          continuation.resume(with: completed.mapError { $0 as Error })
        } else {
          self.continuation = continuation
        }
      }
    }
  }

  func complete(_ result: Result<Data, HermesProtocolClientError>) {
    let continuation: CheckedContinuation<Data, Error>? = lock.withLock {
      if completed != nil {
        return nil
      }
      completed = result
      let continuation = self.continuation
      self.continuation = nil
      return continuation
    }
    continuation?.resume(with: result.mapError { $0 as Error })
  }
}

extension Data {
  fileprivate func base64URLEncodedString() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
