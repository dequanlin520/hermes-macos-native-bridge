import Foundation
import XCTest

@testable import HermesRuntimeFoundation

final class HermesAgentProtocolDescriptorTests: XCTestCase {
  func testOpenAPIMetadataParsingAndCapabilityCategories() throws {
    let descriptor = try HermesAgentProtocolDescriptor.discover(
      statusData: statusData(authRequired: true),
      openAPIMetadataData: openAPIData(paths: ["/api/status", "/api/ws"])
    )

    XCTAssertEqual(descriptor.protocolFamily, "hermes-jsonrpc-websocket")
    XCTAssertEqual(descriptor.protocolVersion, "0.18.2")
    XCTAssertEqual(descriptor.metadataSource, "openapi-api-status-and-local-implementation")
    XCTAssertEqual(descriptor.request.routeCategory, "jsonrpc-websocket-session-create")
    XCTAssertEqual(descriptor.status.routeCategory, "jsonrpc-websocket-session-status")
    XCTAssertEqual(descriptor.cancel.routeCategory, "jsonrpc-websocket-session-interrupt")
    XCTAssertEqual(descriptor.approval.routeCategory, "jsonrpc-websocket-approval-respond")
    XCTAssertEqual(descriptor.streamingModesAdvertised, ["websocket-jsonrpc-events"])
  }

  func testUnadvertisedGuessedRoutesRejected() throws {
    let descriptor = try HermesAgentProtocolDescriptor.discover(
      statusData: statusData(),
      openAPIMetadataData: openAPIData(paths: ["/api/status", "/api/requests", "/api/cancel"]),
      implementationMethods: ["session.status"]
    )

    XCTAssertEqual(descriptor.request.status, .unsupported)
    XCTAssertEqual(descriptor.request.reasonCode, "protocol.request-route-unsupported")
    XCTAssertEqual(descriptor.cancel.status, .unsupported)
    XCTAssertEqual(descriptor.cancel.reasonCode, "protocol.cancel-route-unsupported")
  }

  func testAuthenticationCategoryParsingAndEphemeralIsolation() throws {
    let descriptor = try HermesAgentProtocolDescriptor.discover(
      statusData: statusData(authRequired: true, authMode: "loopback_token"),
      openAPIMetadataData: nil
    )

    XCTAssertTrue(descriptor.authenticationRequired)
    XCTAssertEqual(descriptor.authenticationCategory, "loopback_token")
    XCTAssertTrue(descriptor.ephemeralCredentialIsolated)
    XCTAssertEqual(descriptor.authenticationState, .requiredAvailable)
  }

  func testAuthenticationNoneWhenStatusSaysNotRequired() throws {
    let descriptor = try HermesAgentProtocolDescriptor.discover(
      statusData: statusData(authRequired: false, authMode: nil),
      openAPIMetadataData: nil
    )

    XCTAssertFalse(descriptor.authenticationRequired)
    XCTAssertEqual(descriptor.authenticationCategory, "none")
    XCTAssertFalse(descriptor.ephemeralCredentialIsolated)
    XCTAssertEqual(descriptor.authenticationState, .notRequired)
    XCTAssertEqual(descriptor.authenticationState.ephemeralCredentialIsolatedResult, "skip")
  }

  func testAuthenticationStringNoMapsToTypedNotRequired() throws {
    let status = Data(
      #"{"version":"0.18.2","auth_required":"no","desktop_contract":3,"gateway_running":true}"#.utf8
    )

    let descriptor = try HermesAgentProtocolDescriptor.discover(statusData: status, openAPIMetadataData: nil)

    XCTAssertFalse(descriptor.authenticationRequired)
    XCTAssertEqual(descriptor.authenticationCategory, "none")
    XCTAssertEqual(descriptor.authenticationState, .notRequired)
  }

  func testMalformedJSONRejected() {
    XCTAssertThrowsError(
      try HermesAgentProtocolDescriptor.discover(statusData: Data("{".utf8), openAPIMetadataData: nil)
    ) {
      XCTAssertEqual(($0 as? HermesAgentProtocolError)?.reasonCode, "protocol.status-malformed")
    }
  }

  func testArbitraryHTTP200ShapeRejected() {
    XCTAssertThrowsError(
      try HermesAgentProtocolDescriptor.discover(
        statusData: Data(#"{"ok":true}"#.utf8),
        openAPIMetadataData: nil
      )
    ) {
      XCTAssertEqual(($0 as? HermesAgentProtocolError)?.reasonCode, "protocol.status-not-hermes")
    }
  }

  func testTokenPathsUUIDsAndPortsRedacted() {
    let raw = """
      token abcdefghijklmnopqrstuvwxyz123456 at /Users/jerrysmith/.hermes/profile \
      id 123e4567-e89b-12d3-a456-426614174000 endpoint 127.0.0.1:49152
      """
    let redacted = HermesAgentProtocolSanitizer.redactEvidence(raw)

    XCTAssertFalse(redacted.contains("abcdefghijklmnopqrstuvwxyz123456"))
    XCTAssertFalse(redacted.contains("/Users/jerrysmith"))
    XCTAssertFalse(redacted.contains("123e4567-e89b-12d3-a456-426614174000"))
    XCTAssertFalse(redacted.contains(":49152"))
    XCTAssertTrue(redacted.contains("<redacted-token>"))
    XCTAssertTrue(redacted.contains("<redacted-path>"))
    XCTAssertTrue(redacted.contains("<redacted-port>"))
  }

  private func statusData(authRequired: Bool = true, authMode: String? = "loopback_token") -> Data {
    var object: [String: Any] = [
      "version": "0.18.2",
      "auth_required": authRequired,
      "desktop_contract": 3,
      "gateway_running": true,
    ]
    if let authMode {
      object["auth_mode"] = authMode
    }
    return try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
  }

  private func openAPIData(paths: [String]) -> Data {
    let pathMap = Dictionary(uniqueKeysWithValues: paths.map { ($0, ["get": [:]]) })
    return try! JSONSerialization.data(withJSONObject: ["paths": pathMap], options: [.sortedKeys])
  }
}
