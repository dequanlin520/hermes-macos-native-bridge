import CryptoKit
import Foundation
import XCTest

@testable import HermesRuntimeFoundation

final class HermesAuditLogTests: XCTestCase {
  func testEventKindCatalogIsFixedAndComplete() {
    XCTAssertEqual(HermesAuditEventKind.allCases.count, 25)
    XCTAssertTrue(HermesAuditEventKind.allCases.contains(.doctorExecuted))
    XCTAssertTrue(HermesAuditEventKind.allCases.contains(.auditExported))
    XCTAssertTrue(HermesAuditEventKind.allCases.contains(.auditSigningKeyRotated))
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
    XCTAssertNotNil(manifest.integrity)
  }

  func testDigestValidationAndDeterministicCanonicalEncoding() throws {
    let id = try HermesAuditEventID(rawValue: "haud_" + String(repeating: "A", count: 43))
    let first = try HermesAuditEvent(
      eventID: id,
      timestamp: Date(timeIntervalSince1970: 1),
      kind: .doctorExecuted,
      actor: .controlCLI,
      outcome: .succeeded,
      reasonCode: "complete",
      metadata: try HermesAuditMetadata(["b": "2", "a": "1"])
    )
    let second = try HermesAuditEvent(
      eventID: id,
      timestamp: Date(timeIntervalSince1970: 1),
      kind: .doctorExecuted,
      actor: .controlCLI,
      outcome: .succeeded,
      reasonCode: "complete",
      metadata: try HermesAuditMetadata(["a": "1", "b": "2"])
    )
    let firstBytes = try HermesAuditCanonical.canonicalEventBytes(first)
    let secondBytes = try HermesAuditCanonical.canonicalEventBytes(second)
    XCTAssertEqual(firstBytes, secondBytes)
    XCTAssertEqual(HermesAuditDigest(firstBytes), HermesAuditDigest(secondBytes))
    XCTAssertNil(HermesAuditDigest(rawValue: "BAD"))
  }

  func testCleanGenesisAndUnsignedActiveChainVerification() async throws {
    let root = try temporaryDirectory()
    let store = try FileBackedHermesAuditStore(
      configuration: HermesAuditStoreConfiguration(root: root))
    try await appendFixtureEvents(to: store, count: 3)

    let report = try HermesAuditIntegrityVerifier(root: root).verify()

    XCTAssertEqual(report.state, .verifiedUnsigned, "\(report.issueCodes)")
    XCTAssertEqual(report.verifiedEventCount, 3)
    XCTAssertFalse(report.issueCodes.contains(.previousEventMismatch))
  }

  func testSegmentManifestChecksumAndRotationChainVerification() async throws {
    let root = try temporaryDirectory()
    let store = try FileBackedHermesAuditStore(
      configuration: HermesAuditStoreConfiguration(root: root))
    try await appendFixtureEvents(to: store, count: 2)
    try await store.rotateActiveSegment()
    try await appendFixtureEvents(to: store, count: 2, offset: 2)
    try await store.rotateActiveSegment()

    let manifests = try FileManager.default.contentsOfDirectory(atPath: root.path)
      .filter { $0.hasSuffix(".manifest.json") }
    let report = try HermesAuditIntegrityVerifier(root: root).verify()

    XCTAssertEqual(manifests.count, 2)
    XCTAssertEqual(report.state, .verifiedUnsigned, "\(report.issueCodes)")
    XCTAssertEqual(report.verifiedEventCount, 4)
  }

  func testModificationDeletionInsertionReorderingAndSequenceGapDetection() async throws {
    let root = try await closedFixtureStore(eventCount: 4)

    let modified = try copyDirectory(root)
    try rewriteFirstRecord(in: modified) { object in
      var event = object["event"] as! [String: Any]
      event["reasonCode"] = "modified"
      object["event"] = event
    }
    XCTAssertEqual(try HermesAuditIntegrityVerifier(root: modified).verify().state, .corrupted)
    XCTAssertTrue(
      try HermesAuditIntegrityVerifier(root: modified).verify().issueCodes.contains(
        .eventDigestMismatch))

    let deleted = try copyDirectory(root)
    try mutateFirstLog(in: deleted) { lines in Array(lines.dropFirst()) }
    XCTAssertTrue(
      try HermesAuditIntegrityVerifier(root: deleted).verify().issueCodes.contains(
        .expectedEventCountMismatch))

    let inserted = try copyDirectory(root)
    try mutateFirstLog(in: inserted) { lines in [lines[0]] + lines }
    XCTAssertTrue(
      try HermesAuditIntegrityVerifier(root: inserted).verify().issueCodes.contains(.sequenceGap))

    let reordered = try copyDirectory(root)
    try mutateFirstLog(in: reordered) { lines in [lines[1], lines[0]] + lines.dropFirst(2) }
    XCTAssertTrue(
      try HermesAuditIntegrityVerifier(root: reordered).verify().issueCodes.contains(
        .previousEventMismatch))

    let gap = try copyDirectory(root)
    try rewriteFirstRecord(in: gap) { object in
      var chain = object["chain"] as! [String: Any]
      chain["sequenceNumber"] = 9
      object["chain"] = chain
    }
    XCTAssertTrue(
      try HermesAuditIntegrityVerifier(root: gap).verify().issueCodes.contains(.sequenceGap))
  }

  func testPreviousHashMismatchMissingDuplicateUnsupportedAndClosedTruncation() async throws {
    let root = try await closedFixtureStore(eventCount: 3)

    let mismatch = try copyDirectory(root)
    try rewriteFirstRecord(in: mismatch) { object in
      var chain = object["chain"] as! [String: Any]
      chain["previousDigest"] = String(repeating: "f", count: 64)
      object["chain"] = chain
    }
    XCTAssertTrue(
      try HermesAuditIntegrityVerifier(root: mismatch).verify().issueCodes.contains(
        .previousEventMismatch))

    let missing = try copyDirectory(root)
    let jsonl = try firstLog(in: missing)
    try FileManager.default.removeItem(at: jsonl)
    XCTAssertTrue(
      try HermesAuditIntegrityVerifier(root: missing).verify().issueCodes.contains(.missingSegment))

    let duplicate = try copyDirectory(root)
    let duplicateURL = duplicate.appendingPathComponent("audit.zzz_duplicate.jsonl")
    try FileManager.default.copyItem(at: try firstLog(in: duplicate), to: duplicateURL)
    XCTAssertTrue(
      try HermesAuditIntegrityVerifier(root: duplicate).verify().issueCodes.contains(
        .duplicateSegment))

    let unsupported = try copyDirectory(root)
    try rewriteFirstRecord(in: unsupported) { object in object["recordSchemaVersion"] = 99 }
    XCTAssertEqual(try HermesAuditIntegrityVerifier(root: unsupported).verify().state, .unsupported)

    let truncated = try copyDirectory(root)
    let file = try firstLog(in: truncated)
    let data = try Data(contentsOf: file)
    try data.dropLast(8).write(to: file)
    XCTAssertTrue(
      try HermesAuditIntegrityVerifier(root: truncated).verify().issueCodes.contains(
        .unexpectedTruncation))
  }

  func testRecoverableActivePartialTailAndCorruptActiveTailDistinction() async throws {
    let root = try temporaryDirectory()
    let store = try FileBackedHermesAuditStore(
      configuration: HermesAuditStoreConfiguration(root: root))
    try await appendFixtureEvents(to: store, count: 2)
    let active = root.appendingPathComponent(FileBackedHermesAuditStore.activeLogName)
    let handle = try FileHandle(forWritingTo: active)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(#"{"partial":"tail""#.utf8))
    try handle.close()
    XCTAssertEqual(
      try HermesAuditIntegrityVerifier(root: root).verify().state, .incompleteRecoverableTail)

    let corruptRoot = try temporaryDirectory()
    let corruptStore = try FileBackedHermesAuditStore(
      configuration: HermesAuditStoreConfiguration(root: corruptRoot))
    try await appendFixtureEvents(to: corruptStore, count: 2)
    let corruptActive = corruptRoot.appendingPathComponent(FileBackedHermesAuditStore.activeLogName)
    let corruptHandle = try FileHandle(forWritingTo: corruptActive)
    try corruptHandle.seekToEnd()
    try corruptHandle.write(contentsOf: Data(#"{"recordSchemaVersion":99}"#.utf8))
    try corruptHandle.close()
    XCTAssertTrue(
      try HermesAuditIntegrityVerifier(root: corruptRoot).verify().issueCodes.contains(
        .corruptActiveTail))
  }

  func testSignatureValidationInvalidSignatureAndWrongPublicKey() async throws {
    let root = try temporaryDirectory()
    let signer = HermesEphemeralTestAuditManifestSigningProvider()
    let store = try FileBackedHermesAuditStore(
      configuration: HermesAuditStoreConfiguration(root: root),
      signingProvider: signer
    )
    try await appendFixtureEvents(to: store, count: 2)
    try await store.rotateActiveSegment()
    XCTAssertEqual(
      try HermesAuditIntegrityVerifier(root: root, signingProvider: signer).verify().state,
      .verifiedSigned
    )

    let invalid = try copyDirectory(root)
    let manifest = try firstManifest(in: invalid)
    var data = try String(contentsOf: manifest, encoding: .utf8)
    data = data.replacingOccurrences(
      of: "\"encodedSignature\":\"", with: "\"encodedSignature\":\"AA")
    try data.write(to: manifest, atomically: true, encoding: .utf8)
    let invalidReport = try HermesAuditIntegrityVerifier(root: invalid, signingProvider: signer)
      .verify()
    XCTAssertEqual(invalidReport.state, .signatureInvalid, "\(invalidReport.issueCodes)")

    let wrong = HermesEphemeralTestAuditManifestSigningProvider()
    XCTAssertEqual(
      try HermesAuditIntegrityVerifier(root: root, signingProvider: wrong).verify().state,
      .unknownSigner
    )
  }

  func testM6003SigningModelsAndTrustAnchorVerification() async throws {
    XCTAssertNoThrow(try HermesAuditSignerID(rawValue: "hasg_valid-01"))
    XCTAssertThrowsError(try HermesAuditSignerID(rawValue: "bad"))

    let signer = HermesEphemeralTestAuditManifestSigningProvider(keyID: "hasg_m6003")
    let fingerprint = signer.publicKeyFingerprint!
    XCTAssertEqual(
      fingerprint,
      HermesAuditSigningKeyFingerprint(publicKeyDER: signer.exportedPublicKey.derRepresentation)
    )

    let anchor = signer.publicTrustAnchor
    XCTAssertTrue(anchor.checksumIsValid())
    XCTAssertEqual(anchor.publicKeyDER, signer.exportedPublicKey.derRepresentation)
    XCTAssertFalse(String(describing: anchor).localizedCaseInsensitiveContains("private"))

    let root = try temporaryDirectory()
    let store = try FileBackedHermesAuditStore(
      configuration: HermesAuditStoreConfiguration(root: root),
      signingProvider: signer
    )
    try await appendFixtureEvents(to: store, count: 2)
    try await store.rotateActiveSegment()

    XCTAssertEqual(
      try HermesAuditIntegrityVerifier(root: root, trustAnchors: [anchor]).verify().state,
      .verifiedSigned
    )

    let retired = try HermesAuditPublicTrustAnchor(
      signerID: anchor.signerID,
      publicKeyDER: anchor.publicKeyDER!,
      fingerprint: anchor.fingerprint,
      createdAt: anchor.createdAt,
      state: .retired,
      keyGenerationID: anchor.keyGenerationID
    )
    XCTAssertEqual(
      try HermesAuditIntegrityVerifier(root: root, trustAnchors: [retired]).verify().state,
      .retiredSignerValid
    )

    let unknown = HermesEphemeralTestAuditManifestSigningProvider(keyID: "hasg_unknown")
    XCTAssertEqual(
      try HermesAuditIntegrityVerifier(root: root, trustAnchors: [unknown.publicTrustAnchor])
        .verify().state,
      .unknownSigner
    )
  }

  func testM6003ModifiedManifestSignatureAndFingerprintFailures() async throws {
    let signer = HermesEphemeralTestAuditManifestSigningProvider(keyID: "hasg_m6003_failure")
    let root = try temporaryDirectory()
    let store = try FileBackedHermesAuditStore(
      configuration: HermesAuditStoreConfiguration(root: root),
      signingProvider: signer
    )
    try await appendFixtureEvents(to: store, count: 2)
    try await store.rotateActiveSegment()

    let modifiedManifest = try copyDirectory(root)
    try rewriteFirstManifest(in: modifiedManifest) { object in
      object["eventCount"] = 99
    }
    XCTAssertEqual(
      try HermesAuditIntegrityVerifier(
        root: modifiedManifest,
        trustAnchors: [
          signer.publicTrustAnchor
        ]
      ).verify().state,
      .signatureInvalid
    )

    let wrongFingerprint = try copyDirectory(root)
    try rewriteFirstManifest(in: wrongFingerprint) { object in
      var signature = object["signature"] as! [String: Any]
      signature["publicKeyFingerprint"] = ["rawValue": String(repeating: "f", count: 64)]
      object["signature"] = signature
    }
    XCTAssertEqual(
      try HermesAuditIntegrityVerifier(
        root: wrongFingerprint,
        trustAnchors: [
          signer.publicTrustAnchor
        ]
      ).verify().state,
      .signatureInvalid
    )
  }

  func testM6003TrustAnchorStoreStatusAndPrivateKeychainStatesAreTyped() throws {
    let root = try temporaryDirectory()
    let store = HermesAuditPublicTrustAnchorStore(root: root)
    XCTAssertEqual(store.status().state, .missing)

    let signer = HermesEphemeralTestAuditManifestSigningProvider(keyID: "hasg_anchor_store")
    try store.appendCreatedAnchor(signer.publicTrustAnchor)
    let loaded = try store.load()
    XCTAssertEqual(loaded.count, 1)
    XCTAssertTrue(loaded[0].checksumIsValid())

    XCTAssertThrowsError(
      try HermesAuditSigningKeyFingerprint(rawValue: String(repeating: "A", count: 64)))
    XCTAssertEqual(
      HermesAuditSigningKeyManager().state(
        signerID: try HermesAuditSignerID(rawValue: "hasg_missing"),
        keyGenerationID: "missing"
      ),
      .missing
    )
  }

  func testConcurrentAppendRetentionExportPrivacyAndNonMutatingVerification() async throws {
    let root = try temporaryDirectory()
    let store = try FileBackedHermesAuditStore(
      configuration: HermesAuditStoreConfiguration(
        root: root,
        maximumFileBytes: 64 * 1024,
        maximumRetainedFiles: 2,
        maximumRetainedEvents: 30
      ))
    try await withThrowingTaskGroup(of: Void.self) { group in
      for index in 0..<20 {
        group.addTask {
          try await store.append(
            HermesAuditEvent.make(
              kind: .requestStarted,
              actor: .testFixture,
              outcome: .started,
              reasonCode: "started_\(index)",
              metadata: try HermesAuditMetadata(["safe": "value_\(index)"])
            ))
        }
      }
      try await group.waitForAll()
    }
    try await store.rotateActiveSegment()
    let before = try directoryFingerprint(root)
    let report = try HermesAuditIntegrityVerifier(root: root).verify()
    let after = try directoryFingerprint(root)
    XCTAssertEqual(before, after)
    XCTAssertEqual(report.state, .verifiedUnsigned, "\(report.issueCodes)")

    let output = try temporaryDirectory()
    let manifest = try await HermesAuditExporter(store: store).export(
      HermesAuditExportRequest(query: try HermesAuditQuery(limit: 100), outputDirectory: output))
    let exported = try String(
      contentsOf: output.appendingPathComponent(manifest.dataFileName),
      encoding: .utf8
    )
    let manifestText = try String(contentsOf: output.appendingPathComponent("manifest.json"))
    XCTAssertNotNil(manifest.integrity)
    XCTAssertFalse((exported + manifestText).localizedCaseInsensitiveContains("prompt"))
    XCTAssertFalse((exported + manifestText).localizedCaseInsensitiveContains("token"))
    XCTAssertFalse((exported + manifestText).localizedCaseInsensitiveContains("bookmark"))
    XCTAssertFalse((exported + manifestText).localizedCaseInsensitiveContains("file content"))
    XCTAssertFalse((exported + manifestText).contains("/Users/"))
  }

  private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("hermes-audit-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func appendFixtureEvents(
    to store: FileBackedHermesAuditStore,
    count: Int,
    offset: Int = 0
  ) async throws {
    for index in 0..<count {
      try await store.append(
        HermesAuditEvent.make(
          kind: .doctorExecuted,
          actor: .testFixture,
          outcome: .succeeded,
          reasonCode: "fixture_\(index + offset)",
          correlationID: "corr_m6_002",
          metadata: try HermesAuditMetadata(["ordinal": "\(index + offset)"]),
          timestamp: Date(timeIntervalSince1970: TimeInterval(index + offset))
        ))
    }
  }

  private func closedFixtureStore(eventCount: Int) async throws -> URL {
    let root = try temporaryDirectory()
    let store = try FileBackedHermesAuditStore(
      configuration: HermesAuditStoreConfiguration(root: root))
    try await appendFixtureEvents(to: store, count: eventCount)
    try await store.rotateActiveSegment()
    return root
  }

  private func copyDirectory(_ source: URL) throws -> URL {
    let destination = try temporaryDirectory()
    try FileManager.default.removeItem(at: destination)
    try FileManager.default.copyItem(at: source, to: destination)
    return destination
  }

  private func firstLog(in root: URL) throws -> URL {
    try FileManager.default.contentsOfDirectory(
      at: root,
      includingPropertiesForKeys: nil
    ).filter {
      $0.pathExtension == "jsonl"
        && $0.lastPathComponent != FileBackedHermesAuditStore.activeLogName
    }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
    .first!
  }

  private func firstManifest(in root: URL) throws -> URL {
    try FileManager.default.contentsOfDirectory(
      at: root,
      includingPropertiesForKeys: nil
    ).filter { $0.lastPathComponent.hasSuffix(".manifest.json") }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
      .first!
  }

  private func mutateFirstLog(in root: URL, mutate: ([String]) -> [String]) throws {
    let file = try firstLog(in: root)
    let lines = try String(contentsOf: file, encoding: .utf8)
      .split(separator: "\n").map(String.init)
    try (mutate(lines).joined(separator: "\n") + "\n").write(
      to: file,
      atomically: true,
      encoding: .utf8
    )
  }

  private func rewriteFirstRecord(
    in root: URL,
    mutate: (inout [String: Any]) -> Void
  ) throws {
    try mutateFirstLog(in: root) { lines in
      var object = try! JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as! [String: Any]
      mutate(&object)
      let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
      return [String(decoding: data, as: UTF8.self)] + lines.dropFirst()
    }
  }

  private func rewriteFirstManifest(
    in root: URL,
    mutate: (inout [String: Any]) -> Void
  ) throws {
    let file = try firstManifest(in: root)
    var object = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
    mutate(&object)
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    try data.write(to: file)
  }

  private func directoryFingerprint(_ root: URL) throws -> [String: String] {
    let files = try FileManager.default.contentsOfDirectory(
      at: root, includingPropertiesForKeys: nil)
    return Dictionary(
      uniqueKeysWithValues: try files.map {
        ($0.lastPathComponent, HermesAuditDigest(try Data(contentsOf: $0))!.rawValue)
      })
  }
}
