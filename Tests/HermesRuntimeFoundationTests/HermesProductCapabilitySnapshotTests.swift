import XCTest
@testable import HermesRuntimeFoundation

final class HermesProductCapabilitySnapshotTests: XCTestCase {
  func testRC1SnapshotMarksHermes0182RequestCancelApprovalUnsupported() {
    let snapshot = HermesProductCapabilitySnapshot.rc1(
      xpcProtocolVersion: "1.8",
      bridgeServiceConnected: true,
      executableAvailable: true,
      observedHermesVersion: "0.18.2",
      compatibilityLevel: .partiallyCompatible,
      runtimeStatus: .ready,
      statusReady: true,
      endpointOwnershipProven: true,
      lifecycleExercised: true,
      controlledReconnectExercised: true,
      exactShutdownExercised: true
    )

    XCTAssertEqual(snapshot.xpcProtocolVersion, "1.8")
    XCTAssertEqual(snapshot.observedHermesVersion, "0.18.2")
    XCTAssertEqual(snapshot.capability(.requestSubmission)?.status, .unsupported)
    XCTAssertEqual(snapshot.capability(.requestCancellation)?.status, .unsupported)
    XCTAssertEqual(snapshot.capability(.approvalResponse)?.status, .unsupported)
    XCTAssertEqual(
      snapshot.capability(.requestSubmission)?.reasonCode,
      "transport.route-unsupported"
    )
    XCTAssertEqual(
      snapshot.capability(.requestCancellation)?.reasonCode,
      "transport.route-unsupported"
    )
    XCTAssertEqual(
      snapshot.capability(.approvalResponse)?.reasonCode,
      "transport.route-unsupported"
    )
  }

  func testSnapshotUsesServiceOwnershipAndDoesNotLeakPortsPIDsPathsOrURLs() throws {
    let snapshot = HermesProductCapabilitySnapshot.rc1(
      xpcProtocolVersion: "1.8",
      bridgeServiceConnected: true,
      executableAvailable: true,
      observedHermesVersion: "0.18.2+dirty:/Users/example:127.0.0.1:9000",
      compatibilityLevel: .partiallyCompatible,
      runtimeStatus: .ready,
      statusReady: true,
      endpointOwnershipProven: true
    )

    let encoded = String(data: try JSONEncoder().encode(snapshot), encoding: .utf8)!
    XCTAssertFalse(encoded.contains("/Users/"))
    XCTAssertFalse(encoded.contains("127.0.0.1"))
    XCTAssertFalse(encoded.contains(":9000"))
    XCTAssertFalse(encoded.contains("\"pid\""))
    XCTAssertFalse(encoded.contains("ws://"))
    XCTAssertEqual(snapshot.observedHermesVersion, "0.18.2")
    XCTAssertEqual(
      snapshot.capability(.dynamicEndpointOwnership)?.ownershipSource,
      "bridge-service"
    )
  }

  func testSupportedLifecycleCapabilitiesAreServiceOwnedWhenEvidenceIsExercised() {
    let snapshot = HermesProductCapabilitySnapshot.rc1(
      xpcProtocolVersion: "1.8",
      bridgeServiceConnected: true,
      executableAvailable: true,
      observedHermesVersion: "0.18.2",
      compatibilityLevel: .partiallyCompatible,
      runtimeStatus: .ready,
      statusReady: true,
      endpointOwnershipProven: true,
      lifecycleExercised: true,
      controlledReconnectExercised: true,
      exactShutdownExercised: true
    )

    XCTAssertEqual(snapshot.capability(.isolatedAgentStart)?.status, .supported)
    XCTAssertEqual(snapshot.capability(.agentReadinessStatus)?.status, .supported)
    XCTAssertEqual(snapshot.capability(.exactAgentShutdown)?.status, .supported)
    XCTAssertTrue(snapshot.capability(.isolatedAgentStart)?.exercised == true)
    XCTAssertTrue(snapshot.capability(.agentReadinessStatus)?.exercised == true)
    XCTAssertTrue(snapshot.capability(.exactAgentShutdown)?.exercised == true)
    XCTAssertEqual(snapshot.capability(.isolatedAgentStart)?.ownershipSource, "bridge-service")
    XCTAssertEqual(snapshot.capability(.exactAgentShutdown)?.ownershipSource, "bridge-service")
  }

  func testPrivateWebSocketRouteIsNeverClaimedSupported() {
    let snapshot = HermesProductCapabilitySnapshot.rc1(
      xpcProtocolVersion: "1.8",
      bridgeServiceConnected: true,
      executableAvailable: true,
      observedHermesVersion: "0.18.2",
      compatibilityLevel: .partiallyCompatible
    )

    XCTAssertEqual(snapshot.capability(.privateWebSocketRoute)?.status, .unsupported)
    XCTAssertEqual(snapshot.capability(.privateWebSocketRoute)?.reasonCode, "private-route.not-assumed")
  }

  func testValidObservedVersionIsPreservedAcrossSnapshotAndCapabilityRows() {
    let snapshot = HermesProductCapabilitySnapshot.rc1(
      xpcProtocolVersion: "1.8",
      bridgeServiceConnected: true,
      executableAvailable: true,
      observedHermesVersion: "0.18.2",
      compatibilityLevel: .partiallyCompatible
    )

    XCTAssertEqual(snapshot.observedHermesVersion, "0.18.2")
    for identifier in [
      HermesProductCapabilityIdentifier.requestSubmission,
      .requestCancellation,
      .approvalResponse,
      .hermesVersionDiscovery,
    ] {
      XCTAssertEqual(snapshot.capability(identifier)?.observedHermesVersion, "0.18.2")
    }
    XCTAssertEqual(snapshot.capability(.hermesVersionDiscovery)?.status, .supported)
  }

  func testSnapshotRoundTripPreservesSemanticVersionAndCapabilityReasons() throws {
    let snapshot = HermesProductCapabilitySnapshot.rc1(
      xpcProtocolVersion: "1.8",
      bridgeServiceConnected: true,
      executableAvailable: true,
      observedHermesVersion: "0.18.2",
      compatibilityLevel: .partiallyCompatible
    )

    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(HermesProductCapabilitySnapshot.self, from: data)

    XCTAssertEqual(decoded.observedHermesVersion, "0.18.2")
    XCTAssertEqual(decoded.capability(.requestSubmission)?.reasonCode, "transport.route-unsupported")
    XCTAssertEqual(decoded.capability(.requestCancellation)?.reasonCode, "transport.route-unsupported")
    XCTAssertEqual(decoded.capability(.approvalResponse)?.reasonCode, "transport.route-unsupported")
  }
}
