import Foundation
import HermesBridgeService
import HermesRuntimeFoundation

@main
struct HermesReleaseAgentPreflight {
  static func main() {
    if CommandLine.arguments.dropFirst().first == "m14-005-inspect" {
      printM14005Inspect()
      return
    }
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

  private static func printM14005Inspect() {
    let report = M14005ProductionInspector.inspect()
    for key in M14005ProductionInspector.orderedKeys {
      print("\(key)=\(report[key] ?? "unknown")")
    }
  }
}

private enum M14005ProductionInspector {
  static let orderedKeys = [
    "USER_SCOPE_ONLY",
    "SERVICE_OWNED_CONTRACT_SELECTION",
    "SERVICE_OWNED_DISCOVERY_USED",
    "HERMES_EXECUTABLE_STATUS",
    "HERMES_EXECUTABLE_FAMILY",
    "HERMES_EXECUTABLE_BASENAME",
    "HERMES_EXECUTABLE_SOURCE",
    "HERMES_VERSION_STATUS",
    "HERMES_VERSION",
    "DISCOVERY_PARITY",
    "ISOLATED_START_ADVERTISED",
    "STATUS_MECHANISM_ADVERTISED",
    "EXACT_ISOLATED_SHUTDOWN_ADVERTISED",
    "BROAD_SHUTDOWN_ADVERTISED",
    "BROAD_SHUTDOWN_SAFE_FOR_ISOLATED_LIFECYCLE",
    "LAUNCH_CONTRACT_STATUS",
    "LAUNCH_CONTRACT_REASON",
    "M14_005_EXPECTED_RESULT",
    "EXPECTED_EXIT_CODE",
  ]

  static func inspect() -> [String: String] {
    var values = defaults()
    do {
      let configuration = try HermesBridgeServiceConfiguration.productionDefault()
      let discovery = HermesDiscovery(
        allowlistedExecutableCandidates: configuration.allowlistedHermesExecutableCandidates,
        timeoutSeconds: 5,
        outputLimitBytes: 16 * 1024
      )
      guard let result = firstDiscoveryResult(
        discovery: discovery,
        candidates: configuration.allowlistedHermesExecutableCandidates
      ) else {
        values["HERMES_EXECUTABLE_STATUS"] = "unavailable"
        values["HERMES_EXECUTABLE_FAMILY"] = "unknown"
        values["HERMES_EXECUTABLE_BASENAME"] = "unknown"
        values["HERMES_EXECUTABLE_SOURCE"] = "unknown"
        values["HERMES_VERSION_STATUS"] = "blocked"
        values["LAUNCH_CONTRACT_REASON"] = "executable.unavailable"
        values["M14_005_EXPECTED_RESULT"] = "BLOCKED"
        values["EXPECTED_EXIT_CODE"] = "3"
        return values
      }

      let descriptor = HermesAgentVersionDescriptor(result: result, sourceCategory: "PATH")
      values["HERMES_EXECUTABLE_STATUS"] = descriptor.discoveryStatus
      values["HERMES_EXECUTABLE_FAMILY"] = descriptor.executableFamily
      values["HERMES_EXECUTABLE_BASENAME"] = descriptor.executableBasename
      values["HERMES_EXECUTABLE_SOURCE"] = descriptor.sourceCategory
      values["HERMES_VERSION_STATUS"] = "available"
      values["HERMES_VERSION"] = descriptor.semanticVersion ?? "unknown"
      values["DISCOVERY_PARITY"] = discoveryParity(
        first: descriptor,
        discovery: discovery,
        candidate: URL(fileURLWithPath: result.candidate.originalPath)
      )

      let probe = HermesCommandSurfaceProbe(executableURL: URL(fileURLWithPath: result.candidate.originalPath))
      guard let surface = probe.commandSurface(versionOutput: result.versionInfo.displayVersion) else {
        values["LAUNCH_CONTRACT_STATUS"] = "blocked"
        values["LAUNCH_CONTRACT_REASON"] = "command.surface.probe_failed"
        values["M14_005_EXPECTED_RESULT"] = "BLOCKED"
        values["EXPECTED_EXIT_CODE"] = "3"
        return values
      }

      values["ISOLATED_START_ADVERTISED"] = surface.isolatedStartupAdvertised ? "yes" : "no"
      values["STATUS_MECHANISM_ADVERTISED"] = surface.statusMechanismAdvertised ? "yes" : "no"
      values["EXACT_ISOLATED_SHUTDOWN_ADVERTISED"] =
        surface.exactIsolatedShutdownAdvertised ? "yes" : "no"
      values["BROAD_SHUTDOWN_ADVERTISED"] = surface.broadShutdownAdvertised ? "yes" : "no"
      values["BROAD_SHUTDOWN_SAFE_FOR_ISOLATED_LIFECYCLE"] = "no"

      let contract = HermesAgentLaunchContractSelector.select(
        discoveryResult: result,
        commandSurface: surface
      )
      values["LAUNCH_CONTRACT_STATUS"] = contract.status.rawValue
      values["LAUNCH_CONTRACT_REASON"] = contract.reasonCode
      switch contract.status {
      case .supported:
        values["M14_005_EXPECTED_RESULT"] = "PASS"
        values["EXPECTED_EXIT_CODE"] = "0"
      case .unsupported, .incompatible, .partiallySupported:
        values["M14_005_EXPECTED_RESULT"] = "UNSUPPORTED"
        values["EXPECTED_EXIT_CODE"] = "6"
      case .blocked:
        values["M14_005_EXPECTED_RESULT"] = "BLOCKED"
        values["EXPECTED_EXIT_CODE"] = "3"
      }
      return values
    } catch {
      values["LAUNCH_CONTRACT_STATUS"] = "blocked"
      values["LAUNCH_CONTRACT_REASON"] = "discovery.unknown_error"
      values["M14_005_EXPECTED_RESULT"] = "BLOCKED"
      values["EXPECTED_EXIT_CODE"] = "3"
      return values
    }
  }

  private static func defaults() -> [String: String] {
    [
      "USER_SCOPE_ONLY": "yes",
      "SERVICE_OWNED_CONTRACT_SELECTION": "yes",
      "SERVICE_OWNED_DISCOVERY_USED": "yes",
      "HERMES_EXECUTABLE_STATUS": "unknown",
      "HERMES_EXECUTABLE_FAMILY": "unknown",
      "HERMES_EXECUTABLE_BASENAME": "unknown",
      "HERMES_EXECUTABLE_SOURCE": "unknown",
      "HERMES_VERSION_STATUS": "unknown",
      "HERMES_VERSION": "unknown",
      "DISCOVERY_PARITY": "unknown",
      "ISOLATED_START_ADVERTISED": "no",
      "STATUS_MECHANISM_ADVERTISED": "no",
      "EXACT_ISOLATED_SHUTDOWN_ADVERTISED": "no",
      "BROAD_SHUTDOWN_ADVERTISED": "no",
      "BROAD_SHUTDOWN_SAFE_FOR_ISOLATED_LIFECYCLE": "no",
      "LAUNCH_CONTRACT_STATUS": "blocked",
      "LAUNCH_CONTRACT_REASON": "unknown",
      "M14_005_EXPECTED_RESULT": "BLOCKED",
      "EXPECTED_EXIT_CODE": "3",
    ]
  }

  private static func firstDiscoveryResult(
    discovery: HermesDiscovery,
    candidates: [URL]
  ) -> HermesDiscoveryResult? {
    for candidate in candidates {
      do {
        return try discovery.discover(at: candidate)
      } catch HermesDiscoveryError.executableNotFound {
        continue
      } catch {
        return nil
      }
    }
    return nil
  }

  private static func discoveryParity(
    first descriptor: HermesAgentVersionDescriptor,
    discovery: HermesDiscovery,
    candidate: URL
  ) -> String {
    guard let second = try? discovery.discover(at: candidate) else {
      return "no"
    }
    let secondDescriptor = HermesAgentVersionDescriptor(result: second, sourceCategory: "PATH")
    return descriptor == secondDescriptor ? "yes" : "no"
  }
}

private struct HermesCommandSurfaceProbe {
  let executableURL: URL

  func commandSurface(versionOutput: String) -> HermesAgentCommandSurface? {
    guard let rootHelp = runHelp(arguments: ["--help"]) else {
      return nil
    }
    var subcommandHelp: [String: String] = [:]
    for subcommand in ["serve", "status", "health", "agent", "daemon", "start"] {
      guard HermesAgentCommandSurface(
        versionOutput: versionOutput,
        rootHelpOutput: rootHelp,
        subcommandHelp: subcommandHelp
      ).advertisesSubcommand(subcommand) else {
        continue
      }
      if let help = runHelp(arguments: [subcommand, "--help"]) {
        subcommandHelp[subcommand] = help
      }
    }
    return HermesAgentCommandSurface(
      versionOutput: versionOutput,
      rootHelpOutput: rootHelp,
      subcommandHelp: subcommandHelp
    )
  }

  private func runHelp(arguments: [String]) -> String? {
    do {
      try HermesAgentCommandSafetyPolicy.validateProbeArguments(arguments)
    } catch {
      return nil
    }
    let runtimeRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("hermes-m14-005-preflight-\(UUID().uuidString)", isDirectory: true)
    defer {
      try? FileManager.default.removeItem(at: runtimeRoot)
    }
    guard
      let environment = try? HermesAgentLaunchEnvironment.construct(
        runtimeRoot: runtimeRoot,
        inherited: ProcessInfo.processInfo.environment
      )
    else {
      return nil
    }

    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments
    process.environment = environment.variables
    process.standardInput = FileHandle.nullDevice
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    let termination = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in termination.signal() }
    do {
      try process.run()
    } catch {
      return nil
    }
    guard process.processIdentifier > 1 else {
      return nil
    }
    if termination.wait(timeout: .now() + 5) != .success {
      process.terminate()
      if termination.wait(timeout: .now() + 1) != .success, process.isRunning {
        kill(process.processIdentifier, SIGKILL)
        _ = termination.wait(timeout: .now() + 2)
      }
      return nil
    }

    let output = stdout.fileHandleForReading.readDataToEndOfFile()
      + stderr.fileHandleForReading.readDataToEndOfFile()
    guard process.terminationStatus == 0 else {
      return nil
    }
    let bounded = output.prefix(64 * 1024)
    return String(data: bounded, encoding: .utf8)
  }
}
