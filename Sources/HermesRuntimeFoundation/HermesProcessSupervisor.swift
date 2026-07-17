import Darwin
import Foundation

public struct HermesProcessConfiguration: Equatable, Sendable {
  public let executable: HermesExecutableCandidate
  public let host: String
  public let port: Int
  public let runtimeRoot: URL
  public let startupTimeout: TimeInterval
  public let gracefulShutdownTimeout: TimeInterval
  public let forcedShutdownTimeout: TimeInterval
  public let outputLimitBytes: Int

  public init(
    executable: HermesExecutableCandidate,
    host: String = "127.0.0.1",
    port: Int,
    runtimeRoot: URL,
    startupTimeout: TimeInterval = 10,
    gracefulShutdownTimeout: TimeInterval = 5,
    forcedShutdownTimeout: TimeInterval = 5,
    outputLimitBytes: Int = 128 * 1024
  ) throws {
    guard host == "127.0.0.1" else {
      throw HermesProcessFailure.invalidHost(host)
    }
    guard (1...65535).contains(port) else {
      throw HermesProcessFailure.invalidPort(port)
    }

    self.executable = executable
    self.host = host
    self.port = port
    self.runtimeRoot = runtimeRoot
    self.startupTimeout = max(0.001, startupTimeout)
    self.gracefulShutdownTimeout = max(0.001, gracefulShutdownTimeout)
    self.forcedShutdownTimeout = max(0.001, forcedShutdownTimeout)
    self.outputLimitBytes = max(1, outputLimitBytes)
  }

  public var fixedArguments: [String] {
    [
      "--safe-mode",
      "serve",
      "--host",
      "127.0.0.1",
      "--port",
      String(port),
      "--skip-build",
      "--isolated",
    ]
  }
}

public struct HermesProcessIdentity: Equatable, Sendable {
  public let pid: pid_t
  public let pgid: pid_t
  public let processStartIdentity: String
  public let resolvedExecutablePath: String
  public let launchNonce: UUID
  public let expectedCommandShape: [String]
}

public enum HermesProcessState: Equatable, Sendable {
  case idle
  case starting
  case ready(HermesProcessIdentity)
  case stopping(HermesProcessIdentity)
  case exited(HermesProcessExit)
  case failed(HermesProcessFailure)
}

public struct HermesProcessExit: Equatable, Sendable {
  public let pid: pid_t
  public let status: Int32
}

public enum HermesProcessFailure: Error, Equatable, Sendable {
  case alreadyRunning
  case invalidHost(String)
  case invalidPort(Int)
  case runtimeRootCreationFailed(String)
  case portAlreadyInUse(port: Int)
  case launchFailed(String)
  case startupTimedOut
  case exitedBeforeReady(status: Int32)
  case malformedReadinessSignal(String)
  case identityVerificationFailed(String)
  case gracefulShutdownTimedOut
  case forcedShutdownFailed(String)
  case portDidNotClose(port: Int)
  case outputLimitExceeded(stream: HermesOutputStream, limitBytes: Int)
}

public enum HermesOutputStream: String, Equatable, Sendable {
  case stdout
  case stderr
}

public struct HermesProcessOutputSnapshot: Equatable, Sendable {
  public let stdout: Data
  public let stderr: Data
  public let stdoutTruncated: Bool
  public let stderrTruncated: Bool
}

public struct HermesEscapedDescendantObservation: Equatable, Sendable {
  public let pid: pid_t
  public let pgid: pid_t
  public let command: String
}

public struct HermesProcessLaunchResult: Equatable, Sendable {
  public let identity: HermesProcessIdentity
  public let runtimeDirectory: URL
  public let output: HermesProcessOutputSnapshot
}

public struct HermesProcessStopResult: Equatable, Sendable {
  public let exitStatus: Int32
  public let output: HermesProcessOutputSnapshot
  public let escapedDescendants: [HermesEscapedDescendantObservation]
}

public final class HermesProcessSupervisor: @unchecked Sendable {
  private let lock = NSLock()
  private var currentState: HermesProcessState = .idle
  private var launched: LaunchedProcess?

  public init() {}

  public var state: HermesProcessState {
    lock.withLock { currentState }
  }

  public func start(configuration: HermesProcessConfiguration) throws -> HermesProcessLaunchResult {
    try transitionToStarting()

    do {
      guard Self.isPortAvailable(port: configuration.port) else {
        throw HermesProcessFailure.portAlreadyInUse(port: configuration.port)
      }

      let runtimeDirectory = try Self.createRuntimeDirectory(under: configuration.runtimeRoot)
      let environment = Self.fixedEnvironment(runtimeDirectory: runtimeDirectory)
      let capture = DualStreamCapture(limitBytes: configuration.outputLimitBytes)
      let readySignal = DispatchSemaphore(value: 0)
      let exitSignal = DispatchSemaphore(value: 0)
      let statusBox = LockedBox<Int32?>(nil)
      let readinessBox = LockedBox<Result<Void, HermesProcessFailure>?>(nil)

      let launch = try FixedHermesServeLauncher.launch(
        executablePath: configuration.executable.resolvedPath,
        arguments: configuration.fixedArguments,
        environment: environment,
        outputHandler: { stream, data in
          capture.append(data, stream: stream)
          if let lineFailure = Self.scanReadiness(
            data: data,
            stream: stream,
            expectedPort: configuration.port
          ) {
            readinessBox.set(.failure(lineFailure))
            readySignal.signal()
          } else if Self.containsReadyLine(data: data, expectedPort: configuration.port) {
            readinessBox.set(.success(()))
            readySignal.signal()
          }
        },
        terminationHandler: { status in
          statusBox.set(status)
          exitSignal.signal()
        }
      )

      let identity = HermesProcessIdentity(
        pid: launch.pid,
        pgid: launch.pgid,
        processStartIdentity: Self.processStartIdentity(pid: launch.pid) ?? "unknown",
        resolvedExecutablePath: configuration.executable.resolvedPath,
        launchNonce: UUID(),
        expectedCommandShape: [configuration.executable.resolvedPath] + configuration.fixedArguments
      )
      let process = LaunchedProcess(
        configuration: configuration,
        runtimeDirectory: runtimeDirectory,
        launcher: launch,
        identity: identity,
        capture: capture,
        exitSignal: exitSignal,
        statusBox: statusBox
      )
      lock.withLock {
        launched = process
      }

      let deadline = DispatchTime.now() + configuration.startupTimeout
      while true {
        if readySignal.wait(timeout: .now()) == .success {
          if let readiness = readinessBox.value {
            switch readiness {
            case .success:
              lock.withLock { currentState = .ready(identity) }
              return HermesProcessLaunchResult(
                identity: identity,
                runtimeDirectory: runtimeDirectory,
                output: capture.snapshot()
              )
            case .failure(let failure):
              try cleanupAfterStartFailure(process: process, failure: failure)
            }
          }
        }

        if exitSignal.wait(timeout: .now()) == .success {
          let status = statusBox.value ?? -1
          try cleanupAfterStartFailure(
            process: process,
            failure: .exitedBeforeReady(status: status)
          )
        }

        if DispatchTime.now() >= deadline {
          try cleanupAfterStartFailure(process: process, failure: .startupTimedOut)
        }

        Thread.sleep(forTimeInterval: 0.01)
      }
    } catch let failure as HermesProcessFailure {
      lock.withLock {
        currentState = .failed(failure)
      }
      throw failure
    } catch {
      let failure = HermesProcessFailure.launchFailed(String(describing: error))
      lock.withLock {
        currentState = .failed(failure)
      }
      throw failure
    }
  }

  public func stop() throws -> HermesProcessStopResult {
    let process: LaunchedProcess? = lock.withLock {
      switch currentState {
      case .idle:
        return nil
      case .exited, .failed:
        return launched
      case .ready(let identity), .stopping(let identity):
        if case .ready = currentState {
          currentState = .stopping(identity)
        }
        return launched
      case .starting:
        return launched
      }
    }

    guard let process else {
      return HermesProcessStopResult(exitStatus: 0, output: .empty, escapedDescendants: [])
    }

    if process.statusBox.value != nil {
      return try finalizeStoppedProcess(process)
    }

    guard verifyIdentity(process.identity) else {
      let failure = HermesProcessFailure.identityVerificationFailed(
        "PID/PGID/start identity mismatch")
      lock.withLock { currentState = .failed(failure) }
      throw failure
    }

    kill(-process.identity.pgid, SIGTERM)
    if !waitForParentAndGroupExit(process, timeout: process.configuration.gracefulShutdownTimeout) {
      guard verifyIdentity(process.identity, allowMissingParent: true) else {
        let failure = HermesProcessFailure.identityVerificationFailed(
          "identity mismatch before SIGKILL escalation"
        )
        lock.withLock { currentState = .failed(failure) }
        throw failure
      }

      kill(-process.identity.pgid, SIGKILL)
      guard
        waitForGroupExit(
          pgid: process.identity.pgid, timeout: process.configuration.forcedShutdownTimeout)
      else {
        let failure = HermesProcessFailure.forcedShutdownFailed("process group did not exit")
        lock.withLock { currentState = .failed(failure) }
        throw failure
      }
    }

    return try finalizeStoppedProcess(process)
  }

  public var outputSnapshot: HermesProcessOutputSnapshot {
    lock.withLock { launched?.capture.snapshot() ?? .empty }
  }

  func corruptRetainedIdentityForTesting() {
    lock.withLock {
      guard let process = launched else {
        return
      }
      launched = LaunchedProcess(
        configuration: process.configuration,
        runtimeDirectory: process.runtimeDirectory,
        launcher: process.launcher,
        identity: HermesProcessIdentity(
          pid: process.identity.pid,
          pgid: process.identity.pgid,
          processStartIdentity: "corrupted",
          resolvedExecutablePath: process.identity.resolvedExecutablePath,
          launchNonce: process.identity.launchNonce,
          expectedCommandShape: process.identity.expectedCommandShape
        ),
        capture: process.capture,
        exitSignal: process.exitSignal,
        statusBox: process.statusBox
      )
    }
  }

  private func transitionToStarting() throws {
    try lock.withLock {
      switch currentState {
      case .idle, .exited, .failed:
        currentState = .starting
      case .starting, .ready, .stopping:
        throw HermesProcessFailure.alreadyRunning
      }
    }
  }

  private func cleanupAfterStartFailure(
    process: LaunchedProcess,
    failure: HermesProcessFailure
  ) throws -> Never {
    if process.statusBox.value == nil, verifyIdentity(process.identity, allowMissingParent: true) {
      kill(-process.identity.pgid, SIGKILL)
      _ = process.exitSignal.wait(timeout: .now() + process.configuration.forcedShutdownTimeout)
    }
    lock.withLock {
      currentState = .failed(failure)
    }
    throw failure
  }

  private func finalizeStoppedProcess(_ process: LaunchedProcess) throws -> HermesProcessStopResult
  {
    process.launcher.close()
    let status = process.statusBox.value ?? 0
    let escaped = Self.escapedDescendants(
      runtimeDirectory: process.runtimeDirectory, excludingPGID: process.identity.pgid)
    guard Self.waitForPortClosed(port: process.configuration.port, timeout: 1.0) else {
      let failure = HermesProcessFailure.portDidNotClose(port: process.configuration.port)
      lock.withLock { currentState = .failed(failure) }
      throw failure
    }
    let result = HermesProcessStopResult(
      exitStatus: status,
      output: process.capture.snapshot(),
      escapedDescendants: escaped
    )
    lock.withLock {
      currentState = .exited(HermesProcessExit(pid: process.identity.pid, status: status))
    }
    return result
  }

  private func verifyIdentity(
    _ identity: HermesProcessIdentity,
    allowMissingParent: Bool = false
  ) -> Bool {
    if kill(identity.pid, 0) != 0 {
      return allowMissingParent
    }
    guard getpgid(identity.pid) == identity.pgid else {
      return false
    }
    guard let currentStart = Self.processStartIdentity(pid: identity.pid) else {
      return false
    }
    return currentStart == identity.processStartIdentity
  }

  private func waitForParentAndGroupExit(_ process: LaunchedProcess, timeout: TimeInterval) -> Bool
  {
    let deadline = Date().addingTimeInterval(timeout)
    var parentExited = process.statusBox.value != nil
    while Date() < deadline {
      if !parentExited, process.exitSignal.wait(timeout: .now()) == .success {
        parentExited = true
      }
      if parentExited, !Self.groupHasMembers(pgid: process.identity.pgid) {
        return true
      }
      Thread.sleep(forTimeInterval: 0.02)
    }
    return parentExited && !Self.groupHasMembers(pgid: process.identity.pgid)
  }

  private func waitForGroupExit(pgid: pid_t, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if !Self.groupHasMembers(pgid: pgid) {
        return true
      }
      Thread.sleep(forTimeInterval: 0.02)
    }
    return !Self.groupHasMembers(pgid: pgid)
  }

  private static func scanReadiness(
    data: Data,
    stream _: HermesOutputStream,
    expectedPort: Int
  ) -> HermesProcessFailure? {
    guard let text = String(data: data, encoding: .utf8) else {
      return nil
    }
    for line in text.split(whereSeparator: \.isNewline) {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard trimmed.hasPrefix("HERMES_BACKEND_READY") else {
        continue
      }
      let expected = "HERMES_BACKEND_READY port=\(expectedPort)"
      if trimmed != expected {
        return .malformedReadinessSignal(trimmed)
      }
    }
    return nil
  }

  private static func containsReadyLine(data: Data, expectedPort: Int) -> Bool {
    guard let text = String(data: data, encoding: .utf8) else {
      return false
    }
    let expected = "HERMES_BACKEND_READY port=\(expectedPort)"
    return text.split(whereSeparator: \.isNewline)
      .contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == expected }
  }

  private static func createRuntimeDirectory(under root: URL) throws -> URL {
    let base = root.standardizedFileURL
    let runtimeDirectory = base.appendingPathComponent(
      "hermes-process-\(UUID().uuidString)",
      isDirectory: true
    )
    do {
      try FileManager.default.createDirectory(
        at: runtimeDirectory,
        withIntermediateDirectories: true
      )
      try setPrivatePermissions(runtimeDirectory)
      for child in [
        "home", "hermes-home", "xdg-config", "xdg-cache", "xdg-data", "xdg-state", "xdg-runtime",
      ] {
        let childURL = runtimeDirectory.appendingPathComponent(child, isDirectory: true)
        try FileManager.default.createDirectory(at: childURL, withIntermediateDirectories: true)
        try setPrivatePermissions(childURL)
      }
      return runtimeDirectory
    } catch {
      throw HermesProcessFailure.runtimeRootCreationFailed(String(describing: error))
    }
  }

  private static func setPrivatePermissions(_ url: URL) throws {
    try FileManager.default.setAttributes(
      [.posixPermissions: NSNumber(value: Int16(0o700))],
      ofItemAtPath: url.path
    )
  }

  private static func fixedEnvironment(runtimeDirectory: URL) -> [String] {
    let home = runtimeDirectory.appendingPathComponent("home", isDirectory: true).path
    let hermesHome = runtimeDirectory.appendingPathComponent("hermes-home", isDirectory: true).path
    return [
      "HOME=\(home)",
      "HERMES_HOME=\(hermesHome)",
      "XDG_CONFIG_HOME=\(runtimeDirectory.appendingPathComponent("xdg-config", isDirectory: true).path)",
      "XDG_CACHE_HOME=\(runtimeDirectory.appendingPathComponent("xdg-cache", isDirectory: true).path)",
      "XDG_DATA_HOME=\(runtimeDirectory.appendingPathComponent("xdg-data", isDirectory: true).path)",
      "XDG_STATE_HOME=\(runtimeDirectory.appendingPathComponent("xdg-state", isDirectory: true).path)",
      "XDG_RUNTIME_DIR=\(runtimeDirectory.appendingPathComponent("xdg-runtime", isDirectory: true).path)",
      "PATH=/usr/bin:/bin:/usr/sbin:/sbin",
      "LANG=C",
    ]
  }

  private static func isPortAvailable(port: Int) -> Bool {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else {
      return false
    }
    defer { close(fd) }
    var yes: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
    var address = sockaddr_in(
      sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
      sin_family: sa_family_t(AF_INET),
      sin_port: UInt16(port).bigEndian,
      sin_addr: in_addr(s_addr: inet_addr("127.0.0.1")),
      sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
    )
    return withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
      }
    }
  }

  private static func waitForPortClosed(port: Int, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if isPortAvailable(port: port) {
        return true
      }
      Thread.sleep(forTimeInterval: 0.05)
    }
    return isPortAvailable(port: port)
  }

  private static func groupHasMembers(pgid: pid_t) -> Bool {
    kill(-pgid, 0) == 0
  }

  private static func processStartIdentity(pid: pid_t) -> String? {
    var info = proc_bsdinfo()
    let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
    guard size == Int32(MemoryLayout<proc_bsdinfo>.size) else {
      return nil
    }
    return "\(info.pbi_start_tvsec).\(info.pbi_start_tvusec)"
  }

  private static func escapedDescendants(
    runtimeDirectory: URL,
    excludingPGID: pid_t
  ) -> [HermesEscapedDescendantObservation] {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/ps")
    task.arguments = ["-axo", "pid=,pgid=,command="]
    let pipe = Pipe()
    task.standardOutput = pipe
    do {
      try task.run()
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      task.waitUntilExit()
      guard let text = String(data: data, encoding: .utf8) else {
        return []
      }
      return text.components(separatedBy: .newlines).compactMap { line in
        guard line.contains(runtimeDirectory.path) else {
          return nil
        }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count == 3,
          let pid = pid_t(parts[0]),
          let pgid = pid_t(parts[1]),
          pgid != excludingPGID
        else {
          return nil
        }
        return HermesEscapedDescendantObservation(pid: pid, pgid: pgid, command: String(parts[2]))
      }
    } catch {
      return []
    }
  }
}

private struct LaunchedProcess {
  let configuration: HermesProcessConfiguration
  let runtimeDirectory: URL
  let launcher: FixedHermesServeLauncher.Launched
  let identity: HermesProcessIdentity
  let capture: DualStreamCapture
  let exitSignal: DispatchSemaphore
  let statusBox: LockedBox<Int32?>
}

private final class LockedBox<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: Value

  init(_ value: Value) {
    storage = value
  }

  var value: Value {
    lock.withLock { storage }
  }

  func set(_ value: Value) {
    lock.withLock { storage = value }
  }
}

private final class DualStreamCapture: @unchecked Sendable {
  private let stdout: BoundedProcessOutput
  private let stderr: BoundedProcessOutput

  init(limitBytes: Int) {
    stdout = BoundedProcessOutput(limitBytes: limitBytes)
    stderr = BoundedProcessOutput(limitBytes: limitBytes)
  }

  func append(_ data: Data, stream: HermesOutputStream) {
    switch stream {
    case .stdout:
      stdout.append(data)
    case .stderr:
      stderr.append(data)
    }
  }

  func snapshot() -> HermesProcessOutputSnapshot {
    HermesProcessOutputSnapshot(
      stdout: stdout.data,
      stderr: stderr.data,
      stdoutTruncated: stdout.wasTruncated,
      stderrTruncated: stderr.wasTruncated
    )
  }
}

private final class BoundedProcessOutput: @unchecked Sendable {
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

private enum FixedHermesServeLauncher {
  final class Launched: @unchecked Sendable {
    let pid: pid_t
    let pgid: pid_t
    private let stdoutReadHandle: FileHandle
    private let stderrReadHandle: FileHandle

    init(pid: pid_t, pgid: pid_t, stdoutReadHandle: FileHandle, stderrReadHandle: FileHandle) {
      self.pid = pid
      self.pgid = pgid
      self.stdoutReadHandle = stdoutReadHandle
      self.stderrReadHandle = stderrReadHandle
    }

    func close() {
      stdoutReadHandle.readabilityHandler = nil
      stderrReadHandle.readabilityHandler = nil
      try? stdoutReadHandle.close()
      try? stderrReadHandle.close()
    }
  }

  static func launch(
    executablePath: String,
    arguments: [String],
    environment: [String],
    outputHandler: @escaping @Sendable (HermesOutputStream, Data) -> Void,
    terminationHandler: @escaping @Sendable (Int32) -> Void
  ) throws -> Launched {
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    var fileActions: posix_spawn_file_actions_t?
    var attributes: posix_spawnattr_t?
    posix_spawn_file_actions_init(&fileActions)
    posix_spawnattr_init(&attributes)
    defer {
      posix_spawn_file_actions_destroy(&fileActions)
      posix_spawnattr_destroy(&attributes)
    }

    posix_spawn_file_actions_adddup2(
      &fileActions, stdoutPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
    posix_spawn_file_actions_adddup2(
      &fileActions, stderrPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
    posix_spawn_file_actions_addclose(&fileActions, stdoutPipe.fileHandleForReading.fileDescriptor)
    posix_spawn_file_actions_addclose(&fileActions, stderrPipe.fileHandleForReading.fileDescriptor)

    let flags = Int16(POSIX_SPAWN_SETPGROUP)
    posix_spawnattr_setflags(&attributes, flags)
    posix_spawnattr_setpgroup(&attributes, 0)

    let argv = [executablePath] + arguments
    var pid: pid_t = 0
    let result = argv.withCStringArray { argvPointer in
      environment.withCStringArray { envPointer in
        posix_spawn(&pid, executablePath, &fileActions, &attributes, argvPointer, envPointer)
      }
    }
    guard result == 0 else {
      throw HermesProcessFailure.launchFailed(String(cString: strerror(result)))
    }

    try? stdoutPipe.fileHandleForWriting.close()
    try? stderrPipe.fileHandleForWriting.close()

    stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      if !data.isEmpty {
        outputHandler(.stdout, data)
      }
    }
    stderrPipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      if !data.isEmpty {
        outputHandler(.stderr, data)
      }
    }

    let launchedPID = pid
    DispatchQueue.global(qos: .utility).async {
      var status: Int32 = 0
      while waitpid(launchedPID, &status, 0) == -1, errno == EINTR {}
      terminationHandler(status)
    }

    return Launched(
      pid: pid,
      pgid: pid,
      stdoutReadHandle: stdoutPipe.fileHandleForReading,
      stderrReadHandle: stderrPipe.fileHandleForReading
    )
  }
}

extension HermesProcessOutputSnapshot {
  fileprivate static let empty = HermesProcessOutputSnapshot(
    stdout: Data(),
    stderr: Data(),
    stdoutTruncated: false,
    stderrTruncated: false
  )
}

extension Array where Element == String {
  fileprivate func withCStringArray<R>(_ body: ([UnsafeMutablePointer<CChar>?]) -> R) -> R {
    let cStrings = map { strdup($0) }
    defer {
      for pointer in cStrings {
        free(pointer)
      }
    }
    return body(cStrings + [nil])
  }
}
