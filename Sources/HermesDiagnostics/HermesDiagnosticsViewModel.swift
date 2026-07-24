import Foundation
import SwiftUI

@MainActor
public final class HermesDiagnosticsViewModel: ObservableObject {
  @Published public private(set) var state: HermesDiagnosticsState

  private let controller: HermesDiagnosticsController

  public init(controller: HermesDiagnosticsController) {
    self.controller = controller
    self.state = HermesDiagnosticsState()
  }

  public convenience init(provider: HermesDiagnosticProviding) {
    self.init(controller: HermesDiagnosticsController(provider: provider))
  }

  public func refresh() {
    Task {
      state = await controller.refresh()
    }
  }

  public func runDiagnostics() {
    Task {
      state = await controller.runDiagnostics()
    }
  }
}
