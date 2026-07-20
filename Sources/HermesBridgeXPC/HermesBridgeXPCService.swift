import Foundation
import HermesRuntimeFoundation

@objc public protocol HermesBridgeXPCProtocol {
  func handleRequest(_ requestData: Data, withReply reply: @escaping (Data) -> Void)
}

public protocol HermesBridgeRequestHandling: Sendable {
  func listEnabledBindings() async throws -> [HermesBridgeBindingSummary]
  func listAuthorizedRoots() async throws -> HermesBridgeAuthorizedRootListPayload
  func registerAuthorizedRoot(
    displayName: String,
    bookmarkData: Data
  ) async throws -> HermesBridgeAuthorizedRootPayload
  func refreshAuthorizedRoot(
    rootID: HermesAuthorizedRootID,
    bookmarkData: Data,
    expectedRevision: Int?
  ) async throws -> HermesBridgeAuthorizedRootPayload
  func deactivateAuthorizedRoot(
    rootID: HermesAuthorizedRootID,
    expectedRevision: Int?
  ) async throws -> HermesBridgeAuthorizedRootPayload
  func reactivateAuthorizedRoot(
    rootID: HermesAuthorizedRootID,
    bookmarkData: Data,
    expectedRevision: Int?
  ) async throws -> HermesBridgeAuthorizedRootPayload
  func removeAuthorizedRoot(
    rootID: HermesAuthorizedRootID,
    expectedRevision: Int?
  ) async throws -> HermesBridgeAuthorizedRootPayload
  func authorizedRootStatus(rootID: HermesAuthorizedRootID) async throws
    -> HermesBridgeAuthorizedRootStatusPayload
  func resolveAuthorizedRoot(rootID: HermesAuthorizedRootID) async throws
    -> HermesBridgeAuthorizedRootResolutionPayload
  func createFileEventSubscription(rootIDs: [HermesAuthorizedRootID]) async throws
    -> HermesBridgeFileEventSubscriptionPayload
  func pollFileEventSubscription(
    subscriptionID: HermesBridgeFileEventSubscriptionID,
    timeoutMilliseconds: Int
  ) async throws -> HermesBridgeFileEventBatchPayload
  func acknowledgeFileEventBatch(
    subscriptionID: HermesBridgeFileEventSubscriptionID,
    acknowledgedEventID: UInt64
  ) async throws -> HermesBridgeAcknowledgementPayload
  func cancelFileEventSubscription(subscriptionID: HermesBridgeFileEventSubscriptionID) async throws
    -> HermesBridgeFileEventSubscriptionPayload
  func fileEventMonitorStatus() async throws -> HermesBridgeFileEventMonitorStatusPayload
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

  public func listAuthorizedRoots() async throws -> HermesBridgeAuthorizedRootListPayload {
    throw HermesBridgeXPCError.unsupportedCapability
  }

  public func registerAuthorizedRoot(
    displayName _: String,
    bookmarkData _: Data
  ) async throws -> HermesBridgeAuthorizedRootPayload {
    throw HermesBridgeXPCError.unsupportedCapability
  }

  public func refreshAuthorizedRoot(
    rootID _: HermesAuthorizedRootID,
    bookmarkData _: Data,
    expectedRevision _: Int?
  ) async throws -> HermesBridgeAuthorizedRootPayload {
    throw HermesBridgeXPCError.unsupportedCapability
  }

  public func deactivateAuthorizedRoot(
    rootID _: HermesAuthorizedRootID,
    expectedRevision _: Int?
  ) async throws -> HermesBridgeAuthorizedRootPayload {
    throw HermesBridgeXPCError.unsupportedCapability
  }

  public func reactivateAuthorizedRoot(
    rootID _: HermesAuthorizedRootID,
    bookmarkData _: Data,
    expectedRevision _: Int?
  ) async throws -> HermesBridgeAuthorizedRootPayload {
    throw HermesBridgeXPCError.unsupportedCapability
  }

  public func removeAuthorizedRoot(
    rootID _: HermesAuthorizedRootID,
    expectedRevision _: Int?
  ) async throws -> HermesBridgeAuthorizedRootPayload {
    throw HermesBridgeXPCError.unsupportedCapability
  }

  public func authorizedRootStatus(rootID _: HermesAuthorizedRootID) async throws
    -> HermesBridgeAuthorizedRootStatusPayload
  {
    throw HermesBridgeXPCError.unsupportedCapability
  }

  public func resolveAuthorizedRoot(rootID _: HermesAuthorizedRootID) async throws
    -> HermesBridgeAuthorizedRootResolutionPayload
  {
    throw HermesBridgeXPCError.unsupportedCapability
  }

  public func createFileEventSubscription(rootIDs _: [HermesAuthorizedRootID]) async throws
    -> HermesBridgeFileEventSubscriptionPayload
  {
    throw HermesBridgeXPCError.unsupportedCapability
  }

  public func pollFileEventSubscription(
    subscriptionID _: HermesBridgeFileEventSubscriptionID,
    timeoutMilliseconds _: Int
  ) async throws -> HermesBridgeFileEventBatchPayload {
    throw HermesBridgeXPCError.unsupportedCapability
  }

  public func acknowledgeFileEventBatch(
    subscriptionID _: HermesBridgeFileEventSubscriptionID,
    acknowledgedEventID _: UInt64
  ) async throws -> HermesBridgeAcknowledgementPayload {
    throw HermesBridgeXPCError.unsupportedCapability
  }

  public func cancelFileEventSubscription(
    subscriptionID _: HermesBridgeFileEventSubscriptionID
  ) async throws -> HermesBridgeFileEventSubscriptionPayload {
    throw HermesBridgeXPCError.unsupportedCapability
  }

  public func fileEventMonitorStatus() async throws -> HermesBridgeFileEventMonitorStatusPayload {
    throw HermesBridgeXPCError.unsupportedCapability
  }
}

public actor HermesBridgeXPCRequestDispatcher {
  private let handler: HermesBridgeRequestHandling
  private let auditStore: any HermesAuditStore
  private let maximumConcurrentRequests: Int
  private let decoder: JSONDecoder
  private let encoder: JSONEncoder
  private var inFlight = 0

  public init(
    handler: HermesBridgeRequestHandling,
    auditStore: any HermesAuditStore = NoopHermesAuditStore(),
    maximumConcurrentRequests: Int = 8
  ) {
    self.handler = handler
    self.auditStore = auditStore
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
      try await auditOperationStarted(envelope)
      let payload = try await dispatch(envelope)
      try await auditOperationCompleted(envelope, payload: payload)
      return encodeResponse(
        HermesBridgeResponseEnvelope(
          correlationID: envelope.correlationID,
          result: .success(payload)
        ))
    } catch let error as HermesBridgeXPCError {
      try? await auditOperationFailed(preflight: preflight, error: error)
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
        envelope.approvalResponse == nil, envelope.filePayloadCount == 0
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
        envelope.approvalResponse == nil, envelope.filePayloadCount == 0
      else {
        throw HermesBridgeXPCError.malformedPayload
      }
    case .cancel:
      guard envelope.cancel != nil, envelope.submit == nil, envelope.status == nil,
        envelope.approvalResponse == nil, envelope.filePayloadCount == 0
      else {
        throw HermesBridgeXPCError.malformedPayload
      }
    case .approvalResponse:
      guard envelope.approvalResponse != nil, envelope.submit == nil, envelope.status == nil,
        envelope.cancel == nil, envelope.filePayloadCount == 0
      else {
        throw HermesBridgeXPCError.malformedPayload
      }
    case .capabilities, .protocolVersion, .listEnabledBindings:
      guard envelope.submit == nil, envelope.status == nil, envelope.cancel == nil,
        envelope.approvalResponse == nil, envelope.filePayloadCount == 0
      else {
        throw HermesBridgeXPCError.malformedPayload
      }
    case .listAuthorizedRoots, .fileEventMonitorStatus:
      try validateOnlyFilePayload(envelope, expected: 0)
    case .registerAuthorizedRoot:
      try validateOnlyFilePayload(envelope, expected: 1)
      guard let payload = envelope.registerAuthorizedRoot,
        !payload.bookmarkData.isEmpty,
        payload.bookmarkData.count <= HermesBridgeRegisterAuthorizedRootPayload.maximumBookmarkBytes
      else {
        throw HermesBridgeXPCError.bookmarkTooLarge
      }
    case .refreshAuthorizedRoot:
      try validateOnlyFilePayload(envelope, expected: 1)
      guard let payload = envelope.refreshAuthorizedRoot,
        !payload.bookmarkData.isEmpty,
        payload.bookmarkData.count <= HermesBridgeRegisterAuthorizedRootPayload.maximumBookmarkBytes
      else {
        throw HermesBridgeXPCError.bookmarkTooLarge
      }
    case .deactivateAuthorizedRoot:
      try validateOnlyFilePayload(envelope, expected: 1)
      guard envelope.deactivateAuthorizedRoot != nil else {
        throw HermesBridgeXPCError.malformedPayload
      }
    case .reactivateAuthorizedRoot:
      try validateOnlyFilePayload(envelope, expected: 1)
      guard let payload = envelope.reactivateAuthorizedRoot,
        !payload.bookmarkData.isEmpty,
        payload.bookmarkData.count <= HermesBridgeRegisterAuthorizedRootPayload.maximumBookmarkBytes
      else {
        throw HermesBridgeXPCError.bookmarkTooLarge
      }
    case .removeAuthorizedRoot:
      try validateOnlyFilePayload(envelope, expected: 1)
      guard envelope.removeAuthorizedRoot != nil else {
        throw HermesBridgeXPCError.malformedPayload
      }
    case .authorizedRootStatus:
      try validateOnlyFilePayload(envelope, expected: 1)
      guard envelope.authorizedRootStatus != nil else {
        throw HermesBridgeXPCError.malformedPayload
      }
    case .resolveAuthorizedRoot:
      try validateOnlyFilePayload(envelope, expected: 1)
      guard envelope.resolveAuthorizedRoot != nil else {
        throw HermesBridgeXPCError.malformedPayload
      }
    case .createFileEventSubscription:
      try validateOnlyFilePayload(envelope, expected: 1)
      guard envelope.createFileEventSubscription != nil else {
        throw HermesBridgeXPCError.malformedPayload
      }
    case .pollFileEventSubscription:
      try validateOnlyFilePayload(envelope, expected: 1)
      guard envelope.pollFileEventSubscription != nil else {
        throw HermesBridgeXPCError.malformedPayload
      }
    case .acknowledgeFileEventBatch:
      try validateOnlyFilePayload(envelope, expected: 1)
      guard envelope.acknowledgeFileEventBatch != nil else {
        throw HermesBridgeXPCError.malformedPayload
      }
    case .cancelFileEventSubscription:
      try validateOnlyFilePayload(envelope, expected: 1)
      guard envelope.cancelFileEventSubscription != nil else {
        throw HermesBridgeXPCError.malformedPayload
      }
    }
  }

  private func validateOnlyFilePayload(
    _ envelope: HermesBridgeRequestEnvelope,
    expected: Int
  ) throws {
    guard envelope.submit == nil, envelope.status == nil, envelope.cancel == nil,
      envelope.approvalResponse == nil, envelope.filePayloadCount == expected
    else {
      throw HermesBridgeXPCError.malformedPayload
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
    case .listAuthorizedRoots:
      return .listAuthorizedRoots(
        try await mapFileIntegrationError {
          try await handler.listAuthorizedRoots()
        })
    case .registerAuthorizedRoot:
      guard let payload = envelope.registerAuthorizedRoot else {
        throw HermesBridgeXPCError.malformedPayload
      }
      return .registerAuthorizedRoot(
        try await mapFileIntegrationError {
          try await handler.registerAuthorizedRoot(
            displayName: payload.displayName,
            bookmarkData: payload.bookmarkData
          )
        })
    case .refreshAuthorizedRoot:
      guard let payload = envelope.refreshAuthorizedRoot else {
        throw HermesBridgeXPCError.malformedPayload
      }
      return .refreshAuthorizedRoot(
        try await mapFileIntegrationError {
          try await handler.refreshAuthorizedRoot(
            rootID: try decodeRootID(payload.rootID),
            bookmarkData: payload.bookmarkData,
            expectedRevision: payload.expectedRevision
          )
        })
    case .deactivateAuthorizedRoot:
      guard let payload = envelope.deactivateAuthorizedRoot else {
        throw HermesBridgeXPCError.malformedPayload
      }
      return .deactivateAuthorizedRoot(
        try await mapFileIntegrationError {
          try await handler.deactivateAuthorizedRoot(
            rootID: try decodeRootID(payload.rootID),
            expectedRevision: payload.expectedRevision
          )
        })
    case .reactivateAuthorizedRoot:
      guard let payload = envelope.reactivateAuthorizedRoot else {
        throw HermesBridgeXPCError.malformedPayload
      }
      return .reactivateAuthorizedRoot(
        try await mapFileIntegrationError {
          try await handler.reactivateAuthorizedRoot(
            rootID: try decodeRootID(payload.rootID),
            bookmarkData: payload.bookmarkData,
            expectedRevision: payload.expectedRevision
          )
        })
    case .removeAuthorizedRoot:
      guard let payload = envelope.removeAuthorizedRoot else {
        throw HermesBridgeXPCError.malformedPayload
      }
      return .removeAuthorizedRoot(
        try await mapFileIntegrationError {
          try await handler.removeAuthorizedRoot(
            rootID: try decodeRootID(payload.rootID),
            expectedRevision: payload.expectedRevision
          )
        })
    case .authorizedRootStatus:
      guard let payload = envelope.authorizedRootStatus else {
        throw HermesBridgeXPCError.malformedPayload
      }
      return .authorizedRootStatus(
        try await mapFileIntegrationError {
          try await handler.authorizedRootStatus(rootID: try decodeRootID(payload.rootID))
        })
    case .resolveAuthorizedRoot:
      guard let payload = envelope.resolveAuthorizedRoot else {
        throw HermesBridgeXPCError.malformedPayload
      }
      return .resolveAuthorizedRoot(
        try await mapFileIntegrationError {
          try await handler.resolveAuthorizedRoot(rootID: try decodeRootID(payload.rootID))
        })
    case .createFileEventSubscription:
      guard let payload = envelope.createFileEventSubscription else {
        throw HermesBridgeXPCError.malformedPayload
      }
      return .createFileEventSubscription(
        try await mapFileIntegrationError {
          try await handler.createFileEventSubscription(
            rootIDs: try payload.rootIDs.map(decodeRootID)
          )
        })
    case .pollFileEventSubscription:
      guard let payload = envelope.pollFileEventSubscription else {
        throw HermesBridgeXPCError.malformedPayload
      }
      return .pollFileEventSubscription(
        try await mapFileIntegrationError {
          try await handler.pollFileEventSubscription(
            subscriptionID: try decodeSubscriptionID(payload.subscriptionID),
            timeoutMilliseconds: payload.timeoutMilliseconds
          )
        })
    case .acknowledgeFileEventBatch:
      guard let payload = envelope.acknowledgeFileEventBatch else {
        throw HermesBridgeXPCError.malformedPayload
      }
      return .acknowledgeFileEventBatch(
        try await mapFileIntegrationError {
          try await handler.acknowledgeFileEventBatch(
            subscriptionID: try decodeSubscriptionID(payload.subscriptionID),
            acknowledgedEventID: payload.acknowledgedEventID
          )
        })
    case .cancelFileEventSubscription:
      guard let payload = envelope.cancelFileEventSubscription else {
        throw HermesBridgeXPCError.malformedPayload
      }
      return .cancelFileEventSubscription(
        try await mapFileIntegrationError {
          try await handler.cancelFileEventSubscription(
            subscriptionID: try decodeSubscriptionID(payload.subscriptionID)
          )
        })
    case .fileEventMonitorStatus:
      return .fileEventMonitorStatus(
        try await mapFileIntegrationError {
          try await handler.fileEventMonitorStatus()
        })
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

  private func decodeRootID(_ rawValue: String) throws -> HermesAuthorizedRootID {
    do {
      return try HermesAuthorizedRootID(rawValue: rawValue)
    } catch {
      throw HermesBridgeXPCError.malformedPayload
    }
  }

  private func decodeSubscriptionID(_ rawValue: String) throws
    -> HermesBridgeFileEventSubscriptionID
  {
    do {
      return try HermesBridgeFileEventSubscriptionID(rawValue: rawValue)
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

  private func mapFileIntegrationError<T>(_ body: () async throws -> T) async throws -> T {
    do {
      return try await body()
    } catch let error as HermesBridgeXPCError {
      throw error
    } catch let error as HermesAuthorizedRootRegistryError {
      switch error {
      case .unknownRoot:
        throw HermesBridgeXPCError.rootNotFound
      case .inactiveRoot:
        throw HermesBridgeXPCError.rootInactive
      case .duplicateResolvedRoot:
        throw HermesBridgeXPCError.duplicateAuthorizedRoot
      case .bookmarkTooLarge:
        throw HermesBridgeXPCError.bookmarkTooLarge
      case .bookmarkResolutionFailed:
        throw HermesBridgeXPCError.invalidBookmark
      default:
        throw HermesBridgeXPCError.internalFailure
      }
    } catch is HermesFileEventError {
      throw HermesBridgeXPCError.oversizedPayload
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
    case .unsupportedCapability:
      return "Bridge XPC capability is unsupported."
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
    case .duplicateAuthorizedRoot:
      return "Authorized root already exists."
    case .rootNotFound:
      return "Authorized root was not found."
    case .rootInactive:
      return "Authorized root is inactive."
    case .invalidBookmark:
      return "Authorized-root bookmark is invalid."
    case .bookmarkTooLarge:
      return "Authorized-root bookmark exceeds the size limit."
    case .staleAuthorization:
      return "Authorized-root bookmark is stale."
    case .securityScopeUnavailable:
      return "Security scope is unavailable."
    case .subscriptionNotFound:
      return "File-event subscription was not found."
    case .subscriptionExpired:
      return "File-event subscription expired."
    case .acknowledgementRejected:
      return "File-event acknowledgement was rejected."
    case .eventBufferOverflow:
      return "File-event buffer overflow requires rescan."
    case .rescanRequired:
      return "File-event rescan is required."
    }
  }

  private func auditOperationStarted(_ envelope: HermesBridgeRequestEnvelope) async throws {
    switch envelope.operation {
    case .submit:
      try await appendAudit(
        .requestAccepted,
        envelope: envelope,
        outcome: .accepted,
        reasonCode: "accepted"
      )
    case .approvalResponse:
      try await appendAudit(
        .approvalResponded,
        envelope: envelope,
        outcome: .started,
        reasonCode: envelope.approvalResponse?.decision.rawValue ?? "responded"
      )
    default:
      return
    }
  }

  private func auditOperationCompleted(
    _ envelope: HermesBridgeRequestEnvelope,
    payload: HermesBridgeSuccessPayload
  ) async throws {
    switch payload {
    case .submit(let result):
      try await appendAudit(
        .requestStarted,
        envelope: envelope,
        outcome: .started,
        reasonCode: "submitted",
        requestID: result.requestID
      )
    case .cancel(let result):
      try await appendAudit(
        .requestCancelled,
        envelope: envelope,
        outcome: .cancelled,
        reasonCode: "cancelled",
        requestID: result.requestID
      )
    case .status(let result):
      if result.lifecycleState == HermesRequestLifecycleState.completed.rawValue {
        try await appendAudit(
          .requestCompleted,
          envelope: envelope,
          outcome: .succeeded,
          reasonCode: "completed",
          requestID: result.requestID
        )
      } else if result.lifecycleState == HermesRequestLifecycleState.failed.rawValue {
        try await appendAudit(
          .requestFailed,
          envelope: envelope,
          outcome: .failed,
          reasonCode: result.failureCode ?? "failed",
          requestID: result.requestID
        )
      } else if result.lifecycleState == HermesRequestLifecycleState.waitingForApproval.rawValue {
        try await appendAudit(
          .approvalRequested,
          envelope: envelope,
          outcome: .started,
          reasonCode: "waiting_for_approval",
          requestID: result.requestID
        )
      }
    case .approvalResponse(let result):
      try await appendAudit(
        .approvalResponded,
        envelope: envelope,
        outcome: .succeeded,
        reasonCode: envelope.approvalResponse?.decision.rawValue ?? "responded",
        requestID: result.requestID
      )
    case .registerAuthorizedRoot(let payload):
      try await appendAudit(
        .authorizedRootAdded,
        envelope: envelope,
        outcome: .succeeded,
        reasonCode: "root_added",
        rootID: payload.root.rootID
      )
    case .refreshAuthorizedRoot(let payload), .reactivateAuthorizedRoot(let payload):
      try await appendAudit(
        .authorizedRootRefreshed,
        envelope: envelope,
        outcome: .succeeded,
        reasonCode: "root_refreshed",
        rootID: payload.root.rootID
      )
    case .deactivateAuthorizedRoot(let payload):
      try await appendAudit(
        .authorizedRootDeactivated,
        envelope: envelope,
        outcome: .succeeded,
        reasonCode: "root_deactivated",
        rootID: payload.root.rootID
      )
      try await appendAudit(
        .fileRescanRequired,
        envelope: envelope,
        outcome: .started,
        reasonCode: "root_deactivated",
        rootID: payload.root.rootID
      )
    case .removeAuthorizedRoot(let payload):
      try await appendAudit(
        .authorizedRootRemoved,
        envelope: envelope,
        outcome: .succeeded,
        reasonCode: "root_removed",
        rootID: payload.root.rootID
      )
      try await appendAudit(
        .fileRescanRequired,
        envelope: envelope,
        outcome: .started,
        reasonCode: "root_removed",
        rootID: payload.root.rootID
      )
    case .createFileEventSubscription(let payload):
      try await appendAudit(
        .fileSubscriptionCreated,
        envelope: envelope,
        outcome: .succeeded,
        reasonCode: "subscription_created",
        subscriptionID: payload.subscriptionID
      )
    case .cancelFileEventSubscription(let payload):
      try await appendAudit(
        .fileSubscriptionCancelled,
        envelope: envelope,
        outcome: .cancelled,
        reasonCode: "subscription_cancelled",
        subscriptionID: payload.subscriptionID
      )
    case .pollFileEventSubscription(let payload):
      if payload.rescanRequired {
        try await appendAudit(
          .fileRescanRequired,
          envelope: envelope,
          outcome: .started,
          reasonCode: payload.droppedEventReason ?? "rescan_required",
          rootID: payload.rootID,
          subscriptionID: payload.subscriptionID
        )
      }
    case .protocolVersion, .capabilities, .listEnabledBindings, .listAuthorizedRoots,
      .authorizedRootStatus, .resolveAuthorizedRoot, .acknowledgeFileEventBatch,
      .fileEventMonitorStatus:
      return
    }
  }

  private func auditOperationFailed(
    preflight: HermesBridgeRequestPreflight,
    error: HermesBridgeXPCError
  ) async throws {
    guard let operation = HermesBridgeOperation(rawValue: preflight.operation) else {
      return
    }
    let kind: HermesAuditEventKind
    switch operation {
    case .submit, .status:
      kind = .requestFailed
    case .cancel:
      kind = .requestCancelled
    case .approvalResponse:
      kind = .approvalResponded
    case .registerAuthorizedRoot, .refreshAuthorizedRoot, .deactivateAuthorizedRoot,
      .reactivateAuthorizedRoot, .removeAuthorizedRoot:
      kind = .authorizedRootRefreshed
    case .createFileEventSubscription:
      kind = .fileSubscriptionCreated
    case .cancelFileEventSubscription:
      kind = .fileSubscriptionCancelled
    case .pollFileEventSubscription, .acknowledgeFileEventBatch, .fileEventMonitorStatus,
      .protocolVersion, .capabilities, .listEnabledBindings, .listAuthorizedRoots,
      .authorizedRootStatus, .resolveAuthorizedRoot:
      return
    }
    try await auditStore.append(
      HermesAuditEvent.make(
        kind: kind,
        actor: .xpcClient,
        outcome: .failed,
        reasonCode: error.rawValue,
        correlationID: preflight.correlationID.rawValue
      ))
  }

  private func appendAudit(
    _ kind: HermesAuditEventKind,
    envelope: HermesBridgeRequestEnvelope,
    outcome: HermesAuditOutcome,
    reasonCode: String,
    requestID: String? = nil,
    rootID: String? = nil,
    subscriptionID: String? = nil
  ) async throws {
    try await auditStore.append(
      HermesAuditEvent.make(
        kind: kind,
        actor: .xpcClient,
        outcome: outcome,
        reasonCode: reasonCode,
        correlationID: envelope.correlationID.rawValue,
        requestID: requestID ?? envelope.status?.requestID ?? envelope.cancel?.requestID
          ?? envelope.approvalResponse?.requestID,
        rootID: rootID ?? envelope.deactivateAuthorizedRoot?.rootID
          ?? envelope.removeAuthorizedRoot?.rootID
          ?? envelope.refreshAuthorizedRoot?.rootID
          ?? envelope.reactivateAuthorizedRoot?.rootID,
        subscriptionID: subscriptionID ?? envelope.pollFileEventSubscription?.subscriptionID
          ?? envelope.cancelFileEventSubscription?.subscriptionID
      ))
  }
}

extension HermesBridgeRequestEnvelope {
  fileprivate var filePayloadCount: Int {
    var count = 0
    if registerAuthorizedRoot != nil { count += 1 }
    if refreshAuthorizedRoot != nil { count += 1 }
    if deactivateAuthorizedRoot != nil { count += 1 }
    if reactivateAuthorizedRoot != nil { count += 1 }
    if removeAuthorizedRoot != nil { count += 1 }
    if authorizedRootStatus != nil { count += 1 }
    if resolveAuthorizedRoot != nil { count += 1 }
    if createFileEventSubscription != nil { count += 1 }
    if pollFileEventSubscription != nil { count += 1 }
    if acknowledgeFileEventBatch != nil { count += 1 }
    if cancelFileEventSubscription != nil { count += 1 }
    return count
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
    auditStore: any HermesAuditStore = NoopHermesAuditStore(),
    maximumConcurrentRequests: Int = 8
  ) {
    self.init(
      dispatcher: HermesBridgeXPCRequestDispatcher(
        handler: handler,
        auditStore: auditStore,
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
