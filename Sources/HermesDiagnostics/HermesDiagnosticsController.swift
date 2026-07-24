import Foundation

public actor HermesDiagnosticsController {
  private let provider: HermesDiagnosticProviding
  private var state: HermesDiagnosticsState

  public init(provider: HermesDiagnosticProviding) {
    self.provider = provider
    self.state = HermesDiagnosticsState()
  }

  public func currentState() -> HermesDiagnosticsState {
    state
  }

  @discardableResult
  public func refresh() async -> HermesDiagnosticsState {
    state.isRefreshing = true
    state.lastErrorMessage = nil
    do {
      state.result = try await provider.runDiagnostics()
    } catch {
      state.lastErrorMessage = HermesDiagnosticRedactor.safeDisplayText(String(describing: error), limit: 180)
    }
    state.isRefreshing = false
    return state
  }

  @discardableResult
  public func runDiagnostics() async -> HermesDiagnosticsState {
    state.isRunningDiagnostics = true
    state.lastErrorMessage = nil
    do {
      state.result = try await provider.runDiagnostics()
    } catch {
      state.lastErrorMessage = HermesDiagnosticRedactor.safeDisplayText(String(describing: error), limit: 180)
    }
    state.isRunningDiagnostics = false
    return state
  }
}
