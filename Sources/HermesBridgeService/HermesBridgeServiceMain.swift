import Foundation

public enum HermesBridgeServiceMain {
  public static let readinessMarkerPrefix = "HERMES_BRIDGE_SERVICE_READY service="

  public static func readinessMarker(serviceName: String) -> String {
    "\(readinessMarkerPrefix)\(serviceName)"
  }

  public static func loadTrustedConfiguration(environment: [String: String]) throws
    -> HermesBridgeServiceConfiguration
  {
    guard let configPath = environment["HERMES_BRIDGE_SERVICE_CONFIG"] else {
      return try HermesBridgeServiceConfiguration.productionDefault()
    }

    let allowTest = environment["HERMES_BRIDGE_SERVICE_ALLOW_TEST_CONFIG"] == "1"
    let url = URL(fileURLWithPath: configPath).standardizedFileURL
    if allowTest {
      guard url.path.contains("/artifacts/m2-008/") || url.path.contains("/artifacts/m8-001/")
      else {
        throw HermesBridgeServiceConfigurationError.invalidRoot("test_config_outside_artifacts")
      }
      return try HermesBridgeServiceConfiguration.decodeTrustedConfiguration(
        from: url,
        allowTestMachServiceName: true
      )
    }

    guard url.path.hasSuffix("/HermesBridge/configuration.json") else {
      throw HermesBridgeServiceConfigurationError.invalidRoot("untrusted_configuration_path")
    }
    return try HermesBridgeServiceConfiguration.decodeTrustedConfiguration(from: url)
  }

  public static func redactedStartupFailure(_ error: Error) -> String {
    let code = String(describing: type(of: error))
      .filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
      .prefix(96)
    return "HERMES_BRIDGE_SERVICE_STARTUP_FAILED error=\(code)"
  }
}
