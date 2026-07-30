import Darwin
import Foundation

public protocol HermesAgentLifecycleProcessControlling: Sendable {
  func launch(
    executableURL: URL,
    arguments: [String],
    environment: HermesAgentLaunchEnvironment
  ) throws -> pid_t
  func waitUntilReady(
    identity: HermesAgentProcessIdentity,
    timeout: TimeInterval
  ) throws -> HermesAgentReadinessEvidence
  func runStatus(
    executableURL: URL,
    arguments: [String],
    environment: HermesAgentLaunchEnvironment,
    timeout: TimeInterval
  ) throws -> HermesAgentReadinessEvidence
  func runGracefulShutdown(
    executableURL: URL,
    arguments: [String],
    environment: HermesAgentLaunchEnvironment,
    timeout: TimeInterval
  ) throws -> Bool
  func waitForExit(pid: pid_t, timeout: TimeInterval) -> Bool
  func signalExactPID(_ pid: pid_t, signal: Int32) throws
}

public struct HermesAgentLifecycleStartResult: Equatable, Sendable {
  public let identity: HermesAgentProcessIdentity
  public let readinessEvidence: HermesAgentReadinessEvidence

  public init(
    identity: HermesAgentProcessIdentity,
    readinessEvidence: HermesAgentReadinessEvidence
  ) {
    self.identity = identity
    self.readinessEvidence = readinessEvidence
  }
}

public final class HermesAgentLifecycleCoordinator: @unchecked Sendable {
  public let contract: HermesAgentLaunchContract
  public let executableURL: URL
  public let environment: HermesAgentLaunchEnvironment

  private let controller: HermesAgentLifecycleProcessControlling
  private let identityValidator: HermesAgentProcessIdentityValidating
  private let lock = NSLock()
  private var currentIdentity: HermesAgentProcessIdentity?

  public init(
    contract: HermesAgentLaunchContract,
    executableURL: URL,
    environment: HermesAgentLaunchEnvironment,
    controller: HermesAgentLifecycleProcessControlling = DarwinHermesAgentLifecycleProcessController(),
    identityValidator: HermesAgentProcessIdentityValidating = DarwinHermesAgentProcessIdentityValidator()
  ) {
    self.contract = contract
    self.executableURL = executableURL
    self.environment = environment
    self.controller = controller
    self.identityValidator = identityValidator
  }

  public func start(runIdentifier: String) throws -> HermesAgentLifecycleStartResult {
    guard contract.isStartable else {
      throw HermesAgentLifecycleError.unsupportedContract(contract.reasonCode)
    }
    guard contract.readinessMechanism != .unsupported else {
      throw HermesAgentLifecycleError.unsupportedReadinessContract
    }
    guard !contract.descriptor.requiredArguments.isEmpty else {
      throw HermesAgentLifecycleError.forbiddenCommand("bare-hermes")
    }

    let pid = try controller.launch(
      executableURL: executableURL,
      arguments: contract.descriptor.requiredArguments,
      environment: environment
    )
    let identity = try identityValidator.capture(
      pid: pid,
      executableURL: executableURL,
      launchRunIdentifier: runIdentifier
    )
    let evidence = try controller.waitUntilReady(
      identity: identity,
      timeout: contract.timeoutPolicy.readinessSeconds
    )
    guard evidence.mechanism != .unsupported, evidence.status == "ready" else {
      throw HermesAgentLifecycleError.malformedReadinessEvidence
    }
    lock.withLock { currentIdentity = identity }
    return HermesAgentLifecycleStartResult(identity: identity, readinessEvidence: evidence)
  }

  public func status() throws -> HermesAgentReadinessEvidence {
    guard contract.isStartable else {
      throw HermesAgentLifecycleError.unsupportedContract(contract.reasonCode)
    }
    guard let arguments = contract.descriptor.statusArguments, !arguments.isEmpty else {
      throw HermesAgentLifecycleError.unsupportedReadinessContract
    }
    return try controller.runStatus(
      executableURL: executableURL,
      arguments: arguments,
      environment: environment,
      timeout: contract.timeoutPolicy.readinessSeconds
    )
  }

  public func shutdown() throws -> HermesAgentShutdownResult {
    guard contract.isStartable else {
      return HermesAgentShutdownResult(status: .unsupported, exactTermUsed: false, exactKillUsed: false)
    }
    guard let identity = lock.withLock({ currentIdentity }) else {
      return HermesAgentShutdownResult(status: .alreadyExited, exactTermUsed: false, exactKillUsed: false)
    }

    if !identityValidator.validate(identity) {
      lock.withLock { currentIdentity = nil }
      return HermesAgentShutdownResult(status: .identityMismatch, exactTermUsed: false, exactKillUsed: false)
    }

    if let arguments = contract.descriptor.shutdownArguments,
      try controller.runGracefulShutdown(
        executableURL: executableURL,
        arguments: arguments,
        environment: environment,
        timeout: contract.timeoutPolicy.gracefulShutdownSeconds
      )
    {
      lock.withLock { currentIdentity = nil }
      return HermesAgentShutdownResult(status: .graceful, exactTermUsed: false, exactKillUsed: false)
    }

    guard identityValidator.validate(identity) else {
      lock.withLock { currentIdentity = nil }
      return HermesAgentShutdownResult(status: .identityMismatch, exactTermUsed: false, exactKillUsed: false)
    }
    try HermesAgentCommandSafetyPolicy.validateNoBroadSignal(pid: identity.pid)
    try controller.signalExactPID(identity.pid, signal: SIGTERM)
    if controller.waitForExit(pid: identity.pid, timeout: contract.timeoutPolicy.gracefulShutdownSeconds) {
      lock.withLock { currentIdentity = nil }
      return HermesAgentShutdownResult(status: .exactTerm, exactTermUsed: true, exactKillUsed: false)
    }

    guard identityValidator.validate(identity) else {
      lock.withLock { currentIdentity = nil }
      return HermesAgentShutdownResult(status: .identityMismatch, exactTermUsed: true, exactKillUsed: false)
    }
    try controller.signalExactPID(identity.pid, signal: SIGKILL)
    if controller.waitForExit(pid: identity.pid, timeout: contract.timeoutPolicy.forcedShutdownSeconds) {
      lock.withLock { currentIdentity = nil }
      return HermesAgentShutdownResult(status: .exactKill, exactTermUsed: true, exactKillUsed: true)
    }
    return HermesAgentShutdownResult(status: .timeout, exactTermUsed: true, exactKillUsed: true)
  }
}

public final class DarwinHermesAgentLifecycleProcessController:
  HermesAgentLifecycleProcessControlling, @unchecked Sendable
{
  public init() {}

  public func launch(
    executableURL: URL,
    arguments: [String],
    environment: HermesAgentLaunchEnvironment
  ) throws -> pid_t {
    guard !arguments.isEmpty else {
      throw HermesAgentLifecycleError.forbiddenCommand("bare-hermes")
    }
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments
    process.environment = environment.variables
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    do {
      try process.run()
      return process.processIdentifier
    } catch {
      throw HermesAgentLifecycleError.launchFailed("process-run-failed")
    }
  }

  public func waitUntilReady(
    identity _: HermesAgentProcessIdentity,
    timeout _: TimeInterval
  ) throws -> HermesAgentReadinessEvidence {
    throw HermesAgentLifecycleError.unsupportedReadinessContract
  }

  public func runStatus(
    executableURL: URL,
    arguments: [String],
    environment: HermesAgentLaunchEnvironment,
    timeout: TimeInterval
  ) throws -> HermesAgentReadinessEvidence {
    guard !arguments.isEmpty else {
      throw HermesAgentLifecycleError.forbiddenCommand("bare-hermes")
    }
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments
    process.environment = environment.variables
    process.standardInput = FileHandle.nullDevice
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning && Date() < deadline {
      Thread.sleep(forTimeInterval: 0.02)
    }
    if process.isRunning {
      process.terminate()
      throw HermesAgentLifecycleError.readinessTimeout
    }
    return HermesAgentReadinessEvidence(
      mechanism: .documentedStatusCommand,
      status: process.terminationStatus == 0 ? "ready" : "not-ready",
      serviceDiscoveryMatched: false
    )
  }

  public func runGracefulShutdown(
    executableURL: URL,
    arguments: [String],
    environment: HermesAgentLaunchEnvironment,
    timeout: TimeInterval
  ) throws -> Bool {
    guard !arguments.isEmpty else { return false }
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments
    process.environment = environment.variables
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try process.run()
    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning && Date() < deadline {
      Thread.sleep(forTimeInterval: 0.02)
    }
    if process.isRunning {
      process.terminate()
      return false
    }
    return process.terminationStatus == 0
  }

  public func waitForExit(pid: pid_t, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if kill(pid, 0) != 0 {
        return true
      }
      Thread.sleep(forTimeInterval: 0.02)
    }
    return kill(pid, 0) != 0
  }

  public func signalExactPID(_ pid: pid_t, signal: Int32) throws {
    try HermesAgentCommandSafetyPolicy.validateNoBroadSignal(pid: pid)
    guard kill(pid, signal) == 0 else {
      throw HermesAgentLifecycleError.shutdownTimeout
    }
  }
}

