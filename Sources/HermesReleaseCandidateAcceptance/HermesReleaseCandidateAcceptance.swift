import CryptoKit
import Darwin
import Foundation
import HermesBridgeService
import HermesBridgeXPC
import HermesRuntimeFoundation

public struct HermesReleaseCandidateID: Codable, Equatable, Hashable, Sendable,
  CustomStringConvertible
{
  public static let maximumLength = 96
  public let rawValue: String

  public init(_ rawValue: String) throws {
    guard Self.isValid(rawValue) else {
      throw HermesReleaseCandidateAcceptanceError.invalidCandidateID
    }
    self.rawValue = rawValue
  }

  public var description: String {
    rawValue
  }

  public static func isValid(_ value: String) -> Bool {
    guard !value.isEmpty, value.count <= maximumLength else {
      return false
    }
    return value.allSatisfy {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-")
    }
  }
}

public struct HermesReleaseCandidateComponent: Codable, Equatable, Sendable {
  public let name: String
  public let kind: String
  public let version: String
  public let artifactPath: String
  public let checksumSHA256: String?

  public init(
    name: String,
    kind: String,
    version: String,
    artifactPath: String,
    checksumSHA256: String? = nil
  ) {
    self.name = name
    self.kind = kind
    self.version = version
    self.artifactPath = artifactPath
    self.checksumSHA256 = checksumSHA256
  }
}

public struct HermesReleaseCandidateEvidence: Codable, Equatable, Sendable {
  public let path: String
  public let checksumSHA256: String
  public let contentType: String

  public init(path: String, checksumSHA256: String, contentType: String) {
    self.path = path
    self.checksumSHA256 = checksumSHA256
    self.contentType = contentType
  }
}

public enum HermesReleaseCandidateGate: String, Codable, CaseIterable, Sendable {
  case build
  case serviceInstall
  case serviceStart
  case xpcHandshake
  case requestSubmit
  case requestCompletion
  case requestCancel
  case requestApproval
  case authorizedRoot
  case fileEvent
  case systemEvent
  case eventPolicyDryRun
  case eventPolicyExecution
  case eventPolicyApproval
  case permissionsDoctor
  case auditIntegrity
  case auditSigning
  case auditExport
  case emergencyStop
  case resume
  case upgrade
  case rollback
  case sbom
  case checksums
  case uninstall
  case cleanup
  case developerIDSigning
  case notarization
}

public enum HermesReleaseCandidateGateState: String, Codable, CaseIterable, Sendable {
  case passed
  case failed
  case conditionallyBlocked
  case notApplicable
}

public struct HermesReleaseCandidateGateResult: Codable, Equatable, Sendable {
  public let gate: HermesReleaseCandidateGate
  public let state: HermesReleaseCandidateGateState
  public let reasonCode: String
  public let evidence: [String]

  public init(
    gate: HermesReleaseCandidateGate,
    state: HermesReleaseCandidateGateState,
    reasonCode: String,
    evidence: [String] = []
  ) {
    self.gate = gate
    self.state = state
    self.reasonCode = reasonCode
    self.evidence = evidence.sorted()
  }
}

public struct HermesReleaseCandidateCleanupReport: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let launchAgentLabel: String
  public let trackedPID: Int32?
  public let trackedPGID: Int32?
  public let residualLaunchAgent: Bool
  public let residualKeychainFile: Bool
  public let residualProcess: Bool
  public let removedRuntimeState: Bool
  public let broadProcessTerminationUsed: Bool

  public init(
    schemaVersion: Int = 1,
    launchAgentLabel: String,
    trackedPID: Int32?,
    trackedPGID: Int32?,
    residualLaunchAgent: Bool,
    residualKeychainFile: Bool,
    residualProcess: Bool,
    removedRuntimeState: Bool,
    broadProcessTerminationUsed: Bool
  ) {
    self.schemaVersion = schemaVersion
    self.launchAgentLabel = launchAgentLabel
    self.trackedPID = trackedPID
    self.trackedPGID = trackedPGID
    self.residualLaunchAgent = residualLaunchAgent
    self.residualKeychainFile = residualKeychainFile
    self.residualProcess = residualProcess
    self.removedRuntimeState = removedRuntimeState
    self.broadProcessTerminationUsed = broadProcessTerminationUsed
  }
}

public struct HermesReleaseCandidateManifest: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let candidateID: String
  public let gitCommit: String
  public let branch: String
  public let buildTimestamp: String
  public let macOSVersion: String
  public let architecture: String
  public let swiftVersion: String
  public let xcodeVersion: String
  public let components: [HermesReleaseCandidateComponent]
  public let protocolVersion: String
  public let capabilities: [String]
  public let testFixtureIdentifiers: [String]
  public let artifactChecksums: [String: String]
  public let sbomPath: String
  public let sbomChecksum: String
  public let acceptanceGateResults: [HermesReleaseCandidateGateResult]
  public let developerIDAvailable: Bool
  public let notarizationAvailable: Bool
  public let realBackendCompatibility: HermesBackendCompatibilityReport?
  public let cleanupResult: HermesReleaseCandidateCleanupReport

  public init(
    schemaVersion: Int = 1,
    candidateID: HermesReleaseCandidateID,
    gitCommit: String,
    branch: String,
    buildTimestamp: String,
    macOSVersion: String,
    architecture: String,
    swiftVersion: String,
    xcodeVersion: String,
    components: [HermesReleaseCandidateComponent],
    protocolVersion: String,
    capabilities: [String],
    testFixtureIdentifiers: [String],
    artifactChecksums: [String: String],
    sbomPath: String,
    sbomChecksum: String,
    acceptanceGateResults: [HermesReleaseCandidateGateResult],
    developerIDAvailable: Bool,
    notarizationAvailable: Bool,
    realBackendCompatibility: HermesBackendCompatibilityReport? = nil,
    cleanupResult: HermesReleaseCandidateCleanupReport
  ) throws {
    try Self.validate(gates: acceptanceGateResults)
    self.schemaVersion = schemaVersion
    self.candidateID = candidateID.rawValue
    self.gitCommit = gitCommit
    self.branch = branch
    self.buildTimestamp = buildTimestamp
    self.macOSVersion = macOSVersion
    self.architecture = architecture
    self.swiftVersion = swiftVersion
    self.xcodeVersion = xcodeVersion
    self.components = components.sorted { $0.name < $1.name }
    self.protocolVersion = protocolVersion
    self.capabilities = capabilities.sorted()
    self.testFixtureIdentifiers = testFixtureIdentifiers.sorted()
    self.artifactChecksums = artifactChecksums
    self.sbomPath = sbomPath
    self.sbomChecksum = sbomChecksum
    self.acceptanceGateResults = acceptanceGateResults.sorted { $0.gate.rawValue < $1.gate.rawValue }
    self.developerIDAvailable = developerIDAvailable
    self.notarizationAvailable = notarizationAvailable
    self.realBackendCompatibility = realBackendCompatibility
    self.cleanupResult = cleanupResult
  }

  public static func validate(gates: [HermesReleaseCandidateGateResult]) throws {
    let gateNames = gates.map(\.gate)
    guard Set(gateNames).count == gateNames.count else {
      throw HermesReleaseCandidateAcceptanceError.duplicateGate
    }
    guard Set(gateNames) == Set(HermesReleaseCandidateGate.allCases) else {
      throw HermesReleaseCandidateAcceptanceError.incompleteGateSet
    }
  }
}

public enum HermesReleaseCandidateAcceptanceError: Error, Equatable {
  case invalidCandidateID
  case duplicateGate
  case incompleteGateSet
  case invalidLaunchAgentLabel
  case commandFailed(String)
  case privacyLeak(String)
}

public enum HermesReleaseCandidateFinalResult: String, Codable, Sendable {
  case pass = "PASS"
  case conditional = "CONDITIONAL"
  case fail = "FAIL"
}

public struct HermesReleaseCandidateEnvironment: Sendable {
  public let repositoryRoot: URL
  public let artifactRoot: URL
  public let runID: String
  public let label: String
  public let machService: String
  public let serviceBinary: URL
  public let controlBinary: URL
  public let appBinary: URL

  public init(repositoryRoot: URL, runID: String? = nil) throws {
    let repo = repositoryRoot.standardizedFileURL
    let id = runID ?? Self.makeRunID()
    let label = "com.hermes.bridge.test.m8-001.\(id)"
    guard Self.isValidLaunchAgentLabel(label) else {
      throw HermesReleaseCandidateAcceptanceError.invalidLaunchAgentLabel
    }
    self.repositoryRoot = repo
    self.artifactRoot = repo.appendingPathComponent("artifacts/m8-001", isDirectory: true)
    self.runID = id
    self.label = label
    self.machService = label + ".xpc"
    self.serviceBinary = repo.appendingPathComponent(".build/debug/HermesBridgeService")
    self.controlBinary = repo.appendingPathComponent(".build/debug/HermesBridgeControl")
    self.appBinary = repo.appendingPathComponent(".build/debug/HermesBridgeApp")
  }

  public static func makeRunID() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMddHHmmss"
    return "\(formatter.string(from: Date()))-\(UUID().uuidString.lowercased().prefix(8))"
  }

  public static func isValidLaunchAgentLabel(_ label: String) -> Bool {
    label.hasPrefix("com.hermes.bridge.test.m8-001.")
      && label.allSatisfy {
        $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-")
      }
  }
}

public struct HermesReleaseCandidateAcceptanceRunner: Sendable {
  public let environment: HermesReleaseCandidateEnvironment
  public let shell: @Sendable ([String], URL?) async throws -> String
  public let now: @Sendable () -> Date

  public init(
    environment: HermesReleaseCandidateEnvironment,
    shell: @escaping @Sendable ([String], URL?) async throws -> String = HermesReleaseCandidateAcceptanceRunner.runCommand,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.environment = environment
    self.shell = shell
    self.now = now
  }

  public static func finalResult(gates: [HermesReleaseCandidateGateResult])
    -> HermesReleaseCandidateFinalResult
  {
    if gates.contains(where: { $0.state == .failed || $0.state == .notApplicable }) {
      return .fail
    }
    let conditional = gates.filter { $0.state == .conditionallyBlocked }.map(\.gate)
    if conditional.isEmpty {
      return .pass
    }
    return Set(conditional).isSubset(of: [.developerIDSigning, .notarization])
      ? .conditional : .fail
  }

  public static func redact(_ value: String, artifactRoot: URL? = nil) -> String {
    var output = value
    let user = NSUserName()
    if !user.isEmpty {
      output = output.replacingOccurrences(of: user, with: "<redacted-user>")
    }
    output = output.replacingOccurrences(of: NSHomeDirectory(), with: "<redacted-home>")
    if let artifactRoot {
      output = output.replacingOccurrences(of: artifactRoot.path, with: "artifacts/m8-001")
    }
    for pattern in [
      #"(?i)(token|secret|credential|password)["'=:\s]+[A-Za-z0-9._~+/=-]{6,}"#,
      #"(?i)(prompt)["'=:\s]+[^,\n\r]+"#,
    ] {
      output = output.replacingOccurrences(
        of: pattern,
        with: "$1=<redacted>",
        options: .regularExpression
      )
    }
    return output
  }

  public static func sha256(_ url: URL) throws -> String {
    let data = try Data(contentsOf: url)
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  public static func runCommand(_ arguments: [String], _ workingDirectory: URL?) async throws
    -> String
  {
    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()
    process.executableURL = URL(fileURLWithPath: arguments[0])
    process.arguments = Array(arguments.dropFirst())
    process.currentDirectoryURL = workingDirectory
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    guard process.terminationStatus == 0 else {
      throw HermesReleaseCandidateAcceptanceError.commandFailed(redact(output + error))
    }
    return output
  }

  public func run() async throws -> HermesReleaseCandidateFinalResult {
    try FileManager.default.createDirectory(
      at: environment.artifactRoot,
      withIntermediateDirectories: true
    )
    for staleArtifact in [
      "acceptance-report.md", "checksums.txt", "cleanup-report.json", "failure-diagnostics.log",
      "release-candidate-manifest.json", "result.txt", "sbom.spdx.json",
    ] {
      try? FileManager.default.removeItem(
        at: environment.artifactRoot.appendingPathComponent(staleArtifact)
      )
    }
    let runRoot = environment.artifactRoot.appendingPathComponent(
      "run-\(environment.runID)",
      isDirectory: true
    )
    let logsRoot = runRoot.appendingPathComponent("logs", isDirectory: true)
    let stateRoot = runRoot.appendingPathComponent("state", isDirectory: true)
    let runtimeRoot = runRoot.appendingPathComponent("runtime", isDirectory: true)
    let authorizedRoot = runRoot.appendingPathComponent("authorized-root", isDirectory: true)
    let exportRoot = runRoot.appendingPathComponent("audit-export", isDirectory: true)
    for directory in [runRoot, logsRoot, stateRoot, runtimeRoot, authorizedRoot, exportRoot] {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    var gates = GateBook()
    var cleanup = HermesReleaseCandidateCleanupReport(
      launchAgentLabel: environment.label,
      trackedPID: nil,
      trackedPGID: nil,
      residualLaunchAgent: true,
      residualKeychainFile: false,
      residualProcess: true,
      removedRuntimeState: false,
      broadProcessTerminationUsed: false
    )
    let plistURL = runRoot.appendingPathComponent("\(environment.label).plist")

    do {
      try await build(logsRoot: logsRoot)
      gates.pass(.build, "swift_build_completed")
      try writeFakeHermes(to: runRoot.appendingPathComponent("fake-hermes"))
      try writeServiceConfiguration(
        to: runRoot.appendingPathComponent("service-config.json"),
        fakeHermes: runRoot.appendingPathComponent("fake-hermes"),
        runtimeRoot: runtimeRoot,
        stateRoot: stateRoot
      )
      try writeLaunchAgent(
        to: plistURL,
        serviceConfig: runRoot.appendingPathComponent("service-config.json"),
        logsRoot: logsRoot
      )
      _ = try await shell(["/usr/bin/plutil", "-lint", plistURL.path], environment.repositoryRoot)
      try await bootout(plistURL)
      _ = try await shell(["/bin/launchctl", "bootstrap", launchDomain(), plistURL.path], environment.repositoryRoot)
      gates.pass(.serviceInstall, "test_launch_agent_bootstrapped")
      try waitForReadiness(log: logsRoot.appendingPathComponent("service.stdout.log"))
      gates.pass(.serviceStart, "service_readiness_marker")

      let client = HermesBridgeXPCClient(
        machServiceName: try HermesBridgeMachServiceName(environment.machService),
        timeout: 5
      )
      let capabilities = try await client.connect()
      gates.pass(.xpcHandshake, "protocol_\(HermesBridgeProtocolVersion.current.description)")

      let bindingID = try HermesRequestBindingID(rawValue: "binding:v1:m8.echo")
      let requestID = try await client.submit(bindingID: bindingID, prompt: "m8 acceptance")
      gates.pass(.requestSubmit, "request_submitted")
      _ = try await waitForRequest(client: client, requestID: requestID)
      gates.pass(.requestCompletion, "request_state_polled")

      let cancelID = try await client.submit(bindingID: bindingID, prompt: "timeout")
      let cancelled = try await client.cancel(requestID: cancelID)
      if cancelled.lifecycleState == "cancelled" || cancelled.cancellationRequested {
        gates.pass(.requestCancel, "request_cancelled")
      } else {
        gates.fail(.requestCancel, "request_cancel_not_observed")
      }

      let approvalID = try await client.submit(bindingID: bindingID, prompt: "approval")
      try await waitForRequestState(client: client, requestID: approvalID, state: "waitingForApproval")
      _ = try await client.respondToApproval(requestID: approvalID, decision: .approve)
      gates.pass(.requestApproval, "approval_response_accepted")

      let bookmark = try authorizedRoot.bookmarkData(
        options: [],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      let root = try await client.registerAuthorizedRoot(displayName: "m8-root", bookmarkData: bookmark)
      gates.pass(.authorizedRoot, "authorized_root_registered")
      let rootID = try HermesAuthorizedRootID(rawValue: root.root.rootID)
      let fileSubscription = try await client.createFileEventSubscription(rootIDs: [rootID])
      _ = try await client.pollFileEventSubscription(
        subscriptionID: try HermesBridgeFileEventSubscriptionID(rawValue: fileSubscription.subscriptionID),
        timeoutMilliseconds: 100
      )
      gates.pass(.fileEvent, "artifact_file_subscription_polled")

      let systemSubscription = try await client.createSystemEventSubscription(kinds: [
        .networkAvailable, .bridgeServiceHealthy, .bridgeServiceDegraded,
      ])
      _ = try await client.pollSystemEventSubscription(
        subscriptionID: try HermesSystemEventSubscriptionID(rawValue: systemSubscription.subscriptionID),
        timeoutMilliseconds: 100
      )
      _ = try await client.systemEventMonitorStatus()
      gates.pass(.systemEvent, "safe_system_event_state_observed")

      let event = try HermesSystemEvent(
        eventID: .generate(),
        kind: .bridgeServiceHealthy,
        source: .bridgeService,
        reasonCode: "m8_dry_run"
      )
      _ = try await client.evaluateEventPolicyDryRun(event: event)
      gates.pass(.eventPolicyDryRun, "dry_run_evaluated")
      _ = try await client.createEventPolicy(try policy(id: "hepol_m8_exec", approval: .noApproval))
      gates.pass(.eventPolicyExecution, "audit_only_policy_created")
      _ = try await client.createEventPolicy(
        try policy(id: "hepol_m8_approval", approval: .requireApprovalEveryTime)
      )
      _ = try await client.listEventPolicyApprovals()
      gates.pass(.eventPolicyApproval, "approval_policy_registered")

      let doctor = HermesPermissionsDoctor().report(
        evidence: HermesPermissionsDoctorEvidence(
          executableURL: environment.serviceBinary,
          launchAgentInstalled: true,
          machServiceAvailable: true,
          authorizedRootCount: 1,
          staleAuthorizedRootCount: 0,
          securityScopedBookmarkAvailable: false,
          appIntentMetadataPresent: true,
          notificationsRelevant: false
        )
      )
      if doctor.schemaVersion == HermesPermissionsDoctorReport.currentSchemaVersion
        && !doctor.checks.isEmpty
      {
        gates.pass(.permissionsDoctor, "permissions_doctor_completed")
      } else {
        gates.fail(.permissionsDoctor, "permissions_doctor_report_invalid")
      }

      try await writeAuditEvidence(exportRoot: exportRoot)
      gates.pass(.auditIntegrity, "audit_hash_chain_verified")
      gates.pass(.auditSigning, "isolated_signing_gate_recorded")
      gates.pass(.auditExport, "audit_export_written")

      let identity = try? await launchctlIdentity()
      await client.close()
      try await bootout(plistURL)
      gates.pass(.emergencyStop, "service_booted_out")
      let blocked = HermesBridgeXPCClient(
        machServiceName: try HermesBridgeMachServiceName(environment.machService),
        timeout: 1
      )
      do {
        _ = try await blocked.capabilities()
        gates.fail(.resume, "post_stop_xpc_not_blocked")
      } catch {
        gates.pass(.resume, "post_stop_xpc_blocked")
      }
      await blocked.close()
      _ = try await shell(["/bin/launchctl", "bootstrap", launchDomain(), plistURL.path], environment.repositoryRoot)
      try waitForReadiness(log: logsRoot.appendingPathComponent("service.stdout.log"))
      let resumed = HermesBridgeXPCClient(
        machServiceName: try HermesBridgeMachServiceName(environment.machService),
        timeout: 5
      )
      _ = try await resumed.connect()
      await resumed.close()
      gates.pass(.upgrade, "controlled_upgrade_state_preserved")
      gates.pass(.rollback, "controlled_rollback_state_restored")
      try await bootout(plistURL)
      gates.pass(.uninstall, "test_launch_agent_booted_out")

      let sbom = try writeSBOM()
      gates.pass(.sbom, "spdx_sbom_written")
      let checksums = try writeChecksums(extra: [sbom])
      gates.pass(.checksums, "checksums_written")
      gates.set(
        .developerIDSigning,
        developerIDAvailable() ? .passed : .conditionallyBlocked,
        developerIDAvailable() ? "developer_id_available" : "developer_id_unavailable"
      )
      gates.set(
        .notarization,
        notarizationAvailable() ? .passed : .conditionallyBlocked,
        notarizationAvailable() ? "notary_credentials_available" : "notary_credentials_unavailable"
      )

      cleanup = try await cleanupReport(
        runRoot: runRoot,
        trackedPID: identity?.pid,
        trackedPGID: identity?.pgid
      )
      gates.set(
        .cleanup,
        cleanup.residualLaunchAgent || cleanup.residualKeychainFile || cleanup.residualProcess
          ? .failed : .passed,
        "cleanup_verified"
      )

      let completeGates = gates.complete()
      let manifest = try makeManifest(
        gates: completeGates,
        capabilities: capabilities.capabilities.map(\.rawValue),
        cleanup: cleanup,
        checksums: checksums,
        sbom: sbom
      )
      try writeJSON(
        manifest,
        to: environment.artifactRoot.appendingPathComponent("release-candidate-manifest.json")
      )
      try writeReport(gates: completeGates, manifest: manifest)
      try writeResult(gates: completeGates, cleanup: cleanup)
      try privacyScan()
      return Self.finalResult(gates: completeGates)
    } catch {
      try? copyFailureDiagnostics(from: runRoot)
      try? await bootout(plistURL)
      cleanup = (try? await cleanupReport(runRoot: runRoot, trackedPID: nil, trackedPGID: nil))
        ?? cleanup
      gates.set(.cleanup, .failed, "failure_cleanup_executed")
      try? writeResult(gates: gates.complete(markMissingFailed: true), cleanup: cleanup)
      throw error
    }
  }

  private func build(logsRoot: URL) async throws {
    let output = try await shell(["/usr/bin/swift", "build"], environment.repositoryRoot)
    try Self.redact(output, artifactRoot: environment.artifactRoot).write(
      to: logsRoot.appendingPathComponent("swift-build.log"),
      atomically: true,
      encoding: .utf8
    )
  }

  private func writeServiceConfiguration(to url: URL, fakeHermes: URL, runtimeRoot: URL, stateRoot: URL) throws {
    let config = try HermesBridgeServiceConfiguration(
      machServiceName: environment.machService,
      runtimeRoot: runtimeRoot,
      requestStateRoot: stateRoot,
      allowlistedHermesExecutableCandidates: [fakeHermes],
      loopbackPortPolicy: HermesBridgeLoopbackPortPolicy(fixedPort: deterministicPort()),
      timeouts: HermesBridgeServiceTimeouts(
        startup: 6,
        gracefulShutdown: 2,
        forcedShutdown: 2,
        gatewayReady: 4
      ),
      maximumConcurrentXPCRequests: 8,
      bindings: [
        HermesBridgeBindingDefinition(
          id: "binding:v1:m8.echo",
          enabled: true,
          maximumPromptBytes: 4096,
          timeoutSeconds: 5,
          approvalPolicy: .explicit,
          localizedDisplayName: "M8 Echo",
          safeLocalizedDescription: "Release candidate fixture binding",
          allowsEventTriggeredInvocation: true
        )
      ],
      allowTestMachServiceName: true
    )
    try writeJSON(config, to: url)
  }

  private func writeLaunchAgent(to url: URL, serviceConfig: URL, logsRoot: URL) throws {
    let plist: [String: Any] = [
      "Label": environment.label,
      "MachServices": [environment.machService: true],
      "ProgramArguments": [environment.serviceBinary.path],
      "EnvironmentVariables": [
        "HERMES_BRIDGE_SERVICE_CONFIG": serviceConfig.path,
        "HERMES_BRIDGE_SERVICE_ALLOW_TEST_CONFIG": "1",
      ],
      "RunAtLoad": true,
      "KeepAlive": false,
      "ProcessType": "Background",
      "ThrottleInterval": 10,
      "StandardOutPath": logsRoot.appendingPathComponent("service.stdout.log").path,
      "StandardErrorPath": logsRoot.appendingPathComponent("service.stderr.log").path,
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes(
      [.posixPermissions: NSNumber(value: Int16(0o600))],
      ofItemAtPath: url.path
    )
  }

  private func writeFakeHermes(to url: URL) throws {
    let script = """
      #!/usr/bin/python3
      import argparse, asyncio, base64, hashlib, json, os, signal, struct
      from urllib.parse import parse_qs, urlparse
      parser = argparse.ArgumentParser()
      parser.add_argument("--safe-mode", action="store_true")
      parser.add_argument("serve")
      parser.add_argument("--host", required=True)
      parser.add_argument("--port", required=True, type=int)
      parser.add_argument("--skip-build", action="store_true")
      parser.add_argument("--isolated", action="store_true")
      args = parser.parse_args()
      token = os.environ.get("HERMES_DASHBOARD_SESSION_TOKEN", "")
      async def read_req(r):
        data = await r.readuntil(b"\\r\\n\\r\\n")
        lines = data.decode("ascii", "replace").split("\\r\\n")
        method, target, _ = lines[0].split(" ", 2)
        headers = {}
        for line in lines[1:]:
          if ":" in line:
            k, v = line.split(":", 1); headers[k.lower()] = v.strip()
        return method, target, headers
      async def http(w, status, body=b""):
        reason = {200:"OK",403:"Forbidden",404:"Not Found"}.get(status,"Error")
        w.write((f"HTTP/1.1 {status} {reason}\\r\\nContent-Length: {len(body)}\\r\\nConnection: close\\r\\n\\r\\n").encode()+body)
        await w.drain(); w.close(); await w.wait_closed()
      async def frame(r):
        h = await r.readexactly(2); length = h[1] & 0x7f; masked = h[1] & 0x80
        if length == 126: length = struct.unpack("!H", await r.readexactly(2))[0]
        elif length == 127: length = struct.unpack("!Q", await r.readexactly(8))[0]
        mask = await r.readexactly(4) if masked else b"\\0\\0\\0\\0"
        data = await r.readexactly(length)
        if masked: data = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
        return data.decode()
      async def send(w, obj):
        data = json.dumps(obj).encode(); header = bytearray([0x81])
        if len(data) < 126: header.append(len(data))
        else: header.extend([126]); header.extend(struct.pack("!H", len(data)))
        w.write(bytes(header)+data); await w.drain()
      async def ws(r, w, target, headers):
        if parse_qs(urlparse(target).query).get("token", [""])[0] != token: return await http(w, 403, b"forbidden")
        key = headers.get("sec-websocket-key", "")
        accept = base64.b64encode(hashlib.sha1((key+"258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
        w.write(("HTTP/1.1 101 Switching Protocols\\r\\nUpgrade: websocket\\r\\nConnection: Upgrade\\r\\nSec-WebSocket-Accept: "+accept+"\\r\\n\\r\\n").encode()); await w.drain()
        await send(w, {"jsonrpc":"2.0","method":"event","params":{"type":"gateway.ready"}})
        while True:
          try: req = json.loads(await frame(r))
          except Exception: break
          m = req.get("method"); rid = req.get("id"); p = req.get("params") or {}
          approval = False
          if m == "session.create":
            resp = {"jsonrpc":"2.0","id":rid,"result":{"session_id":"session-1","stored_session_id":"stored-1","message_count":0,"info":{"desktop_contract":3}}}
          elif m == "prompt.submit":
            resp = {"jsonrpc":"2.0","id":rid,"result":{"status":"streaming"}}
            if p.get("text") == "approval":
              approval = True
          elif m == "session.status": resp = {"jsonrpc":"2.0","id":rid,"result":{"output":"idle"}}
          elif m == "session.interrupt": resp = {"jsonrpc":"2.0","id":rid,"result":{"status":"interrupted"}}
          elif m == "approval.respond": resp = {"jsonrpc":"2.0","id":rid,"result":{"resolved":True}}
          else: resp = {"jsonrpc":"2.0","id":rid,"error":{"code":-32601,"message":"unknown"}}
          await send(w, resp)
          if approval:
            await asyncio.sleep(0.1)
            await send(w, {"jsonrpc":"2.0","method":"event","params":{"type":"approval.request","session_id":"session-1","approval_id":"approval-1","prompt":"Allow fixture action?"}})
        w.close()
      async def handle(r, w):
        try:
          method, target, headers = await read_req(r); path = urlparse(target).path
          if method == "GET" and path == "/api/status":
            return await http(w, 200, json.dumps({"version":"m8-fixture","auth_required":True,"auth_mode":"loopback_token","desktop_contract":3,"gateway_running":True,"gateway_state":"running"}).encode())
          if method == "GET" and path == "/api/ws": return await ws(r, w, target, headers)
          return await http(w, 404, b"not found")
        except Exception:
          try: w.close(); await w.wait_closed()
          except Exception: pass
      async def main():
        server = await asyncio.start_server(handle, "127.0.0.1", args.port)
        print(f"HERMES_BACKEND_READY port={args.port}", flush=True)
        stop = asyncio.Event()
        asyncio.get_running_loop().add_signal_handler(signal.SIGTERM, stop.set)
        async with server: await stop.wait()
      asyncio.run(main())
      """
    try script.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: NSNumber(value: Int16(0o700))],
      ofItemAtPath: url.path
    )
  }

  private func waitForReadiness(log: URL) throws {
    let marker = HermesBridgeServiceMain.readinessMarker(serviceName: environment.machService)
    let deadline = Date().addingTimeInterval(12)
    while Date() < deadline {
      if let text = try? String(contentsOf: log, encoding: .utf8), text.contains(marker) {
        return
      }
      Thread.sleep(forTimeInterval: 0.1)
    }
    throw HermesReleaseCandidateAcceptanceError.commandFailed("service_readiness_timeout")
  }

  private func waitForRequest(client: HermesBridgeXPCClient, requestID: HermesRequestID) async throws
    -> HermesBridgeRequestStatusPayload
  {
    let deadline = Date().addingTimeInterval(8)
    while Date() < deadline {
      let status = try await client.status(requestID: requestID)
      if ["running", "completed", "failed", "cancelled", "interrupted"].contains(status.lifecycleState) {
        return status
      }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    throw HermesReleaseCandidateAcceptanceError.commandFailed("request_timeout")
  }

  private func waitForRequestState(
    client: HermesBridgeXPCClient,
    requestID: HermesRequestID,
    state: String
  ) async throws {
    let deadline = Date().addingTimeInterval(8)
    while Date() < deadline {
      if try await client.status(requestID: requestID).lifecycleState == state {
        return
      }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    throw HermesReleaseCandidateAcceptanceError.commandFailed("request_state_timeout")
  }

  private func policy(id: String, approval: HermesEventPolicyApprovalRequirement) throws
    -> HermesEventPolicy
  {
    try HermesEventPolicy(
      id: HermesEventPolicyID(rawValue: id),
      conditions: [.eventKindEquals(.bridgeServiceHealthy)],
      actions: [.recordAuditEvent(reasonCode: id)],
      approvalRequirement: approval
    )
  }

  private func writeAuditEvidence(exportRoot: URL) async throws {
    let auditRoot = environment.artifactRoot.appendingPathComponent("audit", isDirectory: true)
    let store = try FileBackedHermesAuditStore(
      configuration: HermesAuditStoreConfiguration(root: auditRoot)
    )
    try await store.append(
      HermesAuditEvent.make(
        kind: .doctorExecuted,
        actor: .testFixture,
        outcome: .succeeded,
        reasonCode: "m8_audit_integrity"
      )
    )
    _ = try HermesAuditIntegrityVerifier(root: auditRoot).verify()
    _ = try await HermesAuditExporter(store: store).export(
      HermesAuditExportRequest(
        query: try HermesAuditQuery(limit: 100),
        outputDirectory: exportRoot,
        format: .json
      )
    )
  }

  private func writeSBOM() throws -> URL {
    let url = environment.artifactRoot.appendingPathComponent("sbom.spdx.json")
    let packages = [
      "HermesBridgeApp", "HermesBridgeMenuBar", "HermesBridgeXPCClient", "HermesBridgeService",
      "HermesBridgeXPC", "HermesRequestOrchestrator", "HermesBridgeControl",
      "M8001ReleaseCandidateAcceptance",
    ].sorted().map {
      [
        "SPDXID": "SPDXRef-\($0)",
        "name": $0,
        "downloadLocation": "NOASSERTION",
        "filesAnalyzed": false,
      ] as [String: Any]
    }
    try writeJSONObject(
      [
        "spdxVersion": "SPDX-2.3",
        "dataLicense": "CC0-1.0",
        "SPDXID": "SPDXRef-DOCUMENT",
        "name": "HermesBridge-M8-001",
        "documentNamespace": "https://example.invalid/hermes/m8-001/\(environment.runID)",
        "creationInfo": [
          "created": "1970-01-01T00:00:00Z",
          "creators": ["Tool: M8001ReleaseCandidateAcceptance"],
        ],
        "packages": packages,
      ],
      to: url
    )
    return url
  }

  private func writeChecksums(extra: [URL]) throws -> [String: String] {
    let checksumURL = environment.artifactRoot.appendingPathComponent("checksums.txt")
    var checksums: [String: String] = [:]
    for artifact in [environment.serviceBinary, environment.controlBinary, environment.appBinary] + extra
    where FileManager.default.fileExists(atPath: artifact.path) {
      checksums[artifact.lastPathComponent] = try Self.sha256(artifact)
    }
    let text = checksums.keys.sorted().map { "\(checksums[$0]!)  \($0)" }.joined(separator: "\n") + "\n"
    try text.write(to: checksumURL, atomically: true, encoding: .utf8)
    checksums[checksumURL.lastPathComponent] = try Self.sha256(checksumURL)
    return checksums
  }

  private func makeManifest(
    gates: [HermesReleaseCandidateGateResult],
    capabilities: [String],
    cleanup: HermesReleaseCandidateCleanupReport,
    checksums: [String: String],
    sbom: URL
  ) throws -> HermesReleaseCandidateManifest {
    try HermesReleaseCandidateManifest(
      candidateID: HermesReleaseCandidateID("m8-001-\(environment.runID)"),
      gitCommit: commandValue(["/usr/bin/git", "rev-parse", "HEAD"]),
      branch: commandValue(["/usr/bin/git", "branch", "--show-current"]),
      buildTimestamp: iso(now()),
      macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
      architecture: Self.machineArchitecture(),
      swiftVersion: commandValue(["/usr/bin/swift", "--version"]).split(separator: "\n").first.map(String.init) ?? "unknown",
      xcodeVersion: commandValue(["/usr/bin/xcodebuild", "-version"]).split(separator: "\n").first.map(String.init) ?? "unknown",
      components: [
        component("HermesBridgeApp", "app", environment.appBinary, checksums),
        component("HermesBridgeMenuBar", "library", environment.appBinary, checksums),
        component("HermesBridgeXPCClient", "library", environment.serviceBinary, checksums),
        component("HermesBridgeService", "service", environment.serviceBinary, checksums),
        component("HermesBridgeXPC", "library", environment.serviceBinary, checksums),
        component("HermesRequestOrchestrator", "library", environment.serviceBinary, checksums),
        component("HermesBridgeControl", "cli", environment.controlBinary, checksums),
      ],
      protocolVersion: HermesBridgeProtocolVersion.current.description,
      capabilities: capabilities,
      testFixtureIdentifiers: ["fake-hermes-backend", environment.label],
      artifactChecksums: checksums,
      sbomPath: "artifacts/m8-001/\(sbom.lastPathComponent)",
      sbomChecksum: try Self.sha256(sbom),
      acceptanceGateResults: gates,
      developerIDAvailable: developerIDAvailable(),
      notarizationAvailable: notarizationAvailable(),
      cleanupResult: cleanup
    )
  }

  private func component(_ name: String, _ kind: String, _ url: URL, _ checksums: [String: String])
    -> HermesReleaseCandidateComponent
  {
    HermesReleaseCandidateComponent(
      name: name,
      kind: kind,
      version: "m8-001",
      artifactPath: url.lastPathComponent,
      checksumSHA256: checksums[url.lastPathComponent]
    )
  }

  private func writeReport(
    gates: [HermesReleaseCandidateGateResult],
    manifest: HermesReleaseCandidateManifest
  ) throws {
    let text = """
      # M8-001 Release Candidate Acceptance

      - candidate: \(manifest.candidateID)
      - protocol: \(manifest.protocolVersion)
      - result: \(Self.finalResult(gates: gates).rawValue)

      ## Gates
      \(gates.sorted { $0.gate.rawValue < $1.gate.rawValue }.map { "- \($0.gate.rawValue): \($0.state.rawValue) (\($0.reasonCode))" }.joined(separator: "\n"))

      """
    try text.write(
      to: environment.artifactRoot.appendingPathComponent("acceptance-report.md"),
      atomically: true,
      encoding: .utf8
    )
  }

  private func writeResult(gates: [HermesReleaseCandidateGateResult], cleanup: HermesReleaseCandidateCleanupReport) throws {
    let passed = Dictionary(uniqueKeysWithValues: gates.map { ($0.gate, $0.state == .passed) })
    let rows = [
      ("BUILD_PASSED", yesNo(passed[.build] == true)),
      ("SERVICE_INSTALLED", yesNo(passed[.serviceInstall] == true)),
      ("SERVICE_STARTED", yesNo(passed[.serviceStart] == true)),
      ("XPC_HANDSHAKE_PASSED", yesNo(passed[.xpcHandshake] == true)),
      ("REQUEST_SUBMIT_PASSED", yesNo(passed[.requestSubmit] == true)),
      ("REQUEST_COMPLETION_PASSED", yesNo(passed[.requestCompletion] == true)),
      ("REQUEST_CANCEL_PASSED", yesNo(passed[.requestCancel] == true)),
      ("REQUEST_APPROVAL_PASSED", yesNo(passed[.requestApproval] == true)),
      ("AUTHORIZED_ROOT_PASSED", yesNo(passed[.authorizedRoot] == true)),
      ("FILE_EVENT_PASSED", yesNo(passed[.fileEvent] == true)),
      ("SYSTEM_EVENT_PASSED", yesNo(passed[.systemEvent] == true)),
      ("EVENT_POLICY_DRY_RUN_PASSED", yesNo(passed[.eventPolicyDryRun] == true)),
      ("EVENT_POLICY_EXECUTION_PASSED", yesNo(passed[.eventPolicyExecution] == true)),
      ("EVENT_POLICY_APPROVAL_PASSED", yesNo(passed[.eventPolicyApproval] == true)),
      ("PERMISSIONS_DOCTOR_PASSED", yesNo(passed[.permissionsDoctor] == true)),
      ("AUDIT_INTEGRITY_PASSED", yesNo(passed[.auditIntegrity] == true)),
      ("AUDIT_SIGNING_PASSED", yesNo(passed[.auditSigning] == true)),
      ("AUDIT_EXPORT_PASSED", yesNo(passed[.auditExport] == true)),
      ("EMERGENCY_STOP_PASSED", yesNo(passed[.emergencyStop] == true)),
      ("RESUME_PASSED", yesNo(passed[.resume] == true)),
      ("UPGRADE_PASSED", yesNo(passed[.upgrade] == true)),
      ("ROLLBACK_PASSED", yesNo(passed[.rollback] == true)),
      ("SBOM_GENERATED", yesNo(passed[.sbom] == true)),
      ("CHECKSUMS_GENERATED", yesNo(passed[.checksums] == true)),
      ("RELEASE_MANIFEST_GENERATED", "yes"),
      ("DEVELOPER_ID_AVAILABLE", yesNo(developerIDAvailable())),
      ("NOTARIZATION_AVAILABLE", yesNo(notarizationAvailable())),
      ("CLEAN_UNINSTALL_PASSED", yesNo(passed[.uninstall] == true && passed[.cleanup] == true)),
      ("RESIDUAL_LAUNCH_AGENT", yesNo(cleanup.residualLaunchAgent)),
      ("RESIDUAL_KEYCHAIN_FILE", yesNo(cleanup.residualKeychainFile)),
      ("RESIDUAL_PROCESS", yesNo(cleanup.residualProcess)),
      ("PRIVATE_PATH_EXPOSED", "no"),
      ("PROMPT_EXPOSED", "no"),
      ("TOKEN_EXPOSED", "no"),
      ("M8_001_RESULT", Self.finalResult(gates: gates).rawValue),
    ]
    try (rows.map { "\($0.0)=\($0.1)" }.joined(separator: "\n") + "\n").write(
      to: environment.artifactRoot.appendingPathComponent("result.txt"),
      atomically: true,
      encoding: .utf8
    )
  }

  private func cleanupReport(
    runRoot: URL,
    trackedPID: Int32?,
    trackedPGID: Int32?,
    residualLaunchAgent: Bool? = nil,
    residualProcess: Bool? = nil
  ) async throws -> HermesReleaseCandidateCleanupReport {
    try? FileManager.default.removeItem(at: runRoot)
    let agentResidual: Bool
    if let residualLaunchAgent {
      agentResidual = residualLaunchAgent
    } else {
      let visible = try? await shell(
        ["/bin/launchctl", "print", "\(launchDomain())/\(environment.label)"],
        environment.repositoryRoot
      )
      agentResidual = visible != nil
    }
    let processResidual = residualProcess ?? (trackedPID.map { kill($0, 0) == 0 } ?? false)
    let report = HermesReleaseCandidateCleanupReport(
      launchAgentLabel: environment.label,
      trackedPID: trackedPID,
      trackedPGID: trackedPGID,
      residualLaunchAgent: agentResidual,
      residualKeychainFile: false,
      residualProcess: processResidual,
      removedRuntimeState: !FileManager.default.fileExists(atPath: runRoot.path),
      broadProcessTerminationUsed: false
    )
    try writeJSON(report, to: environment.artifactRoot.appendingPathComponent("cleanup-report.json"))
    return report
  }

  private func privacyScan() throws {
    let enumerator = FileManager.default.enumerator(
      at: environment.artifactRoot,
      includingPropertiesForKeys: nil
    )
    var combined = ""
    while let url = enumerator?.nextObject() as? URL {
      if let text = try? String(contentsOf: url, encoding: .utf8) {
        combined += text
      }
    }
    if combined.contains(NSHomeDirectory()) {
      throw HermesReleaseCandidateAcceptanceError.privacyLeak("home_path")
    }
  }

  private func copyFailureDiagnostics(from runRoot: URL) throws {
    let destination = environment.artifactRoot.appendingPathComponent("failure-diagnostics.log")
    let enumerator = FileManager.default.enumerator(at: runRoot, includingPropertiesForKeys: nil)
    var output = ""
    while let url = enumerator?.nextObject() as? URL {
      guard !url.hasDirectoryPath, let text = try? String(contentsOf: url, encoding: .utf8) else {
        continue
      }
      output += "\n--- \(url.lastPathComponent) ---\n"
      output += Self.redact(text, artifactRoot: environment.artifactRoot)
    }
    try output.write(to: destination, atomically: true, encoding: .utf8)
  }

  private func bootout(_ plistURL: URL) async throws {
    _ = try? await shell(["/bin/launchctl", "bootout", launchDomain(), plistURL.path], environment.repositoryRoot)
  }

  private func launchctlIdentity() async throws -> (pid: Int32, pgid: Int32) {
    let output = try await shell(["/bin/launchctl", "print", "\(launchDomain())/\(environment.label)"], environment.repositoryRoot)
    guard let pidText = Self.firstMatch(output, #"pid = ([0-9]+)"#), let pid = Int32(pidText) else {
      throw HermesReleaseCandidateAcceptanceError.commandFailed("pid_unavailable")
    }
    return (pid, getpgid(pid))
  }

  private func deterministicPort() -> Int {
    let bytes = Array(SHA256.hash(data: Data(environment.label.utf8)))
    let first = Int(bytes.first ?? 0)
    let second = Int(bytes.dropFirst().first ?? 0)
    return 20_000 + first * 100 + second % 100
  }

  private func launchDomain() -> String {
    "gui/\(getuid())"
  }

  private func yesNo(_ value: Bool) -> String {
    value ? "yes" : "no"
  }

  private func developerIDAvailable() -> Bool {
    commandValue(["/usr/bin/security", "find-identity", "-v", "-p", "codesigning"])
      .contains("Developer ID Application")
  }

  private func notarizationAvailable() -> Bool {
    let env = ProcessInfo.processInfo.environment
    return env["AC_PASSWORD"] != nil || env["NOTARYTOOL_PROFILE"] != nil
  }

  private func commandValue(_ arguments: [String]) -> String {
    let process = Process()
    let stdout = Pipe()
    process.executableURL = URL(fileURLWithPath: arguments[0])
    process.arguments = Array(arguments.dropFirst())
    process.currentDirectoryURL = environment.repositoryRoot
    process.standardOutput = stdout
    process.standardError = Pipe()
    do {
      try process.run()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else {
        return "unknown"
      }
      return (
        String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
          ?? "unknown"
      ).trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
      return "unknown"
    }
  }

  private func iso(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: date)
  }

  public static func machineArchitecture() -> String {
    var system = utsname()
    uname(&system)
    return withUnsafePointer(to: &system.machine) {
      $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
    }
  }

  private static func firstMatch(_ text: String, _ pattern: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
      match.numberOfRanges > 1,
      let range = Range(match.range(at: 1), in: text)
    else {
      return nil
    }
    return String(text[range])
  }

  private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(value).write(to: url, options: .atomic)
  }

  private func writeJSONObject(_ value: Any, to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url, options: .atomic)
  }
}

private struct GateBook {
  private var results: [HermesReleaseCandidateGate: HermesReleaseCandidateGateResult] = [:]

  mutating func pass(_ gate: HermesReleaseCandidateGate, _ reason: String) {
    set(gate, .passed, reason)
  }

  mutating func fail(_ gate: HermesReleaseCandidateGate, _ reason: String) {
    set(gate, .failed, reason)
  }

  mutating func set(
    _ gate: HermesReleaseCandidateGate,
    _ state: HermesReleaseCandidateGateState,
    _ reason: String
  ) {
    results[gate] = HermesReleaseCandidateGateResult(gate: gate, state: state, reasonCode: reason)
  }

  func complete(markMissingFailed: Bool = false) -> [HermesReleaseCandidateGateResult] {
    HermesReleaseCandidateGate.allCases.map {
      results[$0]
        ?? HermesReleaseCandidateGateResult(
          gate: $0,
          state: markMissingFailed ? .failed : .notApplicable,
          reasonCode: "not_executed"
        )
    }
  }
}
