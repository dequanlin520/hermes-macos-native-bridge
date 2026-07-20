import Foundation
import HermesRuntimeFoundation

@main
struct M6003AuditSigningFixture {
  static func main() async throws {
    let auditRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let store = HermesAuditPublicTrustAnchorStore(root: auditRoot)
    let keyManager = HermesAuditSigningKeyManager()

    let firstKey = try keyManager.createKey()
    try store.appendCreatedAnchor(try firstKey.publicTrustAnchor(state: .active))
    let firstStore = try FileBackedHermesAuditStore(
      configuration: HermesAuditStoreConfiguration(
        root: auditRoot,
        maximumFileBytes: 4096,
        maximumRetainedFiles: 16,
        maximumRetainedEvents: 500
      ),
      signingProvider: firstKey
    )
    try await appendEvents(to: firstStore, count: 24, prefix: "first")
    try await firstStore.rotateActiveSegment()

    let secondKey = try keyManager.rotateKey()
    try store.appendCreatedAnchor(try secondKey.publicTrustAnchor(state: .active))
    let secondStore = try FileBackedHermesAuditStore(
      configuration: HermesAuditStoreConfiguration(
        root: auditRoot,
        maximumFileBytes: 4096,
        maximumRetainedFiles: 16,
        maximumRetainedEvents: 500
      ),
      signingProvider: secondKey
    )
    try await secondStore.append(
      HermesAuditEvent.make(
        kind: .auditSigningKeyRotated,
        actor: .testFixture,
        outcome: .succeeded,
        reasonCode: "audit_signing_key_rotated",
        metadata: try HermesAuditMetadata([
          "newFingerprint": secondKey.publicKeyFingerprint?.prefix ?? "unknown"
        ])
      ))
    try await appendEvents(to: secondStore, count: 24, prefix: "second")
    try await secondStore.rotateActiveSegment()

    let anchors = try store.load()
    let report = try HermesAuditIntegrityVerifier(root: auditRoot, trustAnchors: anchors).verify()
    let output = [
      "anchors": "\(anchors.count)",
      "state": report.state.rawValue,
      "events": "\(report.verifiedEventCount)",
    ]
    FileHandle.standardOutput.write(try JSONEncoder().encode(output))
  }

  private static func appendEvents(
    to store: FileBackedHermesAuditStore,
    count: Int,
    prefix: String
  ) async throws {
    for index in 0..<count {
      try await store.append(
        HermesAuditEvent.make(
          kind: .doctorExecuted,
          actor: .testFixture,
          outcome: .succeeded,
          reasonCode: "\(prefix)_\(index)",
          correlationID: "m6_003",
          metadata: try HermesAuditMetadata(["fixture": "\(index)"])
        ))
    }
  }
}
