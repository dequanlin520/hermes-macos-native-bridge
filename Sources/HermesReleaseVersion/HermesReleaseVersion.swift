import Foundation

public enum HermesReleaseVersion {
  public static let productVersion = "0.1.0-rc.1"
  public static let tagTarget = "v0.1.0-rc.1"
  public static let xpcProtocolVersion = "1.8"
  public static let testedHermesVersion = "0.18.2"
  public static let minimumMacOS = "13.0"
  public static let buildConfiguration = "release"
  public static let packageType = "app-distribution-bundle"

  public static let supportedCapabilities = [
    "lifecycle-management",
    "status-only-hermes-agent-integration",
    "xpc-service-connectivity",
    "user-scoped-launchagent-assets",
  ]

  public static let unsupportedCapabilities = [
    "request-submission:transport.route-unsupported",
    "request-cancellation:transport.route-unsupported",
    "approval-response:transport.route-unsupported",
    "private-api-ws:not-claimed",
    "production-readiness:not-claimed",
  ]

  public static var manifest: [String: Any] {
    [
      "productVersion": productVersion,
      "tagTarget": tagTarget,
      "xpcProtocolVersion": xpcProtocolVersion,
      "testedHermesVersion": testedHermesVersion,
      "minimumMacOS": minimumMacOS,
      "buildConfiguration": buildConfiguration,
      "packageType": packageType,
      "supportedCapabilities": supportedCapabilities,
      "unsupportedCapabilities": unsupportedCapabilities,
    ]
  }
}
