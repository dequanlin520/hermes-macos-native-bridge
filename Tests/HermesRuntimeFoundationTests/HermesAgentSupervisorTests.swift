import Darwin
import Foundation
import XCTest

@testable import HermesRuntimeFoundation

final class HermesAgentSupervisorTests: XCTestCase {
  private var temporaryDirectory: URL!

  override func setUpWithError() throws {
    temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("HermesAgentSupervisorTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: temporaryDirectory)
  }

  func testSemanticVersionSelectionForObserved018Only() throws {
    let environment = try HermesAgentLaunchEnvironment.construct(
      runtimeRoot: temporaryDirectory.appendingPathComponent("runtime", isDirectory: true)
    )
    let surface = HermesAgentCommandSurface(
      versionOutput: "Hermes Agent v0.18.2",
      rootHelpOutput: "Commands:\n  serve\n  status\n",
      subcommandHelp: ["serve": "Usage: serve --isolated", "status": "Usage: status"]
    )

    let accepted = HermesAgentSupervisorConfiguration.from018CommandSurface(
      executableURL: temporaryDirectory.appendingPathComponent("hermes"),
      discoveryResult: discoveryResult(version: "0.18.2"),
      commandSurface: surface,
      environment: environment,
      runIdentifier: "run"
    )
    XCTAssertNotNil(try? accepted.get())

    let rejected = HermesAgentSupervisorConfiguration.from018CommandSurface(
      executableURL: temporaryDirectory.appendingPathComponent("hermes"),
      discoveryResult: discoveryResult(version: "0.19.0"),
      commandSurface: surface,
      environment: environment,
      runIdentifier: "run"
    )
    XCTAssertThrowsError(try rejected.get()) {
      XCTAssertEqual($0 as? HermesAgentSupervisorError, .unsupported("version.out_of_range"))
    }
  }

  func testEndpointOwnershipProofIsRequiredBeyondProcessExistence() throws {
    let controller = FixtureSupervisorController(endpointRelationship: "unrelated-listener")
    let supervisor = HermesAgentSupervisor(controller: controller)

    XCTAssertThrowsError(try supervisor.supervise(configuration: configuration())) {
      XCTAssertEqual($0 as? HermesAgentSupervisorError, .unsupported("endpoint.ownership_not_proven"))
    }
    XCTAssertTrue(controller.signals.contains(.init(pid: 100, signal: SIGTERM)))
    XCTAssertFalse(controller.invocations.contains("serve-stop"))
  }

  func testExactRootTermDescendantTermAndKillFallback() throws {
    let child = identity(pid: 101, ppid: 100)
    let controller = FixtureSupervisorController(
      descendantsAfterRootTerm: [child],
      identitiesAfterTerm: [child],
      waitResults: [false, false, true]
    )
    let result = try HermesAgentSupervisor(controller: controller)
      .supervise(configuration: configuration())

    XCTAssertEqual(result.compatibilityLevel, .supported)
    XCTAssertTrue(result.exactRootTermUsed)
    XCTAssertTrue(result.exactDescendantTermUsed)
    XCTAssertTrue(result.exactKillUsed)
    XCTAssertFalse(result.broadStopInvoked)
    XCTAssertFalse(result.broadProcessKillUsed)
    XCTAssertEqual(
      controller.signals,
      [
        .init(pid: 100, signal: SIGTERM),
        .init(pid: 101, signal: SIGTERM),
        .init(pid: 101, signal: SIGKILL),
      ]
    )
    XCTAssertFalse(controller.signals.contains { $0.pid <= 0 })
  }

  func testNoKillFallbackWhenTermReapsAllProcesses() throws {
    let controller = FixtureSupervisorController(waitResults: [true])
    let result = try HermesAgentSupervisor(controller: controller)
      .supervise(configuration: configuration())

    XCTAssertTrue(result.exactRootTermUsed)
    XCTAssertFalse(result.exactDescendantTermUsed)
    XCTAssertFalse(result.exactKillUsed)
    XCTAssertEqual(controller.signals, [.init(pid: 100, signal: SIGTERM)])
  }

  func testAmbiguousTopologyFails() throws {
    let controller = FixtureSupervisorController(initialTopology: .ambiguousTopology)

    XCTAssertThrowsError(try HermesAgentSupervisor(controller: controller).supervise(configuration: configuration())) {
      XCTAssertEqual($0 as? HermesAgentSupervisorError, .fail("identity.ambiguous_after_launch"))
    }
  }

  func testDaemonizedTopologyIsUnsupported() throws {
    let controller = FixtureSupervisorController(initialTopology: .daemonized)

    XCTAssertThrowsError(try HermesAgentSupervisor(controller: controller).supervise(configuration: configuration())) {
      XCTAssertEqual($0 as? HermesAgentSupervisorError, .unsupported("topology.daemonized"))
    }
  }

  func testRealHomeAccessFailsButExternalMutationIsReportedSeparately() throws {
    let controller = FixtureSupervisorController(realHomeAccess: true, externalMutation: true)
    let result = try HermesAgentSupervisor(controller: controller)
      .supervise(configuration: configuration())

    XCTAssertEqual(result.compatibilityLevel, .fail)
    XCTAssertTrue(result.realHomeModified)
    XCTAssertTrue(result.supervisedProcessRealHomeAccessObserved)
    XCTAssertTrue(result.rawExternalMutationObserved)
  }

  func testOptionalStatusUnavailableIsPartial() throws {
    let controller = FixtureSupervisorController(status: "unavailable")
    let result = try HermesAgentSupervisor(controller: controller)
      .supervise(configuration: configuration())

    XCTAssertEqual(result.compatibilityLevel, .partiallySupported)
  }

  private func configuration(version: String? = "0.18.2") throws -> HermesAgentSupervisorConfiguration {
    HermesAgentSupervisorConfiguration(
      executableURL: temporaryDirectory.appendingPathComponent("hermes"),
      observedVersion: version,
      isolatedArguments: ["serve", "--isolated"],
      statusArguments: ["status"],
      environment: try HermesAgentLaunchEnvironment.construct(
        runtimeRoot: temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
      ),
      runIdentifier: "m14-006-test"
    )
  }

  private func discoveryResult(version: String) -> HermesDiscoveryResult {
    HermesDiscoveryResult(
      candidate: HermesExecutableCandidate(
        allowlistedCandidatePath: "hermes",
        originalPath: "hermes",
        resolvedPath: "hermes",
        symlinkStatus: .notSymlink
      ),
      versionInfo: HermesVersionInfo(
        semanticVersion: version,
        displayVersion: "Hermes Agent v\(version)",
        buildDateText: nil,
        upstreamRevision: nil,
        installationMethod: nil,
        pythonVersion: nil,
        openAISDKVersion: nil,
        rawOutputSHA256Digest: "digest",
        capturedOutputByteCount: 1,
        outputWasTruncated: false,
        sanitizedDiagnosticMetadata: [:]
      )
    )
  }
}

private struct SignalRecord: Equatable {
  let pid: pid_t
  let signal: Int32
}

private final class FixtureSupervisorController: HermesAgentSupervisorProcessControlling,
  @unchecked Sendable
{
  var invocations: [String] = []
  var signals: [SignalRecord] = []

  private let root = identity(pid: 100)
  private let endpointRelationship: String
  private let initialTopology: HermesAgentProcessTopologyStatus
  private let descendantsAfterRootTerm: [HermesAgentProcessIdentity]
  private let identitiesAfterTerm: [HermesAgentProcessIdentity]
  private var captureCount = 0
  private var waitResults: [Bool]
  private let realHomeAccess: Bool
  private let externalMutation: Bool
  private let status: String

  init(
    endpointRelationship: String = "acceptance-owned-root",
    initialTopology: HermesAgentProcessTopologyStatus = .foregroundSingleProcess,
    descendantsAfterRootTerm: [HermesAgentProcessIdentity] = [],
    identitiesAfterTerm: [HermesAgentProcessIdentity] = [],
    waitResults: [Bool] = [true],
    realHomeAccess: Bool = false,
    externalMutation: Bool = false,
    status: String = "ready"
  ) {
    self.endpointRelationship = endpointRelationship
    self.initialTopology = initialTopology
    self.descendantsAfterRootTerm = descendantsAfterRootTerm
    self.identitiesAfterTerm = identitiesAfterTerm
    self.waitResults = waitResults
    self.realHomeAccess = realHomeAccess
    self.externalMutation = externalMutation
    self.status = status
  }

  func launchIsolatedAgent(configuration _: HermesAgentSupervisorConfiguration) throws
    -> HermesAgentProcessIdentity
  {
    invocations.append("launch-isolated")
    return root
  }

  func captureProcessTree(root: HermesAgentProcessIdentity) -> HermesAgentProcessTree {
    captureCount += 1
    if captureCount == 1 {
      let rootProcess = initialTopology == .processExited || initialTopology == .daemonized
        ? nil
        : HermesAgentSupervisedProcess(identity: root, state: "running")
      return HermesAgentProcessTree(root: rootProcess, descendants: [], topologyStatus: initialTopology)
    }
    if captureCount == 2 {
      return HermesAgentProcessTree(
        root: nil,
        descendants: descendantsAfterRootTerm.map { HermesAgentSupervisedProcess(identity: $0, state: "running") },
        topologyStatus: descendantsAfterRootTerm.isEmpty ? .processExited : .launcherExitedChildRemains
      )
    }
    if captureCount > 3 {
      return HermesAgentProcessTree(root: nil, descendants: [], topologyStatus: .processExited)
    }
    return HermesAgentProcessTree(
      root: nil,
      descendants: identitiesAfterTerm.map { HermesAgentSupervisedProcess(identity: $0, state: "running") },
      topologyStatus: identitiesAfterTerm.isEmpty ? .processExited : .launcherExitedChildRemains
    )
  }

  func waitForReadiness(
    root: HermesAgentProcessIdentity,
    processTree _: HermesAgentProcessTree,
    configuration _: HermesAgentSupervisorConfiguration
  ) -> HermesAgentEndpointIdentity {
    HermesAgentEndpointIdentity(
      category: .loopbackTCP,
      isLoopback: true,
      isUnixSocket: false,
      owningPID: root.pid,
      owningPIDRelationship: endpointRelationship,
      readinessTimestamp: "2026-07-30T00:00:00Z",
      protocolStatusOutcome: "ready"
    )
  }

  func serviceDiscoveryMatches(
    endpoint _: HermesAgentEndpointIdentity,
    configuration _: HermesAgentSupervisorConfiguration
  ) -> Bool { true }

  func runStatus(configuration _: HermesAgentSupervisorConfiguration) -> String { status }
  func validate(identity _: HermesAgentProcessIdentity) -> Bool { true }

  func signalExactPID(_ identity: HermesAgentProcessIdentity, signal: Int32) throws {
    XCTAssertGreaterThan(identity.pid, 1)
    signals.append(.init(pid: identity.pid, signal: signal))
  }

  func waitForExit(identity _: HermesAgentProcessIdentity, timeout _: TimeInterval) -> Bool {
    waitResults.isEmpty ? true : waitResults.removeFirst()
  }

  func realHomeAccessObserved(for _: [HermesAgentProcessIdentity]) -> Bool { realHomeAccess }
  func rawExternalRealHomeMutationObserved() -> Bool { externalMutation }
}

private func identity(
  pid: pid_t,
  ppid: pid_t = 1,
  uid: uid_t = 501,
  start: String = "10.0",
  run: String = "m14-006-test"
) -> HermesAgentProcessIdentity {
  HermesAgentProcessIdentity(
    pid: pid,
    ppid: ppid,
    pgid: 100,
    uid: uid,
    executableBasename: "hermes",
    executableFileIdentity: "dev:1,ino:1",
    processStartTime: start,
    launchRunIdentifier: run
  )
}
