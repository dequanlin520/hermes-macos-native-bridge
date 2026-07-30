import Foundation

public struct HermesAgentStatusDescriptor: Codable, Equatable, Sendable {
  public let responseShape: String
  public let agentFamily: String
  public let version: String?
  public let endpointIdentityProven: Bool
  public let routeCategory: String
  public let httpStatus: Int?
  public let responseCategory: String
  public let attemptCount: Int
  public let durationMilliseconds: Int

  public init(
    responseShape: String,
    agentFamily: String,
    version: String?,
    endpointIdentityProven: Bool,
    routeCategory: String = "status",
    httpStatus: Int? = nil,
    responseCategory: String = "unknown",
    attemptCount: Int = 1,
    durationMilliseconds: Int = 0
  ) {
    self.responseShape = Self.safeToken(responseShape)
    self.agentFamily = Self.safeToken(agentFamily)
    self.version = version.map(Self.safeToken)
    self.endpointIdentityProven = endpointIdentityProven
    self.routeCategory = Self.safeToken(routeCategory)
    self.httpStatus = httpStatus
    self.responseCategory = Self.safeToken(responseCategory)
    self.attemptCount = max(0, attemptCount)
    self.durationMilliseconds = max(0, durationMilliseconds)
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
  public let routeCategory: String
  public let httpStatus: Int?
  public let responseCategory: String
  public let attemptCount: Int
  public let durationMilliseconds: Int
  public let serviceDiscoveryAttempted: Bool
  public let serviceDiscoveryMatched: Bool
  public let discoveryMismatchReason: String?

  public init(
    attempted: Bool,
    status: String,
    reasonCode: String,
    statusDescriptor: HermesAgentStatusDescriptor?,
    statusQueryResult: String,
    routeCategory: String = "unknown",
    httpStatus: Int? = nil,
    responseCategory: String = "unknown",
    attemptCount: Int = 0,
    durationMilliseconds: Int = 0,
    serviceDiscoveryAttempted: Bool = false,
    serviceDiscoveryMatched: Bool,
    discoveryMismatchReason: String?
  ) {
    self.attempted = attempted
    self.status = Self.safeToken(status)
    self.reasonCode = Self.safeToken(reasonCode)
    self.statusDescriptor = statusDescriptor
    self.statusQueryResult = Self.safeToken(statusQueryResult)
    self.routeCategory = Self.safeToken(routeCategory)
    self.httpStatus = httpStatus
    self.responseCategory = Self.safeToken(responseCategory)
    self.attemptCount = max(0, attemptCount)
    self.durationMilliseconds = max(0, durationMilliseconds)
    self.serviceDiscoveryAttempted = serviceDiscoveryAttempted
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

public struct HermesAgentReadinessProbeFailure: Error, Equatable, Sendable {
  public let reasonCode: String
  public let routeCategory: String
  public let httpStatus: Int?
  public let responseCategory: String
  public let attemptCount: Int
  public let durationMilliseconds: Int

  public init(
    reasonCode: String,
    routeCategory: String = "unknown",
    httpStatus: Int? = nil,
    responseCategory: String = "unknown",
    attemptCount: Int = 0,
    durationMilliseconds: Int = 0
  ) {
    self.reasonCode = Self.safeToken(reasonCode)
    self.routeCategory = Self.safeToken(routeCategory)
    self.httpStatus = httpStatus
    self.responseCategory = Self.safeToken(responseCategory)
    self.attemptCount = max(0, attemptCount)
    self.durationMilliseconds = max(0, durationMilliseconds)
  }

  private static func safeToken(_ value: String) -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_")
    }
    return filtered.isEmpty ? "unknown" : String(filtered.prefix(128))
  }
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
        routeCategory: "unknown",
        httpStatus: nil,
        responseCategory: "unknown",
        attemptCount: 0,
        durationMilliseconds: 0,
        serviceDiscoveryAttempted: false,
        serviceDiscoveryMatched: false,
        discoveryMismatchReason: "ownership-unproven"
      )
    }

    let descriptor: HermesAgentStatusDescriptor
    do {
      descriptor = try statusProbe.probeStatus(endpoint: endpoint, timeoutSeconds: timeoutSeconds)
    } catch let error as HermesAgentReadinessProbeFailure {
      return failed(
        reason: error.reasonCode,
        routeCategory: error.routeCategory,
        httpStatus: error.httpStatus,
        responseCategory: error.responseCategory,
        attemptCount: error.attemptCount,
        durationMilliseconds: error.durationMilliseconds
      )
    } catch let error as HermesAgentEndpointDiscoveryError {
      return failed(reason: error.reasonCode)
    } catch {
      return failed(reason: "readiness.connection-failed")
    }

    guard descriptor.endpointIdentityProven else {
      return HermesAgentReadinessResult(
        attempted: true,
        status: "blocked",
        reasonCode: "readiness.identity-unproven",
        statusDescriptor: descriptor,
        statusQueryResult: "identity-mismatch",
        routeCategory: descriptor.routeCategory,
        httpStatus: descriptor.httpStatus,
        responseCategory: descriptor.responseCategory,
        attemptCount: descriptor.attemptCount,
        durationMilliseconds: descriptor.durationMilliseconds,
        serviceDiscoveryAttempted: false,
        serviceDiscoveryMatched: false,
        discoveryMismatchReason: "identity-unproven"
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
        routeCategory: descriptor.routeCategory,
        httpStatus: descriptor.httpStatus,
        responseCategory: descriptor.responseCategory,
        attemptCount: descriptor.attemptCount,
        durationMilliseconds: descriptor.durationMilliseconds,
        serviceDiscoveryAttempted: true,
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
      routeCategory: descriptor.routeCategory,
      httpStatus: descriptor.httpStatus,
      responseCategory: descriptor.responseCategory,
      attemptCount: descriptor.attemptCount,
      durationMilliseconds: descriptor.durationMilliseconds,
      serviceDiscoveryAttempted: true,
      serviceDiscoveryMatched: true,
      discoveryMismatchReason: nil
    )
  }

  private func failed(
    reason: String,
    routeCategory: String = "unknown",
    httpStatus: Int? = nil,
    responseCategory: String = "unknown",
    attemptCount: Int = 1,
    durationMilliseconds: Int = 0
  ) -> HermesAgentReadinessResult {
    HermesAgentReadinessResult(
      attempted: true,
      status: "blocked",
      reasonCode: reason,
      statusDescriptor: nil,
      statusQueryResult: "blocked",
      routeCategory: routeCategory,
      httpStatus: httpStatus,
      responseCategory: responseCategory,
      attemptCount: attemptCount,
      durationMilliseconds: durationMilliseconds,
      serviceDiscoveryAttempted: false,
      serviceDiscoveryMatched: false,
      discoveryMismatchReason: nil
    )
  }
}

public struct HermesHTTPAgentStatusProbe: HermesAgentEndpointStatusProbing {
  public struct HTTPResponse: Equatable, Sendable {
    public let statusCode: Int
    public let body: Data

    public init(statusCode: Int, body: Data) {
      self.statusCode = statusCode
      self.body = body
    }
  }

  private let fetcher: @Sendable (URL, TimeInterval) throws -> HTTPResponse
  private let clock: @Sendable () -> Date

  public init(
    fetcher: (@Sendable (URL, TimeInterval) throws -> HTTPResponse)? = nil,
    clock: @escaping @Sendable () -> Date = Date.init
  ) {
    self.fetcher = fetcher ?? HermesHTTPAgentStatusProbe.fetch
    self.clock = clock
  }

  public func probeStatus(endpoint: HermesAgentEndpointDescriptor, timeoutSeconds: TimeInterval) throws
    -> HermesAgentStatusDescriptor
  {
    guard endpoint.listener.transport == .tcp, endpoint.listener.isLoopback,
      let port = endpoint.observedAssignedPort
    else {
      throw HermesAgentReadinessProbeFailure(
        reasonCode: "readiness.route-unsupported",
        routeCategory: "unsupported",
        responseCategory: "unknown"
      )
    }

    let backend = try HermesBackendEndpoint(port: port)
    let started = clock()
    let response: HTTPResponse
    do {
      response = try fetcher(backend.statusURL, timeoutSeconds)
    } catch {
      throw HermesAgentReadinessProbeFailure(
        reasonCode: Self.connectionReason(for: error),
        routeCategory: "status",
        responseCategory: "connection-failed",
        attemptCount: 1,
        durationMilliseconds: Self.durationMilliseconds(since: started, now: clock())
      )
    }
    let duration = Self.durationMilliseconds(since: started, now: clock())
    let category = Self.responseCategory(body: response.body)
    guard response.statusCode == 200 else {
      throw HermesAgentReadinessProbeFailure(
        reasonCode: response.statusCode == 404
          ? "readiness.http-not-found"
          : "readiness.http-unexpected-status",
        routeCategory: "status",
        httpStatus: response.statusCode,
        responseCategory: response.statusCode == 404 ? "not-found" : category,
        attemptCount: 1,
        durationMilliseconds: duration
      )
    }
    guard !response.body.isEmpty else {
      throw HermesAgentReadinessProbeFailure(
        reasonCode: "readiness.response-empty",
        routeCategory: "status",
        httpStatus: response.statusCode,
        responseCategory: "empty",
        attemptCount: 1,
        durationMilliseconds: duration
      )
    }
    guard category != "html" else {
      throw HermesAgentReadinessProbeFailure(
        reasonCode: "readiness.response-malformed",
        routeCategory: "status",
        httpStatus: response.statusCode,
        responseCategory: "html",
        attemptCount: 1,
        durationMilliseconds: duration
      )
    }
    guard let object = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any] else {
      throw HermesAgentReadinessProbeFailure(
        reasonCode: "readiness.response-malformed",
        routeCategory: "status",
        httpStatus: response.statusCode,
        responseCategory: "malformed",
        attemptCount: 1,
        durationMilliseconds: duration
      )
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
        endpointIdentityProven: false,
        routeCategory: "status",
        httpStatus: response.statusCode,
        responseCategory: "malformed",
        attemptCount: 1,
        durationMilliseconds: duration
      )
    }
    return HermesAgentStatusDescriptor(
      responseShape: "api.status",
      agentFamily: "hermes-agent",
      version: object["version"] as? String,
      endpointIdentityProven: true,
      routeCategory: "status",
      httpStatus: response.statusCode,
      responseCategory: object["version"] is String ? "hermes-status" : "hermes-metadata",
      attemptCount: 1,
      durationMilliseconds: duration
    )
  }

  private static func fetch(url: URL, timeout: TimeInterval) throws -> HTTPResponse {
    let semaphore = DispatchSemaphore(value: 0)
    let outcome = HermesAgentReadinessLockedBox<Result<HTTPResponse, Error>?>(nil)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = timeout
    configuration.timeoutIntervalForResource = timeout
    let session = URLSession(configuration: configuration)
    let task = session.dataTask(with: url) { data, response, error in
      if let error {
        outcome.set(.failure(error))
      } else if let http = response as? HTTPURLResponse {
        outcome.set(.success(HTTPResponse(statusCode: http.statusCode, body: data ?? Data())))
      } else {
        outcome.set(.failure(HermesAgentReadinessProbeFailure(reasonCode: "readiness.connection-failed")))
      }
      semaphore.signal()
    }
    task.resume()
    guard semaphore.wait(timeout: .now() + timeout) == .success else {
      task.cancel()
      throw HermesAgentReadinessProbeFailure(reasonCode: "readiness.timeout")
    }
    guard let result = outcome.value else {
      throw HermesAgentEndpointDiscoveryError.unavailable
    }
    return try result.get()
  }

  private static func responseCategory(body: Data) -> String {
    guard !body.isEmpty else { return "empty" }
    let prefix = String(decoding: body.prefix(256), as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    if prefix.hasPrefix("<!doctype html") || prefix.hasPrefix("<html") {
      return "html"
    }
    return "unknown"
  }

  private static func connectionReason(for error: Error) -> String {
    if let failure = error as? HermesAgentReadinessProbeFailure {
      return failure.reasonCode
    }
    if (error as NSError).domain == NSURLErrorDomain && (error as NSError).code == NSURLErrorTimedOut {
      return "readiness.timeout"
    }
    return "readiness.connection-failed"
  }

  private static func durationMilliseconds(since start: Date, now: Date) -> Int {
    max(0, Int((now.timeIntervalSince(start) * 1000).rounded()))
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
