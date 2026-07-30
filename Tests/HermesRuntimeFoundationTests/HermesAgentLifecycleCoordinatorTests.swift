import Darwin
import Foundation
import XCTest

@testable import HermesRuntimeFoundation

final class HermesAgentLifecycleCoordinatorTests: XCTestCase {
  private var temporaryDirectory: URL!
  private var executable: URL!
  private var environment: HermesAgentLaunchEnvironment!

  override func setUpWithError() throws {
    temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("HermesAgentLifecycleCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    executable = temporaryDirectory.appendingPathComponent("hermes")
    try "#!/bin/sh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
    environment = try HermesAgentLaunchEnvironment.construct(
      runtimeRoot: temporaryDirectory.appendingPathComponent("runtime", isDirectory: true)
    )
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: temporaryDirectory)
  }

  func testExactProcessIdentityCapture() throws {
    let validator = FakeIdentityValidator()
    let controller = FakeLifecycleController()
    let coordinator = HermesAgentLifecycleCoordinator(
      contract: supportedContract(),
      executableURL: executable,
      environment: environment,
      controller: controller,
      identityValidator: validator
    )

    let result = try coordinator.start(runIdentifier: "run-1")

    XCTAssertEqual(result.identity.pid, 4242)
    XCTAssertEqual(result.identity.uid, 501)
    XCTAssertEqual(result.identity.processStartTime, "10.20")
    XCTAssertEqual(controller.launchedArguments, ["serve"])
  }

  func testPIDReuseRejection() throws {
    let validator = FakeIdentityValidator()
    validator.valid = false
    let controller = FakeLifecycleController()
    let coordinator = startedCoordinator(controller: controller, validator: validator)

    let result = try coordinator.shutdown()

    XCTAssertEqual(result.status, .identityMismatch)
    XCTAssertEqual(controller.signals, [])
  }

  func testUIDMismatchRejection() throws {
    let validator = FakeIdentityValidator()
    validator.identity = validator.identityWith(uid: 502)
    validator.valid = false
    let controller = FakeLifecycleController()
    let coordinator = startedCoordinator(controller: controller, validator: validator)

    let result = try coordinator.shutdown()

    XCTAssertEqual(result.status, .identityMismatch)
  }

  func testStartTimeMismatchRejection() throws {
    let validator = FakeIdentityValidator()
    validator.identity = validator.identityWith(processStartTime: "99.99")
    validator.valid = false
    let controller = FakeLifecycleController()
    let coordinator = startedCoordinator(controller: controller, validator: validator)

    let result = try coordinator.shutdown()

    XCTAssertEqual(result.status, .identityMismatch)
  }

  func testReadinessIsNotProcessExistenceOnly() throws {
    let contract = HermesAgentLaunchContract(
      observedVersion: "0.18.2",
      status: .supported,
      reasonCode: "test",
      descriptor: HermesAgentLaunchDescriptor(
        invocationMode: .directExecutable,
        requiredArguments: ["serve"],
        statusArguments: nil,
        shutdownArguments: nil
      ),
      advertisedCapabilities: [.noninteractiveStartup, .stableProcessIdentity],
      readinessMechanism: .unsupported,
      shutdownMechanism: .unsupported
    )
    let coordinator = HermesAgentLifecycleCoordinator(
      contract: contract,
      executableURL: executable,
      environment: environment,
      controller: FakeLifecycleController(),
      identityValidator: FakeIdentityValidator()
    )

    XCTAssertThrowsError(try coordinator.start(runIdentifier: "run-1")) {
      XCTAssertEqual($0 as? HermesAgentLifecycleError, .unsupportedReadinessContract)
    }
  }

  func testReadinessTimeoutCleanupSurfacesTimeout() throws {
    let controller = FakeLifecycleController()
    controller.readinessError = .readinessTimeout
    let coordinator = HermesAgentLifecycleCoordinator(
      contract: supportedContract(),
      executableURL: executable,
      environment: environment,
      controller: controller,
      identityValidator: FakeIdentityValidator()
    )

    XCTAssertThrowsError(try coordinator.start(runIdentifier: "run-1")) {
      XCTAssertEqual($0 as? HermesAgentLifecycleError, .readinessTimeout)
    }
  }

  func testGracefulShutdown() throws {
    let controller = FakeLifecycleController()
    controller.gracefulShutdownSucceeds = true
    let coordinator = startedCoordinator(controller: controller, validator: FakeIdentityValidator())

    let result = try coordinator.shutdown()

    XCTAssertEqual(result.status, .graceful)
    XCTAssertEqual(result.exactTermUsed, false)
    XCTAssertEqual(controller.signals, [])
  }

  func testExactTermFallback() throws {
    let controller = FakeLifecycleController()
    controller.waitExitAfterSignals = [SIGTERM: true]
    let coordinator = startedCoordinator(controller: controller, validator: FakeIdentityValidator())

    let result = try coordinator.shutdown()

    XCTAssertEqual(result.status, .exactTerm)
    XCTAssertEqual(result.exactTermUsed, true)
    XCTAssertEqual(result.exactKillUsed, false)
    XCTAssertEqual(controller.signals, [SIGTERM])
  }

  func testExactKillFinalFallback() throws {
    let controller = FakeLifecycleController()
    controller.waitExitAfterSignals = [SIGTERM: false, SIGKILL: true]
    let coordinator = startedCoordinator(controller: controller, validator: FakeIdentityValidator())

    let result = try coordinator.shutdown()

    XCTAssertEqual(result.status, .exactKill)
    XCTAssertEqual(controller.signals, [SIGTERM, SIGKILL])
  }

  func testNoNegativePIDSignalingAndNoBroadKill() throws {
    XCTAssertThrowsError(try HermesAgentCommandSafetyPolicy.validateNoBroadSignal(pid: -10))
    XCTAssertThrowsError(try HermesAgentCommandSafetyPolicy.validateNoBroadSignal(pid: 1))
    try HermesAgentCommandSafetyPolicy.validateNoBroadSignal(pid: 42)
  }

  func testUnsupportedContractProducesUnsupportedShutdown() throws {
    let coordinator = HermesAgentLifecycleCoordinator(
      contract: HermesAgentLaunchContractSelector.unsupported(
        version: "0.18.2",
        reason: "startup.command.not_advertised"
      ),
      executableURL: executable,
      environment: environment,
      controller: FakeLifecycleController(),
      identityValidator: FakeIdentityValidator()
    )

    let result = try coordinator.shutdown()

    XCTAssertEqual(result.status, .unsupported)
  }

  private func startedCoordinator(
    controller: FakeLifecycleController,
    validator: FakeIdentityValidator
  ) -> HermesAgentLifecycleCoordinator {
    let coordinator = HermesAgentLifecycleCoordinator(
      contract: supportedContract(),
      executableURL: executable,
      environment: environment,
      controller: controller,
      identityValidator: validator
    )
    _ = try? coordinator.start(runIdentifier: "run-1")
    return coordinator
  }

  private func supportedContract() -> HermesAgentLaunchContract {
    HermesAgentLaunchContract(
      observedVersion: "0.18.2",
      status: .supported,
      reasonCode: "launch.contract.supported",
      descriptor: HermesAgentLaunchDescriptor(
        invocationMode: .directExecutable,
        requiredArguments: ["serve"],
        statusArguments: ["status"],
        shutdownArguments: ["stop"]
      ),
      advertisedCapabilities: HermesAgentLaunchCapability.allCases,
      readinessMechanism: .documentedStatusCommand,
      shutdownMechanism: .documentedStopCommand,
      timeoutPolicy: HermesAgentTimeoutPolicy(
        readinessSeconds: 0.1,
        gracefulShutdownSeconds: 0.1,
        forcedShutdownSeconds: 0.1
      )
    )
  }
}

private final class FakeIdentityValidator: HermesAgentProcessIdentityValidating, @unchecked Sendable {
  var valid = true
  var identity = HermesAgentProcessIdentity(
    pid: 4242,
    ppid: 100,
    pgid: 4242,
    uid: 501,
    executableBasename: "hermes",
    executableFileIdentity: "dev:1,ino:2",
    processStartTime: "10.20",
    launchRunIdentifier: "run-1"
  )

  func identityWith(uid: uid_t? = nil, processStartTime: String? = nil) -> HermesAgentProcessIdentity {
    HermesAgentProcessIdentity(
      pid: identity.pid,
      ppid: identity.ppid,
      pgid: identity.pgid,
      uid: uid ?? identity.uid,
      executableBasename: identity.executableBasename,
      executableFileIdentity: identity.executableFileIdentity,
      processStartTime: processStartTime ?? identity.processStartTime,
      launchRunIdentifier: identity.launchRunIdentifier
    )
  }

  func capture(
    pid _: pid_t,
    executableURL _: URL,
    launchRunIdentifier: String
  ) throws -> HermesAgentProcessIdentity {
    HermesAgentProcessIdentity(
      pid: identity.pid,
      ppid: identity.ppid,
      pgid: identity.pgid,
      uid: identity.uid,
      executableBasename: identity.executableBasename,
      executableFileIdentity: identity.executableFileIdentity,
      processStartTime: identity.processStartTime,
      launchRunIdentifier: launchRunIdentifier
    )
  }

  func validate(_: HermesAgentProcessIdentity) -> Bool {
    valid
  }
}

private final class FakeLifecycleController: HermesAgentLifecycleProcessControlling, @unchecked Sendable {
  var launchedArguments: [String] = []
  var readinessError: HermesAgentLifecycleError?
  var gracefulShutdownSucceeds = false
  var waitExitAfterSignals: [Int32: Bool] = [:]
  var signals: [Int32] = []

  func launch(
    executableURL _: URL,
    arguments: [String],
    environment _: HermesAgentLaunchEnvironment
  ) throws -> pid_t {
    launchedArguments = arguments
    return 4242
  }

  func waitUntilReady(
    identity _: HermesAgentProcessIdentity,
    timeout _: TimeInterval
  ) throws -> HermesAgentReadinessEvidence {
    if let readinessError {
      throw readinessError
    }
    return HermesAgentReadinessEvidence(
      mechanism: .documentedStatusCommand,
      status: "ready",
      serviceDiscoveryMatched: true
    )
  }

  func runStatus(
    executableURL _: URL,
    arguments _: [String],
    environment _: HermesAgentLaunchEnvironment,
    timeout _: TimeInterval
  ) throws -> HermesAgentReadinessEvidence {
    HermesAgentReadinessEvidence(
      mechanism: .documentedStatusCommand,
      status: "ready",
      serviceDiscoveryMatched: true
    )
  }

  func runGracefulShutdown(
    executableURL _: URL,
    arguments _: [String],
    environment _: HermesAgentLaunchEnvironment,
    timeout _: TimeInterval
  ) throws -> Bool {
    gracefulShutdownSucceeds
  }

  func waitForExit(pid _: pid_t, timeout _: TimeInterval) -> Bool {
    waitExitAfterSignals[signals.last ?? 0] ?? false
  }

  func signalExactPID(_ pid: pid_t, signal: Int32) throws {
    try HermesAgentCommandSafetyPolicy.validateNoBroadSignal(pid: pid)
    signals.append(signal)
  }
}
