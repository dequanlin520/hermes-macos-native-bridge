import Foundation
import HermesBridgeServiceManager
import HermesBridgeXPC
import HermesRuntimeFoundation

public enum HermesAppIntentError: Error, Equatable, Sendable, CustomStringConvertible,
  LocalizedError
{
  case serviceUnavailable
  case invalidBinding
  case oversizedPrompt
  case protocolIncompatible
  case requestNotFound
  case operationRejected
  case internalRedactedFailure

  public var description: String {
    switch self {
    case .serviceUnavailable:
      return "Hermes Bridge is unavailable."
    case .invalidBinding:
      return "The selected Hermes binding is not available."
    case .oversizedPrompt:
      return "The Prompt is empty or too large."
    case .protocolIncompatible:
      return "Hermes Bridge protocol is incompatible."
    case .requestNotFound:
      return "The Hermes Request ID was not found."
    case .operationRejected:
      return "Hermes Bridge rejected the operation."
    case .internalRedactedFailure:
      return "Hermes Bridge returned a redacted internal failure."
    }
  }

  public var errorDescription: String? {
    description
  }
}

public protocol HermesAppIntentClient: Sendable {
  func listEnabledBindings() async throws -> [HermesAppIntentBindingDefinition]
  func submit(bindingID: HermesRequestBindingID, prompt: String) async throws -> HermesRequestID
  func status(requestID: HermesRequestID) async throws -> HermesAppIntentRequestStatus
  func cancel(requestID: HermesRequestID) async throws -> HermesAppIntentRequestStatus
  func respondToApproval(
    requestID: HermesRequestID,
    decision: HermesAppIntentApprovalDecision
  ) async throws -> HermesAppIntentRequestStatus
  func health() async throws -> HermesAppIntentHealthStatus
}

public protocol HermesAppIntentClientFactory: Sendable {
  func makeClient() async throws -> any HermesAppIntentClient
}

public protocol HermesAppIntentBindingProviding: Sendable {
  func enabledBindings() async throws -> [HermesAppIntentBindingDefinition]
}

public struct HermesAppIntentProductionClientFactory: HermesAppIntentClientFactory {
  private let layout: HermesBridgeInstallationLayout
  private let timeout: TimeInterval

  public init(layout: HermesBridgeInstallationLayout = .production(), timeout: TimeInterval = 5) {
    self.layout = layout
    self.timeout = timeout
  }

  public func makeClient() async throws -> any HermesAppIntentClient {
    guard let serviceName = try? HermesBridgeMachServiceName(layout.machService) else {
      throw HermesAppIntentError.protocolIncompatible
    }
    return HermesAppIntentXPCClient(
      client: HermesBridgeXPCClient(machServiceName: serviceName, timeout: timeout)
    )
  }
}

public actor HermesAppIntentXPCClient: HermesAppIntentClient {
  private let client: HermesBridgeXPCClient

  public init(client: HermesBridgeXPCClient) {
    self.client = client
  }

  public func submit(bindingID: HermesRequestBindingID, prompt: String) async throws
    -> HermesRequestID
  {
    do {
      return try await client.submit(bindingID: bindingID, prompt: prompt)
    } catch {
      throw Self.map(error)
    }
  }

  public func listEnabledBindings() async throws -> [HermesAppIntentBindingDefinition] {
    do {
      return try await client.listEnabledBindings().bindings.map {
        try HermesAppIntentBindingDefinition(summary: $0)
      }
    } catch {
      throw Self.map(error)
    }
  }

  public func status(requestID: HermesRequestID) async throws -> HermesAppIntentRequestStatus {
    do {
      return HermesAppIntentRequestStatus(payload: try await client.status(requestID: requestID))
    } catch {
      throw Self.map(error)
    }
  }

  public func cancel(requestID: HermesRequestID) async throws -> HermesAppIntentRequestStatus {
    do {
      return HermesAppIntentRequestStatus(payload: try await client.cancel(requestID: requestID))
    } catch {
      throw Self.map(error)
    }
  }

  public func respondToApproval(
    requestID: HermesRequestID,
    decision: HermesAppIntentApprovalDecision
  ) async throws -> HermesAppIntentRequestStatus {
    do {
      return HermesAppIntentRequestStatus(
        payload: try await client.respondToApproval(
          requestID: requestID,
          decision: decision.bridgeDecision
        ))
    } catch {
      throw Self.map(error)
    }
  }

  public func health() async throws -> HermesAppIntentHealthStatus {
    do {
      let version = try await client.protocolVersion()
      let capabilities = try await client.capabilities()
      let compatible =
        version.version.major == HermesBridgeProtocolVersion.current.major
        && capabilities.protocolVersion.major == HermesBridgeProtocolVersion.current.major
      return HermesAppIntentHealthStatus(
        available: true,
        compatible: compatible,
        protocolVersion: version.version.description,
        supportedCapabilities: capabilities.capabilities.map(\.rawValue).sorted()
      )
    } catch {
      if Self.map(error) == .serviceUnavailable {
        return HermesAppIntentHealthStatus(
          available: false,
          compatible: false,
          protocolVersion: nil,
          supportedCapabilities: []
        )
      }
      throw Self.map(error)
    }
  }

  static func map(_ error: Error) -> HermesAppIntentError {
    if let appIntentError = error as? HermesAppIntentError {
      return appIntentError
    }
    guard let clientError = error as? HermesBridgeXPCClientError else {
      return .internalRedactedFailure
    }
    switch clientError {
    case .timedOut, .interrupted, .invalidated:
      return .serviceUnavailable
    case .protocolNegotiationFailed, .responseDecodingFailure:
      return .protocolIncompatible
    case .service(let xpcError):
      return map(xpcError)
    }
  }

  static func map(_ error: HermesBridgeXPCError) -> HermesAppIntentError {
    switch error {
    case .unsupportedProtocolVersion:
      return .protocolIncompatible
    case .malformedPayload, .unsupportedOperation, .unsupportedCapability, .invalidState,
      .duplicateAuthorizedRoot, .rootNotFound, .rootInactive, .invalidBookmark, .staleAuthorization,
      .securityScopeUnavailable, .subscriptionNotFound, .subscriptionExpired,
      .acknowledgementRejected, .eventBufferOverflow, .rescanRequired:
      return .operationRejected
    case .oversizedPayload, .bookmarkTooLarge:
      return .oversizedPrompt
    case .invalidBinding:
      return .invalidBinding
    case .requestNotFound:
      return .requestNotFound
    case .serviceUnavailable:
      return .serviceUnavailable
    case .internalFailure:
      return .internalRedactedFailure
    }
  }
}

public struct HermesAppIntentStaticBindingProvider: HermesAppIntentBindingProviding {
  private let bindings: [HermesAppIntentBindingDefinition]

  public init(bindings: [HermesAppIntentBindingDefinition]) {
    self.bindings = bindings
  }

  public func enabledBindings() async throws -> [HermesAppIntentBindingDefinition] {
    bindings.filter(\.enabled)
  }
}

public struct HermesAppIntentProductionBindingProvider: HermesAppIntentBindingProviding {
  private let factory: any HermesAppIntentClientFactory
  private let cache: HermesAppIntentBindingCache

  public init(
    factory: any HermesAppIntentClientFactory = HermesAppIntentProductionClientFactory(),
    cacheLifetime: TimeInterval = 30
  ) {
    self.factory = factory
    self.cache = HermesAppIntentBindingCache(lifetime: cacheLifetime)
  }

  public func enabledBindings() async throws -> [HermesAppIntentBindingDefinition] {
    if let cached = await cache.current() {
      return cached
    }
    do {
      let client = try await factory.makeClient()
      let bindings = try await client.listEnabledBindings()
      await cache.store(bindings)
      return bindings
    } catch HermesAppIntentError.serviceUnavailable {
      return []
    } catch HermesAppIntentError.protocolIncompatible {
      return []
    } catch {
      throw error
    }
  }
}

public actor HermesAppIntentBindingCache {
  private let lifetime: TimeInterval
  private var cachedAt: Date?
  private var cachedBindings: [HermesAppIntentBindingDefinition] = []

  public init(lifetime: TimeInterval = 30) {
    self.lifetime = max(0, min(lifetime, 300))
  }

  public func current(now: Date = Date()) -> [HermesAppIntentBindingDefinition]? {
    guard let cachedAt, now.timeIntervalSince(cachedAt) <= lifetime else {
      return nil
    }
    return cachedBindings
  }

  public func store(_ bindings: [HermesAppIntentBindingDefinition], now: Date = Date()) {
    cachedAt = now
    cachedBindings =
      bindings
      .filter(\.enabled)
      .sorted { $0.id.rawValue.localizedStandardCompare($1.id.rawValue) == .orderedAscending }
      .prefixArray(HermesBridgeBindingSummary.maximumCount)
  }
}

extension Array {
  fileprivate func prefixArray(_ count: Int) -> [Element] {
    Array(prefix(count))
  }
}
