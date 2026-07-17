import Foundation
import HermesBridgeXPC
import XCTest

@testable import HermesBridgeService

final class HermesBridgeServiceMachIntegrationTests: XCTestCase {
  func testTemporaryLaunchAgentMachServiceRoundTrip() async throws {
    guard ProcessInfo.processInfo.environment["HERMES_RUN_MACH_SERVICE_INTEGRATION"] == "1" else {
      throw XCTSkip("Set HERMES_RUN_MACH_SERVICE_INTEGRATION=1 to run launchd integration.")
    }

    let repo = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let unique = "m2-008-\(UUID().uuidString.lowercased())"
    let label = "com.hermes.bridge.test.\(unique)"
    let machService = label + ".xpc"
    let root = repo.appendingPathComponent("artifacts/m2-008/\(label)", isDirectory: true)
    let logs = root.appendingPathComponent("logs", isDirectory: true)
    try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
    let serviceBinary = repo.appendingPathComponent(".build/debug/HermesBridgeService")
    guard FileManager.default.isExecutableFile(atPath: serviceBinary.path) else {
      throw XCTSkip("HermesBridgeService binary was not built at .build/debug/HermesBridgeService")
    }
    let candidate = try executableFixture(root: root)
    let configuration = try HermesBridgeServiceConfiguration(
      machServiceName: machService,
      runtimeRoot: root.appendingPathComponent("Runtime", isDirectory: true),
      requestStateRoot: root.appendingPathComponent("State", isDirectory: true),
      allowlistedHermesExecutableCandidates: [candidate],
      loopbackPortPolicy: HermesBridgeLoopbackPortPolicy(fixedPort: 18_493),
      timeouts: HermesBridgeServiceTimeouts(
        startup: 2,
        gracefulShutdown: 1,
        forcedShutdown: 1,
        gatewayReady: 1
      ),
      maximumConcurrentXPCRequests: 2,
      bindings: [],
      allowTestMachServiceName: true
    )
    let configURL = root.appendingPathComponent("service-config.json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(configuration).write(to: configURL)
    let plistURL = root.appendingPathComponent("\(label).plist")
    try launchAgentPlist(
      label: label,
      machService: machService,
      binary: serviceBinary,
      config: configURL,
      logs: logs
    ).write(to: plistURL, atomically: true, encoding: .utf8)
    _ = try shell("plutil -lint '\(plistURL.path)'")

    let domain = "gui/\(getuid())"
    _ = try? shell("launchctl bootout \(domain) '\(plistURL.path)'")
    XCTAssertThrowsError(try shell("launchctl print \(domain)/\(label)"))

    do {
      _ = try shell("launchctl bootstrap \(domain) '\(plistURL.path)'")
      try waitForReadiness(
        log: logs.appendingPathComponent("service.stdout.log"), service: machService)
      let client = HermesBridgeXPCClient(
        machServiceName: try HermesBridgeMachServiceName(machService),
        timeout: 3
      )
      let capabilities = try await client.connect()
      let version = try await client.protocolVersion()
      await client.close()

      XCTAssertEqual(version.version, .current)
      XCTAssertTrue(capabilities.capabilities.contains(.protocolVersion))
      XCTAssertFalse(try combinedText(in: root).localizedCaseInsensitiveContains("token"))
      XCTAssertFalse(try combinedText(in: root).localizedCaseInsensitiveContains("prompt"))
    } catch {
      _ = try? shell("launchctl bootout \(domain) '\(plistURL.path)'")
      throw error
    }

    _ = try shell("launchctl bootout \(domain) '\(plistURL.path)'")
    XCTAssertThrowsError(try shell("launchctl print \(domain)/\(label)"))
    XCTAssertTrue(
      try shell("pgrep -fl '\(label)' || true").trimmingCharacters(in: .whitespacesAndNewlines)
        .isEmpty)
    XCTAssertThrowsError(try shell("launchctl print \(domain)/\(machService)"))
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: NSHomeDirectory() + "/Library/LaunchAgents/\(label).plist"))
  }

  private func executableFixture(root: URL) throws -> URL {
    let url = root.appendingPathComponent("never-launched-hermes-fixture")
    try "#!/bin/zsh\nexit 64\n".write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: NSNumber(value: Int16(0o700))],
      ofItemAtPath: url.path
    )
    return url
  }

  private func launchAgentPlist(
    label: String,
    machService: String,
    binary: URL,
    config: URL,
    logs: URL
  ) -> String {
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
      "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>Label</key>
      <string>\(label)</string>
      <key>MachServices</key>
      <dict>
        <key>\(machService)</key>
        <true/>
      </dict>
      <key>ProgramArguments</key>
      <array>
        <string>\(binary.path)</string>
      </array>
      <key>EnvironmentVariables</key>
      <dict>
        <key>HERMES_BRIDGE_SERVICE_CONFIG</key>
        <string>\(config.path)</string>
        <key>HERMES_BRIDGE_SERVICE_ALLOW_TEST_CONFIG</key>
        <string>1</string>
      </dict>
      <key>RunAtLoad</key>
      <true/>
      <key>KeepAlive</key>
      <false/>
      <key>ProcessType</key>
      <string>Background</string>
      <key>ThrottleInterval</key>
      <integer>10</integer>
      <key>StandardOutPath</key>
      <string>\(logs.appendingPathComponent("service.stdout.log").path)</string>
      <key>StandardErrorPath</key>
      <string>\(logs.appendingPathComponent("service.stderr.log").path)</string>
    </dict>
    </plist>
    """
  }

  private func waitForReadiness(log: URL, service: String) throws {
    let marker = HermesBridgeServiceMain.readinessMarker(serviceName: service)
    let deadline = Date().addingTimeInterval(10)
    while Date() < deadline {
      if let text = try? String(contentsOf: log, encoding: .utf8), text.contains(marker) {
        return
      }
      Thread.sleep(forTimeInterval: 0.1)
    }
    throw NSError(domain: "HermesBridgeServiceMachIntegration", code: 1)
  }

  private func combinedText(in root: URL) throws -> String {
    let urls = try FileManager.default.contentsOfDirectory(
      at: root,
      includingPropertiesForKeys: nil
    )
    var output = ""
    for url in urls where !url.hasDirectoryPath {
      output += (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
    let logRoot = root.appendingPathComponent("logs", isDirectory: true)
    if let logs = try? FileManager.default.contentsOfDirectory(
      at: logRoot,
      includingPropertiesForKeys: nil
    ) {
      for url in logs {
        output += (try? String(contentsOf: url, encoding: .utf8)) ?? ""
      }
    }
    return output
  }
}

private func shell(_ command: String) throws -> String {
  let process = Process()
  let stdout = Pipe()
  let stderr = Pipe()
  process.executableURL = URL(fileURLWithPath: "/bin/zsh")
  process.arguments = ["-lc", command]
  process.standardOutput = stdout
  process.standardError = stderr
  try process.run()
  process.waitUntilExit()
  let output =
    String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
  let errorOutput =
    String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
  guard process.terminationStatus == 0 else {
    throw NSError(
      domain: "ShellError",
      code: Int(process.terminationStatus),
      userInfo: [NSLocalizedDescriptionKey: output + errorOutput]
    )
  }
  return output
}
