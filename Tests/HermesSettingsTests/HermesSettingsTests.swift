import Foundation
@testable import HermesSettings
import XCTest

final class HermesSettingsTests: XCTestCase {
  func testDefaultSettings() throws {
    let store = try makeStore()

    let settings = try store.load()

    XCTAssertEqual(settings, .defaults)
    XCTAssertFalse(settings.runtime.autoStart)
    XCTAssertEqual(settings.runtime.healthCheckIntervalSeconds, 30)
    XCTAssertEqual(settings.runtime.startupTimeoutSeconds, 60)
    XCTAssertTrue(settings.ui.showMenuBarIcon)
    XCTAssertTrue(settings.ui.enableNotifications)
    XCTAssertEqual(settings.ui.dashboardRefreshIntervalSeconds, 5)
    XCTAssertEqual(settings.logLevel, .info)
  }

  func testPersistenceRoundTripUsesUserDefaults() throws {
    let suiteName = "HermesSettingsTests.\(UUID().uuidString)"
    let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { userDefaults.removePersistentDomain(forName: suiteName) }
    let firstStore = HermesConfigurationStore(userDefaults: userDefaults)
    let secondStore = HermesConfigurationStore(userDefaults: userDefaults)
    let settings = HermesSettings(
      runtime: HermesRuntimeSettings(
        autoStart: true,
        healthCheckIntervalSeconds: 45,
        startupTimeoutSeconds: 90
      ),
      ui: HermesUISettings(
        showMenuBarIcon: false,
        enableNotifications: false,
        dashboardRefreshIntervalSeconds: 15
      ),
      logLevel: .warning
    )

    try firstStore.save(settings)

    XCTAssertEqual(try secondStore.load(), settings)
  }

  func testControllerUpdateChangesSettingsWithoutSavingUntilSave() async throws {
    let store = try makeStore()
    let controller = HermesSettingsController(store: store)
    var updated = HermesSettings.defaults
    updated.runtime.autoStart = true
    updated.ui.dashboardRefreshIntervalSeconds = 10

    let state = await controller.update(updated)

    XCTAssertEqual(state.settings, updated)
    XCTAssertNil(state.lastErrorMessage)
    XCTAssertEqual(try store.load(), .defaults)

    _ = await controller.save()
    XCTAssertEqual(try store.load(), updated)
  }

  func testInvalidValuesAreRejectedAndNotPersisted() async throws {
    let store = try makeStore()
    let controller = HermesSettingsController(store: store)
    let original = HermesSettings.defaults
    try store.save(original)
    var invalid = original
    invalid.runtime.healthCheckIntervalSeconds = -1

    let state = await controller.update(invalid)
    _ = await controller.save()

    XCTAssertEqual(state.settings, original)
    XCTAssertTrue(state.lastErrorMessage?.contains("healthCheckIntervalSeconds") ?? false)
    XCTAssertEqual(try store.load(), original)

    invalid = original
    invalid.runtime.startupTimeoutSeconds = 0
    let timeoutState = await controller.update(invalid)

    XCTAssertEqual(timeoutState.settings, original)
    XCTAssertTrue(timeoutState.lastErrorMessage?.contains("startupTimeoutSeconds") ?? false)
  }

  func testInvalidPersistedValuesAreRejectedOnLoad() async throws {
    let suiteName = "HermesSettingsTests.\(UUID().uuidString)"
    let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { userDefaults.removePersistentDomain(forName: suiteName) }
    userDefaults.set(-5, forKey: "com.hermes.settings.v1.ui.dashboardRefreshIntervalSeconds")
    let controller = HermesSettingsController(
      store: HermesConfigurationStore(userDefaults: userDefaults)
    )

    let state = await controller.load()

    XCTAssertEqual(state.settings, .defaults)
    XCTAssertTrue(state.lastErrorMessage?.contains("dashboardRefreshIntervalSeconds") ?? false)
  }

  func testLogLevelSupportsInfoWarningAndError() async throws {
    let store = try makeStore()
    let controller = HermesSettingsController(store: store)

    var state = await controller.setLogLevel(.info)
    XCTAssertEqual(state.settings.logLevel, .info)

    state = await controller.setLogLevel(.warning)
    XCTAssertEqual(state.settings.logLevel, .warning)

    state = await controller.setLogLevel(.error)
    XCTAssertEqual(state.settings.logLevel, .error)

    _ = await controller.save()
    XCTAssertEqual(try store.load().logLevel, .error)
  }

  func testRedactionRemovesSensitiveValues() {
    let redacted = HermesSettingsRedactor.redact(
      "token=settings-secret password=hunter2 api_key=abc123 credential=bridge-secret at /Users/example/.hermes/config"
    )

    XCTAssertTrue(redacted.contains("token=<redacted>"))
    XCTAssertTrue(redacted.contains("password=<redacted>"))
    XCTAssertTrue(redacted.contains("api_key=<redacted>"))
    XCTAssertTrue(redacted.contains("credential=<redacted>"))
    XCTAssertTrue(redacted.contains("<redacted-path>"))
    XCTAssertFalse(redacted.contains("settings-secret"))
    XCTAssertFalse(redacted.contains("hunter2"))
    XCTAssertFalse(redacted.contains("abc123"))
    XCTAssertFalse(redacted.contains("bridge-secret"))
    XCTAssertFalse(redacted.contains("/Users/"))
  }

  private func makeStore(
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws -> HermesConfigurationStore {
    let suiteName = "HermesSettingsTests.\(UUID().uuidString)"
    let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName), file: file, line: line)
    userDefaults.removePersistentDomain(forName: suiteName)
    return HermesConfigurationStore(userDefaults: userDefaults)
  }
}
