import Foundation
import HermesBridgeService
import HermesRuntimeFoundation

@main
struct HermesReleaseAgentPreflight {
  static func main() {
    let status = discoverStatus()
    print(status)
  }

  private static func discoverStatus() -> String {
    do {
      let configuration = try HermesBridgeServiceConfiguration.productionDefault()
      let discovery = HermesDiscovery(
        allowlistedExecutableCandidates: configuration.allowlistedHermesExecutableCandidates,
        timeoutSeconds: 5,
        outputLimitBytes: 16 * 1024
      )

      var sawCandidate = false
      for candidate in configuration.allowlistedHermesExecutableCandidates {
        do {
          _ = try discovery.discover(at: candidate)
          return "available"
        } catch HermesDiscoveryError.executableNotFound {
          continue
        } catch HermesDiscoveryError.executableNotRunnable {
          sawCandidate = true
          continue
        } catch HermesDiscoveryError.malformedVersionOutput {
          return "incompatible"
        } catch HermesDiscoveryError.versionCommandFailed {
          return "incompatible"
        } catch HermesDiscoveryError.timeout {
          return "unknown"
        } catch HermesDiscoveryError.pathNotAllowlisted {
          return "unknown"
        } catch {
          return "unknown"
        }
      }
      return sawCandidate ? "unknown" : "unavailable"
    } catch {
      return "unknown"
    }
  }
}
