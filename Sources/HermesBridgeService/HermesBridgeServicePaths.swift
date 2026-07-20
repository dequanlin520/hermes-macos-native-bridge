import Darwin
import Foundation

public enum HermesBridgeServicePathsError: Error, Equatable, Sendable {
  case rootIsNotFileURL(String)
  case symbolicLinkRoot(String)
  case rootEscapesThroughSymbolicLink(String)
  case nonDirectoryRoot(String)
  case creationFailed(String)
}

public struct HermesBridgeServicePaths: Equatable, Sendable {
  public let runtimeRoot: URL
  public let requestStateRoot: URL
  public let authorizedRootsRoot: URL
  public let logsRoot: URL
  public let temporaryRoot: URL

  public init(configuration: HermesBridgeServiceConfiguration) throws {
    let base = configuration.runtimeRoot.deletingLastPathComponent()
    self.runtimeRoot = try Self.secureDirectory(configuration.runtimeRoot)
    self.requestStateRoot = try Self.secureDirectory(configuration.requestStateRoot)
    self.authorizedRootsRoot = try Self.secureDirectory(
      base.appendingPathComponent("AuthorizedRoots", isDirectory: true))
    self.logsRoot = try Self.secureDirectory(base.appendingPathComponent("Logs", isDirectory: true))
    self.temporaryRoot = try Self.secureDirectory(
      base.appendingPathComponent("Temporary", isDirectory: true))
  }

  public init(
    runtimeRoot: URL,
    requestStateRoot: URL,
    authorizedRootsRoot: URL? = nil,
    logsRoot: URL,
    temporaryRoot: URL
  ) throws {
    self.runtimeRoot = try Self.secureDirectory(runtimeRoot)
    self.requestStateRoot = try Self.secureDirectory(requestStateRoot)
    self.authorizedRootsRoot = try Self.secureDirectory(
      authorizedRootsRoot
        ?? runtimeRoot.deletingLastPathComponent()
        .appendingPathComponent("AuthorizedRoots", isDirectory: true))
    self.logsRoot = try Self.secureDirectory(logsRoot)
    self.temporaryRoot = try Self.secureDirectory(temporaryRoot)
  }

  private static func secureDirectory(_ url: URL) throws -> URL {
    guard url.isFileURL else {
      throw HermesBridgeServicePathsError.rootIsNotFileURL(redacted(url))
    }
    let standardized = url.standardizedFileURL
    do {
      try FileManager.default.createDirectory(
        at: standardized,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
      )
      try rejectSymlinkComponents(standardized)
      var isDirectory: ObjCBool = false
      guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory)
      else {
        throw HermesBridgeServicePathsError.creationFailed("missing_after_create")
      }
      guard isDirectory.boolValue else {
        throw HermesBridgeServicePathsError.nonDirectoryRoot(redacted(standardized))
      }
      chmod(standardized.path, 0o700)
      return standardized
    } catch let error as HermesBridgeServicePathsError {
      throw error
    } catch {
      throw HermesBridgeServicePathsError.creationFailed(Self.safeCode(for: error))
    }
  }

  private static func rejectSymlinkComponents(_ url: URL) throws {
    var current = URL(fileURLWithPath: "/", isDirectory: true)
    for component in url.pathComponents.dropFirst() {
      current.appendPathComponent(component)
      var statInfo = stat()
      guard lstat(current.path, &statInfo) == 0 else {
        throw HermesBridgeServicePathsError.creationFailed("lstat_failed")
      }
      guard (statInfo.st_mode & S_IFMT) != S_IFLNK else {
        if current.path == url.path {
          throw HermesBridgeServicePathsError.symbolicLinkRoot(redacted(url))
        }
        throw HermesBridgeServicePathsError.rootEscapesThroughSymbolicLink(redacted(url))
      }
    }
  }

  private static func redacted(_ url: URL) -> String {
    "path_hash_\(abs(url.path.hashValue))"
  }

  private static func safeCode(for error: Error) -> String {
    String(describing: type(of: error))
      .filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
  }
}
