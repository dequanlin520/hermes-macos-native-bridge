import HermesBridgeApp
import SwiftUI

@main
struct HermesBridgeAppExecutable: App {
  @NSApplicationDelegateAdaptor(HermesBridgeAppDelegate.self) private var appDelegate
  @StateObject private var compositionRoot = HermesAppCompositionRoot()

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
