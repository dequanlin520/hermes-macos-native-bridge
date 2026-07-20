import CoreServices
import Darwin
import Foundation
import Security

public struct HermesAuthorizedRootID: Codable, Equatable, Hashable, Sendable,
  CustomStringConvertible
{
  public static let prefix = "hroot_"
  public static let encodedRandomLength = 43
  public static let maximumLength = prefix.count + encodedRandomLength

  public let rawValue: String

  public static func generate() throws -> HermesAuthorizedRootID {
    var bytes = [UInt8](repeating: 0, count: 32)
    let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    guard result == errSecSuccess else {
      throw HermesAuthorizedRootRegistryError.identifierGenerationFailed
    }
    return try HermesAuthorizedRootID(rawValue: prefix + Data(bytes).hermesBase64URLEncodedString())
  }

  public init(rawValue: String) throws {
    guard Self.isValid(rawValue) else {
      throw HermesAuthorizedRootRegistryError.invalidRootID
    }
    self.rawValue = rawValue
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    try self.init(rawValue: container.decode(String.self))
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  public var description: String {
    rawValue
  }

  static func isValid(_ value: String) -> Bool {
    guard value.count == maximumLength, value.hasPrefix(prefix) else {
      return false
    }
    return value.dropFirst(prefix.count).allSatisfy { character in
      character.isASCII
        && (character.isLetter || character.isNumber || character == "-" || character == "_")
    }
  }
}

public enum HermesAuthorizedRootState: String, Codable, Equatable, Sendable {
  case active
  case inactive
}

public struct HermesAuthorizedRootPolicy: Equatable, Sendable {
  public let permittedRootParents: [URL]

  public init(permittedRootParents: [URL]) {
    self.permittedRootParents = permittedRootParents.map {
      $0.standardizedFileURL.resolvingSymlinksInPath()
    }
  }

  public func permits(_ resolvedRootURL: URL) -> Bool {
    guard !permittedRootParents.isEmpty else {
      return true
    }
    let rootPath = resolvedRootURL.standardizedFileURL.resolvingSymlinksInPath().path
    return permittedRootParents.contains { parent in
      let parentPath = parent.standardizedFileURL.resolvingSymlinksInPath().path
      return rootPath == parentPath || rootPath.hasPrefix(parentPath + "/")
    }
  }
}

public enum HermesBookmarkAuthorizationStatus: Equatable, Sendable {
  case resolved
  case resolvedStale
  case securityScopeStarted
  case securityScopeUnavailable
  case rejected(HermesAuthorizedRootRegistryError)
}

public struct HermesBookmarkAuthorizationResolution: Equatable, Sendable {
  public let status: HermesBookmarkAuthorizationStatus
  public let resolvedURL: URL?
  public let bookmarkDataIsStale: Bool
  public let securityScopedAccessStarted: Bool

  public init(
    status: HermesBookmarkAuthorizationStatus,
    resolvedURL: URL?,
    bookmarkDataIsStale: Bool,
    securityScopedAccessStarted: Bool
  ) {
    self.status = status
    self.resolvedURL = resolvedURL
    self.bookmarkDataIsStale = bookmarkDataIsStale
    self.securityScopedAccessStarted = securityScopedAccessStarted
  }
}

public struct HermesAuthorizedRootRecord: Codable, Equatable, Sendable,
  CustomStringConvertible
{
  public static let currentSchemaVersion = 1
  public static let maximumDisplayNameCharacters = 120
  public static let maximumBookmarkBytes = 256 * 1024

  public let schemaVersion: Int
  public let rootID: HermesAuthorizedRootID
  public let displayName: String
  public let resolvedRootURL: URL
  public let bookmarkData: Data
  public let bookmarkCreatedAt: Date
  public let bookmarkUpdatedAt: Date
  public let bookmarkDataIsStale: Bool
  public let state: HermesAuthorizedRootState
  public let lastObservedFSEventID: UInt64
  public let revision: Int

  public init(
    schemaVersion: Int = currentSchemaVersion,
    rootID: HermesAuthorizedRootID,
    displayName: String,
    resolvedRootURL: URL,
    bookmarkData: Data,
    bookmarkCreatedAt: Date,
    bookmarkUpdatedAt: Date,
    bookmarkDataIsStale: Bool = false,
    state: HermesAuthorizedRootState = .active,
    lastObservedFSEventID: UInt64 = 0,
    revision: Int = 0
  ) throws {
    guard schemaVersion == Self.currentSchemaVersion else {
      throw HermesAuthorizedRootRegistryError.unsupportedSchemaVersion(schemaVersion)
    }
    guard revision >= 0 else {
      throw HermesAuthorizedRootRegistryError.corruptRecord(rootID: rootID)
    }
    guard !bookmarkData.isEmpty, bookmarkData.count <= Self.maximumBookmarkBytes else {
      throw HermesAuthorizedRootRegistryError.bookmarkTooLarge(
        maximumBytes: Self.maximumBookmarkBytes)
    }
    self.schemaVersion = schemaVersion
    self.rootID = rootID
    self.displayName = Self.safeDisplayName(displayName)
    self.resolvedRootURL = resolvedRootURL.standardizedFileURL.resolvingSymlinksInPath()
    self.bookmarkData = bookmarkData
    self.bookmarkCreatedAt = bookmarkCreatedAt
    self.bookmarkUpdatedAt = bookmarkUpdatedAt
    self.bookmarkDataIsStale = bookmarkDataIsStale
    self.state = state
    self.lastObservedFSEventID = lastObservedFSEventID
    self.revision = revision
  }

  public var description: String {
    "HermesAuthorizedRootRecord(rootID: \(rootID), displayName: \(displayName), state: \(state.rawValue), stale: \(bookmarkDataIsStale), revision: \(revision))"
  }

  static func safeDisplayName(_ value: String) -> String {
    let filtered = value.unicodeScalars.filter { scalar in
      scalar.value >= 0x20 && scalar.value != 0x7F
    }
    let text = String(String.UnicodeScalarView(filtered)).trimmingCharacters(in: .whitespaces)
    return String((text.isEmpty ? "Authorized Root" : text).prefix(maximumDisplayNameCharacters))
  }
}

public enum HermesAuthorizedRootRegistryError: Error, Equatable, Sendable,
  CustomStringConvertible
{
  case identifierGenerationFailed
  case invalidRootID
  case unknownRoot(HermesAuthorizedRootID)
  case duplicateResolvedRoot
  case inactiveRoot(HermesAuthorizedRootID)
  case revisionConflict(expected: Int, actual: Int)
  case unsupportedSchemaVersion(Int)
  case corruptRecord(rootID: HermesAuthorizedRootID?)
  case storageRootInvalid(String)
  case storageBoundaryViolation
  case rootLimitExceeded(maximum: Int)
  case bookmarkTooLarge(maximumBytes: Int)
  case recordTooLarge(maximumBytes: Int)
  case bookmarkResolutionFailed
  case rejectedFilesystemRoot
  case rejectedHomeRoot
  case rejectedNonDirectory
  case rejectedSymlinkRoot
  case rejectedOutsidePolicy
  case rejectedPathTraversal
  case rejectedPathEscape
  case persistenceFailed(String)

  public var description: String {
    switch self {
    case .identifierGenerationFailed:
      return "failed to generate Hermes authorized-root identifier"
    case .invalidRootID:
      return "invalid Hermes authorized-root identifier"
    case .unknownRoot(let rootID):
      return "unknown Hermes authorized root \(rootID)"
    case .duplicateResolvedRoot:
      return "duplicate Hermes authorized resolved root"
    case .inactiveRoot(let rootID):
      return "inactive Hermes authorized root \(rootID)"
    case .revisionConflict(let expected, let actual):
      return "Hermes authorized-root revision conflict expected \(expected), actual \(actual)"
    case .unsupportedSchemaVersion(let version):
      return "unsupported Hermes authorized-root schema version \(version)"
    case .corruptRecord:
      return "corrupt Hermes authorized-root record"
    case .storageRootInvalid(let reason):
      return "invalid Hermes authorized-root storage root: \(reason)"
    case .storageBoundaryViolation:
      return "Hermes authorized-root storage boundary violation"
    case .rootLimitExceeded(let maximum):
      return "Hermes authorized-root limit exceeded: \(maximum)"
    case .bookmarkTooLarge(let maximumBytes):
      return "Hermes authorized-root bookmark exceeds \(maximumBytes) bytes"
    case .recordTooLarge(let maximumBytes):
      return "Hermes authorized-root record exceeds \(maximumBytes) bytes"
    case .bookmarkResolutionFailed:
      return "Hermes authorized-root bookmark resolution failed"
    case .rejectedFilesystemRoot:
      return "Hermes authorized root may not be filesystem root"
    case .rejectedHomeRoot:
      return "Hermes authorized root may not be the whole home directory"
    case .rejectedNonDirectory:
      return "Hermes authorized root must be a directory"
    case .rejectedSymlinkRoot:
      return "Hermes authorized root may not be a symbolic link"
    case .rejectedOutsidePolicy:
      return "Hermes authorized root is outside configured policy"
    case .rejectedPathTraversal:
      return "Hermes authorized-root relative path contains traversal"
    case .rejectedPathEscape:
      return "Hermes authorized-root path escape rejected"
    case .persistenceFailed(let reason):
      return "Hermes authorized-root persistence failed: \(reason)"
    }
  }
}

public protocol HermesAuthorizedRootRegistry: Sendable {
  @discardableResult
  func registerBookmark(
    displayName: String,
    bookmarkData: Data,
    createdAt: Date
  ) async throws -> HermesAuthorizedRootRecord

  func resolveRoot(_ rootID: HermesAuthorizedRootID) async throws
    -> HermesBookmarkAuthorizationResolution

  func readRoot(_ rootID: HermesAuthorizedRootID) async throws -> HermesAuthorizedRootRecord

  func listRoots() async throws -> [HermesAuthorizedRootRecord]

  @discardableResult
  func deactivateRoot(
    _ rootID: HermesAuthorizedRootID,
    expectedRevision: Int?,
    updatedAt: Date
  ) async throws -> HermesAuthorizedRootRecord

  @discardableResult
  func reactivateRoot(
    _ rootID: HermesAuthorizedRootID,
    freshBookmarkData: Data,
    expectedRevision: Int?,
    updatedAt: Date
  ) async throws -> HermesAuthorizedRootRecord

  @discardableResult
  func updateEventCursor(
    _ rootID: HermesAuthorizedRootID,
    eventID: UInt64,
    expectedRevision: Int?
  ) async throws -> HermesAuthorizedRootRecord

  @discardableResult
  func markStale(
    _ rootID: HermesAuthorizedRootID,
    expectedRevision: Int?,
    updatedAt: Date
  ) async throws -> HermesAuthorizedRootRecord

  func removeRoot(_ rootID: HermesAuthorizedRootID, expectedRevision: Int?) async throws
}

public actor InMemoryHermesAuthorizedRootRegistry: HermesAuthorizedRootRegistry {
  private var records: [HermesAuthorizedRootID: HermesAuthorizedRootRecord] = [:]
  private let policy: HermesAuthorizedRootPolicy
  private let maximumRoots: Int

  public init(
    policy: HermesAuthorizedRootPolicy,
    maximumRoots: Int = 128
  ) {
    self.policy = policy
    self.maximumRoots = max(1, maximumRoots)
  }

  public func registerBookmark(
    displayName: String,
    bookmarkData: Data,
    createdAt: Date = Date()
  ) async throws -> HermesAuthorizedRootRecord {
    guard records.count < maximumRoots else {
      throw HermesAuthorizedRootRegistryError.rootLimitExceeded(maximum: maximumRoots)
    }
    let resolution = try Self.resolveBookmarkData(bookmarkData, policy: policy)
    if records.values.contains(where: { $0.resolvedRootURL.path == resolution.url.path }) {
      throw HermesAuthorizedRootRegistryError.duplicateResolvedRoot
    }
    let record = try HermesAuthorizedRootRecord(
      rootID: HermesAuthorizedRootID.generate(),
      displayName: displayName,
      resolvedRootURL: resolution.url,
      bookmarkData: bookmarkData,
      bookmarkCreatedAt: createdAt,
      bookmarkUpdatedAt: createdAt,
      bookmarkDataIsStale: resolution.stale
    )
    records[record.rootID] = record
    return record
  }

  public func resolveRoot(_ rootID: HermesAuthorizedRootID) async throws
    -> HermesBookmarkAuthorizationResolution
  {
    let record = try await readRoot(rootID)
    guard record.state == .active else {
      throw HermesAuthorizedRootRegistryError.inactiveRoot(rootID)
    }
    return Self.authorizationResolution(
      bookmarkData: record.bookmarkData,
      policy: policy,
      allowSecurityScope: true
    )
  }

  public func readRoot(_ rootID: HermesAuthorizedRootID) async throws -> HermesAuthorizedRootRecord
  {
    guard let record = records[rootID] else {
      throw HermesAuthorizedRootRegistryError.unknownRoot(rootID)
    }
    return record
  }

  public func listRoots() async throws -> [HermesAuthorizedRootRecord] {
    records.values.sorted {
      $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
    }
  }

  public func deactivateRoot(
    _ rootID: HermesAuthorizedRootID,
    expectedRevision: Int? = nil,
    updatedAt: Date = Date()
  ) async throws -> HermesAuthorizedRootRecord {
    try mutate(rootID, expectedRevision: expectedRevision) {
      try Self.next($0, bookmarkUpdatedAt: updatedAt, state: .inactive)
    }
  }

  public func reactivateRoot(
    _ rootID: HermesAuthorizedRootID,
    freshBookmarkData: Data,
    expectedRevision: Int? = nil,
    updatedAt: Date = Date()
  ) async throws -> HermesAuthorizedRootRecord {
    let resolution = try Self.resolveBookmarkData(freshBookmarkData, policy: policy)
    return try mutate(rootID, expectedRevision: expectedRevision) { record in
      guard record.resolvedRootURL.path == resolution.url.path else {
        throw HermesAuthorizedRootRegistryError.rejectedOutsidePolicy
      }
      return try Self.next(
        record,
        bookmarkData: freshBookmarkData,
        bookmarkUpdatedAt: updatedAt,
        bookmarkDataIsStale: resolution.stale,
        state: .active
      )
    }
  }

  public func updateEventCursor(
    _ rootID: HermesAuthorizedRootID,
    eventID: UInt64,
    expectedRevision: Int? = nil
  ) async throws -> HermesAuthorizedRootRecord {
    try mutate(rootID, expectedRevision: expectedRevision) {
      guard eventID >= $0.lastObservedFSEventID else {
        return $0
      }
      return try Self.next($0, lastObservedFSEventID: eventID)
    }
  }

  public func markStale(
    _ rootID: HermesAuthorizedRootID,
    expectedRevision: Int? = nil,
    updatedAt: Date = Date()
  ) async throws -> HermesAuthorizedRootRecord {
    try mutate(rootID, expectedRevision: expectedRevision) {
      try Self.next($0, bookmarkUpdatedAt: updatedAt, bookmarkDataIsStale: true)
    }
  }

  public func removeRoot(_ rootID: HermesAuthorizedRootID, expectedRevision: Int? = nil)
    async throws
  {
    let record = try await readRoot(rootID)
    if let expectedRevision, expectedRevision != record.revision {
      throw HermesAuthorizedRootRegistryError.revisionConflict(
        expected: expectedRevision,
        actual: record.revision
      )
    }
    records.removeValue(forKey: rootID)
  }

  fileprivate func mutate(
    _ rootID: HermesAuthorizedRootID,
    expectedRevision: Int?,
    _ body: (HermesAuthorizedRootRecord) throws -> HermesAuthorizedRootRecord
  ) throws -> HermesAuthorizedRootRecord {
    guard let record = records[rootID] else {
      throw HermesAuthorizedRootRegistryError.unknownRoot(rootID)
    }
    if let expectedRevision, expectedRevision != record.revision {
      throw HermesAuthorizedRootRegistryError.revisionConflict(
        expected: expectedRevision,
        actual: record.revision
      )
    }
    let updated = try body(record)
    records[rootID] = updated
    return updated
  }

  fileprivate static func next(
    _ record: HermesAuthorizedRootRecord,
    bookmarkData: Data? = nil,
    bookmarkUpdatedAt: Date? = nil,
    bookmarkDataIsStale: Bool? = nil,
    state: HermesAuthorizedRootState? = nil,
    lastObservedFSEventID: UInt64? = nil
  ) throws -> HermesAuthorizedRootRecord {
    try HermesAuthorizedRootRecord(
      rootID: record.rootID,
      displayName: record.displayName,
      resolvedRootURL: record.resolvedRootURL,
      bookmarkData: bookmarkData ?? record.bookmarkData,
      bookmarkCreatedAt: record.bookmarkCreatedAt,
      bookmarkUpdatedAt: bookmarkUpdatedAt ?? record.bookmarkUpdatedAt,
      bookmarkDataIsStale: bookmarkDataIsStale ?? record.bookmarkDataIsStale,
      state: state ?? record.state,
      lastObservedFSEventID: lastObservedFSEventID ?? record.lastObservedFSEventID,
      revision: record.revision + 1
    )
  }

  fileprivate static func authorizationResolution(
    bookmarkData: Data,
    policy: HermesAuthorizedRootPolicy,
    allowSecurityScope: Bool
  ) -> HermesBookmarkAuthorizationResolution {
    do {
      let resolved = try resolveBookmarkData(bookmarkData, policy: policy)
      if allowSecurityScope, resolved.url.startAccessingSecurityScopedResource() {
        resolved.url.stopAccessingSecurityScopedResource()
        return HermesBookmarkAuthorizationResolution(
          status: .securityScopeStarted,
          resolvedURL: resolved.url,
          bookmarkDataIsStale: resolved.stale,
          securityScopedAccessStarted: true
        )
      }
      return HermesBookmarkAuthorizationResolution(
        status: resolved.stale ? .resolvedStale : .securityScopeUnavailable,
        resolvedURL: resolved.url,
        bookmarkDataIsStale: resolved.stale,
        securityScopedAccessStarted: false
      )
    } catch let error as HermesAuthorizedRootRegistryError {
      return HermesBookmarkAuthorizationResolution(
        status: .rejected(error),
        resolvedURL: nil,
        bookmarkDataIsStale: false,
        securityScopedAccessStarted: false
      )
    } catch {
      return HermesBookmarkAuthorizationResolution(
        status: .rejected(.bookmarkResolutionFailed),
        resolvedURL: nil,
        bookmarkDataIsStale: false,
        securityScopedAccessStarted: false
      )
    }
  }

  fileprivate static func resolveBookmarkData(
    _ bookmarkData: Data,
    policy: HermesAuthorizedRootPolicy
  ) throws -> (url: URL, stale: Bool) {
    guard !bookmarkData.isEmpty,
      bookmarkData.count <= HermesAuthorizedRootRecord.maximumBookmarkBytes
    else {
      throw HermesAuthorizedRootRegistryError.bookmarkTooLarge(
        maximumBytes: HermesAuthorizedRootRecord.maximumBookmarkBytes)
    }

    var stale = false
    let url: URL
    do {
      url = try URL(
        resolvingBookmarkData: bookmarkData,
        options: [.withSecurityScope, .withoutUI],
        relativeTo: nil,
        bookmarkDataIsStale: &stale
      )
    } catch {
      do {
        url = try URL(
          resolvingBookmarkData: bookmarkData,
          options: [.withoutUI],
          relativeTo: nil,
          bookmarkDataIsStale: &stale
        )
      } catch {
        throw HermesAuthorizedRootRegistryError.bookmarkResolutionFailed
      }
    }
    let resolved = try validateResolvedRoot(url, policy: policy)
    return (resolved, stale)
  }

  fileprivate static func validateResolvedRoot(
    _ url: URL,
    policy: HermesAuthorizedRootPolicy
  ) throws -> URL {
    let standardized = url.standardizedFileURL
    if HermesPathSecurity.isSymlink(standardized.path) {
      throw HermesAuthorizedRootRegistryError.rejectedSymlinkRoot
    }
    let resolved = standardized.resolvingSymlinksInPath()
    let path = resolved.path
    if path == "/" {
      throw HermesAuthorizedRootRegistryError.rejectedFilesystemRoot
    }
    if path
      == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
      .resolvingSymlinksInPath().path
    {
      throw HermesAuthorizedRootRegistryError.rejectedHomeRoot
    }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      throw HermesAuthorizedRootRegistryError.rejectedNonDirectory
    }
    guard policy.permits(resolved) else {
      throw HermesAuthorizedRootRegistryError.rejectedOutsidePolicy
    }
    return resolved
  }
}

public actor FileBackedHermesAuthorizedRootRegistry: HermesAuthorizedRootRegistry {
  private let root: URL
  private let policy: HermesAuthorizedRootPolicy
  private let maximumRoots: Int
  private let maximumRecordBytes: Int
  private let fileManager: FileManager
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(
    registryRoot: URL,
    policy: HermesAuthorizedRootPolicy,
    maximumRoots: Int = 128,
    maximumRecordBytes: Int = 512 * 1024,
    fileManager: FileManager = .default
  ) throws {
    self.root = registryRoot.standardizedFileURL
    self.policy = policy
    self.maximumRoots = max(1, maximumRoots)
    self.maximumRecordBytes = max(2048, maximumRecordBytes)
    self.fileManager = fileManager
    self.encoder = JSONEncoder()
    self.decoder = JSONDecoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    decoder.dateDecodingStrategy = .iso8601
    try Self.secureStorageRoot(root, fileManager: fileManager)
  }

  public func registerBookmark(
    displayName: String,
    bookmarkData: Data,
    createdAt: Date = Date()
  ) async throws -> HermesAuthorizedRootRecord {
    try rejectEscapingRecordPaths()
    guard try recordFileURLs().count < maximumRoots else {
      throw HermesAuthorizedRootRegistryError.rootLimitExceeded(maximum: maximumRoots)
    }
    let resolution = try InMemoryHermesAuthorizedRootRegistry.resolveBookmarkData(
      bookmarkData,
      policy: policy
    )
    let existing = try recordFileURLs().map { try readRecord(at: $0) }
    if existing.contains(where: { $0.resolvedRootURL.path == resolution.url.path }) {
      throw HermesAuthorizedRootRegistryError.duplicateResolvedRoot
    }
    let record = try HermesAuthorizedRootRecord(
      rootID: HermesAuthorizedRootID.generate(),
      displayName: displayName,
      resolvedRootURL: resolution.url,
      bookmarkData: bookmarkData,
      bookmarkCreatedAt: createdAt,
      bookmarkUpdatedAt: createdAt,
      bookmarkDataIsStale: resolution.stale
    )
    try persist(record)
    return record
  }

  public func resolveRoot(_ rootID: HermesAuthorizedRootID) async throws
    -> HermesBookmarkAuthorizationResolution
  {
    let record = try await readRoot(rootID)
    guard record.state == .active else {
      throw HermesAuthorizedRootRegistryError.inactiveRoot(rootID)
    }
    return InMemoryHermesAuthorizedRootRegistry.authorizationResolution(
      bookmarkData: record.bookmarkData,
      policy: policy,
      allowSecurityScope: true
    )
  }

  public func readRoot(_ rootID: HermesAuthorizedRootID) async throws -> HermesAuthorizedRootRecord
  {
    try readExistingRecord(rootID)
  }

  public func listRoots() async throws -> [HermesAuthorizedRootRecord] {
    try recordFileURLs()
      .map { try readRecord(at: $0) }
      .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
  }

  public func deactivateRoot(
    _ rootID: HermesAuthorizedRootID,
    expectedRevision: Int? = nil,
    updatedAt: Date = Date()
  ) async throws -> HermesAuthorizedRootRecord {
    try mutate(rootID, expectedRevision: expectedRevision) {
      try InMemoryHermesAuthorizedRootRegistry.next(
        $0,
        bookmarkUpdatedAt: updatedAt,
        state: .inactive
      )
    }
  }

  public func reactivateRoot(
    _ rootID: HermesAuthorizedRootID,
    freshBookmarkData: Data,
    expectedRevision: Int? = nil,
    updatedAt: Date = Date()
  ) async throws -> HermesAuthorizedRootRecord {
    let resolution = try InMemoryHermesAuthorizedRootRegistry.resolveBookmarkData(
      freshBookmarkData,
      policy: policy
    )
    return try mutate(rootID, expectedRevision: expectedRevision) { record in
      guard record.resolvedRootURL.path == resolution.url.path else {
        throw HermesAuthorizedRootRegistryError.rejectedOutsidePolicy
      }
      return try InMemoryHermesAuthorizedRootRegistry.next(
        record,
        bookmarkData: freshBookmarkData,
        bookmarkUpdatedAt: updatedAt,
        bookmarkDataIsStale: resolution.stale,
        state: .active
      )
    }
  }

  public func updateEventCursor(
    _ rootID: HermesAuthorizedRootID,
    eventID: UInt64,
    expectedRevision: Int? = nil
  ) async throws -> HermesAuthorizedRootRecord {
    try mutate(rootID, expectedRevision: expectedRevision) {
      guard eventID >= $0.lastObservedFSEventID else {
        return $0
      }
      return try InMemoryHermesAuthorizedRootRegistry.next($0, lastObservedFSEventID: eventID)
    }
  }

  public func markStale(
    _ rootID: HermesAuthorizedRootID,
    expectedRevision: Int? = nil,
    updatedAt: Date = Date()
  ) async throws -> HermesAuthorizedRootRecord {
    try mutate(rootID, expectedRevision: expectedRevision) {
      try InMemoryHermesAuthorizedRootRegistry.next(
        $0,
        bookmarkUpdatedAt: updatedAt,
        bookmarkDataIsStale: true
      )
    }
  }

  public func removeRoot(_ rootID: HermesAuthorizedRootID, expectedRevision: Int? = nil)
    async throws
  {
    let record = try await readRoot(rootID)
    if let expectedRevision, expectedRevision != record.revision {
      throw HermesAuthorizedRootRegistryError.revisionConflict(
        expected: expectedRevision,
        actual: record.revision
      )
    }
    try fileManager.removeItem(at: recordURL(for: rootID))
    fsyncDirectory(root)
  }

  private func mutate(
    _ rootID: HermesAuthorizedRootID,
    expectedRevision: Int?,
    _ body: (HermesAuthorizedRootRecord) throws -> HermesAuthorizedRootRecord
  ) throws -> HermesAuthorizedRootRecord {
    let record = try readExistingRecord(rootID)
    if let expectedRevision, expectedRevision != record.revision {
      throw HermesAuthorizedRootRegistryError.revisionConflict(
        expected: expectedRevision,
        actual: record.revision
      )
    }
    let updated = try body(record)
    if updated == record {
      return updated
    }
    try persist(updated)
    return updated
  }

  private static func secureStorageRoot(_ root: URL, fileManager: FileManager) throws {
    let path = root.path
    if isSymlink(path) {
      throw HermesAuthorizedRootRegistryError.storageRootInvalid("root is a symbolic link")
    }
    var isDirectory: ObjCBool = false
    if fileManager.fileExists(atPath: path, isDirectory: &isDirectory) {
      guard isDirectory.boolValue else {
        throw HermesAuthorizedRootRegistryError.storageRootInvalid("root is a file")
      }
    } else {
      try fileManager.createDirectory(
        at: root,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
    }
    chmod(path, 0o700)
    if isSymlink(path) {
      throw HermesAuthorizedRootRegistryError.storageRootInvalid("root became a symbolic link")
    }
  }

  private func readExistingRecord(_ rootID: HermesAuthorizedRootID) throws
    -> HermesAuthorizedRootRecord
  {
    let url = recordURL(for: rootID)
    guard fileManager.fileExists(atPath: url.path) else {
      throw HermesAuthorizedRootRegistryError.unknownRoot(rootID)
    }
    return try readRecord(at: url)
  }

  private func readRecord(at url: URL) throws -> HermesAuthorizedRootRecord {
    try rejectEscaping(url)
    guard !Self.isSymlink(url.path) else {
      throw HermesAuthorizedRootRegistryError.storageBoundaryViolation
    }
    let data = try boundedData(at: url)
    do {
      let record = try decoder.decode(HermesAuthorizedRootRecord.self, from: data)
      guard record.schemaVersion == HermesAuthorizedRootRecord.currentSchemaVersion else {
        throw HermesAuthorizedRootRegistryError.unsupportedSchemaVersion(record.schemaVersion)
      }
      guard recordURL(for: record.rootID).lastPathComponent == url.lastPathComponent else {
        throw HermesAuthorizedRootRegistryError.corruptRecord(rootID: record.rootID)
      }
      _ = try InMemoryHermesAuthorizedRootRegistry.validateResolvedRoot(
        record.resolvedRootURL,
        policy: policy
      )
      return record
    } catch let error as HermesAuthorizedRootRegistryError {
      throw error
    } catch {
      throw HermesAuthorizedRootRegistryError.corruptRecord(rootID: nil)
    }
  }

  private func boundedData(at url: URL) throws -> Data {
    let attributes = try fileManager.attributesOfItem(atPath: url.path)
    if let size = attributes[.size] as? NSNumber, size.intValue > maximumRecordBytes {
      throw HermesAuthorizedRootRegistryError.recordTooLarge(maximumBytes: maximumRecordBytes)
    }
    let data = try Data(contentsOf: url)
    guard data.count <= maximumRecordBytes else {
      throw HermesAuthorizedRootRegistryError.recordTooLarge(maximumBytes: maximumRecordBytes)
    }
    return data
  }

  private func persist(_ record: HermesAuthorizedRootRecord) throws {
    let data = try encoder.encode(record)
    guard data.count <= maximumRecordBytes else {
      throw HermesAuthorizedRootRegistryError.recordTooLarge(maximumBytes: maximumRecordBytes)
    }
    let destination = recordURL(for: record.rootID)
    try rejectEscaping(destination)
    guard !Self.isSymlink(destination.path) else {
      throw HermesAuthorizedRootRegistryError.storageBoundaryViolation
    }
    let temporary = root.appendingPathComponent(
      ".tmp-\(UUID().uuidString).json",
      isDirectory: false
    )
    try rejectEscaping(temporary)
    do {
      try data.write(to: temporary, options: [.withoutOverwriting])
      chmod(temporary.path, 0o600)
      try renameReplacingItem(at: temporary, with: destination)
      fsyncDirectory(root)
    } catch let error as HermesAuthorizedRootRegistryError {
      try? fileManager.removeItem(at: temporary)
      throw error
    } catch {
      try? fileManager.removeItem(at: temporary)
      throw HermesAuthorizedRootRegistryError.persistenceFailed(String(describing: error))
    }
  }

  private func renameReplacingItem(at source: URL, with destination: URL) throws {
    let result = source.path.withCString { sourcePath in
      destination.path.withCString { destinationPath in
        rename(sourcePath, destinationPath)
      }
    }
    guard result == 0 else {
      throw HermesAuthorizedRootRegistryError.persistenceFailed(String(cString: strerror(errno)))
    }
  }

  private func recordFileURLs() throws -> [URL] {
    try rejectEscapingRecordPaths()
    return try fileManager.contentsOfDirectory(
      at: root,
      includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
      options: []
    )
    .filter { $0.lastPathComponent.hasSuffix(".json") && !$0.lastPathComponent.hasPrefix(".tmp-") }
  }

  private func rejectEscapingRecordPaths() throws {
    let urls = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
    for url in urls {
      try rejectEscaping(url)
      if Self.isSymlink(url.path) {
        throw HermesAuthorizedRootRegistryError.storageBoundaryViolation
      }
    }
  }

  private func recordURL(for rootID: HermesAuthorizedRootID) -> URL {
    root.appendingPathComponent(rootID.rawValue + ".json", isDirectory: false)
  }

  private func rejectEscaping(_ url: URL) throws {
    let rootPath = root.standardizedFileURL.path
    let path = url.standardizedFileURL.path
    guard path == rootPath || path.hasPrefix(rootPath + "/") else {
      throw HermesAuthorizedRootRegistryError.storageBoundaryViolation
    }
  }

  private static func isSymlink(_ path: String) -> Bool {
    HermesPathSecurity.isSymlink(path)
  }

  private func fsyncDirectory(_ url: URL) {
    let fd = open(url.path, O_RDONLY)
    if fd >= 0 {
      fsync(fd)
      close(fd)
    }
  }
}

public struct HermesFileEventFlag: Codable, Equatable, Hashable, Sendable,
  CustomStringConvertible
{
  public static let maximumRawValueLength = 40
  public let rawValue: String

  public init(rawValue: String) throws {
    guard !rawValue.isEmpty, rawValue.count <= Self.maximumRawValueLength,
      rawValue.allSatisfy({
        $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_")
      })
    else {
      throw HermesFileEventError.invalidFlag
    }
    self.rawValue = rawValue
  }

  public var description: String { rawValue }
}

public enum HermesFileEventKind: String, Codable, Equatable, Sendable {
  case created
  case modified
  case renamed
  case removed
  case metadataChanged
  case rootChanged
  case historyDone
  case rescanRequired
}

public struct HermesRootRelativePath: Codable, Equatable, Hashable, Sendable,
  CustomStringConvertible
{
  public static let rootMarker = "."
  public static let maximumUTF8Bytes = 4096
  public let rawValue: String

  public init(rawValue: String) throws {
    guard !rawValue.isEmpty, rawValue.utf8.count <= Self.maximumUTF8Bytes else {
      throw HermesFileEventError.invalidRelativePath
    }
    if rawValue == Self.rootMarker {
      self.rawValue = rawValue
      return
    }
    guard !rawValue.hasPrefix("/"), !rawValue.contains("\0") else {
      throw HermesAuthorizedRootRegistryError.rejectedPathEscape
    }
    let parts = rawValue.split(separator: "/", omittingEmptySubsequences: false)
    guard !parts.contains(where: { $0 == "." || $0 == ".." || $0.isEmpty }) else {
      throw HermesAuthorizedRootRegistryError.rejectedPathTraversal
    }
    self.rawValue = rawValue
  }

  public var description: String { rawValue }
}

public enum HermesFileEventError: Error, Equatable, Sendable {
  case invalidRelativePath
  case invalidFlag
  case eventLimitExceeded(maximum: Int)
  case batchTooLarge(maximumBytes: Int)
}

public enum HermesFileEventDroppedReason: String, Codable, Equatable, Sendable {
  case mustScanSubDirs
  case userDropped
  case kernelDropped
  case eventIDsWrapped
  case malformedPath
}

public struct HermesFileEvent: Codable, Equatable, Sendable {
  public let rootID: HermesAuthorizedRootID
  public let kind: HermesFileEventKind
  public let relativePath: HermesRootRelativePath
  public let fseventID: UInt64
  public let timestamp: Date
  public let isDirectory: Bool?
  public let flags: Set<HermesFileEventFlag>

  public init(
    rootID: HermesAuthorizedRootID,
    kind: HermesFileEventKind,
    relativePath: HermesRootRelativePath,
    fseventID: UInt64,
    timestamp: Date,
    isDirectory: Bool?,
    flags: Set<HermesFileEventFlag>
  ) throws {
    self.rootID = rootID
    self.kind = kind
    self.relativePath = relativePath
    self.fseventID = fseventID
    self.timestamp = timestamp
    self.isDirectory = isDirectory
    self.flags = Set(flags.prefix(32))
  }
}

public struct HermesFileEventBatch: Codable, Equatable, Sendable {
  public static let maximumEventCount = 512
  public static let maximumEncodedBytes = 64 * 1024

  public let rootID: HermesAuthorizedRootID
  public let events: [HermesFileEvent]
  public let newestEventID: UInt64
  public let replayed: Bool
  public let rescanRequired: Bool
  public let droppedEventReason: HermesFileEventDroppedReason?

  public init(
    rootID: HermesAuthorizedRootID,
    events: [HermesFileEvent],
    newestEventID: UInt64,
    replayed: Bool,
    rescanRequired: Bool,
    droppedEventReason: HermesFileEventDroppedReason? = nil
  ) throws {
    guard events.count <= Self.maximumEventCount else {
      throw HermesFileEventError.eventLimitExceeded(maximum: Self.maximumEventCount)
    }
    self.rootID = rootID
    self.events = events
    self.newestEventID = newestEventID
    self.replayed = replayed
    self.rescanRequired = rescanRequired
    self.droppedEventReason = droppedEventReason
    let data = try JSONEncoder().encode(self)
    guard data.count <= Self.maximumEncodedBytes else {
      throw HermesFileEventError.batchTooLarge(maximumBytes: Self.maximumEncodedBytes)
    }
  }
}

public enum HermesFSEventsMonitorError: Error, Equatable, Sendable {
  case invalidLatency
  case noActiveRoots
  case forbiddenRoot
  case alreadyStarted
  case streamCreateFailed
  case streamStartFailed
  case stopped
}

public struct HermesFSEventsMonitorConfiguration: Equatable, Sendable {
  public let latency: TimeInterval

  public init(latency: TimeInterval = 0.25) throws {
    guard latency >= 0.05, latency <= 5.0 else {
      throw HermesFSEventsMonitorError.invalidLatency
    }
    self.latency = latency
  }
}

public final class HermesFSEventsMonitor: @unchecked Sendable {
  public typealias BatchHandler = @Sendable (HermesFileEventBatch) async throws -> Void

  private final class StreamContext {
    let owner: HermesFSEventsMonitor
    let record: HermesAuthorizedRootRecord
    let sinceWhen: UInt64

    init(owner: HermesFSEventsMonitor, record: HermesAuthorizedRootRecord) {
      self.owner = owner
      self.record = record
      self.sinceWhen = record.lastObservedFSEventID
    }
  }

  private struct StreamState {
    let stream: FSEventStreamRef
    let context: StreamContext
  }

  private let registry: HermesAuthorizedRootRegistry
  private let configuration: HermesFSEventsMonitorConfiguration
  private let handler: BatchHandler
  private let queue: DispatchQueue
  private let stateQueue = DispatchQueue(label: "com.hermes.bridge.fsevents.state")
  private var streams: [StreamState] = []
  private var started = false
  private var stopped = true

  public init(
    registry: HermesAuthorizedRootRegistry,
    configuration: HermesFSEventsMonitorConfiguration = try! HermesFSEventsMonitorConfiguration(),
    queueLabel: String = "com.hermes.bridge.fsevents",
    handler: @escaping BatchHandler
  ) {
    self.registry = registry
    self.configuration = configuration
    self.handler = handler
    self.queue = DispatchQueue(label: queueLabel)
  }

  public func start(records: [HermesAuthorizedRootRecord]) async throws {
    let didStart = stateQueue.sync { () -> Bool in
      if started {
        return false
      }
      stopped = false
      started = true
      return true
    }
    if !didStart {
      return
    }

    let active = try records.filter { record in
      guard record.state == .active else { return false }
      try Self.validateMonitorRoot(record.resolvedRootURL)
      return true
    }
    guard !active.isEmpty else {
      try await stop()
      throw HermesFSEventsMonitorError.noActiveRoots
    }

    do {
      for record in active {
        let state = try makeStream(record: record)
        stateQueue.sync {
          streams.append(state)
        }
        guard FSEventStreamStart(state.stream) else {
          throw HermesFSEventsMonitorError.streamStartFailed
        }
      }
    } catch {
      try await stop()
      throw error
    }
  }

  public func stop() async throws {
    let existing = stateQueue.sync { () -> [StreamState] in
      let existing = streams
      streams.removeAll()
      stopped = true
      started = false
      return existing
    }

    queue.sync {
      for state in existing {
        FSEventStreamStop(state.stream)
        FSEventStreamInvalidate(state.stream)
        FSEventStreamRelease(state.stream)
      }
    }
  }

  private func makeStream(record: HermesAuthorizedRootRecord) throws -> StreamState {
    let context = StreamContext(owner: self, record: record)
    var rawContext = FSEventStreamContext(
      version: 0,
      info: UnsafeMutableRawPointer(Unmanaged.passUnretained(context).toOpaque()),
      retain: nil,
      release: nil,
      copyDescription: nil
    )
    let paths = [record.resolvedRootURL.path] as CFArray
    let flags = FSEventStreamCreateFlags(
      kFSEventStreamCreateFlagFileEvents
        | kFSEventStreamCreateFlagUseCFTypes
        | kFSEventStreamCreateFlagWatchRoot
    )
    let stream = FSEventStreamCreate(
      kCFAllocatorDefault,
      Self.callback,
      &rawContext,
      paths,
      FSEventStreamEventId(
        record.lastObservedFSEventID == 0
          ? UInt64(kFSEventStreamEventIdSinceNow)
          : record.lastObservedFSEventID
      ),
      configuration.latency,
      flags
    )
    guard let stream else {
      throw HermesFSEventsMonitorError.streamCreateFailed
    }
    FSEventStreamSetDispatchQueue(stream, queue)
    return StreamState(stream: stream, context: context)
  }

  private static let callback: FSEventStreamCallback = {
    streamRef,
    contextPointer,
    eventCount,
    eventPathsPointer,
    eventFlagsPointer,
    eventIDsPointer in
    guard let contextPointer else {
      return
    }
    let context = Unmanaged<StreamContext>.fromOpaque(contextPointer).takeUnretainedValue()
    context.owner.receive(
      context: context,
      eventCount: eventCount,
      eventPathsPointer: eventPathsPointer,
      eventFlagsPointer: eventFlagsPointer,
      eventIDsPointer: eventIDsPointer
    )
  }

  private func receive(
    context: StreamContext,
    eventCount: Int,
    eventPathsPointer: UnsafeMutableRawPointer,
    eventFlagsPointer: UnsafePointer<FSEventStreamEventFlags>,
    eventIDsPointer: UnsafePointer<FSEventStreamEventId>
  ) {
    let shouldIgnore = stateQueue.sync { stopped }
    guard !shouldIgnore else {
      return
    }

    let paths = unsafeBitCast(eventPathsPointer, to: CFArray.self) as NSArray
    let timestamp = Date()
    let batch: HermesFileEventBatch
    do {
      batch = try Self.normalizeBatch(
        rootID: context.record.rootID,
        rootURL: context.record.resolvedRootURL,
        sinceWhen: context.sinceWhen,
        eventCount: eventCount,
        paths: paths,
        flags: eventFlagsPointer,
        eventIDs: eventIDsPointer,
        timestamp: timestamp
      )
    } catch {
      return
    }

    Task.detached {
      let stopped = self.stateQueue.sync { self.stopped }
      guard !stopped else {
        return
      }
      do {
        try await self.handler(batch)
        try await self.registry.updateEventCursor(
          batch.rootID,
          eventID: batch.newestEventID,
          expectedRevision: nil
        )
      } catch {
        return
      }
    }
  }

  public static func normalizeBatch(
    rootID: HermesAuthorizedRootID,
    rootURL: URL,
    sinceWhen: UInt64,
    eventCount: Int,
    paths: NSArray,
    flags: UnsafePointer<FSEventStreamEventFlags>,
    eventIDs: UnsafePointer<FSEventStreamEventId>,
    timestamp: Date
  ) throws -> HermesFileEventBatch {
    var events: [HermesFileEvent] = []
    var newest: UInt64 = 0
    var dropReason: HermesFileEventDroppedReason?
    var rescanRequired = false
    var replayed = sinceWhen > 0

    for index in 0..<eventCount {
      let eventFlags = flags[index]
      let eventID = UInt64(eventIDs[index])
      newest = max(newest, eventID)
      let flagSet = try eventFlagSet(eventFlags)
      if let reason = droppedReason(for: eventFlags) {
        dropReason = reason
        rescanRequired = true
      }
      if hasFlag(eventFlags, kFSEventStreamEventFlagHistoryDone) {
        replayed = true
      }
      let kind = eventKind(for: eventFlags, rescanRequired: rescanRequired)
      let relative: HermesRootRelativePath
      if kind == .historyDone || kind == .rescanRequired {
        relative = try HermesRootRelativePath(rawValue: HermesRootRelativePath.rootMarker)
      } else if let rawPath = Self.eventPathString(paths[index]) {
        do {
          relative = try HermesAuthorizedRootPathNormalizer.rootRelativePath(
            eventPath: rawPath,
            rootURL: rootURL
          )
        } catch {
          dropReason = .malformedPath
          rescanRequired = true
          relative = try HermesRootRelativePath(rawValue: HermesRootRelativePath.rootMarker)
        }
      } else {
        dropReason = .malformedPath
        rescanRequired = true
        relative = try HermesRootRelativePath(rawValue: HermesRootRelativePath.rootMarker)
      }
      let event = try HermesFileEvent(
        rootID: rootID,
        kind: kind,
        relativePath: relative,
        fseventID: eventID,
        timestamp: timestamp,
        isDirectory: isDirectoryKnown(eventFlags),
        flags: flagSet
      )
      events.append(event)
      if events.count == HermesFileEventBatch.maximumEventCount {
        break
      }
    }
    return try HermesFileEventBatch(
      rootID: rootID,
      events: events,
      newestEventID: newest,
      replayed: replayed,
      rescanRequired: rescanRequired,
      droppedEventReason: dropReason
    )
  }

  public static func eventKind(
    for flags: FSEventStreamEventFlags,
    rescanRequired: Bool = false
  ) -> HermesFileEventKind {
    if rescanRequired || droppedReason(for: flags) != nil {
      return .rescanRequired
    }
    if hasFlag(flags, kFSEventStreamEventFlagHistoryDone) {
      return .historyDone
    }
    if hasFlag(flags, kFSEventStreamEventFlagRootChanged)
      || hasFlag(flags, kFSEventStreamEventFlagMount)
      || hasFlag(flags, kFSEventStreamEventFlagUnmount)
    {
      return .rootChanged
    }
    if hasFlag(flags, kFSEventStreamEventFlagItemRemoved) {
      return .removed
    }
    if hasFlag(flags, kFSEventStreamEventFlagItemRenamed) {
      return .renamed
    }
    if hasFlag(flags, kFSEventStreamEventFlagItemCreated) {
      return .created
    }
    if hasFlag(flags, kFSEventStreamEventFlagItemModified) {
      return .modified
    }
    if hasFlag(flags, kFSEventStreamEventFlagItemInodeMetaMod)
      || hasFlag(flags, kFSEventStreamEventFlagItemFinderInfoMod)
      || hasFlag(flags, kFSEventStreamEventFlagItemChangeOwner)
      || hasFlag(flags, kFSEventStreamEventFlagItemXattrMod)
    {
      return .metadataChanged
    }
    return .modified
  }

  public static func droppedReason(
    for flags: FSEventStreamEventFlags
  ) -> HermesFileEventDroppedReason? {
    if hasFlag(flags, kFSEventStreamEventFlagMustScanSubDirs) {
      return .mustScanSubDirs
    }
    if hasFlag(flags, kFSEventStreamEventFlagUserDropped) {
      return .userDropped
    }
    if hasFlag(flags, kFSEventStreamEventFlagKernelDropped) {
      return .kernelDropped
    }
    if hasFlag(flags, kFSEventStreamEventFlagEventIdsWrapped) {
      return .eventIDsWrapped
    }
    return nil
  }

  public static func eventFlagSet(_ flags: FSEventStreamEventFlags) throws
    -> Set<HermesFileEventFlag>
  {
    let table: [(FSEventStreamEventFlags, String)] = [
      (FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs), "MustScanSubDirs"),
      (FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped), "UserDropped"),
      (FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped), "KernelDropped"),
      (FSEventStreamEventFlags(kFSEventStreamEventFlagEventIdsWrapped), "EventIdsWrapped"),
      (FSEventStreamEventFlags(kFSEventStreamEventFlagHistoryDone), "HistoryDone"),
      (FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged), "RootChanged"),
      (FSEventStreamEventFlags(kFSEventStreamEventFlagMount), "Mount"),
      (FSEventStreamEventFlags(kFSEventStreamEventFlagUnmount), "Unmount"),
      (FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated), "ItemCreated"),
      (FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved), "ItemRemoved"),
      (FSEventStreamEventFlags(kFSEventStreamEventFlagItemInodeMetaMod), "ItemInodeMetaMod"),
      (FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed), "ItemRenamed"),
      (FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified), "ItemModified"),
      (FSEventStreamEventFlags(kFSEventStreamEventFlagItemFinderInfoMod), "ItemFinderInfoMod"),
      (FSEventStreamEventFlags(kFSEventStreamEventFlagItemChangeOwner), "ItemChangeOwner"),
      (FSEventStreamEventFlags(kFSEventStreamEventFlagItemXattrMod), "ItemXattrMod"),
      (FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsFile), "ItemIsFile"),
      (FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir), "ItemIsDir"),
      (FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsSymlink), "ItemIsSymlink"),
      (FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsHardlink), "ItemIsHardlink"),
      (FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsLastHardlink), "ItemIsLastHardlink"),
      (FSEventStreamEventFlags(kFSEventStreamEventFlagItemCloned), "ItemCloned"),
    ]
    return try Set(
      table.filter { hasFlag(flags, Int($0.0)) }.map {
        try HermesFileEventFlag(rawValue: $0.1)
      })
  }

  private static func isDirectoryKnown(_ flags: FSEventStreamEventFlags) -> Bool? {
    if hasFlag(flags, kFSEventStreamEventFlagItemIsDir) {
      return true
    }
    if hasFlag(flags, kFSEventStreamEventFlagItemIsFile)
      || hasFlag(flags, kFSEventStreamEventFlagItemIsSymlink)
    {
      return false
    }
    return nil
  }

  private static func eventPathString(_ value: Any) -> String? {
    if let string = value as? String {
      return string
    }
    if let url = value as? URL {
      return url.path
    }
    return nil
  }

  private static func hasFlag(_ flags: FSEventStreamEventFlags, _ flag: Int) -> Bool {
    (flags & FSEventStreamEventFlags(flag)) != 0
  }

  private static func validateMonitorRoot(_ url: URL) throws {
    let path = url.standardizedFileURL.resolvingSymlinksInPath().path
    let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
      .resolvingSymlinksInPath().path
    guard path != "/", path != home else {
      throw HermesFSEventsMonitorError.forbiddenRoot
    }
    guard !HermesPathSecurity.isSymlink(url.standardizedFileURL.path) else {
      throw HermesFSEventsMonitorError.forbiddenRoot
    }
  }
}

public enum HermesAuthorizedRootPathNormalizer {
  public static func rootRelativePath(eventPath: String, rootURL: URL) throws
    -> HermesRootRelativePath
  {
    guard !eventPath.contains("\0") else {
      throw HermesAuthorizedRootRegistryError.rejectedPathEscape
    }
    let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
    let rootPath = root.path
    let rawURL = URL(fileURLWithPath: eventPath)
    if rawURL.pathComponents.contains("..") {
      throw HermesAuthorizedRootRegistryError.rejectedPathTraversal
    }
    let standardizedPath = rawURL.standardizedFileURL.path
    guard standardizedPath == rootPath || standardizedPath.hasPrefix(rootPath + "/") else {
      throw HermesAuthorizedRootRegistryError.rejectedPathEscape
    }
    if FileManager.default.fileExists(atPath: standardizedPath) {
      let resolvedPath = rawURL.standardizedFileURL.resolvingSymlinksInPath().path
      guard resolvedPath == rootPath || resolvedPath.hasPrefix(rootPath + "/") else {
        throw HermesAuthorizedRootRegistryError.rejectedPathEscape
      }
      if resolvedPath == rootPath {
        return try HermesRootRelativePath(rawValue: HermesRootRelativePath.rootMarker)
      }
      return try HermesRootRelativePath(
        rawValue: String(resolvedPath.dropFirst(rootPath.count + 1)))
    }
    if standardizedPath == rootPath {
      return try HermesRootRelativePath(rawValue: HermesRootRelativePath.rootMarker)
    }
    let relative = String(standardizedPath.dropFirst(rootPath.count + 1))
    return try HermesRootRelativePath(rawValue: relative)
  }
}

enum HermesPathSecurity {
  static func isSymlink(_ path: String) -> Bool {
    var statBuffer = stat()
    return lstat(path, &statBuffer) == 0 && (statBuffer.st_mode & S_IFMT) == S_IFLNK
  }
}

extension Data {
  fileprivate func hermesBase64URLEncodedString() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
