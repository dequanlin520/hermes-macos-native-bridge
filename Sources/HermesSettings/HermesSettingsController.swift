import Foundation

public actor HermesSettingsController {
  private let store: HermesConfigurationStoring
  private var state: HermesSettingsState

  public init(store: HermesConfigurationStoring = HermesConfigurationStore()) {
    self.store = store
    self.state = HermesSettingsState()
  }

  public func currentState() -> HermesSettingsState {
    state
  }

  @discardableResult
  public func load() -> HermesSettingsState {
    do {
      let settings = try store.load()
      state = HermesSettingsState(settings: settings)
    } catch {
      state.lastErrorMessage = HermesSettingsRedactor.redact(error.localizedDescription)
    }
    return state
  }

  @discardableResult
  public func update(_ settings: HermesSettings) -> HermesSettingsState {
    do {
      try Self.validate(settings)
      state.settings = settings
      state.lastErrorMessage = nil
    } catch {
      state.lastErrorMessage = HermesSettingsRedactor.redact(error.localizedDescription)
    }
    return state
  }

  @discardableResult
  public func setLogLevel(_ logLevel: HermesSettingsLogLevel) -> HermesSettingsState {
    var settings = state.settings
    settings.logLevel = logLevel
    return update(settings)
  }

  @discardableResult
  public func save() -> HermesSettingsState {
    state.isSaving = true
    do {
      try Self.validate(state.settings)
      try store.save(state.settings)
      state.lastErrorMessage = nil
    } catch {
      state.lastErrorMessage = HermesSettingsRedactor.redact(error.localizedDescription)
    }
    state.isSaving = false
    return state
  }

  public static func validate(_ settings: HermesSettings) throws {
    try HermesSettingsValidator.validate(settings)
  }
}
