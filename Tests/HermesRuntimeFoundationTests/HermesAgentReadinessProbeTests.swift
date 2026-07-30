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
    XCTAssertEqual(result.reasonCode, "readiness.identity-unproven")
    XCTAssertFalse(result.endpointIdentityProven)
    XCTAssertFalse(result.serviceDiscoveryAttempted)
  }

  func testHermesSpecificReadinessIsAccepted() {
    let result = probe(status: hermesStatus()).probe(ownership: ownership())

    XCTAssertEqual(result.status, "ready")
    XCTAssertEqual(result.statusQueryResult, "ready")
    XCTAssertTrue(result.endpointIdentityProven)
    XCTAssertEqual(result.routeCategory, "status")
    XCTAssertEqual(result.httpStatus, 200)
    XCTAssertEqual(result.responseCategory, "hermes-status")
    XCTAssertEqual(result.attemptCount, 1)
    XCTAssertTrue(result.serviceDiscoveryMatched)
  }

  func testMalformedResponseIsRejected() {
    let result = probe(error: HermesAgentEndpointDiscoveryError.unavailable).probe(ownership: ownership())

    XCTAssertEqual(result.status, "blocked")
    XCTAssertEqual(result.statusQueryResult, "blocked")
  }

  func testProvenEndpointAlwaysEntersReadinessPhase() {
    let result = probe(error: HermesAgentReadinessProbeFailure(
      reasonCode: "readiness.http-not-found",
      routeCategory: "status",
      httpStatus: 404,
      responseCategory: "not-found",
      attemptCount: 1,
      durationMilliseconds: 12
    )).probe(ownership: ownership())

    XCTAssertTrue(result.attempted)
    XCTAssertEqual(result.reasonCode, "readiness.http-not-found")
    XCTAssertEqual(result.httpStatus, 404)
    XCTAssertEqual(result.responseCategory, "not-found")
  }

  func testDiscoveryEndpointMismatchIsReported() {
    let result = probe(status: hermesStatus(), discoveryMatched: false).probe(ownership: ownership())

    XCTAssertEqual(result.reasonCode, "discovery.endpoint-mismatch")
    XCTAssertTrue(result.serviceDiscoveryAttempted)
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

  func testReadinessProbeDoesNotRequireFixedPortAssumption() {
    let result = probe(status: hermesStatus()).probe(
      ownership: HermesAgentEndpointOwnershipEvidence(
        status: .provenRoot,
        ownerRelationship: "acceptance-owned-root",
        endpointUnique: true,
        startupOutputEndpointMatch: "matched",
        descriptor: HermesAgentEndpointDescriptor(
          requestedPortCategory: .fixed,
          observedAssignedPort: 19123,
          loopbackAddressFamily: "ipv4",
          discoveryTimestamp: "2026-07-30T00:00:00Z",
          listener: HermesAgentListenerIdentity(
            transport: .tcp,
            address: "127.0.0.1",
            port: 19123,
            socketPathCategory: nil,
            owningPID: 100,
            owningUID: 501,
            owningProcessStartTime: "10.0",
            appearedAfterLaunchCheckpoint: true
          )
        ),
        reasonCode: "endpoint.ownership-proven"
      ))

    XCTAssertTrue(result.attempted)
    XCTAssertEqual(result.status, "ready")
  }

  func testHTTPStatusProbeRequiresHermesResponseShape() throws {
    let endpoint = descriptor()
    let accepted = try HermesHTTPAgentStatusProbe(fetcher: { _, _ in
      HermesHTTPAgentStatusProbe.HTTPResponse(statusCode: 200, body: Data(#"{"version":"0.18.2","gateway_running":true}"#.utf8))
    }).probeStatus(endpoint: endpoint, timeoutSeconds: 1)
    let rejected = try HermesHTTPAgentStatusProbe(fetcher: { _, _ in
      HermesHTTPAgentStatusProbe.HTTPResponse(statusCode: 200, body: Data(#"{"ok":true}"#.utf8))
    }).probeStatus(endpoint: endpoint, timeoutSeconds: 1)

    XCTAssertEqual(accepted.agentFamily, "hermes-agent")
    XCTAssertEqual(accepted.responseCategory, "hermes-status")
    XCTAssertTrue(accepted.endpointIdentityProven)
    XCTAssertFalse(rejected.endpointIdentityProven)
    XCTAssertEqual(rejected.responseCategory, "malformed")
  }

  func testHTTPStatusProbeClassifies404HTMLMalformedEmptyAndConnectionFailures() throws {
    let endpoint = descriptor()

    XCTAssertThrowsError(try HermesHTTPAgentStatusProbe(fetcher: { _, _ in
      HermesHTTPAgentStatusProbe.HTTPResponse(statusCode: 404, body: Data())
    }).probeStatus(endpoint: endpoint, timeoutSeconds: 1)) { error in
      XCTAssertEqual((error as? HermesAgentReadinessProbeFailure)?.reasonCode, "readiness.http-not-found")
      XCTAssertEqual((error as? HermesAgentReadinessProbeFailure)?.responseCategory, "not-found")
    }

    XCTAssertThrowsError(try HermesHTTPAgentStatusProbe(fetcher: { _, _ in
      HermesHTTPAgentStatusProbe.HTTPResponse(statusCode: 200, body: Data("<html></html>".utf8))
    }).probeStatus(endpoint: endpoint, timeoutSeconds: 1)) { error in
      XCTAssertEqual((error as? HermesAgentReadinessProbeFailure)?.responseCategory, "html")
    }

    XCTAssertThrowsError(try HermesHTTPAgentStatusProbe(fetcher: { _, _ in
      HermesHTTPAgentStatusProbe.HTTPResponse(statusCode: 200, body: Data("{".utf8))
    }).probeStatus(endpoint: endpoint, timeoutSeconds: 1)) { error in
      XCTAssertEqual((error as? HermesAgentReadinessProbeFailure)?.reasonCode, "readiness.response-malformed")
    }

    XCTAssertThrowsError(try HermesHTTPAgentStatusProbe(fetcher: { _, _ in
      HermesHTTPAgentStatusProbe.HTTPResponse(statusCode: 200, body: Data())
    }).probeStatus(endpoint: endpoint, timeoutSeconds: 1)) { error in
      XCTAssertEqual((error as? HermesAgentReadinessProbeFailure)?.reasonCode, "readiness.response-empty")
    }

    XCTAssertThrowsError(try HermesHTTPAgentStatusProbe(fetcher: { _, _ in
      throw URLError(.cannotConnectToHost)
    }).probeStatus(endpoint: endpoint, timeoutSeconds: 1)) { error in
      XCTAssertEqual((error as? HermesAgentReadinessProbeFailure)?.reasonCode, "readiness.connection-failed")
    }
  }

  func testAlternateDocumentedStatusRouteFixtureRemainsAPIStatus() throws {
    let endpoint = descriptor()
    let requestedURL = LockedURLRecorder()
    _ = try HermesHTTPAgentStatusProbe(fetcher: { url, _ in
      requestedURL.set(url)
      return HermesHTTPAgentStatusProbe.HTTPResponse(statusCode: 200, body: Data(#"{"auth_required":false}"#.utf8))
    }).probeStatus(endpoint: endpoint, timeoutSeconds: 1)

    XCTAssertEqual(requestedURL.value?.path, "/api/status")
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
      endpointIdentityProven: true,
      routeCategory: "status",
      httpStatus: 200,
      responseCategory: "hermes-status",
      attemptCount: 1,
      durationMilliseconds: 0
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

private final class LockedURLRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: URL?

  var value: URL? {
    lock.withLock { storage }
  }

  func set(_ value: URL) {
    lock.withLock { storage = value }
  }
}
