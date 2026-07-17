import Darwin
import Foundation
import XCTest

@testable import HermesRuntimeFoundation

final class HermesProcessSupervisorTests: XCTestCase {
  private var temporaryDirectory: URL!
  private var fixtureBinary: URL!
  private var escapedPIDs: [pid_t] = []

  override func setUpWithError() throws {
    temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "HermesProcessSupervisorTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory, withIntermediateDirectories: true)
    fixtureBinary = try compileFixture()
  }

  override func tearDownWithError() throws {
    for pid in escapedPIDs {
      kill(pid, SIGKILL)
      var status: Int32 = 0
      waitpid(pid, &status, 0)
    }
    try? FileManager.default.removeItem(at: temporaryDirectory)
    XCTAssertFalse(hasResidualFixtureProcess())
  }

  func testSuccessfulLaunchAndReadiness() throws {
    let port = try freePort()
    let supervisor = HermesProcessSupervisor()
    let result = try supervisor.start(configuration: configuration(mode: "ready", port: port))

    XCTAssertEqual(result.identity.pgid, result.identity.pid)
    XCTAssertEqual(
      result.identity.expectedCommandShape.dropFirst(),
      [
        "--safe-mode", "serve", "--host", "127.0.0.1", "--port", String(port), "--skip-build",
        "--isolated",
      ])
    XCTAssertReady(supervisor.state)

    let stop = try supervisor.stop()
    XCTAssertEqual(stop.exitStatus, 0)
  }

  func testExactReadinessPortParsingRejectsDifferentPort() throws {
    let supervisor = HermesProcessSupervisor()
    XCTAssertThrowsError(try supervisor.start(configuration: configuration(mode: "wrong-port"))) {
      XCTAssertEqual(
        $0 as? HermesProcessFailure, .malformedReadinessSignal("HERMES_BACKEND_READY port=19001"))
    }
  }

  func testReadinessOnStderr() throws {
    let supervisor = HermesProcessSupervisor()
    _ = try supervisor.start(configuration: configuration(mode: "ready-stderr"))
    XCTAssertReady(supervisor.state)
    _ = try supervisor.stop()
  }

  func testStartupTimeout() throws {
    let supervisor = HermesProcessSupervisor()
    XCTAssertThrowsError(
      try supervisor.start(configuration: configuration(mode: "timeout", startupTimeout: 0.2))
    ) {
      XCTAssertEqual($0 as? HermesProcessFailure, .startupTimedOut)
    }
  }

  func testExitBeforeReadiness() throws {
    let supervisor = HermesProcessSupervisor()
    XCTAssertThrowsError(try supervisor.start(configuration: configuration(mode: "exit-zero"))) {
      guard case .exitedBeforeReady = $0 as? HermesProcessFailure else {
        return XCTFail("expected exitedBeforeReady, got \($0)")
      }
    }
  }

  func testNonzeroEarlyExit() throws {
    let supervisor = HermesProcessSupervisor()
    XCTAssertThrowsError(try supervisor.start(configuration: configuration(mode: "exit-nonzero"))) {
      guard case .exitedBeforeReady(let status) = $0 as? HermesProcessFailure else {
        return XCTFail("expected exitedBeforeReady, got \($0)")
      }
      XCTAssertNotEqual(status, 0)
    }
  }

  func testPortAlreadyOccupied() throws {
    let port = try freePort()
    let fd = try listenSocket(port: port)
    defer { close(fd) }

    let supervisor = HermesProcessSupervisor()
    XCTAssertThrowsError(
      try supervisor.start(configuration: configuration(mode: "ready", port: port))
    ) {
      XCTAssertEqual($0 as? HermesProcessFailure, .portAlreadyInUse(port: port))
    }
  }

  func testInvalidHostRejected() throws {
    XCTAssertThrowsError(
      try HermesProcessConfiguration(
        executable: candidate(mode: "ready"),
        host: "0.0.0.0",
        port: 19000,
        runtimeRoot: temporaryDirectory
      )
    ) {
      XCTAssertEqual($0 as? HermesProcessFailure, .invalidHost("0.0.0.0"))
    }
  }

  func testInvalidPortRejected() throws {
    XCTAssertThrowsError(
      try HermesProcessConfiguration(
        executable: candidate(mode: "ready"),
        port: 0,
        runtimeRoot: temporaryDirectory
      )
    ) {
      XCTAssertEqual($0 as? HermesProcessFailure, .invalidPort(0))
    }
  }

  func testNormalSIGTERMShutdown() throws {
    let supervisor = HermesProcessSupervisor()
    _ = try supervisor.start(configuration: configuration(mode: "ready"))
    let result = try supervisor.stop()
    XCTAssertEqual(result.exitStatus, 0)
    XCTAssertNoThrow(try supervisor.stop())
  }

  func testChildAndGrandchildCleanupThroughOwnedPGID() throws {
    let supervisor = HermesProcessSupervisor()
    let launch = try supervisor.start(configuration: configuration(mode: "tree"))
    _ = try supervisor.stop()
    XCTAssertFalse(groupHasMembers(launch.identity.pgid))
  }

  func testSIGTERMResistantChildRequiresSIGKILLEscalation() throws {
    let supervisor = HermesProcessSupervisor()
    let launch = try supervisor.start(
      configuration: configuration(mode: "ignore-term", gracefulShutdownTimeout: 0.2)
    )
    let result = try supervisor.stop()
    XCTAssertFalse(groupHasMembers(launch.identity.pgid))
    XCTAssertEqual(result.exitStatus, 0)
  }

  func testIdentityMismatchCausesSignalRefusal() throws {
    let supervisor = HermesProcessSupervisor()
    _ = try supervisor.start(configuration: configuration(mode: "ready"))
    supervisor.corruptRetainedIdentityForTesting()

    XCTAssertThrowsError(try supervisor.stop()) {
      guard case .identityVerificationFailed = $0 as? HermesProcessFailure else {
        return XCTFail("expected identityVerificationFailed, got \($0)")
      }
    }
    try cleanupSupervisorAfterIdentityTest(supervisor)
  }

  func testPortRemainsOpenAfterProcessExit() throws {
    let port = try freePort()
    let supervisor = HermesProcessSupervisor()
    let launch = try supervisor.start(
      configuration: configuration(mode: "port-stays-open", port: port))
    let pidFile = launch.runtimeDirectory
      .appendingPathComponent("hermes-home", isDirectory: true)
      .appendingPathComponent("escaped.pid")
    let escapedPID = pid_t(
      (try String(contentsOf: pidFile)).trimmingCharacters(in: .whitespacesAndNewlines))!
    escapedPIDs.append(escapedPID)

    XCTAssertThrowsError(try supervisor.stop()) {
      XCTAssertEqual($0 as? HermesProcessFailure, .portDidNotClose(port: port))
    }
  }

  func testOutputBounding() throws {
    let supervisor = HermesProcessSupervisor()
    _ = try supervisor.start(
      configuration: configuration(mode: "large-output", outputLimitBytes: 128))
    let output = supervisor.outputSnapshot
    XCTAssertTrue(output.stdoutTruncated)
    XCTAssertLessThanOrEqual(output.stdout.count, 128)
    _ = try supervisor.stop()
  }

  func testRuntimeRootsCreatedUnderSuppliedTemporaryRoot() throws {
    let supervisor = HermesProcessSupervisor()
    let launch = try supervisor.start(configuration: configuration(mode: "ready"))
    XCTAssertTrue(launch.runtimeDirectory.path.hasPrefix(temporaryDirectory.path))
    for child in [
      "home", "hermes-home", "xdg-config", "xdg-cache", "xdg-data", "xdg-state", "xdg-runtime",
    ] {
      var isDirectory: ObjCBool = false
      let path = launch.runtimeDirectory.appendingPathComponent(child).path
      XCTAssertTrue(FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory))
      XCTAssertTrue(isDirectory.boolValue)
    }
    _ = try supervisor.stop()
  }

  func testNoShellMetacharacterInterpretation() throws {
    let marker = temporaryDirectory.appendingPathComponent("SHOULD_NOT_EXIST")
    let supervisor = HermesProcessSupervisor()
    _ = try supervisor.start(configuration: configuration(mode: "ready;touch SHOULD_NOT_EXIST"))
    _ = try supervisor.stop()
    XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
  }

  func testRepeatedStopIsIdempotent() throws {
    let supervisor = HermesProcessSupervisor()
    _ = try supervisor.start(configuration: configuration(mode: "ready"))
    XCTAssertNoThrow(try supervisor.stop())
    XCTAssertNoThrow(try supervisor.stop())
  }

  func testConcurrentOrSecondStartRejected() throws {
    let supervisor = HermesProcessSupervisor()
    _ = try supervisor.start(configuration: configuration(mode: "ready"))
    XCTAssertThrowsError(try supervisor.start(configuration: configuration(mode: "ready"))) {
      XCTAssertEqual($0 as? HermesProcessFailure, .alreadyRunning)
    }
    _ = try supervisor.stop()
  }

  func testNoResidualFixtureProcessAfterStop() throws {
    let supervisor = HermesProcessSupervisor()
    _ = try supervisor.start(configuration: configuration(mode: "tree"))
    _ = try supervisor.stop()
    XCTAssertFalse(hasResidualFixtureProcess())
  }

  func testSupervisorInjectsOnlyDashboardSessionTokenHermesEnvironment() throws {
    let token = HermesBackendSessionToken(rawValue: "supervisor-fixture-token")
    let supervisor = HermesProcessSupervisor()
    let launch = try supervisor.start(configuration: configuration(mode: "env-token", token: token))
    let output = String(data: supervisor.outputSnapshot.stdout, encoding: .utf8) ?? ""

    XCTAssertEqual(
      launch.launchContext.endpoint,
      try HermesBackendEndpoint(port: launch.launchContext.endpoint.port))
    XCTAssertEqual(launch.launchContext.sessionToken, token)
    XCTAssertTrue(output.contains("TOKEN_ENV_PRESENT=1"))
    XCTAssertFalse(output.contains(token.rawValue))
    XCTAssertFalse(String(describing: launch.launchContext).contains(token.rawValue))

    _ = try supervisor.stop()
  }

  private func configuration(
    mode: String,
    port: Int = 19000,
    token: HermesBackendSessionToken? = nil,
    startupTimeout: TimeInterval = 2,
    gracefulShutdownTimeout: TimeInterval = 1,
    forcedShutdownTimeout: TimeInterval = 1,
    outputLimitBytes: Int = 4096
  ) throws -> HermesProcessConfiguration {
    try HermesProcessConfiguration(
      executable: candidate(mode: mode),
      port: port == 19000 ? try freePort() : port,
      runtimeRoot: temporaryDirectory,
      sessionToken: token,
      startupTimeout: startupTimeout,
      gracefulShutdownTimeout: gracefulShutdownTimeout,
      forcedShutdownTimeout: forcedShutdownTimeout,
      outputLimitBytes: outputLimitBytes
    )
  }

  private func candidate(mode: String) throws -> HermesExecutableCandidate {
    let executable = temporaryDirectory.appendingPathComponent(mode)
    if !FileManager.default.fileExists(atPath: executable.path) {
      try FileManager.default.copyItem(at: fixtureBinary, to: executable)
      try FileManager.default.setAttributes(
        [.posixPermissions: NSNumber(value: Int16(0o700))],
        ofItemAtPath: executable.path
      )
    }
    return HermesExecutableCandidate(
      allowlistedCandidatePath: executable.path,
      originalPath: executable.path,
      resolvedPath: executable.path,
      symlinkStatus: .notSymlink
    )
  }

  private func compileFixture() throws -> URL {
    let source = temporaryDirectory.appendingPathComponent("fixture.c")
    let binary = temporaryDirectory.appendingPathComponent("fixture-bin")
    try fixtureSource.write(to: source, atomically: true, encoding: .utf8)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
    process.arguments = [source.path, "-o", binary.path]
    try process.run()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    return binary
  }

  private func freePort() throws -> Int {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    XCTAssertGreaterThanOrEqual(fd, 0)
    defer { close(fd) }
    var address = sockaddr_in(
      sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
      sin_family: sa_family_t(AF_INET),
      sin_port: 0,
      sin_addr: in_addr(s_addr: inet_addr("127.0.0.1")),
      sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
    )
    let bindResult = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    XCTAssertEqual(bindResult, 0)
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    getsockname(
      fd,
      withUnsafeMutablePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { $0 }
      }, &length)
    return Int(UInt16(bigEndian: address.sin_port))
  }

  private func listenSocket(port: Int) throws -> Int32 {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    XCTAssertGreaterThanOrEqual(fd, 0)
    var yes: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
    var address = sockaddr_in(
      sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
      sin_family: sa_family_t(AF_INET),
      sin_port: UInt16(port).bigEndian,
      sin_addr: in_addr(s_addr: inet_addr("127.0.0.1")),
      sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
    )
    let result = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    XCTAssertEqual(result, 0)
    XCTAssertEqual(listen(fd, 8), 0)
    return fd
  }

  private func groupHasMembers(_ pgid: pid_t) -> Bool {
    kill(-pgid, 0) == 0
  }

  private func cleanupSupervisorAfterIdentityTest(_ supervisor: HermesProcessSupervisor) throws {
    guard case .failed = supervisor.state else {
      return
    }
    let output = supervisor.outputSnapshot
    XCTAssertFalse(output.stdout.isEmpty)
    // The retained identity is intentionally corrupt, so use the fixture marker to clean up.
    for line in processLines() where line.contains(temporaryDirectory.path) {
      let fields = line.trimmingCharacters(in: .whitespaces)
        .split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
      if let pid = fields.first.flatMap({ pid_t($0) }) {
        kill(pid, SIGKILL)
      }
    }
  }

  private func hasResidualFixtureProcess() -> Bool {
    processLines().contains { $0.contains(temporaryDirectory.path) }
  }

  private func processLines() -> [String] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-axo", "pid=,command="]
    let pipe = Pipe()
    process.standardOutput = pipe
    do {
      try process.run()
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      return String(data: data, encoding: .utf8)?.components(separatedBy: .newlines) ?? []
    } catch {
      return []
    }
  }

  private func XCTAssertReady(
    _ state: HermesProcessState, file: StaticString = #filePath, line: UInt = #line
  ) {
    guard case .ready = state else {
      return XCTFail("expected ready, got \(state)", file: file, line: line)
    }
  }
}

private let fixtureSource = #"""
  #include <arpa/inet.h>
  #include <errno.h>
  #include <libgen.h>
  #include <netinet/in.h>
  #include <signal.h>
  #include <stdio.h>
  #include <stdlib.h>
  #include <string.h>
  #include <sys/socket.h>
  #include <sys/types.h>
  #include <unistd.h>

  extern char **environ;

  static volatile sig_atomic_t keep_running = 1;

  static void stop_handler(int sig) {
    (void)sig;
    keep_running = 0;
  }

  static int parse_port(int argc, char **argv) {
    if (argc != 9) return -1;
    if (strcmp(argv[1], "--safe-mode") != 0) return -1;
    if (strcmp(argv[2], "serve") != 0) return -1;
    if (strcmp(argv[3], "--host") != 0) return -1;
    if (strcmp(argv[4], "127.0.0.1") != 0) return -1;
    if (strcmp(argv[5], "--port") != 0) return -1;
    if (strcmp(argv[7], "--skip-build") != 0) return -1;
    if (strcmp(argv[8], "--isolated") != 0) return -1;
    return atoi(argv[6]);
  }

  static int listen_loopback(int port) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_len = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)port);
    addr.sin_addr.s_addr = inet_addr("127.0.0.1");
    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
      close(fd);
      return -1;
    }
    if (listen(fd, 8) != 0) {
      close(fd);
      return -1;
    }
    return fd;
  }

  static void print_ready(FILE *stream, int port) {
    fprintf(stream, "HERMES_BACKEND_READY port=%d\n", port);
    fflush(stream);
  }

  static void sleep_loop(void) {
    while (keep_running) sleep(1);
  }

  static void fork_tree(int ignore_term) {
    pid_t child = fork();
    if (child == 0) {
      if (ignore_term) signal(SIGTERM, SIG_IGN);
      pid_t grandchild = fork();
      if (grandchild == 0) {
        if (ignore_term) signal(SIGTERM, SIG_IGN);
        for (;;) sleep(1);
      }
      for (;;) sleep(1);
    }
  }

  static const char *mode_name(char *path) {
    char *copy = strdup(path);
    const char *base = basename(copy);
    char *result = strdup(base);
    free(copy);
    return result;
  }

  int main(int argc, char **argv) {
    int port = parse_port(argc, argv);
    if (port < 1) return 64;
    const char *mode = mode_name(argv[0]);

    if (strcmp(mode, "timeout") == 0) {
      sleep(30);
      return 0;
    }
    if (strcmp(mode, "exit-zero") == 0) return 0;
    if (strcmp(mode, "exit-nonzero") == 0) return 42;
    if (strcmp(mode, "wrong-port") == 0) {
      print_ready(stdout, 19001);
      sleep(30);
      return 0;
    }
    if (strcmp(mode, "large-output") == 0) {
      for (int i = 0; i < 10000; i++) fputc('X', stdout);
      fputc('\n', stdout);
      fflush(stdout);
    }
    if (strcmp(mode, "env-token") == 0) {
      int token_present = 0;
      for (char **env = environ; *env != NULL; env++) {
        if (strncmp(*env, "HERMES_DASHBOARD_SESSION_TOKEN=", 31) == 0) {
          token_present = 1;
        }
      }
      fprintf(stdout, "TOKEN_ENV_PRESENT=%d\n", token_present);
      fflush(stdout);
    }
    if (strcmp(mode, "tree") == 0) fork_tree(0);
    if (strcmp(mode, "ignore-term") == 0) fork_tree(1);

    signal(SIGTERM, stop_handler);

    if (strcmp(mode, "port-stays-open") == 0) {
      pid_t child = fork();
      if (child == 0) {
        setsid();
        signal(SIGTERM, SIG_IGN);
        int child_fd = listen_loopback(port);
        const char *home = getenv("HERMES_HOME");
        if (home) {
          char path[4096];
          snprintf(path, sizeof(path), "%s/escaped.pid", home);
          FILE *pidfile = fopen(path, "w");
          if (pidfile) {
            fprintf(pidfile, "%d\n", getpid());
            fclose(pidfile);
          }
        }
        for (;;) sleep(1);
        close(child_fd);
        return 0;
      }
      for (int i = 0; i < 100; i++) {
        const char *home = getenv("HERMES_HOME");
        if (home) {
          char path[4096];
          snprintf(path, sizeof(path), "%s/escaped.pid", home);
          if (access(path, F_OK) == 0) break;
        }
        usleep(10000);
      }
      print_ready(stdout, port);
      sleep_loop();
      return 0;
    }

    int fd = listen_loopback(port);
    if (fd < 0) return 70;
    if (strcmp(mode, "ready-stderr") == 0) {
      print_ready(stderr, port);
    } else {
      print_ready(stdout, port);
    }
    sleep_loop();
    close(fd);
    return 0;
  }
  """#
