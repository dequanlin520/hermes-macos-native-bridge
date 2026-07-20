import CryptoKit
import Foundation
import HermesRuntimeFoundation

@main
struct M6001AuditFixture {
  static func main() async throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let exportRoot = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    let store = try FileBackedHermesAuditStore(
      configuration: HermesAuditStoreConfiguration(
        root: root,
        maximumFileBytes: 4096,
        maximumRetainedFiles: 3,
        maximumRetainedEvents: 200
      ))

    let kinds: [HermesAuditEventKind] = [
      .serviceInstalled,
      .serviceStarted,
      .serviceStopped,
      .serviceRestarted,
      .requestAccepted,
      .requestStarted,
      .requestCancelled,
      .requestCompleted,
      .requestFailed,
      .approvalRequested,
      .approvalResponded,
      .authorizedRootAdded,
      .authorizedRootRefreshed,
      .authorizedRootDeactivated,
      .authorizedRootRemoved,
      .fileSubscriptionCreated,
      .fileSubscriptionCancelled,
      .fileRescanRequired,
      .doctorExecuted,
      .emergencyStopRequested,
      .emergencyStopCompleted,
    ]

    for index in 0..<80 {
      let kind = kinds[index % kinds.count]
      try await store.append(
        HermesAuditEvent.make(
          kind: kind,
          actor: .testFixture,
          outcome: index % 7 == 0 ? .failed : .succeeded,
          reasonCode: "fixture_\(index)",
          correlationID: "m6_001",
          requestID: requestID(for: kind),
          rootID: rootID(for: kind),
          subscriptionID: subscriptionID(for: kind),
          metadata: try HermesAuditMetadata(["fixture": "\(index)"])
        ))
    }

    let events = try await store.query(try HermesAuditQuery(correlationID: "m6_001", limit: 200))
    let manifest = try await HermesAuditExporter(store: store).export(
      HermesAuditExportRequest(
        query: try HermesAuditQuery(correlationID: "m6_001", limit: 200),
        outputDirectory: exportRoot,
        format: .jsonl
      ))
    let data = try Data(contentsOf: exportRoot.appendingPathComponent(manifest.dataFileName))
    let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    let json = try JSONEncoder().encode([
      "events": "\(events.count)",
      "checksum": checksum,
      "manifestChecksum": manifest.sha256,
    ])
    FileHandle.standardOutput.write(json)
  }

  private static func requestID(for kind: HermesAuditEventKind) -> String? {
    switch kind {
    case .requestAccepted, .requestStarted, .requestCancelled, .requestCompleted, .requestFailed,
      .approvalRequested, .approvalResponded:
      return "hrq_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    default:
      return nil
    }
  }

  private static func rootID(for kind: HermesAuditEventKind) -> String? {
    switch kind {
    case .authorizedRootAdded, .authorizedRootRefreshed, .authorizedRootDeactivated,
      .authorizedRootRemoved, .fileRescanRequired:
      return "hroot_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    default:
      return nil
    }
  }

  private static func subscriptionID(for kind: HermesAuditEventKind) -> String? {
    switch kind {
    case .fileSubscriptionCreated, .fileSubscriptionCancelled, .fileRescanRequired:
      return "fsub_AAAAAAAAAAAAAAAAAAAAAAAA"
    default:
      return nil
    }
  }
}
