import Foundation
import HermesReleaseVersion

@main
struct HermesReleaseVersionPrinter {
  static func main() throws {
    if CommandLine.arguments.dropFirst().first == "--json" {
      let data = try JSONSerialization.data(
        withJSONObject: HermesReleaseVersion.manifest,
        options: [.prettyPrinted, .sortedKeys]
      )
      FileHandle.standardOutput.write(data)
      print()
      return
    }

    for key in [
      "PRODUCT_VERSION", "TAG_TARGET", "XPC_PROTOCOL_VERSION",
      "TESTED_HERMES_VERSION", "MINIMUM_MACOS", "BUILD_CONFIGURATION", "PACKAGE_TYPE",
    ] {
      print("\(key)=\(value(for: key))")
    }
  }

  private static func value(for key: String) -> String {
    switch key {
    case "PRODUCT_VERSION": return HermesReleaseVersion.productVersion
    case "TAG_TARGET": return HermesReleaseVersion.tagTarget
    case "XPC_PROTOCOL_VERSION": return HermesReleaseVersion.xpcProtocolVersion
    case "TESTED_HERMES_VERSION": return HermesReleaseVersion.testedHermesVersion
    case "MINIMUM_MACOS": return HermesReleaseVersion.minimumMacOS
    case "BUILD_CONFIGURATION": return HermesReleaseVersion.buildConfiguration
    case "PACKAGE_TYPE": return HermesReleaseVersion.packageType
    default: return "unknown"
    }
  }
}
