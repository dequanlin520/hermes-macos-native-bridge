import AppIntents
import HermesAppIntents
import HermesBridgeMenuBar
import HermesRuntimeFoundation
import SwiftUI

@main
struct HermesBridgeApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var model = HermesBridgeAppModel()
  @Environment(\.openWindow) private var openWindow

  var body: some Scene {
    MenuBarExtra("Hermes Bridge", systemImage: "point.3.connected.trianglepath.dotted") {
      VStack(alignment: .leading, spacing: 8) {
        Text("Hermes Bridge")
          .font(.headline)
        Text("Status: \(model.state.serviceStatus.rawValue)")
        Text("Installed: \(model.state.installed ? "yes" : "no")")
        Text("Running: \(model.state.running ? "yes" : "no")")
        Text("Healthy: \(model.state.healthy ? "yes" : "no")")
        Text("Protocol: \(model.state.protocolVersion ?? "unavailable")")
        Text("Compatible: \(model.state.protocolCompatible ? "yes" : "no")")
        Text("Capabilities: \(model.state.capabilities.joined(separator: ", "))")
          .lineLimit(2)
        Text("Enabled bindings: \(model.state.enabledBindingCount)")
        Text("Pending approvals: \(model.state.pendingApprovalCount)")
        Divider()
        if model.state.recentRequests.isEmpty {
          Text("Recent requests: none")
        } else {
          ForEach(model.state.recentRequests, id: \.requestID) { request in
            Text("\(request.requestID) \(request.lifecycleState)")
              .lineLimit(1)
          }
        }
        if let message = model.state.lastActionMessage {
          Divider()
          Text(message)
        }
        Divider()
        Button("Refresh") {
          model.refresh()
        }
        Button("Start Service") {
          model.start()
        }
        Button("Restart Service") {
          model.restart()
        }
        Button("Run Doctor") {
          model.doctor()
        }
        Button("View Permissions") {
          model.permissions()
          openWindow(id: "permissions")
        }
        Button("Run Permissions Doctor") {
          model.permissions()
          openWindow(id: "permissions")
        }
        Button("Latest Audit Events") {
          model.auditEvents()
          openWindow(id: "audit-events")
        }
        Button("Export Audit Log") {
          model.exportAudit()
        }
        Button("Authorized Folders") {
          openWindow(id: "authorized-folders")
        }
        Button("Approval Inbox") {
          model.approvals()
          openWindow(id: "approval-inbox")
        }
        Button("Open Shortcuts") {
          NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
        }
        Divider()
        Button("Quit") {
          model.cancel()
          NSApplication.shared.terminate(nil)
        }
      }
      .padding(12)
      .frame(width: 320)
      .task {
        await model.load()
      }
    }
    .menuBarExtraStyle(.window)

    WindowGroup("Authorized Folders", id: "authorized-folders") {
      HermesAuthorizedFoldersWindow()
    }
    .defaultSize(width: 560, height: 520)

    WindowGroup("Permissions", id: "permissions") {
      HermesPermissionsWindow(model: model)
    }
    .defaultSize(width: 560, height: 520)

    WindowGroup("Audit Events", id: "audit-events") {
      HermesAuditEventsWindow(model: model)
    }
    .defaultSize(width: 640, height: 520)

    WindowGroup("Approval Inbox", id: "approval-inbox") {
      HermesApprovalInboxWindow(model: model)
    }
    .defaultSize(width: 640, height: 520)
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_: Notification) {
    NSApp.setActivationPolicy(.accessory)
  }
}

@MainActor
final class HermesBridgeAppModel: ObservableObject {
  @Published var state = HermesBridgeMenuBarState()
  private let viewModel = HermesBridgeMenuBarViewModel(environment: .production())

  func load() async {
    await viewModel.load()
    state = await viewModel.state
  }

  func refresh() {
    Task {
      await viewModel.refresh()
      state = await viewModel.state
    }
  }

  func start() {
    Task {
      _ = await viewModel.startService()
      state = await viewModel.state
    }
  }

  func restart() {
    Task {
      _ = await viewModel.restartService()
      state = await viewModel.state
    }
  }

  func doctor() {
    Task {
      _ = await viewModel.runDoctor()
      state = await viewModel.state
    }
  }

  func permissions() {
    Task {
      _ = await viewModel.viewPermissions()
      state = await viewModel.state
    }
  }

  func openSettings(_ code: HermesPermissionRemediationCode) {
    Task {
      _ = await viewModel.openSettings(remediationCode: code)
      state = await viewModel.state
    }
  }

  func auditEvents() {
    Task {
      _ = await viewModel.latestAuditEvents()
      state = await viewModel.state
    }
  }

  func approvals() {
    Task {
      _ = await viewModel.refreshApprovalInbox()
      state = await viewModel.state
    }
  }

  func approve(_ approvalID: String) {
    Task {
      guard let id = try? HermesEventPolicyApprovalID(rawValue: approvalID) else { return }
      _ = await viewModel.approvePolicyApproval(id: id)
      state = await viewModel.state
    }
  }

  func deny(_ approvalID: String) {
    Task {
      guard let id = try? HermesEventPolicyApprovalID(rawValue: approvalID) else { return }
      _ = await viewModel.denyPolicyApproval(id: id)
      state = await viewModel.state
    }
  }

  func exportAudit() {
    Task { @MainActor in
      let panel = NSOpenPanel()
      panel.canChooseDirectories = true
      panel.canChooseFiles = false
      panel.allowsMultipleSelection = false
      panel.canCreateDirectories = true
      panel.prompt = "Export"
      panel.title = "Choose Audit Export Folder"
      let response = await panel.begin()
      guard response == .OK, let url = panel.urls.first else {
        return
      }
      _ = await viewModel.exportAudit(to: url)
      state = await viewModel.state
    }
  }

  func cancel() {
    Task {
      await viewModel.cancelRefresh()
    }
  }
}

struct HermesApprovalInboxWindow: View {
  @ObservedObject var model: HermesBridgeAppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Pending approvals: \(model.state.pendingApprovalCount)")
          .font(.headline)
        Spacer()
        Button("Refresh") {
          model.approvals()
        }
      }
      if model.state.approvalInboxUnavailable {
        Text("Approval inbox unavailable")
          .foregroundStyle(.secondary)
      }
      List {
        Section("Pending") {
          ForEach(model.state.pendingApprovals) { approval in
            VStack(alignment: .leading, spacing: 6) {
              Text(approval.safeSummary)
                .font(.headline)
              Text("\(approval.eventKind) · \(approval.actionKind)")
                .foregroundStyle(.secondary)
              Text("Expires \(approval.expiresAt.formatted(date: .omitted, time: .standard))")
                .foregroundStyle(.secondary)
              HStack {
                Button("Approve") {
                  model.approve(approval.approvalID)
                }
                Button("Deny") {
                  model.deny(approval.approvalID)
                }
              }
            }
          }
        }
        Section("Recent") {
          ForEach(model.state.recentCompletedApprovals) { approval in
            VStack(alignment: .leading) {
              Text("\(approval.policyID) · \(approval.state)")
              Text("\(approval.result) · \(approval.reasonCode)")
                .foregroundStyle(.secondary)
            }
          }
        }
      }
    }
    .padding(16)
    .task {
      model.approvals()
    }
  }
}

struct HermesPermissionsWindow: View {
  @ObservedObject var model: HermesBridgeAppModel

  var body: some View {
    List {
      ForEach(model.state.permissionChecks) { check in
        HStack {
          VStack(alignment: .leading) {
            Text(check.kind)
              .font(.headline)
            Text("\(check.state) · \(check.detailCode)")
              .foregroundStyle(.secondary)
          }
          Spacer()
          if let code = check.remediationCode,
            let remediation = HermesPermissionRemediationCode(rawValue: code),
            HermesSystemSettingsRemediationURL.url(for: remediation) != nil
          {
            Button("Open Settings") {
              model.openSettings(remediation)
            }
          }
        }
      }
    }
    .task {
      model.permissions()
    }
  }
}

struct HermesAuditEventsWindow: View {
  @ObservedObject var model: HermesBridgeAppModel

  var body: some View {
    List {
      ForEach(model.state.recentAuditEvents) { event in
        VStack(alignment: .leading) {
          Text("\(event.kind) · \(event.outcome)")
            .font(.headline)
          Text("\(event.reasonCode) · \(event.actor)")
            .foregroundStyle(.secondary)
        }
      }
    }
    .task {
      model.auditEvents()
    }
  }
}

@MainActor
final class HermesAuthorizedFoldersModel: ObservableObject {
  @Published var state = HermesAuthorizedRootManagementState()
  private let viewModel: HermesAuthorizedRootManagementViewModel

  init(
    viewModel: HermesAuthorizedRootManagementViewModel = HermesAuthorizedRootManagementViewModel(
      panelSelector: NSOpenPanelHermesAuthorizedRootSelector(),
      bookmarkCreator: ProductionHermesAuthorizedRootBookmarkCreator(),
      client: ProductionAuthorizedRootAppClient(layout: .production())
    )
  ) {
    self.viewModel = viewModel
  }

  func load() async {
    await viewModel.load()
    state = await viewModel.state
  }

  func refresh() {
    Task {
      await viewModel.refresh()
      state = await viewModel.state
    }
  }

  func addFolder() {
    Task {
      _ = await viewModel.addFolder()
      state = await viewModel.state
    }
  }

  func refreshAuthorization(_ root: HermesAuthorizedRootViewState) {
    Task {
      _ = await viewModel.refreshAuthorization(rootID: root.rootID, expectedRevision: root.revision)
      state = await viewModel.state
    }
  }

  func deactivate(_ root: HermesAuthorizedRootViewState) {
    Task {
      _ = await viewModel.deactivate(rootID: root.rootID, expectedRevision: root.revision)
      state = await viewModel.state
    }
  }

  func reactivate(_ root: HermesAuthorizedRootViewState) {
    Task {
      _ = await viewModel.reactivate(rootID: root.rootID, expectedRevision: root.revision)
      state = await viewModel.state
    }
  }

  func remove(_ root: HermesAuthorizedRootViewState, confirmed: Bool) {
    Task {
      _ = await viewModel.remove(
        rootID: root.rootID,
        expectedRevision: root.revision,
        confirmed: confirmed
      )
      state = await viewModel.state
    }
  }

  func cancel() {
    Task {
      await viewModel.cancelTasks()
    }
  }
}

struct HermesAuthorizedFoldersWindow: View {
  @StateObject private var model = HermesAuthorizedFoldersModel()
  @State private var pendingRemoval: HermesAuthorizedRootViewState?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Authorized Folders")
          .font(.title2)
        Spacer()
        Button {
          model.refresh()
        } label: {
          Label("Refresh Status", systemImage: "arrow.clockwise")
        }
        Button {
          model.addFolder()
        } label: {
          Label("Add Folder", systemImage: "folder.badge.plus")
        }
        .disabled(model.state.addInProgress)
      }

      statusView

      if model.state.roots.isEmpty && model.state.loadingState == .loaded {
        VStack(spacing: 8) {
          Image(systemName: "folder")
            .font(.largeTitle)
            .foregroundStyle(.secondary)
          Text("No Authorized Folders")
            .font(.headline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List(model.state.roots) { root in
          HermesAuthorizedRootRow(
            root: root,
            refreshAuthorization: { model.refreshAuthorization(root) },
            deactivate: { model.deactivate(root) },
            reactivate: { model.reactivate(root) },
            remove: { pendingRemoval = root }
          )
        }
        .listStyle(.inset)
      }

      if let action = model.state.lastAction {
        Text(action.safeMessage)
          .foregroundStyle(action.succeeded ? Color.secondary : Color.red)
          .lineLimit(2)
      }
    }
    .padding(16)
    .frame(minWidth: 520, minHeight: 460)
    .task {
      await model.load()
    }
    .onDisappear {
      model.cancel()
    }
    .confirmationDialog(
      "Remove Authorized Folder?",
      isPresented: Binding(
        get: { pendingRemoval != nil },
        set: { if !$0 { pendingRemoval = nil } }
      ),
      presenting: pendingRemoval
    ) { root in
      Button("Remove", role: .destructive) {
        model.remove(root, confirmed: true)
        pendingRemoval = nil
      }
      Button("Cancel", role: .cancel) {
        pendingRemoval = nil
      }
    } message: { root in
      Text("Remove authorization for \(root.displayName)?")
    }
  }

  @ViewBuilder
  private var statusView: some View {
    switch model.state.loadingState {
    case .loading:
      Label("Loading authorized folders", systemImage: "hourglass")
        .foregroundStyle(.secondary)
    case .loaded:
      Label("\(model.state.roots.count) authorized folder(s)", systemImage: "checkmark.circle")
        .foregroundStyle(.secondary)
    case .unavailable:
      Label(
        model.state.safeMessage ?? "Authorized folder service unavailable",
        systemImage: "exclamationmark.triangle"
      )
      .foregroundStyle(.orange)
    case .failed:
      Label(model.state.safeMessage ?? "Authorized folders failed", systemImage: "xmark.circle")
        .foregroundStyle(.red)
    }
  }
}

struct HermesAuthorizedRootRow: View {
  let root: HermesAuthorizedRootViewState
  let refreshAuthorization: () -> Void
  let deactivate: () -> Void
  let reactivate: () -> Void
  let remove: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Text(root.displayName)
          .font(.headline)
        Spacer()
        Text(root.active ? "Active" : "Inactive")
          .foregroundStyle(root.active ? .green : .secondary)
      }
      HStack(spacing: 10) {
        Label(
          root.staleAuthorization ? "Stale authorization" : "Authorization current",
          systemImage: root.staleAuthorization ? "exclamationmark.triangle" : "checkmark.seal")
        Label("Monitor \(root.monitorState.rawValue)", systemImage: "waveform.path.ecg")
        if root.rescanRequired {
          Label("Rescan required", systemImage: "arrow.triangle.2.circlepath")
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)

      Text("Last event ID: \(root.lastObservedEventID)")
        .font(.caption)
        .foregroundStyle(.secondary)

      HStack {
        Button {
          refreshAuthorization()
        } label: {
          Label("Refresh Authorization", systemImage: "lock.rotation")
        }
        if root.active {
          Button {
            deactivate()
          } label: {
            Label("Deactivate", systemImage: "pause.circle")
          }
        } else {
          Button {
            reactivate()
          } label: {
            Label("Activate", systemImage: "play.circle")
          }
        }
        Spacer()
        Button(role: .destructive) {
          remove()
        } label: {
          Label("Remove", systemImage: "trash")
        }
      }
      .buttonStyle(.bordered)
    }
    .padding(.vertical, 6)
  }
}
