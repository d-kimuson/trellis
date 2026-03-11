import AppKit
import Combine
#if SWIFT_PACKAGE
import Trellis  // SPM/xcodebuild only; Makefile compiles all files as one module
#endif
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var ghosttyApp: GhosttyAppWrapper!
    var store: WorkspaceStore!
    var notificationManager: NotificationManager!
    var notificationStore: NotificationStore!
    private var cancellables = Set<AnyCancellable>()
    private var sessionTitleCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ghosttyApp = GhosttyAppWrapper()

        store = WorkspaceStore(ghosttyApp: ghosttyApp)
        notificationStore = NotificationStore()
        store.notificationStore = notificationStore

        // Sync unread count to Dock badge
        notificationStore.$notifications
            .map { notifs in notifs.count(where: { !$0.isRead }) }
            .removeDuplicates()
            .sink { count in
                NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : ""
            }
            .store(in: &cancellables)

        // Dynamic window title: update on store changes and session pwd changes
        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateWindowTitle()
                    self?.subscribeToRepresentativeSession()
                }
            }
            .store(in: &cancellables)

        // Set up notification manager
        notificationManager = NotificationManager()
        notificationManager.requestAuthorization()
        notificationManager.onNotificationClicked = { [weak self] workspaceIndex, areaId in
            guard let self else { return }
            self.store.focusArea(workspaceIndex: workspaceIndex, areaId: areaId)
            self.notificationStore.markAsRead(areaId: areaId)
            NSApp.activate(ignoringOtherApps: true)
            self.window?.makeKeyAndOrderFront(nil)
        }

        // OSC 9/777 desktop notification — direct callback (no async dispatch)
        ghosttyApp.onDesktopNotification = { [weak self] title, body in
            self?.handleDesktopNotification(title: title, body: body)
        }

        let contentView = ContentView(store: store, notificationStore: notificationStore)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Trellis"
        window.delegate = self
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
    }

    private func subscribeToRepresentativeSession() {
        sessionTitleCancellable = store.activeWorkspace?.representativeSession?.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateWindowTitle() }
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

    private func handleDesktopNotification(title: String, body: String) {
        let workspaceIndex = store.activeWorkspaceIndex
        let areaId = store.activeWorkspace?.activeAreaId ?? UUID()

        notificationStore.add(
            title: title,
            body: body,
            workspaceIndex: workspaceIndex,
            areaId: areaId
        )

        // Desktop notification only when app is inactive
        if !NSApp.isActive {
            notificationManager.sendNotification(
                title: title,
                body: body,
                workspaceIndex: workspaceIndex,
                areaId: areaId
            )
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
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
        // Post notification for ContentView to handle
        NotificationCenter.default.post(name: .toggleSidebar, object: nil)
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
        NotificationCenter.default.post(name: .openSettings, object: nil)
    }

    @objc func checkForUpdates(_ sender: Any?) {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

        let url = URL(string: "https://api.github.com/repos/d-kimuson/trellis/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                guard let data, error == nil,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String,
                      let htmlUrl = json["html_url"] as? String
                else {
                    let alert = NSAlert()
                    alert.messageText = "Update Check Failed"
                    alert.informativeText = "Could not reach GitHub. Check your connection."
                    alert.runModal()
                    return
                }

                let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

                if latestVersion == currentVersion {
                    let alert = NSAlert()
                    alert.messageText = "Trellis is up to date"
                    alert.informativeText = "Version \(currentVersion) is the latest."
                    alert.runModal()
                } else {
                    let alert = NSAlert()
                    alert.messageText = "Update Available"
                    alert.informativeText = "Version \(latestVersion) is available (you have \(currentVersion))."
                    alert.addButton(withTitle: "Open Release Page")
                    alert.addButton(withTitle: "Cancel")
                    if alert.runModal() == .alertFirstButtonReturn {
                        NSWorkspace.shared.open(URL(string: htmlUrl)!)
                    }
                }
            }
        }.resume()
    }
}

// Entry point
let app = NSApplication.shared
app.setActivationPolicy(.regular)

let delegate = AppDelegate()
app.delegate = delegate

// Create menu bar
let mainMenu = NSMenu()

// App menu
let appMenuItem = NSMenuItem()
mainMenu.addItem(appMenuItem)
let appMenu = NSMenu()
appMenu.addItem(
    withTitle: "About Trellis",
    action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
    keyEquivalent: ""
)
appMenu.addItem(NSMenuItem.separator())

let settingsItem = NSMenuItem(
    title: "Settings...",
    action: #selector(AppDelegate.openSettings(_:)),
    keyEquivalent: ","
)
settingsItem.keyEquivalentModifierMask = [.command]
appMenu.addItem(settingsItem)

appMenu.addItem(NSMenuItem.separator())
appMenu.addItem(
    withTitle: "Check for Updates...",
    action: #selector(AppDelegate.checkForUpdates(_:)),
    keyEquivalent: ""
)
appMenu.addItem(NSMenuItem.separator())
appMenu.addItem(
    withTitle: "Quit Trellis",
    action: #selector(NSApplication.terminate(_:)),
    keyEquivalent: "q"
)
appMenuItem.submenu = appMenu

// View menu
let viewMenuItem = NSMenuItem()
mainMenu.addItem(viewMenuItem)
let viewMenu = NSMenu(title: "View")

let resetFontSizeItem = NSMenuItem(
    title: "Reset Font Size",
    action: #selector(AppDelegate.resetFontSize(_:)),
    keyEquivalent: "0"
)
resetFontSizeItem.keyEquivalentModifierMask = [.command]
viewMenu.addItem(resetFontSizeItem)

let increaseFontSizeItem = NSMenuItem(
    title: "Increase Font Size",
    action: #selector(AppDelegate.increaseFontSize(_:)),
    keyEquivalent: "+"
)
increaseFontSizeItem.keyEquivalentModifierMask = [.command]
viewMenu.addItem(increaseFontSizeItem)

let decreaseFontSizeItem = NSMenuItem(
    title: "Decrease Font Size",
    action: #selector(AppDelegate.decreaseFontSize(_:)),
    keyEquivalent: "-"
)
decreaseFontSizeItem.keyEquivalentModifierMask = [.command]
viewMenu.addItem(decreaseFontSizeItem)

viewMenu.addItem(NSMenuItem.separator())

let splitHItem = NSMenuItem(
    title: "Split Horizontal",
    action: #selector(AppDelegate.splitHorizontal(_:)),
    keyEquivalent: "d"
)
splitHItem.keyEquivalentModifierMask = [.command]
viewMenu.addItem(splitHItem)

let splitVItem = NSMenuItem(
    title: "Split Vertical",
    action: #selector(AppDelegate.splitVertical(_:)),
    keyEquivalent: "d"
)
splitVItem.keyEquivalentModifierMask = [.command, .shift]
viewMenu.addItem(splitVItem)

viewMenu.addItem(NSMenuItem.separator())

let closeTabItem = NSMenuItem(
    title: "Close Tab",
    action: #selector(AppDelegate.closeTab(_:)),
    keyEquivalent: "w"
)
closeTabItem.keyEquivalentModifierMask = [.command]
viewMenu.addItem(closeTabItem)

let closeAreaItem = NSMenuItem(
    title: "Close Area",
    action: #selector(AppDelegate.closeArea(_:)),
    keyEquivalent: "w"
)
closeAreaItem.keyEquivalentModifierMask = [.command, .shift]
viewMenu.addItem(closeAreaItem)

viewMenu.addItem(NSMenuItem.separator())

let toggleSidebarItem = NSMenuItem(
    title: "Toggle Sidebar",
    action: #selector(AppDelegate.toggleSidebar(_:)),
    keyEquivalent: "b"
)
toggleSidebarItem.keyEquivalentModifierMask = [.command]
viewMenu.addItem(toggleSidebarItem)

viewMenuItem.submenu = viewMenu

app.mainMenu = mainMenu

app.run()
