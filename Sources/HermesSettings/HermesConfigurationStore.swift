import Foundation

public protocol HermesConfigurationStoring: Sendable {
  func load() throws -> HermesSettings
  func save(_ settings: HermesSettings) throws
}

public final class HermesConfigurationStore: HermesConfigurationStoring, @unchecked Sendable {
  public enum StoreError: Error, Equatable, LocalizedError, Sendable {
    case sensitiveKeyRejected(String)

    public var errorDescription: String? {
      switch self {
      case .sensitiveKeyRejected(let key):
        return "Sensitive settings key rejected: \(key)"
      }
    }
  }

  private enum Keys {
    static let prefix = "com.hermes.settings.v1."
    static let autoStart = prefix + "runtime.autoStart"
    static let healthCheckIntervalSeconds = prefix + "runtime.healthCheckIntervalSeconds"
    static let startupTimeoutSeconds = prefix + "runtime.startupTimeoutSeconds"
    static let showMenuBarIcon = prefix + "ui.showMenuBarIcon"
    static let enableNotifications = prefix + "ui.enableNotifications"
    static let dashboardRefreshIntervalSeconds = prefix + "ui.dashboardRefreshIntervalSeconds"
    static let logLevel = prefix + "logging.level"

    static let all = [
      autoStart,
      healthCheckIntervalSeconds,
      startupTimeoutSeconds,
      showMenuBarIcon,
      enableNotifications,
      dashboardRefreshIntervalSeconds,
      logLevel,
    ]
  }

  private let userDefaults: UserDefaults
  private let lock = NSLock()

  public init(userDefaults: UserDefaults = .standard) {
    self.userDefaults = userDefaults
  }

  public func load() throws -> HermesSettings {
    try rejectSensitiveKeys(Keys.all)
    let settings = lock.withLock {
      let defaults = HermesSettings.defaults
      return HermesSettings(
        runtime: HermesRuntimeSettings(
          autoStart: bool(for: Keys.autoStart, defaultValue: defaults.runtime.autoStart),
          healthCheckIntervalSeconds: int(
            for: Keys.healthCheckIntervalSeconds,
            defaultValue: defaults.runtime.healthCheckIntervalSeconds
          ),
          startupTimeoutSeconds: int(
            for: Keys.startupTimeoutSeconds,
            defaultValue: defaults.runtime.startupTimeoutSeconds
          )
        ),
        ui: HermesUISettings(
          showMenuBarIcon: bool(for: Keys.showMenuBarIcon, defaultValue: defaults.ui.showMenuBarIcon),
          enableNotifications: bool(
            for: Keys.enableNotifications,
            defaultValue: defaults.ui.enableNotifications
          ),
          dashboardRefreshIntervalSeconds: int(
            for: Keys.dashboardRefreshIntervalSeconds,
            defaultValue: defaults.ui.dashboardRefreshIntervalSeconds
          )
        ),
        logLevel: HermesSettingsLogLevel(
          rawValue: string(for: Keys.logLevel, defaultValue: defaults.logLevel.rawValue)
        ) ?? defaults.logLevel
      )
    }
    try HermesSettingsValidator.validate(settings)
    return settings
  }

  public func save(_ settings: HermesSettings) throws {
    try HermesSettingsValidator.validate(settings)
    try rejectSensitiveKeys(Keys.all)
    lock.withLock {
      userDefaults.set(settings.runtime.autoStart, forKey: Keys.autoStart)
      userDefaults.set(settings.runtime.healthCheckIntervalSeconds, forKey: Keys.healthCheckIntervalSeconds)
      userDefaults.set(settings.runtime.startupTimeoutSeconds, forKey: Keys.startupTimeoutSeconds)
      userDefaults.set(settings.ui.showMenuBarIcon, forKey: Keys.showMenuBarIcon)
      userDefaults.set(settings.ui.enableNotifications, forKey: Keys.enableNotifications)
      userDefaults.set(settings.ui.dashboardRefreshIntervalSeconds, forKey: Keys.dashboardRefreshIntervalSeconds)
      userDefaults.set(settings.logLevel.rawValue, forKey: Keys.logLevel)
    }
  }

  public func removePersistedSettings() {
    lock.withLock {
      Keys.all.forEach { userDefaults.removeObject(forKey: $0) }
    }
  }

  private func rejectSensitiveKeys(_ keys: [String]) throws {
    let sensitiveFragments = ["token", "password", "apiKey", "api_key", "credential", "secret"]
    if let sensitiveKey = keys.first(where: { key in
      sensitiveFragments.contains { key.localizedCaseInsensitiveContains($0) }
    }) {
      throw StoreError.sensitiveKeyRejected(sensitiveKey)
    }
  }

  private func bool(for key: String, defaultValue: Bool) -> Bool {
    guard userDefaults.object(forKey: key) != nil else { return defaultValue }
    return userDefaults.bool(forKey: key)
  }

  private func int(for key: String, defaultValue: Int) -> Int {
    guard userDefaults.object(forKey: key) != nil else { return defaultValue }
    return userDefaults.integer(forKey: key)
  }

  private func string(for key: String, defaultValue: String) -> String {
    userDefaults.string(forKey: key) ?? defaultValue
  }
}
