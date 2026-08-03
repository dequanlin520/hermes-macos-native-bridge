import CryptoKit
import Darwin
import Foundation

public struct HermesExecutableCandidate: Equatable, Sendable {
  public enum SymlinkStatus: Equatable, Sendable {
    case notSymlink
    case symlink(resolved: Bool)
  }

  public let allowlistedCandidatePath: String
  public let originalPath: String
  public let resolvedPath: String
  public let symlinkStatus: SymlinkStatus
  public let sourceCategory: String

  public init(
    allowlistedCandidatePath: String,
    originalPath: String,
    resolvedPath: String,
    symlinkStatus: SymlinkStatus,
    sourceCategory: String = "explicit"
  ) {
    self.allowlistedCandidatePath = allowlistedCandidatePath
    self.originalPath = originalPath
    self.resolvedPath = resolvedPath
    self.symlinkStatus = symlinkStatus
    self.sourceCategory = Self.safeSourceCategory(sourceCategory)
  }

  private static func safeSourceCategory(_ value: String) -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_")
    }
    return filtered.isEmpty ? "unknown" : String(filtered.prefix(64))
  }
}

public struct HermesVersionInfo: Equatable, Sendable {
  public let semanticVersion: String
  public let displayVersion: String
  public let buildDateText: String?
  public let upstreamRevision: String?
  public let installationMethod: String?
  public let pythonVersion: String?
  public let openAISDKVersion: String?
  public let rawOutputSHA256Digest: String
  public let capturedOutputByteCount: Int
  public let outputWasTruncated: Bool
  public let sanitizedDiagnosticMetadata: [String: String]

  public init(
    semanticVersion: String,
    displayVersion: String,
    buildDateText: String?,
    upstreamRevision: String?,
    installationMethod: String?,
    pythonVersion: String?,
    openAISDKVersion: String?,
    rawOutputSHA256Digest: String,
    capturedOutputByteCount: Int,
    outputWasTruncated: Bool,
    sanitizedDiagnosticMetadata: [String: String]
  ) {
    self.semanticVersion = semanticVersion
    self.displayVersion = displayVersion
    self.buildDateText = buildDateText
    self.upstreamRevision = upstreamRevision
    self.installationMethod = installationMethod
    self.pythonVersion = pythonVersion
    self.openAISDKVersion = openAISDKVersion
    self.rawOutputSHA256Digest = rawOutputSHA256Digest
    self.capturedOutputByteCount = capturedOutputByteCount
    self.outputWasTruncated = outputWasTruncated
    self.sanitizedDiagnosticMetadata = sanitizedDiagnosticMetadata
  }
}

public enum HermesDiscoveryError: Error, Equatable, Sendable {
  case executableNotFound(path: String)
  case pathNotAllowlisted(path: String)
  case executableNotRunnable(path: String)
  case unsafeExecutablePath(path: String)
  case versionCommandFailed(exitCode: Int32)
  case malformedVersionOutput
  case timeout
}

public struct HermesDiscoveryResult: Equatable, Sendable {
  public let candidate: HermesExecutableCandidate
  public let versionInfo: HermesVersionInfo

  public init(candidate: HermesExecutableCandidate, versionInfo: HermesVersionInfo) {
    self.candidate = candidate
    self.versionInfo = versionInfo
  }
}

public final class HermesDiscovery: Sendable {
  private let allowlistedPaths: Set<String>
  private let sourceCategoriesByPath: [String: String]
  private let approvedResolvedPathPrefixes: [String]
  private let currentUserHomePath: String?
  private let currentUserID: uid_t
  private let enforceCurrentUserSafety: Bool
  private let timeoutSeconds: TimeInterval
  private let outputLimitBytes: Int
  private let executor: FixedHermesVersionCommandExecuting

  public convenience init(
    allowlistedExecutableCandidates: [URL],
    sourceCategoriesByCandidatePath: [String: String] = [:],
    approvedResolvedPathPrefixes: [URL] = [],
    currentUserHomeURL: URL? = nil,
    enforceCurrentUserSafety: Bool = false,
    timeoutSeconds: TimeInterval = 5,
    outputLimitBytes: Int = 64 * 1024
  ) {
    self.init(
      allowlistedExecutableCandidates: allowlistedExecutableCandidates,
      sourceCategoriesByCandidatePath: sourceCategoriesByCandidatePath,
      approvedResolvedPathPrefixes: approvedResolvedPathPrefixes,
      currentUserHomeURL: currentUserHomeURL,
      enforceCurrentUserSafety: enforceCurrentUserSafety,
      timeoutSeconds: timeoutSeconds,
      outputLimitBytes: outputLimitBytes,
      executor: FixedHermesVersionCommandExecutor(outputLimitBytes: outputLimitBytes)
    )
  }

  init(
    allowlistedExecutableCandidates: [URL],
    sourceCategoriesByCandidatePath: [String: String] = [:],
    approvedResolvedPathPrefixes: [URL] = [],
    currentUserHomeURL: URL? = nil,
    enforceCurrentUserSafety: Bool = false,
    timeoutSeconds: TimeInterval,
    outputLimitBytes: Int,
    executor: FixedHermesVersionCommandExecuting
  ) {
    self.allowlistedPaths = Set(
      allowlistedExecutableCandidates.map { Self.normalizedPath(for: $0) }
    )
    var categories: [String: String] = [:]
    for (path, category) in sourceCategoriesByCandidatePath {
      categories[Self.normalizedPath(for: URL(fileURLWithPath: path))] = category
    }
    self.sourceCategoriesByPath = categories
    self.approvedResolvedPathPrefixes = approvedResolvedPathPrefixes
      .map { Self.normalizedPath(for: $0) }
      .sorted { $0.count > $1.count }
    self.currentUserHomePath = currentUserHomeURL.map { Self.normalizedPath(for: $0) }
    self.currentUserID = geteuid()
    self.enforceCurrentUserSafety = enforceCurrentUserSafety
    self.timeoutSeconds = timeoutSeconds
    self.outputLimitBytes = outputLimitBytes
    self.executor = executor
  }

  public static func currentUserHomeURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
    if let home = environment["HOME"], !home.isEmpty, home.hasPrefix("/") {
      return URL(fileURLWithPath: home, isDirectory: true).standardizedFileURL
    }
    return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).standardizedFileURL
  }

  public static func approvedProductionResolvedPathPrefixes(
    currentUserHomeURL: URL = currentUserHomeURL()
  ) -> [URL] {
    [
      currentUserHomeURL.appendingPathComponent(".local/bin", isDirectory: true),
      currentUserHomeURL.appendingPathComponent(".hermes", isDirectory: true),
      URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
      URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
    ]
  }

  public static func productionSourceCategoriesByCandidatePath(
    candidates: [URL],
    currentUserHomeURL: URL = currentUserHomeURL()
  ) -> [String: String] {
    var values: [String: String] = [:]
    for candidate in candidates {
      let path = normalizedPath(for: candidate)
      let category: String
      if path == normalizedPath(for: currentUserHomeURL.appendingPathComponent(".local/bin/hermes")) {
        category = "user-local-bin"
      } else if path == "/opt/homebrew/bin/hermes" {
        category = "homebrew"
      } else if path == "/usr/local/bin/hermes" {
        category = "usr-local"
      } else {
        category = "path"
      }
      values[path] = category
    }
    return values
  }

  public func discoverFirstAvailable(candidates: [URL]) throws -> HermesDiscoveryResult {
    var firstRunnableError: HermesDiscoveryError?
    var lastMissingError: HermesDiscoveryError?
    for candidate in candidates {
      do {
        return try discover(at: candidate)
      } catch let error as HermesDiscoveryError {
        switch error {
        case .executableNotFound:
          lastMissingError = error
        default:
          firstRunnableError = firstRunnableError ?? error
        }
        continue
      }
    }
    if let firstRunnableError {
      throw firstRunnableError
    }
    if let lastMissingError {
      throw lastMissingError
    }
    throw HermesDiscoveryError.executableNotFound(path: "none")
  }

  public func discover(at candidateURL: URL) throws -> HermesDiscoveryResult {
    let candidatePath = Self.normalizedPath(for: candidateURL)
    guard allowlistedPaths.contains(candidatePath) else {
      throw HermesDiscoveryError.pathNotAllowlisted(path: candidatePath)
    }

    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: candidatePath, isDirectory: &isDirectory),
      !isDirectory.boolValue
    else {
      throw HermesDiscoveryError.executableNotFound(path: candidatePath)
    }

    guard FileManager.default.isExecutableFile(atPath: candidatePath) else {
      throw HermesDiscoveryError.executableNotRunnable(path: candidatePath)
    }

    let resolvedPath = Self.resolvedPath(for: candidateURL)
    if enforceCurrentUserSafety {
      try validateSafeExecutable(candidatePath: candidatePath, resolvedPath: resolvedPath)
    }

    let candidate = HermesExecutableCandidate(
      allowlistedCandidatePath: candidatePath,
      originalPath: candidatePath,
      resolvedPath: resolvedPath,
      symlinkStatus: Self.symlinkStatus(for: candidateURL),
      sourceCategory: sourceCategoriesByPath[candidatePath] ?? "explicit"
    )

    let output = try executor.runHermesVersion(
      executableURL: URL(fileURLWithPath: candidatePath),
      timeoutSeconds: timeoutSeconds
    )
    let versionInfo = try HermesVersionOutputParser.parse(
      stdout: output.stdout,
      stderr: output.stderr,
      stdoutTruncated: output.stdoutTruncated,
      stderrTruncated: output.stderrTruncated,
      outputLimitBytes: outputLimitBytes
    )

    return HermesDiscoveryResult(candidate: candidate, versionInfo: versionInfo)
  }

  private static func normalizedPath(for url: URL) -> String {
    url.standardizedFileURL.path
  }

  private static func resolvedPath(for url: URL) -> String {
    url.standardizedFileURL.resolvingSymlinksInPath().path
  }

  private static func symlinkStatus(for url: URL) -> HermesExecutableCandidate.SymlinkStatus {
    do {
      _ = try FileManager.default.destinationOfSymbolicLink(atPath: normalizedPath(for: url))
      return .symlink(resolved: FileManager.default.fileExists(atPath: resolvedPath(for: url)))
    } catch {
      return .notSymlink
    }
  }

  private func validateSafeExecutable(candidatePath: String, resolvedPath: String) throws {
    guard !candidatePath.contains("\u{0}"), !resolvedPath.contains("\u{0}"),
      Self.pathIsInsideApprovedPrefix(candidatePath, prefixes: approvedResolvedPathPrefixes),
      Self.pathIsInsideApprovedPrefix(resolvedPath, prefixes: approvedResolvedPathPrefixes),
      Self.candidateIsRegularExecutableOrSymlinkToRegularExecutable(path: candidatePath),
      FileManager.default.isReadableFile(atPath: resolvedPath)
    else {
      throw HermesDiscoveryError.unsafeExecutablePath(path: candidatePath)
    }
    if let home = currentUserHomePath,
      (Self.pathIsInside(candidatePath, prefix: home) || Self.pathIsInside(resolvedPath, prefix: home))
    {
      guard Self.pathIsInside(candidatePath, prefix: home),
        Self.pathIsInside(resolvedPath, prefix: home)
      else {
        throw HermesDiscoveryError.unsafeExecutablePath(path: candidatePath)
      }
      guard Self.ownerUID(path: resolvedPath) == currentUserID else {
        throw HermesDiscoveryError.unsafeExecutablePath(path: candidatePath)
      }
    }
    guard !Self.hasWorldWritableParent(path: candidatePath),
      !Self.hasWorldWritableParent(path: resolvedPath)
    else {
      throw HermesDiscoveryError.unsafeExecutablePath(path: candidatePath)
    }
  }

  private static func pathIsInsideApprovedPrefix(_ path: String, prefixes: [String]) -> Bool {
    prefixes.contains { pathIsInside(path, prefix: $0) }
  }

  private static func pathIsInside(_ path: String, prefix: String) -> Bool {
    path == prefix || path.hasPrefix(prefix.hasSuffix("/") ? prefix : "\(prefix)/")
  }

  private static func ownerUID(path: String) -> uid_t? {
    var info = stat()
    guard lstat(path, &info) == 0 else { return nil }
    return info.st_uid
  }

  private static func candidateIsRegularExecutableOrSymlinkToRegularExecutable(path: String) -> Bool {
    var candidateInfo = stat()
    guard lstat(path, &candidateInfo) == 0 else { return false }
    let candidateMode = candidateInfo.st_mode & S_IFMT
    guard candidateMode == S_IFREG || candidateMode == S_IFLNK else { return false }

    var resolvedInfo = stat()
    guard stat(path, &resolvedInfo) == 0 else { return false }
    return resolvedInfo.st_mode & S_IFMT == S_IFREG
  }

  private static func hasWorldWritableParent(path: String) -> Bool {
    var url = URL(fileURLWithPath: path).deletingLastPathComponent()
    while url.path != "/" {
      var info = stat()
      if lstat(url.path, &info) == 0, (info.st_mode & S_IWOTH) != 0 {
        return true
      }
      url.deleteLastPathComponent()
    }
    return false
  }
}

protocol FixedHermesVersionCommandExecuting: Sendable {
  func runHermesVersion(
    executableURL: URL,
    timeoutSeconds: TimeInterval
  ) throws -> FixedHermesVersionCommandOutput
}

struct FixedHermesVersionCommandOutput: Equatable, Sendable {
  let stdout: Data
  let stderr: Data
  let stdoutTruncated: Bool
  let stderrTruncated: Bool
}

private final class FixedHermesVersionCommandExecutor: FixedHermesVersionCommandExecuting,
  @unchecked Sendable
{
  private let outputLimitBytes: Int

  init(outputLimitBytes: Int) {
    self.outputLimitBytes = max(1, outputLimitBytes)
  }

  func runHermesVersion(
    executableURL: URL,
    timeoutSeconds: TimeInterval
  ) throws -> FixedHermesVersionCommandOutput {
    let process = Process()
    process.executableURL = executableURL
    process.arguments = ["--version"]

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    let stdoutCapture = BoundedPipeCapture(limitBytes: outputLimitBytes)
    let stderrCapture = BoundedPipeCapture(limitBytes: outputLimitBytes)
    stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
      stdoutCapture.append(handle.availableData)
    }
    stderrPipe.fileHandleForReading.readabilityHandler = { handle in
      stderrCapture.append(handle.availableData)
    }

    let termination = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in
      termination.signal()
    }

    do {
      try process.run()
    } catch {
      stdoutPipe.fileHandleForReading.readabilityHandler = nil
      stderrPipe.fileHandleForReading.readabilityHandler = nil
      throw HermesDiscoveryError.executableNotRunnable(path: executableURL.path)
    }

    let deadline = DispatchTime.now() + timeoutSeconds
    guard termination.wait(timeout: deadline) == .success else {
      process.terminate()
      _ = termination.wait(timeout: .now() + 1)
      if process.isRunning {
        kill(process.processIdentifier, SIGKILL)
      }
      stdoutPipe.fileHandleForReading.readabilityHandler = nil
      stderrPipe.fileHandleForReading.readabilityHandler = nil
      throw HermesDiscoveryError.timeout
    }

    stdoutPipe.fileHandleForReading.readabilityHandler = nil
    stderrPipe.fileHandleForReading.readabilityHandler = nil
    stdoutCapture.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
    stderrCapture.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())

    guard process.terminationStatus == 0 else {
      throw HermesDiscoveryError.versionCommandFailed(exitCode: process.terminationStatus)
    }

    return FixedHermesVersionCommandOutput(
      stdout: stdoutCapture.data,
      stderr: stderrCapture.data,
      stdoutTruncated: stdoutCapture.wasTruncated,
      stderrTruncated: stderrCapture.wasTruncated
    )
  }
}

private final class BoundedPipeCapture: @unchecked Sendable {
  private let lock = NSLock()
  private let limitBytes: Int
  private var storage = Data()
  private var truncated = false

  init(limitBytes: Int) {
    self.limitBytes = max(1, limitBytes)
  }

  var data: Data {
    lock.withLock { storage }
  }

  var wasTruncated: Bool {
    lock.withLock { truncated }
  }

  func append(_ data: Data) {
    guard !data.isEmpty else {
      return
    }

    lock.withLock {
      let remaining = limitBytes - storage.count
      if remaining > 0 {
        storage.append(data.prefix(remaining))
      }
      if data.count > remaining {
        truncated = true
      }
    }
  }
}

private enum HermesVersionOutputParser {
  static func parse(
    stdout: Data,
    stderr: Data,
    stdoutTruncated: Bool,
    stderrTruncated: Bool,
    outputLimitBytes: Int
  ) throws -> HermesVersionInfo {
    let combined = stdout + stderr
    let digest = SHA256.hash(data: combined)
      .map { String(format: "%02x", $0) }
      .joined()

    guard let stdoutText = String(data: stdout, encoding: .utf8) else {
      throw HermesDiscoveryError.malformedVersionOutput
    }

    let lines =
      stdoutText
      .split(whereSeparator: \.isNewline)
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    guard let firstLine = lines.first,
      let header = parseHeader(firstLine)
    else {
      throw HermesDiscoveryError.malformedVersionOutput
    }

    let metadata = parseMetadata(from: lines.dropFirst())

    return HermesVersionInfo(
      semanticVersion: header.semanticVersion,
      displayVersion: header.displayVersion,
      buildDateText: header.buildDateText,
      upstreamRevision: metadata["upstream"] ?? metadata["upstream revision"],
      installationMethod: metadata["install method"] ?? metadata["installation method"],
      pythonVersion: metadata["python"],
      openAISDKVersion: metadata["openai sdk"] ?? metadata["openai"],
      rawOutputSHA256Digest: digest,
      capturedOutputByteCount: min(combined.count, outputLimitBytes * 2),
      outputWasTruncated: stdoutTruncated || stderrTruncated,
      sanitizedDiagnosticMetadata: [
        "stdoutTruncated": String(stdoutTruncated),
        "stderrTruncated": String(stderrTruncated),
        "stderrCaptured": String(!stderr.isEmpty),
      ]
    )
  }

  private static func parseHeader(
    _ line: String
  ) -> (semanticVersion: String, displayVersion: String, buildDateText: String?)? {
    let pattern = #"^Hermes Agent v([0-9]+(?:\.[0-9]+){1,3})(?:\s+\(([^)]+)\))?(?:\s+.*)?$"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(
        in: line,
        range: NSRange(line.startIndex..., in: line)
      ),
      let semanticVersionRange = Range(match.range(at: 1), in: line)
    else {
      return nil
    }

    let buildDateText: String?
    if match.range(at: 2).location != NSNotFound,
      let buildDateRange = Range(match.range(at: 2), in: line)
    {
      buildDateText = String(line[buildDateRange])
    } else {
      buildDateText = nil
    }

    let semanticVersion = String(line[semanticVersionRange])
    return (
      semanticVersion: semanticVersion,
      displayVersion: line,
      buildDateText: buildDateText
    )
  }

  private static func parseMetadata<S: Sequence>(from lines: S) -> [String: String]
  where S.Element == String {
    var metadata: [String: String] = [:]
    for line in lines {
      let separators = [":", "="]
      guard let separator = separators.compactMap({ line.range(of: $0) }).first else {
        continue
      }
      let key = line[..<separator.lowerBound]
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
      let value = line[separator.upperBound...]
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !key.isEmpty, !value.isEmpty else {
        continue
      }
      metadata[key] = value
    }
    return metadata
  }
}
