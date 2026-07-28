import AppKit
import Foundation

public enum HermesNativeUIWindowIdentifier: String, CaseIterable, Equatable, Hashable, Sendable {
  case onboarding = "com.hermes.bridge.window.onboarding"
  case dashboard = "com.hermes.bridge.window.dashboard"
  case logs = "com.hermes.bridge.window.logs"
  case settings = "com.hermes.bridge.window.settings"
  case diagnostics = "com.hermes.bridge.window.diagnostics"
  case update = "com.hermes.bridge.window.update"
  case notifications = "com.hermes.bridge.window.notifications"
  case timeline = "com.hermes.bridge.window.timeline"
  case search = "com.hermes.bridge.window.search"
  case recovery = "com.hermes.bridge.window.recovery"
}

@MainActor
public protocol HermesNativeUIWindowControlling: AnyObject {
  var identifier: HermesNativeUIWindowIdentifier { get }
  var isOpen: Bool { get }
  func show()
  func focus()
  func close()
  func cleanup()
}

public protocol HermesNativeUIWindowFactory: Sendable {
  @MainActor
  func makeWindow(
    for identifier: HermesNativeUIWindowIdentifier,
    clientGraph: HermesAppClientGraph
  ) -> HermesNativeUIWindowControlling
}

@MainActor
public final class HermesWindowCoordinator {
  public private(set) var openedWindowIdentifiers: Set<HermesNativeUIWindowIdentifier> = []

  public let clientGraph: HermesAppClientGraph
  private let windowFactory: HermesNativeUIWindowFactory
  private var windows: [HermesNativeUIWindowIdentifier: HermesNativeUIWindowControlling] = [:]

  public init(
    clientGraph: HermesAppClientGraph,
    windowFactory: HermesNativeUIWindowFactory
  ) {
    self.clientGraph = clientGraph
    self.windowFactory = windowFactory
  }

  public func open(_ identifier: HermesNativeUIWindowIdentifier) {
    if let existing = windows[identifier] {
      if existing.isOpen {
        existing.focus()
      } else {
        existing.show()
      }
      openedWindowIdentifiers.insert(identifier)
      return
    }

    let window = windowFactory.makeWindow(for: identifier, clientGraph: clientGraph)
    windows[identifier] = window
    openedWindowIdentifiers.insert(identifier)
    window.show()
  }

  public func close(_ identifier: HermesNativeUIWindowIdentifier) {
    windows[identifier]?.close()
  }

  public func cleanup() {
    for window in windows.values {
      window.cleanup()
    }
    windows.removeAll()
    openedWindowIdentifiers.removeAll()
  }

  public func windowCount(for identifier: HermesNativeUIWindowIdentifier) -> Int {
    windows[identifier] == nil ? 0 : 1
  }
}

@MainActor
public final class HermesAppKitWindowControllerAdapter: NSObject, HermesNativeUIWindowControlling,
  NSWindowDelegate
{
  public let identifier: HermesNativeUIWindowIdentifier
  private let controller: NSWindowController

  public init(
    identifier: HermesNativeUIWindowIdentifier,
    controller: NSWindowController
  ) {
    self.identifier = identifier
    self.controller = controller
    super.init()
    controller.window?.identifier = NSUserInterfaceItemIdentifier(identifier.rawValue)
    controller.window?.isReleasedWhenClosed = false
    controller.window?.delegate = self
  }

  public var isOpen: Bool {
    controller.window?.isVisible == true
  }

  public func show() {
    controller.showWindow(nil)
    controller.window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  public func focus() {
    show()
  }

  public func close() {
    controller.window?.close()
  }

  public func cleanup() {
    controller.window?.delegate = nil
    controller.close()
  }
}
