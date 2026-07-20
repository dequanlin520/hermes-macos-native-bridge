import CryptoKit
import Foundation
import XCTest

@testable import HermesRuntimeFoundation

final class HermesAuditLogTests: XCTestCase {
  func testEventKindCatalogIsFixedAndComplete() {
    XCTAssertEqual(HermesAuditEventKind.allCases.count, 24)
    XCTAssertTrue(HermesAuditEventKind.allCases.contains(.doctorExecuted))
    XCTAssertTrue(HermesAuditEventKind.allCases.contains(.auditExported))
  }

  func testAuditEventIDValidation() throws {
    let id = try HermesAuditEventID.generate()
    XCTAssertTrue(HermesAuditEventID.isValid(id.rawValue))
    XCTAssertThrowsError(try HermesAuditEventID(rawValue: "bad"))
  }

  func testMetadataBoundsAndSensitiveRejection() throws {
    XCTAssertThrowsError(try HermesAuditMetadata(["prompt": "redacted"]))
    XCTAssertThrowsError(try HermesAuditMetadata(["safe": "token=abc"]))
    XCTAssertThrowsError(try HermesAuditMetadata(["safe": "/Users/example/private"]))
    XCTAssertThrowsError(try HermesAuditMetadata(["safe": "bookmark bytes"]))
    XCTAssertNoThrow(try HermesAuditMetadata(["operation": "restart_complete"]))
  }

  func testEventRejectsUnsafeIdentifiers() throws {
    XCTAssertThrowsError(
      try HermesAuditEvent.make(
        kind: .requestStarted,
        actor: .xpcClient,
        outcome: .started,
        reasonCode: "ok",
        requestID: "/Users/example/request"
      ))
  }

  func testAppendReloadOrderingAndQueries() async throws {
    let root = try temporaryDirectory()
    let store = try FileBackedHermesAuditStore(
      configuration: HermesAuditStoreConfiguration(root: root))
    let first = try HermesAuditEvent.make(
      kind: .serviceStarted,
      actor: .controlCLI,
      outcome: .started,
      reasonCode: "started",
      correlationID: "corr_1",
      timestamp: Date(timeIntervalSince1970: 1)
    )
    let second = try HermesAuditEvent.make(
      kind: .doctorExecuted,
      actor: .controlCLI,
      outcome: .succeeded,
      reasonCode: "complete",
      correlationID: "corr_2",
      timestamp: Date(timeIntervalSince1970: 2)
    )
    try await store.append(second)
    try await store.append(first)

    let reloaded = try FileBackedHermesAuditStore(
      configuration: HermesAuditStoreConfiguration(root: root))
    let all = try await reloaded.query(try HermesAuditQuery(limit: 10))
    XCTAssertEqual(all.map(\.kind), [.serviceStarted, .doctorExecuted])

    let kind = try await reloaded.query(
      try HermesAuditQuery(kinds: [.doctorExecuted], limit: 10))
    XCTAssertEqual(kind.map(\.kind), [.doctorExecuted])

    let corr = try await reloaded.query(
      try HermesAuditQuery(correlationID: "corr_1", limit: 10))
    XCTAssertEqual(corr.map(\.correlationID), ["corr_1"])

    let range = try await reloaded.query(
      try HermesAuditQuery(
        start: Date(timeIntervalSince1970: 1.5),
        end: Date(timeIntervalSince1970: 2.5),
        limit: 10
      ))
    XCTAssertEqual(range.map(\.kind), [.doctorExecuted])
  }

  func testCorruptRecordAndPartialTailRecovery() async throws {
    let root = try temporaryDirectory()
    let store = try FileBackedHermesAuditStore(
      configuration: HermesAuditStoreConfiguration(root: root))
    let event = try HermesAuditEvent.make(
      kind: .serviceStopped,
      actor: .controlCLI,
      outcome: .succeeded,
      reasonCode: "stopped"
    )
    try await store.append(event)
    let file = root.appendingPathComponent(FileBackedHermesAuditStore.activeLogName)
    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(#"{"schemaVersion":1,"bad":"record"}"#.utf8))
    try handle.write(contentsOf: Data(#"{"partial":"tail""#.utf8))
    try handle.close()

    let events = try await store.query(try HermesAuditQuery(limit: 10))
    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(events.first?.eventID, event.eventID)
  }

  func testRotationRetentionAndConcurrentAppend() async throws {
    let root = try temporaryDirectory()
    let store = try FileBackedHermesAuditStore(
      configuration: HermesAuditStoreConfiguration(
        root: root,
        maximumFileBytes: 4_096,
        maximumRetainedFiles: 2,
        maximumRetainedEvents: 25
      ))
    try await withThrowingTaskGroup(of: Void.self) { group in
      for index in 0..<40 {
        group.addTask {
          try await store.append(
            HermesAuditEvent.make(
              kind: .requestStarted,
              actor: .testFixture,
              outcome: .started,
              reasonCode: "started_\(index)"
            ))
        }
      }
      try await group.waitForAll()
    }
    let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
      .filter { $0.hasSuffix(".jsonl") }
    XCTAssertLessThanOrEqual(files.count, 2)
    let events = try await store.query(try HermesAuditQuery(limit: 100))
    XCTAssertLessThanOrEqual(events.count, 25)
  }

  func testSymlinkRootRejected() throws {
    let parent = try temporaryDirectory()
    let real = parent.appendingPathComponent("real", isDirectory: true)
    let link = parent.appendingPathComponent("link", isDirectory: true)
    try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
    XCTAssertThrowsError(
      try FileBackedHermesAuditStore(configuration: HermesAuditStoreConfiguration(root: link)))
  }

  func testExportManifestChecksumRedactionAndAuditEvent() async throws {
    let root = try temporaryDirectory()
    let output = try temporaryDirectory()
    let store = try FileBackedHermesAuditStore(
      configuration: HermesAuditStoreConfiguration(root: root))
    try await store.append(
      HermesAuditEvent.make(
        kind: .doctorExecuted,
        actor: .controlCLI,
        outcome: .succeeded,
        reasonCode: "complete",
        metadata: try HermesAuditMetadata(["summary": "safe"])
      ))
    let manifest = try await HermesAuditExporter(store: store).export(
      HermesAuditExportRequest(
        query: try HermesAuditQuery(limit: 100),
        outputDirectory: output
      ))
    let exported = try Data(
      contentsOf: output.appendingPathComponent(manifest.dataFileName))
    let digest = SHA256.hash(data: exported).map { String(format: "%02x", $0) }.joined()
    XCTAssertEqual(digest, manifest.sha256)
    let text = String(decoding: exported, as: UTF8.self)
    XCTAssertFalse(text.contains("Prompt"))
    XCTAssertFalse(text.contains("token"))
    XCTAssertFalse(text.contains("bookmark"))
    XCTAssertFalse(text.contains("/Users/"))
    let events = try await store.query(
      try HermesAuditQuery(kinds: [.auditExported], limit: 10))
    XCTAssertEqual(events.count, 1)
  }

  private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("hermes-audit-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
