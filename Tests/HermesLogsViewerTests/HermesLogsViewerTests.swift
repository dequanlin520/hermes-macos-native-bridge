import Foundation
@testable import HermesLogsViewer
@testable import HermesRuntimeFoundation
import XCTest

final class HermesLogsViewerTests: XCTestCase {
  func testReceivesRuntimeEventsFromEventBus() async throws {
    let eventBus = HermesRuntimeEventBus()
    let controller = HermesLogsViewerController(eventBus: eventBus)
    await controller.startEventSubscription()

    eventBus.publish(Self.event(kind: .sessionCreated, status: .created))

    let state = try await waitForState(controller) { !$0.entries.isEmpty }
    XCTAssertEqual(state.entries.count, 1)
    XCTAssertEqual(state.entries.first?.eventType, .sessionCreated)
    XCTAssertEqual(state.entries.first?.timestamp, Self.eventDate)
  }

  func testConvertsRuntimeEventToLogEntry() {
    let runtimeEvent = Self.event(
      kind: .sessionStopped,
      status: .stopped,
      shutdownReason: .requested
    )

    let entry = HermesRuntimeLogEntry(event: runtimeEvent)

    XCTAssertEqual(entry.id, 0)
    XCTAssertEqual(entry.timestamp, Self.eventDate)
    XCTAssertEqual(entry.eventType, .sessionStopped)
    XCTAssertEqual(entry.severity, .info)
    XCTAssertTrue(entry.redactedSummary.contains("Runtime session stopped"))
    XCTAssertTrue(entry.redactedSummary.contains("shutdown: requested"))
  }

  func testFilteringSupportsAllInfoWarningAndError() async throws {
    let eventBus = HermesRuntimeEventBus()
    let controller = HermesLogsViewerController(eventBus: eventBus)
    await controller.startEventSubscription()

    eventBus.publish(Self.event(kind: .sessionRunning, status: .running))
    eventBus.publish(Self.event(kind: .sessionHealthChanged, status: .degraded))
    eventBus.publish(Self.event(kind: .sessionFailed, status: .failed, errorMessage: "startup failed"))

    _ = try await waitForState(controller) { $0.entries.count == 3 }

    var state = await controller.setFilter(.all)
    XCTAssertEqual(state.filteredEntries.count, 3)

    state = await controller.setFilter(.info)
    XCTAssertEqual(state.filteredEntries.map(\.severity), [.info])

    state = await controller.setFilter(.warning)
    XCTAssertEqual(state.filteredEntries.map(\.severity), [.warning])

    state = await controller.setFilter(.error)
    XCTAssertEqual(state.filteredEntries.map(\.severity), [.error])
  }

  func testSeverityMapping() {
    XCTAssertEqual(
      HermesRuntimeLogEntry.severity(for: Self.event(kind: .sessionRunning, status: .running)),
      .info
    )
    XCTAssertEqual(
      HermesRuntimeLogEntry.severity(for: Self.event(kind: .sessionHealthChanged, status: .running)),
      .warning
    )
    XCTAssertEqual(
      HermesRuntimeLogEntry.severity(for: Self.event(kind: .sessionRunning, status: .degraded)),
      .warning
    )
    XCTAssertEqual(
      HermesRuntimeLogEntry.severity(for: Self.event(kind: .sessionFailed, status: .failed)),
      .error
    )
  }

  func testClearViewClearsOnlyViewerState() async throws {
    let eventBus = HermesRuntimeEventBus()
    let controller = HermesLogsViewerController(eventBus: eventBus)
    await controller.startEventSubscription()

    eventBus.publish(Self.event(kind: .sessionRunning, status: .running))
    _ = try await waitForState(controller) { $0.entries.count == 1 }

    var state = await controller.clearView()
    XCTAssertTrue(state.entries.isEmpty)

    eventBus.publish(Self.event(kind: .sessionStopped, status: .stopped))
    state = try await waitForState(controller) { $0.entries.count == 1 }
    XCTAssertEqual(state.entries.first?.eventType, .sessionStopped)
  }

  func testErrorHandlingRedactsSensitiveEventSummary() async throws {
    let eventBus = HermesRuntimeEventBus()
    let controller = HermesLogsViewerController(eventBus: eventBus)
    await controller.startEventSubscription()

    eventBus.publish(
      Self.event(
        kind: .sessionFailed,
        status: .failed,
        errorMessage:
          "token=runtime-secret credential=bridge-secret failed at /Users/example/.hermes/bin/hermes pid=4312 process id: 9821"
      )
    )

    let state = try await waitForState(controller) { !$0.entries.isEmpty }
    let summary = try XCTUnwrap(state.entries.first?.redactedSummary)
    XCTAssertEqual(state.entries.first?.severity, .error)
    XCTAssertEqual(state.lastErrorMessage, summary)
    XCTAssertTrue(summary.contains("token=<redacted>"))
    XCTAssertTrue(summary.contains("credential=<redacted>"))
    XCTAssertTrue(summary.contains("<redacted-path>"))
    XCTAssertTrue(summary.contains("pid=<redacted>"))
    XCTAssertTrue(summary.contains("process id=<redacted>"))
    XCTAssertFalse(summary.contains("runtime-secret"))
    XCTAssertFalse(summary.contains("bridge-secret"))
    XCTAssertFalse(summary.contains("/Users/"))
    XCTAssertFalse(summary.contains("4312"))
    XCTAssertFalse(summary.contains("9821"))
  }

  private func waitForState(
    _ controller: HermesLogsViewerController,
    matching predicate: (HermesLogsViewerState) -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async throws -> HermesLogsViewerState {
    for _ in 0..<50 {
      let state = await controller.currentState()
      if predicate(state) {
        return state
      }
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTFail("Timed out waiting for logs viewer state", file: file, line: line)
    return await controller.currentState()
  }

  private static let eventDate = Date(timeIntervalSince1970: 1_800_001_000)

  private static func event(
    kind: HermesRuntimeEventKind,
    status: HermesRuntimeSessionStatus,
    errorMessage: String? = nil,
    shutdownReason: HermesRuntimeSessionShutdownReason? = nil
  ) -> HermesRuntimeEvent {
    HermesRuntimeEvent(
      kind: kind,
      session: HermesRuntimeEventSessionSummary(
        snapshot: HermesRuntimeSessionSnapshot(
          sessionID: UUID(uuidString: "10000000-0000-0000-0000-000000000301")!,
          backendIdentity: status == .created ? nil : HermesRuntimeBackendIdentity(
            executablePath: "/Applications/Hermes.app/Contents/MacOS/Hermes",
            semanticVersion: "0.18.2",
            displayVersion: "Hermes 0.18.2",
            installationMethod: "fixture",
            releaseDate: "2026-07-01",
            desktopContract: 3
          ),
          processIdentity: nil,
          startTime: status == .created ? nil : Date(timeIntervalSince1970: 1_800_000_000),
          currentStatus: status,
          capabilities: status == .created ? nil : HermesRuntimeCapabilities(
            authMode: .loopbackToken,
            desktopContract: 3,
            gatewayRunning: status == .running,
            gatewayState: status == .degraded ? "degraded" : "ready",
            gatewayBusy: false,
            gatewayDrainable: true,
            activeAgents: 0
          ),
          lastError: errorMessage.map(HermesRuntimeSessionError.init(message:)),
          shutdownReason: shutdownReason
        )
      ),
      occurredAt: eventDate
    )
  }
}
