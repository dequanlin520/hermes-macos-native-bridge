import Foundation

public enum HermesAgentProtocolCapabilityStatus: String, Codable, Equatable, Sendable {
  case supportedExercised = "supported-exercised"
  case supportedUnexercised = "supported-unexercised"
  case unsupported
  case blocked
  case protocolIncompatible = "protocol-incompatible"
}

public struct HermesAgentProtocolCapability: Codable, Equatable, Sendable {
  public let status: HermesAgentProtocolCapabilityStatus
  public let routeCategory: String
  public let reasonCode: String

  public init(
    status: HermesAgentProtocolCapabilityStatus,
    routeCategory: String,
    reasonCode: String
  ) {
    self.status = status
    self.routeCategory = Self.safeToken(routeCategory)
    self.reasonCode = Self.safeToken(reasonCode)
  }

  private static func safeToken(_ value: String) -> String {
    HermesAgentProtocolSanitizer.safeToken(value, maximumLength: 128)
  }
}

public enum HermesAgentAuthenticationState: String, Codable, Equatable, Sendable {
  case notRequired = "not-required"
  case requiredAvailable = "required-available"
  case requiredUnavailable = "required-unavailable"
  case unknown

  public var resultAuthenticationRequired: String {
    switch self {
    case .notRequired:
      return "no"
    case .requiredAvailable, .requiredUnavailable:
      return "yes"
    case .unknown:
      return "unknown"
    }
  }

  public var ephemeralCredentialIsolatedResult: String {
    switch self {
    case .notRequired:
      return "skip"
    case .requiredAvailable:
      return "yes"
    case .requiredUnavailable, .unknown:
      return "no"
    }
  }
}

public struct HermesAgentProtocolDescriptor: Codable, Equatable, Sendable {
  public let protocolFamily: String
  public let protocolVersion: String
  public let request: HermesAgentProtocolCapability
  public let status: HermesAgentProtocolCapability
  public let cancel: HermesAgentProtocolCapability
  public let approval: HermesAgentProtocolCapability
  public let authenticationRequired: Bool
  public let authenticationCategory: String
  public let ephemeralCredentialIsolated: Bool
  public let authenticationState: HermesAgentAuthenticationState
  public let streamingModesAdvertised: [String]
  public let metadataSource: String

  public init(
    protocolFamily: String,
    protocolVersion: String,
    request: HermesAgentProtocolCapability,
    status: HermesAgentProtocolCapability,
    cancel: HermesAgentProtocolCapability,
    approval: HermesAgentProtocolCapability,
    authenticationRequired: Bool,
    authenticationCategory: String,
    ephemeralCredentialIsolated: Bool,
    authenticationState: HermesAgentAuthenticationState? = nil,
    streamingModesAdvertised: [String],
    metadataSource: String
  ) {
    self.protocolFamily = HermesAgentProtocolSanitizer.safeToken(protocolFamily)
    self.protocolVersion = HermesAgentProtocolSanitizer.safeToken(protocolVersion)
    self.request = request
    self.status = status
    self.cancel = cancel
    self.approval = approval
    self.authenticationRequired = authenticationRequired
    self.authenticationCategory = HermesAgentProtocolSanitizer.safeToken(authenticationCategory)
    self.ephemeralCredentialIsolated = ephemeralCredentialIsolated
    self.authenticationState = authenticationState ?? Self.authenticationState(
      required: authenticationRequired,
      category: authenticationCategory,
      isolated: ephemeralCredentialIsolated
    )
    self.streamingModesAdvertised = streamingModesAdvertised
      .map { HermesAgentProtocolSanitizer.safeToken($0) }
      .sorted()
    self.metadataSource = HermesAgentProtocolSanitizer.safeToken(metadataSource)
  }

  public static func discover(
    statusData: Data,
    openAPIMetadataData: Data?,
    implementationMethods: Set<String> = [
      "session.create", "session.status", "session.interrupt", "approval.respond",
    ]
  ) throws -> HermesAgentProtocolDescriptor {
    let statusObject = try decodeObject(statusData, malformedReason: "protocol.status-malformed")
    guard statusObject["version"] is String || statusObject["auth_required"] != nil
      || statusObject["desktop_contract"] != nil || statusObject["gateway_running"] != nil
    else {
      throw HermesAgentProtocolError.protocolIncompatible("protocol.status-not-hermes")
    }

    let openAPIPaths = try parseOpenAPIPaths(openAPIMetadataData)
    let hasStatus = openAPIPaths.contains("/api/status") || statusObject["version"] != nil
    let hasWebSocket = openAPIPaths.contains("/api/ws") || implementationMethods.contains("session.create")
    let requestSupported = hasWebSocket && implementationMethods.contains("session.create")
    let statusSupported = hasWebSocket && implementationMethods.contains("session.status")
    let cancelSupported = hasWebSocket && implementationMethods.contains("session.interrupt")
    let approvalSupported = hasWebSocket && implementationMethods.contains("approval.respond")
    let version = statusObject["version"] as? String ?? "unknown"
    let authRequirement = parseAuthenticationRequirement(statusObject["auth_required"])
    let authRequired = authRequirement == .required
    let authMode = statusObject["auth_mode"] as? String
    let authCategory: String
    let authenticationState: HermesAgentAuthenticationState
    switch authRequirement {
    case .notRequired:
      authCategory = "none"
      authenticationState = .notRequired
    case .required:
      authCategory = authMode ?? "required-unspecified"
      authenticationState = authMode == "loopback_token" ? .requiredAvailable : .requiredUnavailable
    case .unknown:
      authCategory = "unknown"
      authenticationState = .unknown
    }

    return HermesAgentProtocolDescriptor(
      protocolFamily: hasWebSocket ? "hermes-jsonrpc-websocket" : "hermes-http-status",
      protocolVersion: version,
      request: HermesAgentProtocolCapability(
        status: requestSupported ? .supportedUnexercised : .unsupported,
        routeCategory: requestSupported ? "jsonrpc-websocket-session-create" : "unsupported",
        reasonCode: requestSupported ? "protocol.request-advertised" : "protocol.request-route-unsupported"
      ),
      status: HermesAgentProtocolCapability(
        status: hasStatus && statusSupported ? .supportedUnexercised : .unsupported,
        routeCategory: hasStatus && statusSupported ? "jsonrpc-websocket-session-status" : "http-status-only",
        reasonCode: hasStatus && statusSupported ? "protocol.status-advertised" : "protocol.status-route-unsupported"
      ),
      cancel: HermesAgentProtocolCapability(
        status: cancelSupported ? .supportedUnexercised : .unsupported,
        routeCategory: cancelSupported ? "jsonrpc-websocket-session-interrupt" : "unsupported",
        reasonCode: cancelSupported ? "protocol.cancel-advertised" : "protocol.cancel-route-unsupported"
      ),
      approval: HermesAgentProtocolCapability(
        status: approvalSupported ? .supportedUnexercised : .unsupported,
        routeCategory: approvalSupported ? "jsonrpc-websocket-approval-respond" : "unsupported",
        reasonCode: approvalSupported
          ? "protocol.approval-supported-no-harmless-trigger"
          : "protocol.approval-route-unsupported"
      ),
      authenticationRequired: authRequired,
      authenticationCategory: authCategory,
      ephemeralCredentialIsolated: authRequired && authMode == "loopback_token",
      authenticationState: authenticationState,
      streamingModesAdvertised: hasWebSocket ? ["websocket-jsonrpc-events"] : [],
      metadataSource: openAPIPaths.isEmpty ? "api-status-and-local-implementation" : "openapi-api-status-and-local-implementation"
    )
  }

  public func exercised(
    request: HermesAgentProtocolCapabilityStatus? = nil,
    status: HermesAgentProtocolCapabilityStatus? = nil,
    cancel: HermesAgentProtocolCapabilityStatus? = nil,
    approval: HermesAgentProtocolCapabilityStatus? = nil
  ) -> HermesAgentProtocolDescriptor {
    HermesAgentProtocolDescriptor(
      protocolFamily: protocolFamily,
      protocolVersion: protocolVersion,
      request: replacing(self.request, status: request),
      status: replacing(self.status, status: status),
      cancel: replacing(self.cancel, status: cancel),
      approval: replacing(self.approval, status: approval),
      authenticationRequired: authenticationRequired,
      authenticationCategory: authenticationCategory,
      ephemeralCredentialIsolated: ephemeralCredentialIsolated,
      authenticationState: authenticationState,
      streamingModesAdvertised: streamingModesAdvertised,
      metadataSource: metadataSource
    )
  }

  public func withAuthenticationState(
    _ state: HermesAgentAuthenticationState
  ) -> HermesAgentProtocolDescriptor {
    HermesAgentProtocolDescriptor(
      protocolFamily: protocolFamily,
      protocolVersion: protocolVersion,
      request: request,
      status: status,
      cancel: cancel,
      approval: approval,
      authenticationRequired: state.resultAuthenticationRequired == "yes",
      authenticationCategory: state == .notRequired ? "none" : authenticationCategory,
      ephemeralCredentialIsolated: state == .requiredAvailable,
      authenticationState: state,
      streamingModesAdvertised: streamingModesAdvertised,
      metadataSource: metadataSource
    )
  }

  private static func authenticationState(
    required: Bool,
    category: String,
    isolated: Bool
  ) -> HermesAgentAuthenticationState {
    if !required { return .notRequired }
    if category == "loopback_token" && isolated { return .requiredAvailable }
    return .requiredUnavailable
  }

  private enum AuthenticationRequirement {
    case notRequired
    case required
    case unknown
  }

  private static func parseAuthenticationRequirement(_ rawValue: Any?) -> AuthenticationRequirement {
    switch rawValue {
    case let value as Bool:
      return value ? .required : .notRequired
    case let value as String:
      switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
      case "no", "false", "0":
        return .notRequired
      case "yes", "true", "1":
        return .required
      default:
        return .unknown
      }
    case .none:
      return .unknown
    default:
      return .unknown
    }
  }

  private func replacing(
    _ capability: HermesAgentProtocolCapability,
    status: HermesAgentProtocolCapabilityStatus?
  ) -> HermesAgentProtocolCapability {
    guard let status else { return capability }
    return HermesAgentProtocolCapability(
      status: status,
      routeCategory: capability.routeCategory,
      reasonCode: capability.reasonCode
    )
  }

  private static func parseOpenAPIPaths(_ data: Data?) throws -> Set<String> {
    guard let data, !data.isEmpty else { return [] }
    let object = try decodeObject(data, malformedReason: "protocol.openapi-malformed")
    guard let paths = object["paths"] as? [String: Any] else {
      return []
    }
    return Set(paths.keys)
  }

  private static func decodeObject(_ data: Data, malformedReason: String) throws -> [String: Any] {
    do {
      guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw HermesAgentProtocolError.malformedJSON(malformedReason)
      }
      return object
    } catch let error as HermesAgentProtocolError {
      throw error
    } catch {
      throw HermesAgentProtocolError.malformedJSON(malformedReason)
    }
  }
}

public struct HermesAgentRequestIdentity: Codable, Equatable, Hashable, Sendable,
  CustomStringConvertible
{
  public let rawValue: String

  public init(rawValue: String) throws {
    guard Self.isValid(rawValue) else {
      throw HermesAgentProtocolError.identityMissing("request.identity-missing")
    }
    self.rawValue = rawValue
  }

  public var description: String { "<redacted HermesAgentRequestIdentity>" }

  public var syntaxCategory: String {
    if rawValue.range(of: #"^[0-9a-fA-F-]{32,36}$"#, options: .regularExpression) != nil {
      return "uuid-like"
    }
    if rawValue.range(of: #"^[A-Za-z0-9._:-]+$"#, options: .regularExpression) != nil {
      return "token-like"
    }
    return "unknown"
  }

  public static func isValid(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.count <= 256
      && value.range(of: #"^[A-Za-z0-9._:-]+$"#, options: .regularExpression) != nil
  }
}

public enum HermesAgentRequestState: String, Codable, Equatable, Sendable {
  case queued
  case running
  case awaitingApproval = "awaiting-approval"
  case cancelling
  case cancelled
  case completed
  case failed
  case unknown

  public static func map(statusOutput: String?) -> HermesAgentRequestState {
    guard let output = statusOutput?.lowercased(), !output.isEmpty else {
      return .unknown
    }
    if output.contains("queued") { return .queued }
    if output.contains("await") && output.contains("approval") { return .awaitingApproval }
    if output.contains("cancelling") { return .cancelling }
    if output.contains("cancel") || output.contains("interrupt") { return .cancelled }
    if output.contains("running") || output.contains("stream") { return .running }
    if output.contains("fail") || output.contains("error") { return .failed }
    if output.contains("complete") || output.contains("idle") { return .completed }
    return .unknown
  }
}

public struct HermesAgentRequestDescriptor: Codable, Equatable, Sendable {
  public let identity: HermesAgentRequestIdentity
  public let creationTimestamp: String
  public let state: HermesAgentRequestState
  public let identitySyntaxCategory: String

  public init(
    identity: HermesAgentRequestIdentity,
    creationTimestamp: String,
    state: HermesAgentRequestState
  ) {
    self.identity = identity
    self.creationTimestamp = HermesAgentProtocolSanitizer.safeTimestamp(creationTimestamp)
    self.state = state
    self.identitySyntaxCategory = identity.syntaxCategory
  }
}

public struct HermesAgentCancellationResult: Codable, Equatable, Sendable {
  public let accepted: Bool
  public let targetIdentityMatched: Bool
  public let terminalState: HermesAgentRequestState
  public let reasonCode: String

  public init(
    accepted: Bool,
    targetIdentityMatched: Bool,
    terminalState: HermesAgentRequestState,
    reasonCode: String
  ) {
    self.accepted = accepted
    self.targetIdentityMatched = targetIdentityMatched
    self.terminalState = terminalState
    self.reasonCode = HermesAgentProtocolSanitizer.safeToken(reasonCode)
  }
}

public struct HermesAgentApprovalDescriptor: Codable, Equatable, Sendable {
  public let approvalIDCategory: String
  public let requestIdentity: HermesAgentRequestIdentity
  public let safeSyntheticFixture: Bool
  public let reasonCode: String

  public init(
    approvalIDCategory: String,
    requestIdentity: HermesAgentRequestIdentity,
    safeSyntheticFixture: Bool,
    reasonCode: String
  ) {
    self.approvalIDCategory = HermesAgentProtocolSanitizer.safeToken(approvalIDCategory)
    self.requestIdentity = requestIdentity
    self.safeSyntheticFixture = safeSyntheticFixture
    self.reasonCode = HermesAgentProtocolSanitizer.safeToken(reasonCode)
  }
}

public enum HermesAgentApprovalDecision: String, Codable, Equatable, Sendable {
  case approve
  case reject
}

public enum HermesAgentProtocolError: Error, Equatable, Sendable, CustomStringConvertible {
  case unsupported(String)
  case blocked(String)
  case protocolIncompatible(String)
  case malformedJSON(String)
  case responseMalformed(String)
  case identityMissing(String)
  case identityMismatch(String)
  case unsafeApproval(String)

  public var reasonCode: String {
    switch self {
    case .unsupported(let code), .blocked(let code), .protocolIncompatible(let code),
      .malformedJSON(let code), .responseMalformed(let code), .identityMissing(let code),
      .identityMismatch(let code), .unsafeApproval(let code):
      HermesAgentProtocolSanitizer.safeToken(code)
    }
  }

  public var description: String { reasonCode }
}

public protocol HermesAgentRequestProtocolServing: Sendable {
  func fetchStatus() async throws -> HermesBackendStatus
  func connectAndWaitUntilReady(timeout: TimeInterval) async throws
  func createSession() async throws -> HermesSessionCreationResult
  func sessionStatus(sessionID: String) async throws -> HermesSessionStatusResult
  func interruptSession(sessionID: String) async throws -> HermesSessionInterruptResult
  func respondToApproval(
    sessionID: String,
    decision: HermesApprovalDecision,
    all: Bool?
  ) async throws -> HermesApprovalResponseResult
  func close() async
}

extension HermesProtocolClient: HermesAgentRequestProtocolServing {}

public struct HermesAgentRequestClientFactory: Sendable {
  public init() {}

  public func makeClient(
    descriptor: HermesAgentProtocolDescriptor,
    endpoint: HermesBackendEndpoint,
    token: HermesBackendSessionToken? = nil
  ) -> HermesAgentRequestClient<HermesProtocolClient> {
    let clientDescriptor = Self.clientDescriptor(for: descriptor, token: token)
    return HermesAgentRequestClient(
      descriptor: clientDescriptor,
      serviceFactory: {
        HermesProtocolClient(
          endpoint: endpoint,
          authentication: Self.protocolAuthentication(for: clientDescriptor, token: token)
        )
      }
    )
  }

  public static func protocolAuthentication(
    for descriptor: HermesAgentProtocolDescriptor,
    token: HermesBackendSessionToken?
  ) -> HermesProtocolClientAuthentication {
    switch descriptor.authenticationState {
    case .notRequired, .unknown, .requiredUnavailable:
      return .none
    case .requiredAvailable:
      if let token {
        return .loopbackToken(token)
      }
      return .none
    }
  }

  public static func clientDescriptor(
    for descriptor: HermesAgentProtocolDescriptor,
    token: HermesBackendSessionToken?
  ) -> HermesAgentProtocolDescriptor {
    guard descriptor.authenticationState == .requiredAvailable, token == nil else {
      return descriptor
    }
    return descriptor.withAuthenticationState(.requiredUnavailable)
  }
}

public final class HermesAgentRequestClient<Service: HermesAgentRequestProtocolServing>:
  @unchecked Sendable
{
  private let serviceFactory: @Sendable () -> Service
  private let descriptor: HermesAgentProtocolDescriptor
  private let now: @Sendable () -> String
  private var service: Service

  public init(
    descriptor: HermesAgentProtocolDescriptor,
    serviceFactory: @escaping @Sendable () -> Service,
    now: @escaping @Sendable () -> String = { ISO8601DateFormatter().string(from: Date()) }
  ) {
    self.descriptor = descriptor
    self.serviceFactory = serviceFactory
    self.now = now
    self.service = serviceFactory()
  }

  public func submitSafeSyntheticRequest() async throws -> HermesAgentRequestDescriptor {
    guard descriptor.request.status != .unsupported else {
      throw HermesAgentProtocolError.unsupported("protocol.request-route-unsupported")
    }
    guard HermesAgentSafeSyntheticRequestContract.isAvailable(for: descriptor) else {
      throw HermesAgentProtocolError.unsupported("protocol.safe-request-unavailable")
    }
    switch descriptor.authenticationState {
    case .notRequired, .requiredAvailable:
      break
    case .requiredUnavailable:
      throw HermesAgentProtocolError.blocked("protocol.authentication-unavailable")
    case .unknown:
      throw HermesAgentProtocolError.blocked("protocol.authentication-unknown")
    }
    try await service.connectAndWaitUntilReady(timeout: 5)
    let creation = try await service.createSession()
    let identity = try HermesAgentRequestIdentity(rawValue: creation.sessionID)
    return HermesAgentRequestDescriptor(
      identity: identity,
      creationTimestamp: now(),
      state: .queued
    )
  }

  public func observeStatus(
    for request: HermesAgentRequestDescriptor
  ) async throws -> HermesAgentRequestState {
    guard descriptor.status.status != .unsupported else {
      throw HermesAgentProtocolError.unsupported("protocol.status-route-unsupported")
    }
    let status = try await service.sessionStatus(sessionID: request.identity.rawValue)
    return HermesAgentRequestState.map(statusOutput: status.output)
  }

  public func cancel(
    request: HermesAgentRequestDescriptor,
    targetIdentity: HermesAgentRequestIdentity
  ) async throws -> HermesAgentCancellationResult {
    guard descriptor.cancel.status != .unsupported else {
      throw HermesAgentProtocolError.unsupported("protocol.cancel-route-unsupported")
    }
    guard request.identity == targetIdentity else {
      throw HermesAgentProtocolError.identityMismatch("request.identity-mismatch")
    }
    let result = try await service.interruptSession(sessionID: targetIdentity.rawValue)
    let terminal = HermesAgentRequestState.map(statusOutput: result.status)
    return HermesAgentCancellationResult(
      accepted: true,
      targetIdentityMatched: true,
      terminalState: terminal,
      reasonCode: terminal == .cancelled ? "cancel.accepted" : "cancel.accepted-equivalent"
    )
  }

  public func submitApprovalDecision(
    _ decision: HermesAgentApprovalDecision,
    approval: HermesAgentApprovalDescriptor
  ) async throws -> Bool {
    guard descriptor.approval.status != .unsupported else {
      throw HermesAgentProtocolError.unsupported("protocol.approval-route-unsupported")
    }
    guard approval.safeSyntheticFixture else {
      throw HermesAgentProtocolError.unsafeApproval("approval.trigger-unsafe")
    }
    let response = try await service.respondToApproval(
      sessionID: approval.requestIdentity.rawValue,
      decision: decision == .approve ? .approve : .reject,
      all: nil
    )
    return response.resolved
  }

  public func reconnectAndObserve(
    request: HermesAgentRequestDescriptor
  ) async throws -> HermesAgentRequestState {
    await service.close()
    service = serviceFactory()
    try await service.connectAndWaitUntilReady(timeout: 5)
    return try await observeStatus(for: request)
  }

  public func close() async {
    await service.close()
  }
}

public enum HermesAgentSafeSyntheticRequestContract {
  public static func isAvailable(for descriptor: HermesAgentProtocolDescriptor) -> Bool {
    descriptor.protocolFamily == "hermes-jsonrpc-websocket"
      && descriptor.protocolVersion.hasPrefix("0.18.")
      && descriptor.request.routeCategory == "jsonrpc-websocket-session-create"
      && descriptor.request.status != .unsupported
  }
}

public enum HermesAgentProtocolSanitizer {
  public static func safeToken(_ value: String, maximumLength: Int = 96) -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_")
    }
    return filtered.isEmpty ? "unknown" : String(filtered.prefix(maximumLength))
  }

  public static func safeTimestamp(_ value: String) -> String {
    let filtered = value.filter {
      $0.isASCII
        && ($0.isNumber || $0 == "-" || $0 == ":" || $0 == "." || $0 == "T" || $0 == "Z")
    }
    return filtered.isEmpty ? "unknown" : String(filtered.prefix(64))
  }

  public static func redactEvidence(_ value: String) -> String {
    var redacted = value.replacingOccurrences(
      of: #"[A-Za-z0-9_\-]{24,}"#,
      with: "<redacted-token>",
      options: .regularExpression
    )
    redacted = redacted.replacingOccurrences(
      of: #"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b"#,
      with: "<redacted-uuid>",
      options: .regularExpression
    )
    redacted = redacted.replacingOccurrences(
      of: #"/Users/[^ \n\t\"]+"#,
      with: "<redacted-path>",
      options: .regularExpression
    )
    redacted = redacted.replacingOccurrences(
      of: #"127\.0\.0\.1:[0-9]{1,5}"#,
      with: "127.0.0.1:<redacted-port>",
      options: .regularExpression
    )
    return redacted
  }
}
