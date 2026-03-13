import AppKit
import Combine
#if SWIFT_PACKAGE
import Trellis  // SPM/xcodebuild only; Makefile compiles all files as one module
#endif
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var ghosttyApp: GhosttyAppWrapper!
    var store: WorkspaceStore!
    var notificationManager: NotificationManager!
    var notificationStore: NotificationStore!
    var ipcServer: IPCServer!
    private var sessionTitleCancellable: AnyCancellable?
    private var settingsPanel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.migrateFromUserDefaultsIfNeeded()

        ghosttyApp = GhosttyAppWrapper()

        store = WorkspaceStore(ghosttyApp: ghosttyApp)
        ghosttyApp.store = store
        notificationStore = NotificationStore()
        store.notificationStore = notificationStore

        // Sync unread count to Dock badge
        observeNotificationBadge()

        // Dynamic window title: update on store changes and session pwd changes
        observeStoreForWindowTitle()

        // Set up notification manager
        notificationManager = NotificationManager()
        notificationManager.requestAuthorization()
        notificationManager.onNotificationClicked = { [weak self] sessionId in
            guard let self else { return }
            self.store.focusSession(id: sessionId)
            NSApp.activate(ignoringOtherApps: true)
            self.window?.makeKeyAndOrderFront(nil)
        }

        // OSC 9/777 desktop notification — direct callback (no async dispatch)
        ghosttyApp.onDesktopNotification = { [weak self] title, body, shouldFireDesktop, sourceSession in
            self?.handleDesktopNotification(title: title, body: body, shouldFireDesktop: shouldFireDesktop, sourceSession: sourceSession)
        }

        let contentView = ContentView(store: store, notificationStore: notificationStore,
                                       onOpenSettings: { [weak self] in self?.openSettingsPanel() })

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Trellis"
        window.delegate = self
        window.collectionBehavior = [.fullScreenPrimary]
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)

        // IPC server for external CLI control (trellis-cli)
        let settings = AppSettings.shared
        ipcServer = IPCServer(store: store, ghosttyApp: ghosttyApp)
        if settings.ipcServerEnabled {
            do {
                try ipcServer.start()
                debugLog("[STARTUP] IPC server started at \(IPCServer.socketPath)")
            } catch {
                debugLog("[STARTUP] IPC server failed to start: \(error)")
            }
        }
        observeIPCServerEnabled()
        observeKeyBindings()
    }

    private func observeKeyBindings() {
        withObservationTracking {
            _ = AppSettings.shared.keyBindings
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard self != nil else { return }
                NSApp.mainMenu = buildMainMenu(keyBindings: AppSettings.shared.keyBindings)
                self?.observeKeyBindings()
            }
        }
    }

    func openSettingsPanel() {
        if let panel = settingsPanel, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let settings = AppSettings.shared
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 680),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Settings"
        panel.isReleasedWhenClosed = false
        let settingsView = SettingsView(
            settings: settings,
            onApply: { [weak self] in self?.store?.ghosttyApp.applySettings(settings) },
            onClose: { [weak panel] in panel?.close() }
        )
        panel.contentView = NSHostingView(rootView: settingsView)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        settingsPanel = panel
    }

    private func observeIPCServerEnabled() {
        withObservationTracking {
            _ = AppSettings.shared.ipcServerEnabled
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let enabled = AppSettings.shared.ipcServerEnabled
                if enabled {
                    do {
                        try self.ipcServer.start()
                        debugLog("[IPC] Server started at \(IPCServer.socketPath)")
                    } catch {
                        debugLog("[IPC] Server failed to start: \(error)")
                    }
                } else {
                    self.ipcServer.stop()
                    debugLog("[IPC] Server stopped")
                }
                observeIPCServerEnabled()
            }
        }
    }

    private func observeNotificationBadge() {
        withObservationTracking {
            _ = notificationStore.notifications
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let count = notificationStore.notifications.count(where: { !$0.isRead })
                NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : ""
                observeNotificationBadge()
            }
        }
    }

    private func observeStoreForWindowTitle() {
        withObservationTracking {
            _ = store.workspaces
            _ = store.activeWorkspaceIndex
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                updateWindowTitle()
                subscribeToRepresentativeSession()
                observeStoreForWindowTitle()
            }
        }
    }

    private func subscribeToRepresentativeSession() {
        guard let session = store.activeWorkspace?.representativeSession else {
            sessionTitleCancellable = nil
            return
        }
        // Observe session properties used in window title (pwd, title) via @Observable tracking.
        sessionTitleCancellable = nil  // Clear previous subscription
        observeSessionForWindowTitle(session)
    }

    private func observeSessionForWindowTitle(_ session: TerminalSession) {
        withObservationTracking {
            _ = session.pwd
            _ = session.title
        } onChange: { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.updateWindowTitle()
                // Re-arm observation if the session is still representative
                if self?.store.activeWorkspace?.representativeSession === session {
                    self?.observeSessionForWindowTitle(session)
                }
            }
        }
    }

    private func updateWindowTitle() {
        guard let workspace = store.activeWorkspace else {
            window.title = "Trellis"
            return
        }
        if let cwd = workspace.representativeSession?.shortPwd {
            let safeCwd = cwd.replacingOccurrences(of: "/", with: "∕")
            window.title = "Trellis / 📂 \(safeCwd) / \(workspace.name)"
        } else {
            window.title = "Trellis / \(workspace.name)"
        }
    }

    private func handleDesktopNotification(
        title: String,
        body: String,
        shouldFireDesktop: Bool,
        sourceSession: TerminalSession?
    ) {
        // Use the source session's ID, falling back to the active terminal session.
        let sessionId: UUID
        if let session = sourceSession {
            sessionId = session.id
        } else if let activeSession = store.activeWorkspace?.activeArea?.activeTab?.content.terminalSession {
            sessionId = activeSession.id
        } else {
            sessionId = UUID()
        }

        let workspaceName = store.workspaceName(forSession: sessionId)
        notificationStore.add(title: title, body: body, sessionId: sessionId, workspaceName: workspaceName)

        // Fire desktop notification when the source terminal is not the focused surface
        if shouldFireDesktop {
            notificationManager.sendNotification(title: title, body: body, sessionId: sessionId, workspaceName: workspaceName)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.saveSnapshot()
        ipcServer?.stop()
        ghosttyApp?.shutdown()
    }

    // MARK: - Window Delegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        true
    }

    // MARK: - Menu Actions

    @objc func splitHorizontal(_ sender: Any?) {
        store?.splitActiveArea(direction: .horizontal)
    }

    @objc func splitVertical(_ sender: Any?) {
        store?.splitActiveArea(direction: .vertical)
    }

    @objc func closeArea(_ sender: Any?) {
        store?.closeActiveArea()
    }

    @objc func closeTab(_ sender: Any?) {
        guard let workspace = store?.activeWorkspace,
              let areaId = workspace.activeAreaId,
              let area = workspace.layout.findArea(id: areaId) else { return }
        store?.closeTab(in: areaId, at: area.activeTabIndex)
    }

    @objc func toggleSidebar(_ sender: Any?) {
        store?.dispatch(.toggleSidebar)
    }

    @objc func increaseFontSize(_ sender: Any?) {
        ghosttyApp?.increaseFontSize()
    }

    @objc func decreaseFontSize(_ sender: Any?) {
        ghosttyApp?.decreaseFontSize()
    }

    @objc func resetFontSize(_ sender: Any?) {
        ghosttyApp?.resetFontSize()
    }

    @objc func openSettings(_ sender: Any?) {
        openSettingsPanel()
    }

    private struct GithubRelease: Decodable {
        let tagName: String
        let htmlUrl: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlUrl = "html_url"
        }
    }

    @objc func checkForUpdates(_ sender: Any?) {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

        let url = URL(string: "https://api.github.com/repos/d-kimuson/trellis/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                let window = NSApp.keyWindow ?? NSApp.mainWindow

                guard let data, error == nil,
                      let release = try? JSONDecoder().decode(GithubRelease.self, from: data)
                else {
                    let alert = NSAlert()
                    alert.messageText = "Update Check Failed"
                    alert.informativeText = "Could not reach GitHub. Check your connection."
                    if let window {
                        alert.beginSheetModal(for: window) { _ in }
                    } else {
                        alert.runModal()
                    }
                    return
                }

                let tagName = release.tagName
                let htmlUrl = release.htmlUrl
                let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

                if latestVersion == currentVersion {
                    let alert = NSAlert()
                    alert.messageText = "Trellis is up to date"
                    alert.informativeText = "Version \(currentVersion) is the latest."
                    if let window {
                        alert.beginSheetModal(for: window) { _ in }
                    } else {
                        alert.runModal()
                    }
                } else {
                    let alert = NSAlert()
                    alert.messageText = "Update Available"
                    alert.informativeText = "Version \(latestVersion) is available (you have \(currentVersion))."
                    alert.addButton(withTitle: "Open Release Page")
                    alert.addButton(withTitle: "Cancel")
                    if let window {
                        alert.beginSheetModal(for: window) { response in
                            if response == .alertFirstButtonReturn {
                                NSWorkspace.shared.open(URL(string: htmlUrl)!)
                            }
                        }
                    } else {
                        if alert.runModal() == .alertFirstButtonReturn {
                            NSWorkspace.shared.open(URL(string: htmlUrl)!)
                        }
                    }
                }
            }
        }.resume()
    }
}

// CLI mode check: exits early if invoked as a CLI subcommand (e.g. `trellis list-panels`).
checkAndRunCLIMode()

// GUI entry point
let app = NSApplication.shared
app.setActivationPolicy(.regular)

let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate

// Create menu bar
app.mainMenu = MainActor.assumeIsolated {
    buildMainMenu(keyBindings: AppSettings.shared.keyBindings)
}

app.run()
