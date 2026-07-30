import XCTest

@testable import HermesRuntimeFoundation

final class HermesAgentEndpointDiscoveryTests: XCTestCase {
  func testDynamicPortRequestAndExactRootOwnedListenerAreProven() {
    let root = endpointIdentity(pid: 100)
    let listener = tcpListener(pid: 100, uid: root.uid, start: root.processStartTime, port: 49152)
    let result = discovery(listeners: [listener]).discover(
      root: root,
      processTree: tree(root: root),
      requestedPortCategory: .dynamic
    )

    XCTAssertEqual(result.status, .provenRoot)
    XCTAssertEqual(result.ownerRelationship, "acceptance-owned-root")
    XCTAssertEqual(result.descriptor?.requestedPortCategory, .dynamic)
    XCTAssertEqual(result.descriptor?.observedAssignedPort, 49152)
  }

  func testFixedPortAssumptionIsNotRequiredForOwnershipProof() {
    let root = endpointIdentity(pid: 100)
    let result = discovery(listeners: [
      tcpListener(pid: 100, uid: root.uid, start: root.processStartTime, port: 52001)
    ]).discover(root: root, processTree: tree(root: root), requestedPortCategory: .dynamic)

    XCTAssertEqual(result.status, .provenRoot)
    XCTAssertEqual(result.descriptor?.requestedPortCategory, .dynamic)
    XCTAssertEqual(result.descriptor?.observedAssignedPort, 52001)
  }

  func testProvenDescendantOwnedListenerIsAccepted() {
    let root = endpointIdentity(pid: 100, start: "10.0")
    let child = endpointIdentity(pid: 101, ppid: 100, start: "11.0")
    let result = discovery(listeners: [tcpListener(pid: 101, uid: child.uid, start: child.processStartTime)])
      .discover(root: root, processTree: tree(root: root, descendants: [child]), requestedPortCategory: .dynamic)

    XCTAssertEqual(result.status, .provenDescendant)
    XCTAssertEqual(result.ownerRelationship, "acceptance-owned-descendant")
  }

  func testUnrelatedListenerIsRejected() {
    let root = endpointIdentity(pid: 100)
    let result = discovery(listeners: [tcpListener(pid: 999, uid: root.uid, start: root.processStartTime)])
      .discover(root: root, processTree: tree(root: root), requestedPortCategory: .dynamic)

    XCTAssertEqual(result.status, .identityMismatch)
    XCTAssertEqual(result.reasonCode, "endpoint.identity-mismatch")
  }

  func testPreExistingListenerIsRejected() {
    let root = endpointIdentity(pid: 100)
    let result = discovery(listeners: [
      tcpListener(pid: 100, uid: root.uid, start: root.processStartTime, appearedAfterLaunch: false)
    ]).discover(root: root, processTree: tree(root: root), requestedPortCategory: .dynamic)

    XCTAssertEqual(result.status, .identityMismatch)
  }

  func testMultipleListenersAreAmbiguous() {
    let root = endpointIdentity(pid: 100)
    let result = discovery(listeners: [
      tcpListener(pid: 100, uid: root.uid, start: root.processStartTime, port: 40001),
      tcpListener(pid: 100, uid: root.uid, start: root.processStartTime, port: 40002),
    ]).discover(root: root, processTree: tree(root: root), requestedPortCategory: .dynamic)

    XCTAssertEqual(result.status, .multipleCandidates)
    XCTAssertFalse(result.endpointUnique)
  }

  func testNonLoopbackListenerIsRejected() {
    let root = endpointIdentity(pid: 100)
    let result = discovery(listeners: [
      tcpListener(pid: 100, uid: root.uid, start: root.processStartTime, address: "0.0.0.0")
    ]).discover(root: root, processTree: tree(root: root), requestedPortCategory: .dynamic)

    XCTAssertEqual(result.status, .nonLoopbackRejected)
  }

  func testPIDReuseUIDAndStartTimeMismatchesAreRejected() {
    let root = endpointIdentity(pid: 100, uid: 501, start: "10.0")
    for listener in [
      tcpListener(pid: 100, uid: 502, start: "10.0"),
      tcpListener(pid: 100, uid: 501, start: "99.0"),
    ] {
      let result = discovery(listeners: [listener])
        .discover(root: root, processTree: tree(root: root), requestedPortCategory: .dynamic)
      XCTAssertEqual(result.status, .identityMismatch)
    }
  }

  func testStartupOutputCorroboratesAndMismatchIsRejected() {
    let root = endpointIdentity(pid: 100)
    let matched = discovery(listeners: [tcpListener(pid: 100, uid: root.uid, start: root.processStartTime, port: 12345)])
      .discover(
        root: root,
        processTree: tree(root: root),
        requestedPortCategory: .dynamic,
        startupOutputCandidatePort: 12345
      )
    let mismatched = discovery(listeners: [tcpListener(pid: 100, uid: root.uid, start: root.processStartTime, port: 12345)])
      .discover(
        root: root,
        processTree: tree(root: root),
        requestedPortCategory: .dynamic,
        startupOutputCandidatePort: 54321
      )

    XCTAssertEqual(matched.startupOutputEndpointMatch, "matched")
    XCTAssertEqual(mismatched.reasonCode, "endpoint.output-socket-mismatch")
  }

  func testLsofParserAcceptsLoopbackTCP() {
    let identity = endpointIdentity(pid: 100)
    let listeners = LsofHermesAgentSocketOwnershipInspector.parseLsof(
      "p100\ncheremes\nPTCP\nn127.0.0.1:49152\n",
      identity: identity,
      checkpoint: "1.0"
    )

    XCTAssertEqual(listeners.first?.address, "127.0.0.1")
    XCTAssertEqual(listeners.first?.port, 49152)
  }

  private func discovery(listeners: [HermesAgentListenerIdentity]) -> HermesAgentEndpointDiscovery {
    HermesAgentEndpointDiscovery(inspector: FakeSocketInspector(listeners: listeners), now: { "2026-07-30T00:00:00Z" })
  }
}

private struct FakeSocketInspector: HermesAgentSocketOwnershipInspecting {
  let listeners: [HermesAgentListenerIdentity]
  func listeners(for _: [HermesAgentProcessIdentity]) throws -> [HermesAgentListenerIdentity] { listeners }
}

private func tree(
  root: HermesAgentProcessIdentity,
  descendants: [HermesAgentProcessIdentity] = []
) -> HermesAgentProcessTree {
  HermesAgentProcessTree(
    root: HermesAgentSupervisedProcess(identity: root, state: "running"),
    descendants: descendants.map { HermesAgentSupervisedProcess(identity: $0, state: "running") },
    topologyStatus: descendants.isEmpty ? .foregroundSingleProcess : .foregroundWithHelpers
  )
}

private func tcpListener(
  pid: pid_t,
  uid: uid_t,
  start: String,
  port: Int = 49152,
  address: String = "127.0.0.1",
  appearedAfterLaunch: Bool = true
) -> HermesAgentListenerIdentity {
  HermesAgentListenerIdentity(
    transport: .tcp,
    address: address,
    port: port,
    socketPathCategory: nil,
    owningPID: pid,
    owningUID: uid,
    owningProcessStartTime: start,
    appearedAfterLaunchCheckpoint: appearedAfterLaunch
  )
}

private func endpointIdentity(
  pid: pid_t,
  ppid: pid_t = 1,
  uid: uid_t = 501,
  start: String = "10.0"
) -> HermesAgentProcessIdentity {
  HermesAgentProcessIdentity(
    pid: pid,
    ppid: ppid,
    pgid: 100,
    uid: uid,
    executableBasename: "hermes",
    executableFileIdentity: "dev:1,ino:1",
    processStartTime: start,
    launchRunIdentifier: "m14-007-test"
  )
}
