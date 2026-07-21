import Foundation

public protocol HermesBackendAdapting: Sendable {
  func discover() throws -> HermesDiscoveryResult
  func start() async throws -> HermesBackendStartResult
  func stop() async throws -> HermesBackendStopResult
  func health() async throws -> HermesBackendHealthSnapshot
}

public protocol HermesBackendDiscovering: Sendable {
  func discover(at candidateURL: URL) throws -> HermesDiscoveryResult
}

extension HermesDiscovery: HermesBackendDiscovering {}

public protocol HermesBackendSupervising: Sendable {
  var state: HermesProcessState { get }
  func start(configuration: HermesProcessConfiguration) throws -> HermesProcessLaunchResult
  func stop() throws -> HermesProcessStopResult
}

extension HermesProcessSupervisor: HermesBackendSupervising {}

public protocol HermesBackendProtocolClienting: AnyObject, Sendable {
  var state: HermesProtocolClientState { get }
  func fetchStatus() async throws -> HermesBackendStatus
  func close() async
}

extension HermesProtocolClient: HermesBackendProtocolClienting {}

public struct HermesBackendAdapterConfiguration: Equatable, Sendable {
  public let executableURL: URL
  public let port: Int
  public let runtimeRoot: URL
  public let startupTimeout: TimeInterval
  public let gracefulShutdownTimeout: TimeInterval
  public let forcedShutdownTimeout: TimeInterval
  public let outputLimitBytes: Int
  public let protocolRequestTimeout: TimeInterval

  public init(
    executableURL: URL,
    port: Int,
    runtimeRoot: URL,
    startupTimeout: TimeInterval = 10,
    gracefulShutdownTimeout: TimeInterval = 5,
    forcedShutdownTimeout: TimeInterval = 5,
    outputLimitBytes: Int = 128 * 1024,
    protocolRequestTimeout: TimeInterval = 5
  ) {
    self.executableURL = executableURL.standardizedFileURL
    self.port = port
    self.runtimeRoot = runtimeRoot.standardizedFileURL
    self.startupTimeout = max(0.001, startupTimeout)
    self.gracefulShutdownTimeout = max(0.001, gracefulShutdownTimeout)
    self.forcedShutdownTimeout = max(0.001, forcedShutdownTimeout)
    self.outputLimitBytes = max(1, outputLimitBytes)
    self.protocolRequestTimeout = max(0.001, protocolRequestTimeout)
  }
}

public struct HermesBackendStartResult: Equatable, Sendable {
  public let discovery: HermesDiscoveryResult
  public let launch: HermesProcessLaunchResult
  public let initialStatus: HermesBackendStatus
}

public struct HermesBackendHealthSnapshot: Equatable, Sendable {
  public let processState: HermesProcessState
  public let protocolState: HermesProtocolClientState
  public let status: HermesBackendStatus
}

public struct HermesBackendStopResult: Equatable, Sendable {
  public let processStop: HermesProcessStopResult
  public let protocolState: HermesProtocolClientState?
}

public enum HermesBackendAdapterError: Error, Equatable, Sendable, CustomStringConvertible {
  case discoveryFailed(String)
  case startupFailed(String)
  case protocolUnavailable(String)
  case healthFailed(String)
  case shutdownFailed(String)
  case notStarted

  public var description: String {
    switch self {
    case .discoveryFailed(let message):
      return "Hermes backend discovery failed: \(message)"
    case .startupFailed(let message):
      return "Hermes backend startup failed: \(message)"
    case .protocolUnavailable(let message):
      return "Hermes backend protocol unavailable: \(message)"
    case .healthFailed(let message):
      return "Hermes backend health failed: \(message)"
    case .shutdownFailed(let message):
      return "Hermes backend shutdown failed: \(message)"
    case .notStarted:
      return "Hermes backend has not been started"
    }
  }
}

public final class HermesBackendAdapter: HermesBackendAdapting, @unchecked Sendable {
  public typealias ProtocolClientFactory = @Sendable (HermesBackendLaunchContext)
    -> HermesBackendProtocolClienting

  private let configuration: HermesBackendAdapterConfiguration
  private let discovery: HermesBackendDiscovering
  private let supervisor: HermesBackendSupervising
  private let protocolClientFactory: ProtocolClientFactory
  private let lock = NSLock()
  private var currentDiscovery: HermesDiscoveryResult?
  private var currentLaunch: HermesProcessLaunchResult?
  private var currentClient: HermesBackendProtocolClienting?

  public convenience init(
    allowlistedExecutableCandidates: [URL],
    configuration: HermesBackendAdapterConfiguration,
    supervisor: HermesBackendSupervising = HermesProcessSupervisor()
  ) {
    self.init(
      configuration: configuration,
      discovery: HermesDiscovery(allowlistedExecutableCandidates: allowlistedExecutableCandidates),
      supervisor: supervisor
    )
  }

  public init(
    configuration: HermesBackendAdapterConfiguration,
    discovery: HermesBackendDiscovering,
    supervisor: HermesBackendSupervising = HermesProcessSupervisor(),
    protocolClientFactory: ProtocolClientFactory? = nil
  ) {
    self.configuration = configuration
    self.discovery = discovery
    self.supervisor = supervisor
    self.protocolClientFactory =
      protocolClientFactory
      ?? { context in
        HermesProtocolClient(
          endpoint: context.endpoint,
          token: context.sessionToken,
          requestTimeout: configuration.protocolRequestTimeout
        )
      }
  }

  public func discover() throws -> HermesDiscoveryResult {
    do {
      let result = try discovery.discover(at: configuration.executableURL)
      lock.withLock { currentDiscovery = result }
      return result
    } catch {
      throw HermesBackendAdapterError.discoveryFailed(Self.redactedMessage(for: error))
    }
  }

  public func start() async throws -> HermesBackendStartResult {
    let discoveryResult = try discover()
    let launch: HermesProcessLaunchResult
    do {
      let processConfiguration = try HermesProcessConfiguration(
        executable: discoveryResult.candidate,
        port: configuration.port,
        runtimeRoot: configuration.runtimeRoot,
        startupTimeout: configuration.startupTimeout,
        gracefulShutdownTimeout: configuration.gracefulShutdownTimeout,
        forcedShutdownTimeout: configuration.forcedShutdownTimeout,
        outputLimitBytes: configuration.outputLimitBytes
      )
      launch = try supervisor.start(configuration: processConfiguration)
      lock.withLock { currentLaunch = launch }
    } catch {
      throw HermesBackendAdapterError.startupFailed(Self.redactedMessage(for: error))
    }

    let client = protocolClientFactory(launch.launchContext)
    lock.withLock { currentClient = client }

    do {
      let status = try await client.fetchStatus()
      return HermesBackendStartResult(
        discovery: discoveryResult,
        launch: launch,
        initialStatus: status
      )
    } catch {
      await client.close()
      lock.withLock { currentClient = nil }
      _ = try? supervisor.stop()
      throw HermesBackendAdapterError.protocolUnavailable(Self.redactedMessage(for: error))
    }
  }

  public func stop() async throws -> HermesBackendStopResult {
    let client = lock.withLock { currentClient }
    await client?.close()

    do {
      let stop = try supervisor.stop()
      lock.withLock {
        currentClient = nil
        currentLaunch = nil
      }
      return HermesBackendStopResult(processStop: stop, protocolState: client?.state)
    } catch {
      throw HermesBackendAdapterError.shutdownFailed(Self.redactedMessage(for: error))
    }
  }

  public func health() async throws -> HermesBackendHealthSnapshot {
    guard let client = lock.withLock({ currentClient }) else {
      throw HermesBackendAdapterError.notStarted
    }

    do {
      let status = try await client.fetchStatus()
      return HermesBackendHealthSnapshot(
        processState: supervisor.state,
        protocolState: client.state,
        status: status
      )
    } catch {
      throw HermesBackendAdapterError.healthFailed(Self.redactedMessage(for: error))
    }
  }

  static func redactedMessage(for error: Error) -> String {
    sanitize(String(describing: error))
  }

  private static func sanitize(_ message: String) -> String {
    var sanitized = message
    for marker in ["token=", "X-Hermes-Session-Token=", "HERMES_DASHBOARD_SESSION_TOKEN="] {
      var searchStart = sanitized.startIndex
      while searchStart < sanitized.endIndex,
        let range = sanitized.range(of: marker, range: searchStart..<sanitized.endIndex)
      {
        let valueStart = range.upperBound
        let valueEnd = sanitized[valueStart...].firstIndex {
          $0 == "&" || $0 == " " || $0 == "\n" || $0 == "\t" || $0 == ")" || $0 == ","
        } ?? sanitized.endIndex
        sanitized.replaceSubrange(valueStart..<valueEnd, with: "<redacted>")
        searchStart = sanitized.index(valueStart, offsetBy: "<redacted>".count)
      }
    }
    return sanitized
  }
}
