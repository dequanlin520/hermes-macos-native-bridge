import Foundation

public enum HermesSettingsLogLevel: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case info
  case warning
  case error
}

public struct HermesRuntimeSettings: Codable, Equatable, Sendable {
  public var autoStart: Bool
  public var healthCheckIntervalSeconds: Int
  public var startupTimeoutSeconds: Int

  public init(
    autoStart: Bool = false,
    healthCheckIntervalSeconds: Int = 30,
    startupTimeoutSeconds: Int = 60
  ) {
    self.autoStart = autoStart
    self.healthCheckIntervalSeconds = healthCheckIntervalSeconds
    self.startupTimeoutSeconds = startupTimeoutSeconds
  }
}

public struct HermesUISettings: Codable, Equatable, Sendable {
  public var showMenuBarIcon: Bool
  public var enableNotifications: Bool
  public var dashboardRefreshIntervalSeconds: Int

  public init(
    showMenuBarIcon: Bool = true,
    enableNotifications: Bool = true,
    dashboardRefreshIntervalSeconds: Int = 5
  ) {
    self.showMenuBarIcon = showMenuBarIcon
    self.enableNotifications = enableNotifications
    self.dashboardRefreshIntervalSeconds = dashboardRefreshIntervalSeconds
  }
}

public struct HermesSettings: Codable, Equatable, Sendable {
  public var runtime: HermesRuntimeSettings
  public var ui: HermesUISettings
  public var logLevel: HermesSettingsLogLevel

  public init(
    runtime: HermesRuntimeSettings = HermesRuntimeSettings(),
    ui: HermesUISettings = HermesUISettings(),
    logLevel: HermesSettingsLogLevel = .info
  ) {
    self.runtime = runtime
    self.ui = ui
    self.logLevel = logLevel
  }

  public static let defaults = HermesSettings()
}

public enum HermesSettingsValidationError: Error, Equatable, LocalizedError, Sendable {
  case negativeInterval(String)
  case invalidTimeout(String)

  public var errorDescription: String? {
    switch self {
    case .negativeInterval(let field):
      return "\(field) must not be negative"
    case .invalidTimeout(let field):
      return "\(field) must be between 1 and 3600 seconds"
    }
  }
}

public enum HermesSettingsValidator {
  public static func validate(_ settings: HermesSettings) throws {
    if settings.runtime.healthCheckIntervalSeconds < 0 {
      throw HermesSettingsValidationError.negativeInterval("healthCheckIntervalSeconds")
    }
    if settings.ui.dashboardRefreshIntervalSeconds < 0 {
      throw HermesSettingsValidationError.negativeInterval("dashboardRefreshIntervalSeconds")
    }
    if !(1...3600).contains(settings.runtime.startupTimeoutSeconds) {
      throw HermesSettingsValidationError.invalidTimeout("startupTimeoutSeconds")
    }
  }
}

public enum HermesSettingsRedactor {
  public static func redact(_ value: String, limit: Int = 240) -> String {
    var output = String(value.prefix(limit))
    let patterns = [
      #"(?i)\b(token|password|api[_ -]?key|credential|secret)\s*[:=]\s*[^,\s]+"#,
      #"(?i)\b(bearer)\s+[A-Za-z0-9._~+/\-=]+"#,
    ]
    for pattern in patterns {
      output = output.replacingOccurrences(
        of: pattern,
        with: "$1=<redacted>",
        options: .regularExpression
      )
    }
    output = output.replacingOccurrences(
      of: #"/Users/[^,\s]+"#,
      with: "<redacted-path>",
      options: .regularExpression
    )
    return output
  }
}

public struct HermesSettingsState: Equatable, Sendable {
  public var settings: HermesSettings
  public var lastErrorMessage: String?
  public var isSaving: Bool

  public init(
    settings: HermesSettings = .defaults,
    lastErrorMessage: String? = nil,
    isSaving: Bool = false
  ) {
    self.settings = settings
    self.lastErrorMessage = lastErrorMessage.map { HermesSettingsRedactor.redact($0) }
    self.isSaving = isSaving
  }
}
