import AppKit
import OreoreTerminal  // SPM build only; ignored in Makefile build (same module)
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var ghosttyApp: GhosttyAppWrapper!
    var store: WorkspaceStore!
    var notificationManager: NotificationManager!
    var notificationStore: NotificationStore!

    func applicationDidFinishLaunching(_ notification: Notification) {
        ghosttyApp = GhosttyAppWrapper()

        store = WorkspaceStore(ghosttyApp: ghosttyApp)
        notificationStore = NotificationStore()
        store.notificationStore = notificationStore

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
        window.title = "Oreore Terminal"
        window.delegate = self
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
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
    withTitle: "Quit Oreore Terminal",
    action: #selector(NSApplication.terminate(_:)),
    keyEquivalent: "q"
)
appMenuItem.submenu = appMenu

// View menu
let viewMenuItem = NSMenuItem()
mainMenu.addItem(viewMenuItem)
let viewMenu = NSMenu(title: "View")

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
