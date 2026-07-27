import HermesBridgeApp
import HermesBridgeAppAcceptanceSupport
import SwiftUI

@main
struct HermesBridgeAppAcceptanceHarness: App {
  @NSApplicationDelegateAdaptor(HermesBridgeAppDelegate.self) private var appDelegate
  @StateObject private var compositionRoot = HermesAppCompositionRoot()

  init() {
    if var controller = HermesM11003AcceptanceController.fromCommandLine() {
      Task { @MainActor in
        controller.startIfNeeded(compositionRoot: HermesAppCompositionRoot())
      }
    }
  }

  var body: some Scene {
    MenuBarExtra("Hermes Bridge", systemImage: "point.3.connected.trianglepath.dotted") {
      HermesBridgeMenuBarContent(compositionRoot: compositionRoot)
        .onAppear {
          appDelegate.compositionRoot = compositionRoot
          compositionRoot.start()
        }
    }
    .menuBarExtraStyle(.window)
  }
}
