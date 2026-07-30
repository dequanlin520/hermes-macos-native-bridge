import Foundation
import XCTest

@testable import HermesRuntimeFoundation

final class HermesAgentReadinessProbeTests: XCTestCase {
  func testTCPConnectAloneAndArbitraryHTTP200AreNotReadiness() {
    let result = probe(status: .init(
      responseShape: "arbitrary-http-200",
      agentFamily: "unknown",
      version: nil,
      endpointIdentityProven: false
    )).probe(ownership: ownership())

    XCTAssertEqual(result.status, "blocked")
    XCTAssertEqual(result.reasonCode, "readiness.agent-identity-mismatch")
    XCTAssertFalse(result.endpointIdentityProven)
  }

  func testHermesSpecificReadinessIsAccepted() {
    let result = probe(status: hermesStatus()).probe(ownership: ownership())

    XCTAssertEqual(result.status, "ready")
    XCTAssertEqual(result.statusQueryResult, "ready")
    XCTAssertTrue(result.endpointIdentityProven)
    XCTAssertTrue(result.serviceDiscoveryMatched)
  }

  func testMalformedResponseIsRejected() {
    let result = probe(error: HermesAgentEndpointDiscoveryError.unavailable).probe(ownership: ownership())

    XCTAssertEqual(result.status, "blocked")
    XCTAssertEqual(result.statusQueryResult, "blocked")
  }

  func testDiscoveryEndpointMismatchIsReported() {
    let result = probe(status: hermesStatus(), discoveryMatched: false).probe(ownership: ownership())

    XCTAssertEqual(result.reasonCode, "discovery.endpoint-mismatch")
    XCTAssertFalse(result.serviceDiscoveryMatched)
  }

  func testOwnershipIsRequiredBeforeProbe() {
    let result = probe(status: hermesStatus()).probe(
      ownership: HermesAgentEndpointOwnershipEvidence(
        status: .identityMismatch,
        ownerRelationship: "identity-mismatch",
        endpointUnique: false,
        startupOutputEndpointMatch: "not-evaluated",
        descriptor: nil,
        reasonCode: "endpoint.identity-mismatch"
      ))

    XCTAssertFalse(result.attempted)
    XCTAssertEqual(result.status, "blocked")
  }

  func testHTTPStatusProbeRequiresHermesResponseShape() throws {
    let endpoint = descriptor()
    let accepted = try HermesHTTPAgentStatusProbe(fetcher: { _, _ in
      Data(#"{"version":"0.18.2","gateway_running":true}"#.utf8)
    }).probeStatus(endpoint: endpoint, timeoutSeconds: 1)
    let rejected = try HermesHTTPAgentStatusProbe(fetcher: { _, _ in
      Data(#"{"ok":true}"#.utf8)
    }).probeStatus(endpoint: endpoint, timeoutSeconds: 1)

    XCTAssertEqual(accepted.agentFamily, "hermes-agent")
    XCTAssertTrue(accepted.endpointIdentityProven)
    XCTAssertFalse(rejected.endpointIdentityProven)
  }

  private func probe(
    status: HermesAgentStatusDescriptor? = nil,
    error: Error? = nil,
    discoveryMatched: Bool = true
  ) -> HermesAgentReadinessProbe {
    HermesAgentReadinessProbe(
      statusProbe: FakeStatusProbe(status: status, error: error),
      serviceDiscovery: FakeEndpointMatcher(matched: discoveryMatched),
      timeoutSeconds: 1
    )
  }

  private func ownership() -> HermesAgentEndpointOwnershipEvidence {
    HermesAgentEndpointOwnershipEvidence(
      status: .provenRoot,
      ownerRelationship: "acceptance-owned-root",
      endpointUnique: true,
      startupOutputEndpointMatch: "not-emitted",
      descriptor: descriptor(),
      reasonCode: "endpoint.ownership-proven"
    )
  }

  private func descriptor() -> HermesAgentEndpointDescriptor {
    HermesAgentEndpointDescriptor(
      requestedPortCategory: .dynamic,
      observedAssignedPort: 49152,
      loopbackAddressFamily: "ipv4",
      discoveryTimestamp: "2026-07-30T00:00:00Z",
      listener: HermesAgentListenerIdentity(
        transport: .tcp,
        address: "127.0.0.1",
        port: 49152,
        socketPathCategory: nil,
        owningPID: 100,
        owningUID: 501,
        owningProcessStartTime: "10.0",
        appearedAfterLaunchCheckpoint: true
      )
    )
  }

  private func hermesStatus() -> HermesAgentStatusDescriptor {
    HermesAgentStatusDescriptor(
      responseShape: "api.status",
      agentFamily: "hermes-agent",
      version: "0.18.2",
      endpointIdentityProven: true
    )
  }
}

private struct FakeStatusProbe: HermesAgentEndpointStatusProbing {
  let status: HermesAgentStatusDescriptor?
  let error: Error?

  func probeStatus(endpoint _: HermesAgentEndpointDescriptor, timeoutSeconds _: TimeInterval) throws
    -> HermesAgentStatusDescriptor
  {
    if let error { throw error }
    return status!
  }
}

private struct FakeEndpointMatcher: HermesAgentEndpointServiceDiscovering {
  let matched: Bool
  func matchesSupervisedEndpoint(_: HermesAgentEndpointDescriptor) -> Bool { matched }
  func mismatchReason(for _: HermesAgentEndpointDescriptor) -> String { "endpoint-mismatch" }
}
