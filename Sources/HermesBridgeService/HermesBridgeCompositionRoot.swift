import Foundation
import HermesBridgeXPC
import HermesRuntimeFoundation

public enum HermesBridgeCompositionRootError: Error, Equatable, Sendable {
  case missingExecutableCandidate
  case invalidExecutableCandidate
  case processConfigurationFailed(String)
  case stateStoreFailed(String)
  case bindingRegistryFailed(String)
}

public final class HermesBridgeCompositionRoot: @unchecked Sendable {
  public let configuration: HermesBridgeServiceConfiguration
  public let paths: HermesBridgeServicePaths
  public let discovery: HermesDiscovery
  public let supervisor: HermesProcessSupervisor
  public let protocolFactory: HermesProtocolClientFactory
  public let stateStore: FileBackedHermesRequestStateStore
  public let bindingRegistry: ConfigurationBackedHermesRequestBindingRegistry
  public let orchestrator: HermesRequestOrchestrator
  public let dispatcher: HermesBridgeXPCRequestDispatcher
  public let xpcService: HermesBridgeXPCService
  public let logger: HermesBridgeServiceLogger

  private let lock = NSLock()
  private var stopped = false

  public init(
    configuration: HermesBridgeServiceConfiguration,
    paths: HermesBridgeServicePaths? = nil,
    logger: HermesBridgeServiceLogger? = nil
  ) throws {
    self.configuration = configuration
    let resolvedPaths = try paths ?? HermesBridgeServicePaths(configuration: configuration)
    self.paths = resolvedPaths
    self.logger = logger ?? HermesBridgeServiceLogger(logsRoot: resolvedPaths.logsRoot)
    self.discovery = HermesDiscovery(
      allowlistedExecutableCandidates: configuration.allowlistedHermesExecutableCandidates,
      timeoutSeconds: min(configuration.timeouts.startup, 10)
    )
    self.supervisor = HermesProcessSupervisor()
    self.protocolFactory = HermesProtocolClientFactory()

    do {
      self.stateStore = try FileBackedHermesRequestStateStore(
        storageRoot: resolvedPaths.requestStateRoot)
    } catch {
      throw HermesBridgeCompositionRootError.stateStoreFailed(Self.safeCode(for: error))
    }

    do {
      self.bindingRegistry = try ConfigurationBackedHermesRequestBindingRegistry(
        definitions: configuration.bindings)
    } catch {
      throw HermesBridgeCompositionRootError.bindingRegistryFailed(Self.safeCode(for: error))
    }

    let processConfiguration: HermesProcessConfiguration
    do {
      processConfiguration = try HermesProcessConfiguration(
        executable: Self.serviceExecutableCandidate(configuration),
        port: configuration.loopbackPortPolicy.fixedPort,
        runtimeRoot: resolvedPaths.runtimeRoot,
        startupTimeout: configuration.timeouts.startup,
        gracefulShutdownTimeout: configuration.timeouts.gracefulShutdown,
        forcedShutdownTimeout: configuration.timeouts.forcedShutdown
      )
    } catch {
      throw HermesBridgeCompositionRootError.processConfigurationFailed(Self.safeCode(for: error))
    }

    self.orchestrator = HermesRequestOrchestrator(
      bindingRegistry: bindingRegistry,
      stateStore: stateStore,
      supervisor: supervisor,
      processConfiguration: processConfiguration,
      protocolFactory: protocolFactory,
      gatewayReadyTimeout: configuration.timeouts.gatewayReady
    )
    self.dispatcher = HermesBridgeXPCRequestDispatcher(
      handler: orchestrator,
      maximumConcurrentRequests: configuration.maximumConcurrentXPCRequests
    )
    self.xpcService = HermesBridgeXPCService(dispatcher: dispatcher)
  }

  public func shutdown() async throws {
    let shouldStop = lock.withLock {
      if stopped {
        return false
      }
      stopped = true
      return true
    }
    guard shouldStop else {
      return
    }
    logger.log(.stopping)
    xpcService.invalidate()
    do {
      try await orchestrator.shutdown()
      logger.log(.stopped)
    } catch {
      logger.log(.stopped, error: error)
      throw error
    }
  }

  private static func serviceExecutableCandidate(
    _ configuration: HermesBridgeServiceConfiguration
  ) throws -> HermesExecutableCandidate {
    guard let url = configuration.allowlistedHermesExecutableCandidates.first else {
      throw HermesBridgeCompositionRootError.missingExecutableCandidate
    }
    let standardized = url.standardizedFileURL
    guard standardized.isFileURL, !standardized.path.isEmpty else {
      throw HermesBridgeCompositionRootError.invalidExecutableCandidate
    }
    return HermesExecutableCandidate(
      allowlistedCandidatePath: standardized.path,
      originalPath: standardized.path,
      resolvedPath: standardized.resolvingSymlinksInPath().path,
      symlinkStatus: symlinkStatus(for: standardized)
    )
  }

  private static func symlinkStatus(for url: URL) -> HermesExecutableCandidate.SymlinkStatus {
    do {
      _ = try FileManager.default.destinationOfSymbolicLink(atPath: url.path)
      return .symlink(
        resolved: FileManager.default.fileExists(
          atPath: url.resolvingSymlinksInPath().path))
    } catch {
      return .notSymlink
    }
  }

  private static func safeCode(for error: Error) -> String {
    String(describing: type(of: error))
      .filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
  }
}
