import Foundation

public struct HermesAgentStatusDescriptor: Codable, Equatable, Sendable {
  public let responseShape: String
  public let agentFamily: String
  public let version: String?
  public let endpointIdentityProven: Bool

  public init(
    responseShape: String,
    agentFamily: String,
    version: String?,
    endpointIdentityProven: Bool
  ) {
    self.responseShape = Self.safeToken(responseShape)
    self.agentFamily = Self.safeToken(agentFamily)
    self.version = version.map(Self.safeToken)
    self.endpointIdentityProven = endpointIdentityProven
  }

  private static func safeToken(_ value: String) -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_")
    }
    return filtered.isEmpty ? "unknown" : String(filtered.prefix(96))
  }
}

public struct HermesAgentReadinessResult: Codable, Equatable, Sendable {
  public let attempted: Bool
  public let status: String
  public let reasonCode: String
  public let statusDescriptor: HermesAgentStatusDescriptor?
  public let statusQueryResult: String
  public let serviceDiscoveryMatched: Bool
  public let discoveryMismatchReason: String?

  public init(
    attempted: Bool,
    status: String,
    reasonCode: String,
    statusDescriptor: HermesAgentStatusDescriptor?,
    statusQueryResult: String,
    serviceDiscoveryMatched: Bool,
    discoveryMismatchReason: String?
  ) {
    self.attempted = attempted
    self.status = Self.safeToken(status)
    self.reasonCode = Self.safeToken(reasonCode)
    self.statusDescriptor = statusDescriptor
    self.statusQueryResult = Self.safeToken(statusQueryResult)
    self.serviceDiscoveryMatched = serviceDiscoveryMatched
    self.discoveryMismatchReason = discoveryMismatchReason.map(Self.safeToken)
  }

  public var endpointIdentityProven: Bool {
    statusDescriptor?.endpointIdentityProven == true
  }

  private static func safeToken(_ value: String) -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_")
    }
    return filtered.isEmpty ? "unknown" : String(filtered.prefix(128))
  }
}

public protocol HermesAgentEndpointStatusProbing: Sendable {
  func probeStatus(endpoint: HermesAgentEndpointDescriptor, timeoutSeconds: TimeInterval) throws
    -> HermesAgentStatusDescriptor
}

public protocol HermesAgentEndpointServiceDiscovering: Sendable {
  func matchesSupervisedEndpoint(_ endpoint: HermesAgentEndpointDescriptor) -> Bool
  func mismatchReason(for endpoint: HermesAgentEndpointDescriptor) -> String
}

public struct HermesAgentReadinessProbe: Sendable {
  private let statusProbe: HermesAgentEndpointStatusProbing
  private let serviceDiscovery: HermesAgentEndpointServiceDiscovering
  private let timeoutSeconds: TimeInterval

  public init(
    statusProbe: HermesAgentEndpointStatusProbing,
    serviceDiscovery: HermesAgentEndpointServiceDiscovering,
    timeoutSeconds: TimeInterval = 10
  ) {
    self.statusProbe = statusProbe
    self.serviceDiscovery = serviceDiscovery
    self.timeoutSeconds = max(0.001, timeoutSeconds)
  }

  public func probe(ownership: HermesAgentEndpointOwnershipEvidence) -> HermesAgentReadinessResult {
    guard ownership.ownershipProven, let endpoint = ownership.descriptor else {
      return HermesAgentReadinessResult(
        attempted: false,
        status: "blocked",
        reasonCode: ownership.reasonCode,
        statusDescriptor: nil,
        statusQueryResult: "blocked",
        serviceDiscoveryMatched: false,
        discoveryMismatchReason: "ownership-unproven"
      )
    }

    let descriptor: HermesAgentStatusDescriptor
    do {
      descriptor = try statusProbe.probeStatus(endpoint: endpoint, timeoutSeconds: timeoutSeconds)
    } catch let error as HermesAgentEndpointDiscoveryError {
      return failed(reason: error.reasonCode)
    } catch {
      return failed(reason: "readiness.connection-failed")
    }

    guard descriptor.endpointIdentityProven else {
      return HermesAgentReadinessResult(
        attempted: true,
        status: "blocked",
        reasonCode: "readiness.agent-identity-mismatch",
        statusDescriptor: descriptor,
        statusQueryResult: "identity-mismatch",
        serviceDiscoveryMatched: false,
        discoveryMismatchReason: "agent-identity-mismatch"
      )
    }

    let matched = serviceDiscovery.matchesSupervisedEndpoint(endpoint)
    guard matched else {
      return HermesAgentReadinessResult(
        attempted: true,
        status: "blocked",
        reasonCode: "discovery.endpoint-mismatch",
        statusDescriptor: descriptor,
        statusQueryResult: "ready",
        serviceDiscoveryMatched: false,
        discoveryMismatchReason: serviceDiscovery.mismatchReason(for: endpoint)
      )
    }

    return HermesAgentReadinessResult(
      attempted: true,
      status: "ready",
      reasonCode: "readiness.ready",
      statusDescriptor: descriptor,
      statusQueryResult: "ready",
      serviceDiscoveryMatched: true,
      discoveryMismatchReason: nil
    )
  }

  private func failed(reason: String) -> HermesAgentReadinessResult {
    HermesAgentReadinessResult(
      attempted: true,
      status: "blocked",
      reasonCode: reason,
      statusDescriptor: nil,
      statusQueryResult: "blocked",
      serviceDiscoveryMatched: false,
      discoveryMismatchReason: nil
    )
  }
}

public struct HermesHTTPAgentStatusProbe: HermesAgentEndpointStatusProbing {
  private let fetcher: @Sendable (URL, TimeInterval) throws -> Data

  public init(
    fetcher: (@Sendable (URL, TimeInterval) throws -> Data)? = nil
  ) {
    self.fetcher = fetcher ?? HermesHTTPAgentStatusProbe.fetch
  }

  public func probeStatus(endpoint: HermesAgentEndpointDescriptor, timeoutSeconds: TimeInterval) throws
    -> HermesAgentStatusDescriptor
  {
    guard endpoint.listener.transport == .tcp, endpoint.listener.isLoopback,
      let port = endpoint.observedAssignedPort
    else {
      throw HermesAgentEndpointDiscoveryError.unavailable
    }

    let backend = try HermesBackendEndpoint(port: port)
    let data = try fetcher(backend.statusURL, timeoutSeconds)
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw HermesAgentEndpointDiscoveryError.unavailable
    }
    let hasHermesShape =
      object["version"] is String
      || object["auth_required"] != nil
      || object["desktop_contract"] != nil
      || object["gateway_running"] != nil
      || object["active_agents"] != nil
    guard hasHermesShape else {
      return HermesAgentStatusDescriptor(
        responseShape: "malformed",
        agentFamily: "unknown",
        version: nil,
        endpointIdentityProven: false
      )
    }
    return HermesAgentStatusDescriptor(
      responseShape: "api.status",
      agentFamily: "hermes-agent",
      version: object["version"] as? String,
      endpointIdentityProven: true
    )
  }

  private static func fetch(url: URL, timeout: TimeInterval) throws -> Data {
    let semaphore = DispatchSemaphore(value: 0)
    let outcome = HermesAgentReadinessLockedBox<Result<Data, Error>?>(nil)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = timeout
    configuration.timeoutIntervalForResource = timeout
    let session = URLSession(configuration: configuration)
    let task = session.dataTask(with: url) { data, response, error in
      if let error {
        outcome.set(.failure(error))
      } else if let http = response as? HTTPURLResponse, http.statusCode == 200, let data {
        outcome.set(.success(data))
      } else {
        outcome.set(.failure(HermesAgentEndpointDiscoveryError.unavailable))
      }
      semaphore.signal()
    }
    task.resume()
    guard semaphore.wait(timeout: .now() + timeout) == .success else {
      task.cancel()
      throw HermesAgentEndpointDiscoveryError.unavailable
    }
    guard let result = outcome.value else {
      throw HermesAgentEndpointDiscoveryError.unavailable
    }
    return try result.get()
  }
}

public struct ScopedHermesEndpointDiscoveryMatcher: HermesAgentEndpointServiceDiscovering {
  private let expected: HermesAgentEndpointDescriptor?

  public init(expected: HermesAgentEndpointDescriptor?) {
    self.expected = expected
  }

  public func matchesSupervisedEndpoint(_ endpoint: HermesAgentEndpointDescriptor) -> Bool {
    guard let expected else { return false }
    return expected.listener.transport == endpoint.listener.transport
      && expected.listener.address == endpoint.listener.address
      && expected.observedAssignedPort == endpoint.observedAssignedPort
      && expected.listener.owningPID == endpoint.listener.owningPID
      && expected.listener.owningProcessStartTime == endpoint.listener.owningProcessStartTime
  }

  public func mismatchReason(for _: HermesAgentEndpointDescriptor) -> String {
    expected == nil ? "candidate-missing" : "endpoint-mismatch"
  }
}

private final class HermesAgentReadinessLockedBox<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: Value

  init(_ value: Value) {
    self.storage = value
  }

  var value: Value {
    lock.withLock { storage }
  }

  func set(_ value: Value) {
    lock.withLock { storage = value }
  }
}
