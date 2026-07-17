import Foundation
import HermesBridgeXPC

public enum HermesBridgeServiceHostError: Error, Equatable, Sendable {
  case invalidMachServiceName
  case alreadyStarted
}

public final class HermesBridgeServiceHost: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
  public let configuration: HermesBridgeServiceConfiguration
  public let compositionRoot: HermesBridgeCompositionRoot

  private let listener: NSXPCListener
  private let logger: HermesBridgeServiceLogger
  private let lock = NSLock()
  private let stoppedSemaphore = DispatchSemaphore(value: 0)
  private var started = false
  private var stopped = false
  private var activeConnections = 0

  public convenience init(configuration: HermesBridgeServiceConfiguration) throws {
    let compositionRoot = try HermesBridgeCompositionRoot(configuration: configuration)
    try self.init(
      configuration: configuration,
      compositionRoot: compositionRoot,
      listener: NSXPCListener(machServiceName: configuration.machServiceName)
    )
  }

  public init(
    configuration: HermesBridgeServiceConfiguration,
    compositionRoot: HermesBridgeCompositionRoot,
    listener: NSXPCListener
  ) throws {
    guard (try? configuration.machService) != nil else {
      throw HermesBridgeServiceHostError.invalidMachServiceName
    }
    self.configuration = configuration
    self.compositionRoot = compositionRoot
    self.listener = listener
    self.logger = compositionRoot.logger
    super.init()
    self.listener.delegate = self
  }

  public func start() throws {
    try lock.withLock {
      if started {
        throw HermesBridgeServiceHostError.alreadyStarted
      }
      started = true
    }
    logger.log(.starting)
    listener.resume()
    logger.log(.ready, protocolVersion: "1.0")
  }

  public func stop() async {
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
    listener.invalidate()
    try? await compositionRoot.shutdown()
    stoppedSemaphore.signal()
  }

  public func waitUntilStopped() {
    stoppedSemaphore.wait()
  }

  public func listener(
    _: NSXPCListener,
    shouldAcceptNewConnection newConnection: NSXPCConnection
  ) -> Bool {
    let accepted = lock.withLock {
      guard !stopped, activeConnections < configuration.maximumConcurrentXPCRequests else {
        return false
      }
      activeConnections += 1
      return true
    }
    guard accepted else {
      logger.log(.connectionRejected, category: "xpc")
      return false
    }

    newConnection.exportedInterface = NSXPCInterface(with: HermesBridgeXPCProtocol.self)
    newConnection.exportedObject = compositionRoot.xpcService
    newConnection.invalidationHandler = { [weak self] in
      self?.connectionEnded()
    }
    newConnection.interruptionHandler = { [weak self] in
      self?.connectionEnded()
    }
    newConnection.resume()
    logger.log(.connectionAccepted, category: "xpc", protocolVersion: "1.0")
    return true
  }

  private func connectionEnded() {
    lock.withLock {
      if activeConnections > 0 {
        activeConnections -= 1
      }
    }
  }
}
