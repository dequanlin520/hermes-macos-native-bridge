import Foundation
import HermesRuntimeFoundation

public enum HermesBridgeXPCClientError: Error, Equatable, Sendable {
  case timedOut
  case interrupted
  case invalidated
  case responseDecodingFailure
  case service(HermesBridgeXPCError)
  case protocolNegotiationFailed
}

public struct HermesBridgeMachServiceName: Equatable, Hashable, Sendable, CustomStringConvertible {
  public static let maximumLength = 255

  public let rawValue: String

  public init(_ rawValue: String) throws {
    guard !rawValue.isEmpty, rawValue.count <= Self.maximumLength else {
      throw HermesBridgeXPCClientError.protocolNegotiationFailed
    }
    guard
      rawValue.allSatisfy({ character in
        character.isASCII
          && (character.isLetter || character.isNumber || character == "." || character == "-"
            || character == "_")
      })
    else {
      throw HermesBridgeXPCClientError.protocolNegotiationFailed
    }
    self.rawValue = rawValue
  }

  public var description: String {
    rawValue
  }
}

public actor HermesBridgeXPCClient {
  private let transport: HermesBridgeXPCTransport
  private let timeout: TimeInterval
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()
  private var closed = false
  private var connected = false

  public init(machServiceName: HermesBridgeMachServiceName, timeout: TimeInterval = 5) {
    self.transport = HermesBridgeMachServiceTransport(machServiceName: machServiceName.rawValue)
    self.timeout = max(0.001, timeout)
  }

  init(transport: HermesBridgeXPCTransport, timeout: TimeInterval = 5) {
    self.transport = transport
    self.timeout = max(0.001, timeout)
  }

  @discardableResult
  public func connect() async throws -> HermesBridgeCapabilitiesPayload {
    let version = try await protocolVersion()
    guard version.version.major == HermesBridgeProtocolVersion.current.major else {
      throw HermesBridgeXPCClientError.protocolNegotiationFailed
    }
    let capabilities = try await capabilities()
    guard capabilities.protocolVersion.major == HermesBridgeProtocolVersion.current.major else {
      throw HermesBridgeXPCClientError.protocolNegotiationFailed
    }
    connected = true
    return capabilities
  }

  public func protocolVersion() async throws -> HermesBridgeProtocolVersionPayload {
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .protocolVersion
      ))
    guard case .success(.protocolVersion(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func capabilities() async throws -> HermesBridgeCapabilitiesPayload {
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .capabilities
      ))
    guard case .success(.capabilities(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func listEnabledBindings() async throws -> HermesBridgeBindingListPayload {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .listEnabledBindings
      ))
    guard case .success(.listEnabledBindings(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func submit(bindingID: HermesRequestBindingID, prompt: String) async throws
    -> HermesRequestID
  {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .submit,
        submit: HermesBridgeSubmitPayload(bindingID: bindingID.rawValue, prompt: prompt)
      ))
    guard case .success(.submit(let payload)) = response.result else {
      throw clientError(from: response)
    }
    do {
      return try HermesRequestID(rawValue: payload.requestID)
    } catch {
      throw HermesBridgeXPCClientError.responseDecodingFailure
    }
  }

  public func status(requestID: HermesRequestID) async throws -> HermesBridgeRequestStatusPayload {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .status,
        status: HermesBridgeRequestIDPayload(requestID: requestID.rawValue)
      ))
    guard case .success(.status(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func cancel(requestID: HermesRequestID) async throws -> HermesBridgeRequestStatusPayload {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .cancel,
        cancel: HermesBridgeRequestIDPayload(requestID: requestID.rawValue)
      ))
    guard case .success(.cancel(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func respondToApproval(
    requestID: HermesRequestID,
    decision: HermesBridgeApprovalDecision
  ) async throws -> HermesBridgeRequestStatusPayload {
    try ensureOpen()
    let response = try await send(
      HermesBridgeRequestEnvelope(
        correlationID: Self.correlationID(),
        operation: .approvalResponse,
        approvalResponse: HermesBridgeApprovalResponsePayload(
          requestID: requestID.rawValue,
          decision: decision
        )
      ))
    guard case .success(.approvalResponse(let payload)) = response.result else {
      throw clientError(from: response)
    }
    return payload
  }

  public func close() {
    if closed {
      return
    }
    closed = true
    transport.close()
  }

  private func send(_ envelope: HermesBridgeRequestEnvelope) async throws
    -> HermesBridgeResponseEnvelope
  {
    try ensureOpen()
    let requestData = try encoder.encode(envelope)
    let responseData = try await withThrowingTaskGroup(of: Data.self) { group in
      group.addTask {
        try await self.transport.send(requestData)
      }
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(self.timeout * 1_000_000_000))
        throw HermesBridgeXPCClientError.timedOut
      }
      let data = try await group.next()!
      group.cancelAll()
      return data
    }
    do {
      let response = try decoder.decode(HermesBridgeResponseEnvelope.self, from: responseData)
      guard response.correlationID == envelope.correlationID else {
        throw HermesBridgeXPCClientError.responseDecodingFailure
      }
      return response
    } catch let error as HermesBridgeXPCClientError {
      throw error
    } catch {
      throw HermesBridgeXPCClientError.responseDecodingFailure
    }
  }

  private func ensureOpen() throws {
    if closed {
      throw HermesBridgeXPCClientError.invalidated
    }
  }

  private func clientError(from response: HermesBridgeResponseEnvelope)
    -> HermesBridgeXPCClientError
  {
    switch response.result {
    case .failure(let error):
      return .service(error.code)
    case .success:
      return .responseDecodingFailure
    }
  }

  private static func correlationID() -> HermesBridgeCorrelationID {
    try! HermesBridgeCorrelationID(rawValue: UUID().uuidString)
  }
}

public struct HermesBridgeAppIntentAdapter: Sendable {
  private let client: HermesBridgeXPCClient

  public init(client: HermesBridgeXPCClient) {
    self.client = client
  }

  public func submit(bindingID: HermesRequestBindingID, prompt: String) async throws
    -> HermesRequestID
  {
    try await client.submit(bindingID: bindingID, prompt: prompt)
  }

  public func status(requestID: HermesRequestID) async throws -> HermesBridgeRequestStatusPayload {
    try await client.status(requestID: requestID)
  }

  public func cancel(requestID: HermesRequestID) async throws -> HermesBridgeRequestStatusPayload {
    try await client.cancel(requestID: requestID)
  }

  public func listEnabledBindings() async throws -> HermesBridgeBindingListPayload {
    try await client.listEnabledBindings()
  }
}

protocol HermesBridgeXPCTransport: Sendable {
  func send(_ requestData: Data) async throws -> Data
  func close()
}

final class HermesBridgeMachServiceTransport: HermesBridgeXPCTransport, @unchecked Sendable {
  private let lock = NSLock()
  private let connection: NSXPCConnection
  private var closed = false
  private var unavailableError: HermesBridgeXPCClientError?

  init(machServiceName: String) {
    connection = NSXPCConnection(machServiceName: machServiceName, options: [])
    connection.remoteObjectInterface = NSXPCInterface(with: HermesBridgeXPCProtocol.self)
    connection.interruptionHandler = { [weak self] in
      self?.setUnavailable(.interrupted)
    }
    connection.invalidationHandler = { [weak self] in
      self?.setUnavailable(.invalidated)
    }
    connection.resume()
  }

  func send(_ requestData: Data) async throws -> Data {
    let proxy: HermesBridgeXPCProtocol = try lock.withLock {
      if let unavailableError {
        throw unavailableError
      }
      if closed {
        throw HermesBridgeXPCClientError.invalidated
      }
      guard
        let proxy = connection.remoteObjectProxyWithErrorHandler({ [weak self] _ in
          self?.setUnavailable(.interrupted)
        }) as? HermesBridgeXPCProtocol
      else {
        throw HermesBridgeXPCClientError.interrupted
      }
      return proxy
    }

    return try await withCheckedThrowingContinuation { continuation in
      let resumer = HermesBridgeXPCReplyResumer(continuation)
      proxy.handleRequest(requestData) { data in
        resumer.resume(returning: data)
      }
    }
  }

  func close() {
    lock.withLock {
      if closed {
        return
      }
      closed = true
      unavailableError = .invalidated
      connection.invalidate()
    }
  }

  private func setUnavailable(_ error: HermesBridgeXPCClientError) {
    lock.withLock {
      unavailableError = error
    }
  }
}

private final class HermesBridgeXPCReplyResumer: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Data, Error>?

  init(_ continuation: CheckedContinuation<Data, Error>) {
    self.continuation = continuation
  }

  func resume(returning data: Data) {
    let continuation = lock.withLock {
      let current = self.continuation
      self.continuation = nil
      return current
    }
    continuation?.resume(returning: data)
  }
}
