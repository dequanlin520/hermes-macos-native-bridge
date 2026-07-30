import Foundation

public protocol HermesReportHistoryStoring: Sendable {
  func loadHistory() throws -> [HermesReportHistoryEntry]
  func save(_ document: HermesReportDocument) throws -> HermesReportHistoryEntry
}

public struct HermesReportingCenterInputs: Sendable {
  public var healthSummary: @Sendable () async -> HermesReportDomainSummary
  public var operationsSummary: @Sendable () async -> HermesReportDomainSummary
  public var analyticsSummary: @Sendable () async -> HermesReportDomainSummary
  public var complianceSummary: @Sendable () async -> HermesReportDomainSummary
  public var auditSummary: @Sendable () async -> HermesReportDomainSummary

  public init(
    healthSummary: @escaping @Sendable () async -> HermesReportDomainSummary,
    operationsSummary: @escaping @Sendable () async -> HermesReportDomainSummary,
    analyticsSummary: @escaping @Sendable () async -> HermesReportDomainSummary,
    complianceSummary: @escaping @Sendable () async -> HermesReportDomainSummary,
    auditSummary: @escaping @Sendable () async -> HermesReportDomainSummary
  ) {
    self.healthSummary = healthSummary
    self.operationsSummary = operationsSummary
    self.analyticsSummary = analyticsSummary
    self.complianceSummary = complianceSummary
    self.auditSummary = auditSummary
  }
}

public final class HermesReportingCenter: @unchecked Sendable {
  private let inputs: HermesReportingCenterInputs
  private let historyStore: any HermesReportHistoryStoring

  public init(
    inputs: HermesReportingCenterInputs,
    historyStore: any HermesReportHistoryStoring = HermesInMemoryReportHistoryStore()
  ) {
    self.inputs = inputs
    self.historyStore = historyStore
  }

  public func snapshot() async -> HermesReportingSnapshot {
    let history = (try? historyStore.loadHistory()) ?? []
    return await HermesReportingSnapshot(
      health: inputs.healthSummary(),
      operations: inputs.operationsSummary(),
      analytics: inputs.analyticsSummary(),
      compliance: inputs.complianceSummary(),
      audit: inputs.auditSummary(),
      history: history,
      readOnly: true,
      appOwnsRuntime: false,
      processExecutionAvailable: false,
      shellAvailable: false,
      uploadAvailable: false,
      networkAvailable: false,
      filesystemScanAvailable: false
    )
  }

  public func generate(format: HermesReportFormat) async throws -> HermesReportDocument {
    let snapshot = await snapshot()
    return HermesReportingRenderer.render(snapshot: snapshot, format: format)
  }

  public func save(_ document: HermesReportDocument) throws -> HermesReportHistoryEntry {
    try historyStore.save(document)
  }

  public var readOnly: Bool { true }
  public var appOwnsRuntime: Bool { false }
  public var processExecutionAvailable: Bool { false }
  public var shellAvailable: Bool { false }
  public var uploadAvailable: Bool { false }
  public var networkAvailable: Bool { false }
  public var filesystemScanAvailable: Bool { false }
}

public final class HermesInMemoryReportHistoryStore: HermesReportHistoryStoring, @unchecked Sendable {
  private var entries: [HermesReportHistoryEntry]

  public init(entries: [HermesReportHistoryEntry] = []) {
    self.entries = entries
  }

  public func loadHistory() throws -> [HermesReportHistoryEntry] {
    entries
  }

  public func save(_ document: HermesReportDocument) throws -> HermesReportHistoryEntry {
    let entry = HermesReportHistoryEntry(
      id: document.id,
      title: document.title,
      format: document.format,
      createdAt: document.createdAt,
      relativePath: document.fileName,
      byteCount: document.body.utf8.count
    )
    entries.insert(entry, at: 0)
    return entry
  }
}

public final class HermesReportFileHistoryStore: HermesReportHistoryStoring, @unchecked Sendable {
  private let directory: URL
  private let indexURL: URL
  private let fileManager: FileManager
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  public init(directory: URL, fileManager: FileManager = .default) {
    self.directory = directory
    self.indexURL = directory.appendingPathComponent("index.json", isDirectory: false)
    self.fileManager = fileManager
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    decoder.dateDecodingStrategy = .iso8601
  }

  public func loadHistory() throws -> [HermesReportHistoryEntry] {
    guard fileManager.fileExists(atPath: indexURL.path) else { return [] }
    let data = try Data(contentsOf: indexURL)
    return try decoder.decode([HermesReportHistoryEntry].self, from: data)
  }

  public func save(_ document: HermesReportDocument) throws -> HermesReportHistoryEntry {
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let fileName = HermesReportingRedactor.safeFileName(
      document.fileName,
      fallback: "hermes-report.\(document.format.fileExtension)"
    )
    let reportURL = directory.appendingPathComponent(fileName, isDirectory: false)
    try document.body.data(using: .utf8)?.write(to: reportURL, options: .atomic)
    let entry = HermesReportHistoryEntry(
      id: document.id,
      title: document.title,
      format: document.format,
      createdAt: document.createdAt,
      relativePath: fileName,
      byteCount: document.body.utf8.count
    )
    var history = try loadHistory()
    history.removeAll { $0.id == entry.id }
    history.insert(entry, at: 0)
    try encoder.encode(Array(history.prefix(50))).write(to: indexURL, options: .atomic)
    return entry
  }
}
