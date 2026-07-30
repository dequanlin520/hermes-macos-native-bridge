import Foundation
import XCTest

@testable import HermesRuntimeFoundation

final class HermesAgentProcessTopologyTests: XCTestCase {
  func testForegroundProcessTopology() {
    XCTAssertEqual(
      HermesAgentProcessTopology.classify(
        root: identity(pid: 100),
        descendants: [],
        launcherExited: false,
        unprovenChildRemains: false
      ),
      .foregroundSingleProcess
    )
  }

  func testHelperDescendantTopology() {
    XCTAssertEqual(
      HermesAgentProcessTopology.classify(
        root: identity(pid: 100),
        descendants: [identity(pid: 101, ppid: 100)],
        launcherExited: false,
        unprovenChildRemains: false
      ),
      .foregroundWithHelpers
    )
  }

  func testLauncherExitsAndChildRemains() {
    XCTAssertEqual(
      HermesAgentProcessTopology.classify(
        root: nil,
        descendants: [identity(pid: 101, ppid: 100)],
        launcherExited: true,
        unprovenChildRemains: false
      ),
      .launcherExitedChildRemains
    )
  }

  func testAmbiguousDaemonizationBecomesUnsupportedTopology() {
    XCTAssertEqual(
      HermesAgentProcessTopology.classify(
        root: nil,
        descendants: [identity(pid: 101, ppid: 1)],
        launcherExited: false,
        unprovenChildRemains: false
      ),
      .daemonized
    )
    XCTAssertEqual(
      HermesAgentProcessTopology.classify(
        root: identity(pid: 100),
        descendants: [identity(pid: 220, ppid: 1)],
        launcherExited: false,
        unprovenChildRemains: true
      ),
      .ambiguousTopology
    )
  }

  func testExactLineageValidation() {
    let root = identity(pid: 100, start: "10.0", run: "run")
    let child = identity(pid: 101, ppid: 100, start: "10.1", run: "run")

    XCTAssertTrue(HermesAgentProcessTopology.isProvenDescendant(child, parent: root))
    XCTAssertFalse(
      HermesAgentProcessTopology.isProvenDescendant(
        identity(pid: 101, ppid: 1, start: "10.1", run: "run"),
        parent: root
      ))
    XCTAssertFalse(
      HermesAgentProcessTopology.isProvenDescendant(
        identity(pid: 101, ppid: 100, start: "9.9", run: "run"),
        parent: root
      ))
    XCTAssertFalse(
      HermesAgentProcessTopology.isProvenDescendant(
        identity(pid: 101, ppid: 100, start: "10.1", run: "other"),
        parent: root
      ))
  }

  func testRootExitsBeforeFullIdentityStillAllowsProvisionalLineageProof() {
    let root = identity(pid: 100, uid: 501, start: "10.0", run: "run")
    let child = identity(pid: 101, ppid: 100, uid: 501, start: "10.2", run: "run")

    XCTAssertEqual(
      HermesAgentProcessTopology.classify(
        root: nil,
        descendants: [child],
        launcherExited: true,
        unprovenChildRemains: false
      ),
      .launcherExitedChildRemains
    )
    XCTAssertTrue(HermesAgentProcessTopology.isProvenDescendant(child, parent: root))
  }

  func testUnrelatedChildIsNeverProvenDescendant() {
    let root = identity(pid: 100, uid: 501, start: "10.0", run: "run")

    XCTAssertFalse(
      HermesAgentProcessTopology.isProvenDescendant(
        identity(pid: 101, ppid: 99, uid: 501, start: "10.2", run: "run"),
        parent: root
      ))
    XCTAssertFalse(
      HermesAgentProcessTopology.isProvenDescendant(
        identity(pid: 101, ppid: 100, uid: 502, start: "10.2", run: "run"),
        parent: root
      ))
  }

  func testPIDReuseUIDAndStartTimeMismatchesAreRejectedByFixtureValidator() {
    let validator = FixtureIdentityValidator(valid: [identity(pid: 100, uid: 501, start: "10.0")])

    XCTAssertTrue(validator.validate(identity(pid: 100, uid: 501, start: "10.0")))
    XCTAssertFalse(validator.validate(identity(pid: 100, uid: 502, start: "10.0")))
    XCTAssertFalse(validator.validate(identity(pid: 100, uid: 501, start: "11.0")))
    XCTAssertFalse(validator.validate(identity(pid: 101, uid: 501, start: "10.0")))
  }

  private func identity(
    pid: pid_t,
    ppid: pid_t = 1,
    uid: uid_t = 501,
    start: String = "10.0",
    run: String = "run"
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
}

private struct FixtureIdentityValidator {
  let valid: [HermesAgentProcessIdentity]

  func validate(_ identity: HermesAgentProcessIdentity) -> Bool {
    valid.contains(identity)
  }
}
