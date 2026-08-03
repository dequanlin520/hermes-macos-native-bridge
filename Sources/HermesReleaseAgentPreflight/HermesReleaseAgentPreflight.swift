import Foundation
import HermesBridgeXPC
import HermesBridgeService
import HermesRuntimeFoundation
import HermesReleaseVersion

@main
struct HermesReleaseAgentPreflight {
  static func main() {
    if CommandLine.arguments.dropFirst().first == "m14-005-inspect" {
      printM14005Inspect()
      return
    }
    if CommandLine.arguments.dropFirst().first == "m14-009-inspect" {
      printM14009Inspect()
      return
    }
    if CommandLine.arguments.dropFirst().first == "m14-010-version" {
      printM14010Version()
      return
    }
    if CommandLine.arguments.dropFirst().first == "m14-008-exercise-protocol" {
      runM14008ExerciseProtocol()
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

  private static func printM14009Inspect() {
    let report = M14009ProductionInspector.inspect()
    for key in M14009ProductionInspector.orderedKeys {
      print("\(key)=\(report[key] ?? "unknown")")
    }
  }

  private static func runM14008ExerciseProtocol() {
    let args = Array(CommandLine.arguments.dropFirst().dropFirst())
    guard args.count == 4, let port = Int(args[0]) else {
      fputs("websocket.handshake-malformed\n", stderr)
      Foundation.exit(2)
    }

    let result = BlockingAsync.run {
      await M14008ProductionProtocolExercise.run(
        port: port,
        authenticationMode: args[1],
        tokenValue: args[2].isEmpty ? nil : args[2],
        outputPath: args[3]
      )
    }
    if result != 0 {
      Foundation.exit(result)
    }
  }

  private static func printM14010Version() {
    print("PRODUCT_VERSION=\(HermesReleaseVersion.productVersion)")
    print("TAG_TARGET=\(HermesReleaseVersion.tagTarget)")
    print("XPC_PROTOCOL_VERSION=\(HermesReleaseVersion.xpcProtocolVersion)")
    print("TESTED_HERMES_VERSION=\(HermesReleaseVersion.testedHermesVersion)")
    print("MINIMUM_MACOS=\(HermesReleaseVersion.minimumMacOS)")
    print("PACKAGE_TYPE=\(HermesReleaseVersion.packageType)")
  }
}

private enum M14009ProductionInspector {
  static let orderedKeys = [
    "XPC_PROTOCOL_VERSION",
    "HERMES_EXECUTABLE_AVAILABLE",
    "HERMES_EXECUTABLE_FAMILY",
    "HERMES_EXECUTABLE_SOURCE",
    "HERMES_VERSION_STATUS",
    "HERMES_VERSION",
    "DISCOVERY_PARITY",
    "REQUEST_CAPABILITY",
    "REQUEST_CAPABILITY_REASON",
    "CANCEL_CAPABILITY",
    "CANCEL_CAPABILITY_REASON",
    "APPROVAL_CAPABILITY",
    "APPROVAL_CAPABILITY_REASON",
    "RC_SCOPE_STATUS",
    "M14_009_EXPECTED_RESULT",
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
        values["M14_009_EXPECTED_RESULT"] = "BLOCKED"
        return values
      }

      let descriptor = HermesAgentVersionDescriptor(result: result, sourceCategory: "PATH")
      let versionLevel = HermesAgentCompatibilityReport.compatibilityLevel(
        forSemanticVersion: descriptor.semanticVersion
      )
      let compatibilityLevel: HermesAgentCompatibilityLevel =
        versionLevel == .compatible ? .partiallyCompatible : versionLevel
      let snapshot = HermesProductCapabilitySnapshot.rc1(
        xpcProtocolVersion: HermesBridgeProtocolVersion.current.description,
        bridgeServiceConnected: true,
        executableAvailable: true,
        observedHermesVersion: descriptor.semanticVersion,
        compatibilityLevel: compatibilityLevel,
        runtimeStatus: .stopped
      )
      let capabilitiesPayload = HermesBridgeCapabilitiesPayload(
        protocolVersion: .current,
        capabilities: HermesBridgeCapability.allCases,
        productCapabilitySnapshot: snapshot
      )
      let encodedPayload = try JSONEncoder().encode(capabilitiesPayload)
      let decodedPayload = try JSONDecoder().decode(
        HermesBridgeCapabilitiesPayload.self,
        from: encodedPayload
      )
      guard let decodedSnapshot = decodedPayload.productCapabilitySnapshot else {
        values["M14_009_EXPECTED_RESULT"] = "BLOCKED"
        return values
      }

      values["HERMES_EXECUTABLE_AVAILABLE"] = "yes"
      values["HERMES_EXECUTABLE_FAMILY"] = descriptor.executableFamily
      values["HERMES_EXECUTABLE_SOURCE"] = descriptor.sourceCategory
      values["HERMES_VERSION_STATUS"] = descriptor.semanticVersion == nil ? "unknown" : "available"
      values["HERMES_VERSION"] = decodedSnapshot.observedHermesVersion ?? "unknown"
      values["DISCOVERY_PARITY"] = discoveryParity(
        first: descriptor,
        discovery: discovery,
        candidate: URL(fileURLWithPath: result.candidate.originalPath)
      )
      values["REQUEST_CAPABILITY"] =
        decodedSnapshot.capability(.requestSubmission)?.status.rawValue ?? "unknown"
      values["REQUEST_CAPABILITY_REASON"] =
        decodedSnapshot.capability(.requestSubmission)?.reasonCode ?? "unknown"
      values["CANCEL_CAPABILITY"] =
        decodedSnapshot.capability(.requestCancellation)?.status.rawValue ?? "unknown"
      values["CANCEL_CAPABILITY_REASON"] =
        decodedSnapshot.capability(.requestCancellation)?.reasonCode ?? "unknown"
      values["APPROVAL_CAPABILITY"] =
        decodedSnapshot.capability(.approvalResponse)?.status.rawValue ?? "unknown"
      values["APPROVAL_CAPABILITY_REASON"] =
        decodedSnapshot.capability(.approvalResponse)?.reasonCode ?? "unknown"
      values["M14_009_EXPECTED_RESULT"] =
        values["DISCOVERY_PARITY"] == "yes" && decodedSnapshot.observedHermesVersion != nil
        ? "PASS" : "BLOCKED"
      return values
    } catch {
      values["M14_009_EXPECTED_RESULT"] = "BLOCKED"
      return values
    }
  }

  private static func defaults() -> [String: String] {
    [
      "XPC_PROTOCOL_VERSION": HermesBridgeProtocolVersion.current.description,
      "HERMES_EXECUTABLE_AVAILABLE": "no",
      "HERMES_EXECUTABLE_FAMILY": "unknown",
      "HERMES_EXECUTABLE_SOURCE": "unknown",
      "HERMES_VERSION_STATUS": "unknown",
      "HERMES_VERSION": "unknown",
      "DISCOVERY_PARITY": "unknown",
      "REQUEST_CAPABILITY": "unsupported",
      "REQUEST_CAPABILITY_REASON": "transport.route-unsupported",
      "CANCEL_CAPABILITY": "unsupported",
      "CANCEL_CAPABILITY_REASON": "transport.route-unsupported",
      "APPROVAL_CAPABILITY": "unsupported",
      "APPROVAL_CAPABILITY_REASON": "transport.route-unsupported",
      "RC_SCOPE_STATUS": "frozen",
      "M14_009_EXPECTED_RESULT": "BLOCKED",
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

private enum BlockingAsync {
  static func run(_ operation: @escaping @Sendable () async -> Int32) -> Int32 {
    let semaphore = DispatchSemaphore(value: 0)
    let box = LockedBox<Int32>(1)
    Task {
      let value = await operation()
      box.set(value)
      semaphore.signal()
    }
    semaphore.wait()
    return box.get()
  }
}

private final class LockedBox<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Value

  init(_ value: Value) {
    self.value = value
  }

  func set(_ value: Value) {
    lock.withLock {
      self.value = value
    }
  }

  func get() -> Value {
    lock.withLock { value }
  }
}

private enum M14008ProductionProtocolExercise {
  static func run(
    port: Int,
    authenticationMode: String,
    tokenValue: String?,
    outputPath: String
  ) async -> Int32 {
    let started = DispatchTime.now()
    do {
      let endpoint = try HermesBackendEndpoint(port: port)
      let authenticationState: HermesAgentAuthenticationState =
        authenticationMode == "ephemeral" ? .requiredAvailable : .notRequired
      let token = tokenValue.map { HermesBackendSessionToken(rawValue: $0) }
      let descriptor = descriptor(authenticationState: authenticationState)
      let client = HermesAgentRequestClientFactory().makeClient(
        descriptor: descriptor,
        endpoint: endpoint,
        token: token
      )
      let request = try await client.submitSafeSyntheticRequest()
      let observed = try await client.observeStatus(for: request)
      let cancellation = try await client.cancel(request: request, targetIdentity: request.identity)
      let reconnected = try await client.reconnectAndObserve(request: request)
      await client.close()
      try writeEvidence(
        outputPath: outputPath,
        authenticationMode: authenticationMode,
        identityCaptured: true,
        initialState: observed.rawValue,
        cancelState: cancellation.terminalState.rawValue,
        reconnectStatusObserved: reconnected != .unknown,
        durationMilliseconds: elapsedMilliseconds(since: started)
      )
      return 0
    } catch {
      fputs("\(reasonCode(for: error))\n", stderr)
      return 1
    }
  }

  private static func descriptor(
    authenticationState: HermesAgentAuthenticationState
  ) -> HermesAgentProtocolDescriptor {
    HermesAgentProtocolDescriptor(
      protocolFamily: "hermes-jsonrpc-websocket",
      rpcModel: "jsonrpc",
      transportFamily: HermesAgentRequestClientFactory.productionTransportFamily,
      transportRouteCategory: "jsonrpc-websocket-session-create",
      eventStreamingCapability: "websocket-events",
      webSocketSubprotocolCategory: HermesAgentRequestClientFactory.productionWebSocketSubprotocolCategory,
      webSocketOriginMode: HermesAgentRequestClientFactory.productionWebSocketOriginMode,
      protocolVersion: "0.18.2",
      request: HermesAgentProtocolCapability(
        status: .supportedUnexercised,
        routeCategory: "jsonrpc-websocket-session-create",
        reasonCode: "protocol.request-advertised"
      ),
      status: HermesAgentProtocolCapability(
        status: .supportedUnexercised,
        routeCategory: "jsonrpc-websocket-session-status",
        reasonCode: "protocol.status-advertised"
      ),
      cancel: HermesAgentProtocolCapability(
        status: .supportedUnexercised,
        routeCategory: "jsonrpc-websocket-session-interrupt",
        reasonCode: "protocol.cancel-advertised"
      ),
      approval: HermesAgentProtocolCapability(
        status: .supportedUnexercised,
        routeCategory: "jsonrpc-websocket-approval-respond",
        reasonCode: "protocol.approval-supported-no-harmless-trigger"
      ),
      authenticationRequired: authenticationState == .requiredAvailable,
      authenticationCategory: authenticationState == .requiredAvailable ? "loopback_token" : "none",
      ephemeralCredentialIsolated: authenticationState == .requiredAvailable,
      authenticationState: authenticationState,
      streamingModesAdvertised: ["websocket-jsonrpc-events"],
      metadataSource: "local-production-client-contract"
    )
  }

  private static func writeEvidence(
    outputPath: String,
    authenticationMode: String,
    identityCaptured: Bool,
    initialState: String,
    cancelState: String,
    reconnectStatusObserved: Bool,
    durationMilliseconds: Int
  ) throws {
    let object: [String: Any] = [
      "transport": "websocket-jsonrpc",
      "transportFamily": "websocket-jsonrpc",
      "transportRouteCategory": "jsonrpc-websocket-session-create",
      "transportScheme": "ws",
      "webSocketSubprotocolCategory": "none",
      "webSocketOriginMode": "none",
      "handshakeAttempted": true,
      "handshakeHTTPStatus": "unknown",
      "handshakeUpgradeAccepted": true,
      "handshakeErrorCategory": "unknown",
      "handshakeDurationMilliseconds": durationMilliseconds,
      "transportDescriptorParity": true,
      "authenticationMode": authenticationMode,
      "connectionAttempted": true,
      "connectionStatus": "connected",
      "rpcMethodCategory": "session-create",
      "rpcResponseCategory": "success",
      "rpcErrorCode": "none",
      "reasonCode": "none",
      "identityCaptured": identityCaptured,
      "identitySyntaxCategory": identityCaptured ? "token-like" : "none",
      "initialState": initialState,
      "cancelState": cancelState,
      "reconnectStatusObserved": reconnectStatusObserved,
      "rawIdentityOmitted": true,
    ]
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
  }

  private static func reasonCode(for error: Error) -> String {
    if let protocolError = error as? HermesAgentProtocolError {
      return protocolError.reasonCode
    }
    if let clientError = error as? HermesProtocolClientError {
      switch clientError {
      case .requestTimedOut:
        return "websocket.timeout"
      case .webSocketClosed:
        return "websocket.upgrade-rejected"
      case .notReady, .notConnected:
        return "websocket.upgrade-rejected"
      case .malformedFrame, .malformedStatus:
        return "websocket.handshake-malformed"
      case .rpcError:
        return "protocol.rpc-error"
      case .unexpectedHTTPStatus(let status):
        return HermesAgentHandshakeDiagnostics.reasonCode(httpStatus: status, errorCategory: "http-status")
      case .invalidPort:
        return "websocket.handshake-malformed"
      case .transport(let message):
        let lower = message.lowercased()
        if lower.contains("connection refused") || lower.contains("could not connect") {
          return "transport.connection-refused"
        }
        if lower.contains("timed out") {
          return "websocket.timeout"
        }
        return "request.connection-failed"
      default:
        return "request.connection-failed"
      }
    }
    return "request.connection-failed"
  }

  private static func elapsedMilliseconds(since start: DispatchTime) -> Int {
    let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
    return Int(elapsed / 1_000_000)
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
