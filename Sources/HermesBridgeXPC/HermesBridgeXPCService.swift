import Foundation
import HermesRuntimeFoundation

@objc public protocol HermesBridgeXPCProtocol {
  func handleRequest(_ requestData: Data, withReply reply: @escaping (Data) -> Void)
}

public protocol HermesBridgeRequestHandling: Sendable {
  func listEnabledBindings() async throws -> [HermesBridgeBindingSummary]
  func submit(bindingID: HermesRequestBindingID, prompt: String) async throws -> HermesRequestID
  func status(requestID: HermesRequestID) async throws -> HermesRequestRecord
  func cancel(requestID: HermesRequestID) async throws -> HermesRequestRecord
  func respondToApproval(
    requestID: HermesRequestID,
    decision: HermesApprovalResponseDecision
  ) async throws -> HermesRequestRecord
}

extension HermesRequestOrchestrator: HermesBridgeRequestHandling {}

extension HermesBridgeRequestHandling {
  public func listEnabledBindings() async throws -> [HermesBridgeBindingSummary] {
    throw HermesBridgeXPCError.unsupportedOperation
  }
}

public actor HermesBridgeXPCRequestDispatcher {
  private let handler: HermesBridgeRequestHandling
  private let maximumConcurrentRequests: Int
  private let decoder: JSONDecoder
  private let encoder: JSONEncoder
  private var inFlight = 0

  public init(
    handler: HermesBridgeRequestHandling,
    maximumConcurrentRequests: Int = 8
  ) {
    self.handler = handler
    self.maximumConcurrentRequests = max(1, maximumConcurrentRequests)
    self.decoder = JSONDecoder()
    self.encoder = JSONEncoder()
  }

  public func handle(_ requestData: Data) async -> Data {
    guard requestData.count <= HermesBridgeRequestEnvelope.maximumEnvelopeBytes else {
      return encodeFailure(.oversizedPayload, correlationID: .fallback)
    }

    let preflight: HermesBridgeRequestPreflight
    do {
      preflight = try decoder.decode(HermesBridgeRequestPreflight.self, from: requestData)
    } catch {
      return encodeFailure(.malformedPayload, correlationID: .fallback)
    }

    guard preflight.protocolVersion.isSupported else {
      return encodeFailure(.unsupportedProtocolVersion, correlationID: preflight.correlationID)
    }
    guard HermesBridgeOperation(rawValue: preflight.operation) != nil else {
      return encodeFailure(.unsupportedOperation, correlationID: preflight.correlationID)
    }

    guard inFlight < maximumConcurrentRequests else {
      return encodeFailure(.serviceUnavailable, correlationID: preflight.correlationID)
    }
    inFlight += 1
    defer {
      inFlight -= 1
    }

    do {
      let envelope = try decoder.decode(HermesBridgeRequestEnvelope.self, from: requestData)
      try validateEnvelope(envelope)
      let payload = try await dispatch(envelope)
      return encodeResponse(
        HermesBridgeResponseEnvelope(
          correlationID: envelope.correlationID,
          result: .success(payload)
        ))
    } catch let error as HermesBridgeXPCError {
      return encodeFailure(error, correlationID: preflight.correlationID)
    } catch is DecodingError {
      return encodeFailure(.malformedPayload, correlationID: preflight.correlationID)
    } catch {
      return encodeFailure(.internalFailure, correlationID: preflight.correlationID)
    }
  }

  private func validateEnvelope(_ envelope: HermesBridgeRequestEnvelope) throws {
    guard envelope.protocolVersion.isSupported else {
      throw HermesBridgeXPCError.unsupportedProtocolVersion
    }
    switch envelope.operation {
    case .submit:
      guard envelope.submit != nil, envelope.status == nil, envelope.cancel == nil,
        envelope.approvalResponse == nil
      else {
        throw HermesBridgeXPCError.malformedPayload
      }
      guard let prompt = envelope.submit?.prompt,
        !prompt.isEmpty,
        prompt.utf8.count <= HermesBridgeRequestEnvelope.maximumPromptBytes
      else {
        throw HermesBridgeXPCError.oversizedPayload
      }
    case .status:
      guard envelope.status != nil, envelope.submit == nil, envelope.cancel == nil,
        envelope.approvalResponse == nil
      else {
        throw HermesBridgeXPCError.malformedPayload
      }
    case .cancel:
      guard envelope.cancel != nil, envelope.submit == nil, envelope.status == nil,
        envelope.approvalResponse == nil
      else {
        throw HermesBridgeXPCError.malformedPayload
      }
    case .approvalResponse:
      guard envelope.approvalResponse != nil, envelope.submit == nil, envelope.status == nil,
        envelope.cancel == nil
      else {
        throw HermesBridgeXPCError.malformedPayload
      }
    case .capabilities, .protocolVersion, .listEnabledBindings:
      guard envelope.submit == nil, envelope.status == nil, envelope.cancel == nil,
        envelope.approvalResponse == nil
      else {
        throw HermesBridgeXPCError.malformedPayload
      }
    }
  }

  private func dispatch(_ envelope: HermesBridgeRequestEnvelope) async throws
    -> HermesBridgeSuccessPayload
  {
    switch envelope.operation {
    case .protocolVersion:
      return .protocolVersion(HermesBridgeProtocolVersionPayload(version: .current))
    case .capabilities:
      return .capabilities(HermesBridgeCapabilitiesPayload())
    case .listEnabledBindings:
      return .listEnabledBindings(
        try HermesBridgeBindingListPayload(bindings: try await handler.listEnabledBindings()))
    case .submit:
      guard let submit = envelope.submit else {
        throw HermesBridgeXPCError.malformedPayload
      }
      let bindingID: HermesRequestBindingID
      do {
        bindingID = try HermesRequestBindingID(rawValue: submit.bindingID)
      } catch {
        throw HermesBridgeXPCError.invalidBinding
      }
      let requestID = try await mapOrchestratorError {
        try await handler.submit(bindingID: bindingID, prompt: submit.prompt)
      }
      return .submit(HermesBridgeRequestIDPayload(requestID: requestID.rawValue))
    case .status:
      let requestID = try decodeRequestID(envelope.status?.requestID)
      let record = try await mapOrchestratorError {
        try await handler.status(requestID: requestID)
      }
      return .status(HermesBridgeRequestStatusPayload(record: record))
    case .cancel:
      let requestID = try decodeRequestID(envelope.cancel?.requestID)
      let record = try await mapOrchestratorError {
        try await handler.cancel(requestID: requestID)
      }
      return .cancel(HermesBridgeRequestStatusPayload(record: record))
    case .approvalResponse:
      guard let approval = envelope.approvalResponse else {
        throw HermesBridgeXPCError.malformedPayload
      }
      let requestID = try decodeRequestID(approval.requestID)
      let record = try await mapOrchestratorError {
        try await handler.respondToApproval(
          requestID: requestID,
          decision: approval.decision.orchestratorDecision
        )
      }
      return .approvalResponse(HermesBridgeRequestStatusPayload(record: record))
    }
  }

  private func decodeRequestID(_ rawValue: String?) throws -> HermesRequestID {
    guard let rawValue else {
      throw HermesBridgeXPCError.malformedPayload
    }
    do {
      return try HermesRequestID(rawValue: rawValue)
    } catch {
      throw HermesBridgeXPCError.malformedPayload
    }
  }

  private func mapOrchestratorError<T>(
    _ body: () async throws -> T
  ) async throws -> T {
    do {
      return try await body()
    } catch let error as HermesRequestOrchestratorError {
      switch error {
      case .invalidBinding:
        throw HermesBridgeXPCError.invalidBinding
      case .requestNotFound:
        throw HermesBridgeXPCError.requestNotFound
      case .invalidCancellationState:
        throw HermesBridgeXPCError.invalidState
      case .backendLaunchFailure, .backendConnectionFailure, .sessionCreationFailure,
        .promptSubmissionFailure, .shutdownFailure:
        throw HermesBridgeXPCError.serviceUnavailable
      case .duplicateRequest, .stateStoreFailure, .reconciliationRequired:
        throw HermesBridgeXPCError.internalFailure
      }
    } catch {
      throw HermesBridgeXPCError.internalFailure
    }
  }

  private func encodeFailure(
    _ error: HermesBridgeXPCError,
    correlationID: HermesBridgeCorrelationID
  ) -> Data {
    encodeResponse(
      HermesBridgeResponseEnvelope(
        correlationID: correlationID,
        result: .failure(
          HermesBridgeErrorPayload(code: error, safeMessage: Self.safeMessage(for: error))
        )
      ))
  }

  private func encodeResponse(_ response: HermesBridgeResponseEnvelope) -> Data {
    do {
      return try encoder.encode(response)
    } catch {
      let fallback = HermesBridgeResponseEnvelope(
        correlationID: response.correlationID,
        result: .failure(
          HermesBridgeErrorPayload(
            code: .internalFailure,
            safeMessage: Self.safeMessage(for: .internalFailure)
          )
        )
      )
      return (try? encoder.encode(fallback)) ?? Data()
    }
  }

  private static func safeMessage(for error: HermesBridgeXPCError) -> String {
    switch error {
    case .unsupportedProtocolVersion:
      return "Unsupported Bridge XPC protocol version."
    case .malformedPayload:
      return "Bridge XPC payload is malformed."
    case .oversizedPayload:
      return "Bridge XPC payload exceeds the size limit."
    case .unsupportedOperation:
      return "Bridge XPC operation is unsupported."
    case .invalidBinding:
      return "Request binding is not allowed."
    case .requestNotFound:
      return "Request was not found."
    case .invalidState:
      return "Request is not in a valid state for this operation."
    case .serviceUnavailable:
      return "Bridge XPC service is unavailable."
    case .internalFailure:
      return "Bridge XPC service failed internally."
    }
  }
}

public final class HermesBridgeXPCService: NSObject, HermesBridgeXPCProtocol, @unchecked Sendable {
  private let dispatcher: HermesBridgeXPCRequestDispatcher
  private let taskRegistry = HermesBridgeXPCTaskRegistry()

  public init(dispatcher: HermesBridgeXPCRequestDispatcher) {
    self.dispatcher = dispatcher
  }

  public convenience init(
    handler: HermesBridgeRequestHandling,
    maximumConcurrentRequests: Int = 8
  ) {
    self.init(
      dispatcher: HermesBridgeXPCRequestDispatcher(
        handler: handler,
        maximumConcurrentRequests: maximumConcurrentRequests
      ))
  }

  public func handleRequest(_ requestData: Data, withReply reply: @escaping (Data) -> Void) {
    let replyBox = HermesBridgeXPCReplyBox(reply)
    let task = Task {
      let responseData = await dispatcher.handle(requestData)
      if !Task.isCancelled {
        replyBox.reply(responseData)
      }
    }
    taskRegistry.insert(task)
  }

  public func invalidate() {
    taskRegistry.cancelAll()
  }
}

private struct HermesBridgeRequestPreflight: Decodable {
  let protocolVersion: HermesBridgeProtocolVersion
  let correlationID: HermesBridgeCorrelationID
  let operation: String
}

private final class HermesBridgeXPCTaskRegistry: @unchecked Sendable {
  private let lock = NSLock()
  private var tasks: [Task<Void, Never>] = []

  func insert(_ task: Task<Void, Never>) {
    lock.withLock {
      tasks.append(task)
      tasks.removeAll { $0.isCancelled }
    }
  }

  func cancelAll() {
    let current = lock.withLock {
      let current = tasks
      tasks.removeAll()
      return current
    }
    for task in current {
      task.cancel()
    }
  }
}

private final class HermesBridgeXPCReplyBox: @unchecked Sendable {
  private let lock = NSLock()
  private var replyClosure: ((Data) -> Void)?

  init(_ reply: @escaping (Data) -> Void) {
    self.replyClosure = reply
  }

  func reply(_ data: Data) {
    let closure = lock.withLock {
      let current = replyClosure
      replyClosure = nil
      return current
    }
    closure?(data)
  }
}
