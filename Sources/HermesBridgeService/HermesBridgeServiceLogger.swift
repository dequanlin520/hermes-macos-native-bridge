import Darwin
import Foundation

public enum HermesBridgeServiceLogEvent: String, Sendable {
  case starting
  case ready
  case stopping
  case stopped
  case startupFailed
  case connectionAccepted
  case connectionRejected
  case requestHandled
}

public struct HermesBridgeServiceLogRecord: Equatable, Sendable {
  public let timestamp: Date
  public let subsystem: String
  public let category: String
  public let event: HermesBridgeServiceLogEvent
  public let protocolVersion: String?
  public let correlationID: String?
  public let requestID: String?
  public let bindingID: String?
  public let redactedErrorCode: String?
}

public final class HermesBridgeServiceLogger: @unchecked Sendable {
  private let lock = NSLock()
  private let logFile: URL?
  private let dateFormatter: ISO8601DateFormatter

  public init(logsRoot: URL? = nil) {
    self.logFile = logsRoot?.appendingPathComponent("hermes-bridge-service.log")
    self.dateFormatter = ISO8601DateFormatter()
  }

  public func log(
    _ event: HermesBridgeServiceLogEvent,
    category: String = "lifecycle",
    protocolVersion: String? = nil,
    correlationID: String? = nil,
    requestID: String? = nil,
    bindingID: String? = nil,
    error: Error? = nil
  ) {
    let record = HermesBridgeServiceLogRecord(
      timestamp: Date(),
      subsystem: "com.hermes.bridge",
      category: safe(category),
      event: event,
      protocolVersion: protocolVersion.map(safe),
      correlationID: correlationID.map(safe),
      requestID: requestID.map(safe),
      bindingID: bindingID.map(safe),
      redactedErrorCode: error.map { Self.safeCode(for: $0) }
    )
    write(record)
  }

  private func write(_ record: HermesBridgeServiceLogRecord) {
    let line =
      [
        "timestamp=\(dateFormatter.string(from: record.timestamp))",
        "subsystem=\(record.subsystem)",
        "category=\(record.category)",
        "event=\(record.event.rawValue)",
        record.protocolVersion.map { "protocol_version=\($0)" },
        record.correlationID.map { "correlation_id=\($0)" },
        record.requestID.map { "request_id=\($0)" },
        record.bindingID.map { "binding_id=\($0)" },
        record.redactedErrorCode.map { "error_code=\($0)" },
      ]
      .compactMap { $0 }
      .joined(separator: " ") + "\n"

    lock.withLock {
      guard let logFile else {
        FileHandle.standardError.write(Data(line.utf8))
        return
      }
      if !FileManager.default.fileExists(atPath: logFile.path) {
        FileManager.default.createFile(atPath: logFile.path, contents: nil)
        chmod(logFile.path, 0o600)
      }
      if let handle = try? FileHandle(forWritingTo: logFile) {
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
        try? handle.close()
      }
    }
  }

  private func safe(_ value: String) -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-")
    }
    return String(filtered.prefix(160))
  }

  private static func safeCode(for error: Error) -> String {
    String(describing: type(of: error))
      .filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == ".") }
      .prefix(96)
      .description
  }
}
