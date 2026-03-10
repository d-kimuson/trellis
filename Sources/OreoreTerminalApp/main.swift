import AppKit
import OreoreTerminal  // SPM build only; ignored in Makefile build (same module)
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var ghosttyApp: GhosttyAppWrapper!
    var store: WorkspaceStore!
    var notificationManager: NotificationManager!
    var outputMonitor = TerminalOutputMonitor()
    private var titleObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ghosttyApp = GhosttyAppWrapper()

        store = WorkspaceStore(ghosttyApp: ghosttyApp)

        // Set up notification manager
        notificationManager = NotificationManager()
        notificationManager.requestAuthorization()
        notificationManager.onNotificationClicked = { [weak self] workspaceIndex, areaId in
            guard let self else { return }
            self.store.focusArea(workspaceIndex: workspaceIndex, areaId: areaId)
            NSApp.activate(ignoringOtherApps: true)
            self.window?.makeKeyAndOrderFront(nil)
        }

        // Observe terminal title changes for notification triggers
        titleObserver = NotificationCenter.default.addObserver(
            forName: .ghosttyTitleChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let title = notification.userInfo?["title"] as? String else { return }
            self.handleTitleChange(title)
        }

        let contentView = ContentView(store: store)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Oreore Terminal"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
    }

    private func handleTitleChange(_ title: String) {
        let isActive = NSApp.isActive
        guard outputMonitor.shouldNotify(title: title, isAppActive: isActive) else {
            outputMonitor.recordTitle(title)
            return
        }
        guard let info = outputMonitor.buildNotificationInfo(for: title) else {
            outputMonitor.recordTitle(title)
            return
        }

        let workspaceIndex = store.activeWorkspaceIndex
        let areaId = store.activeWorkspace?.activeAreaId ?? UUID()

        notificationManager.sendNotification(
            title: info.title,
            body: info.body,
            workspaceIndex: workspaceIndex,
            areaId: areaId
        )
        outputMonitor.recordTitle(title)
        outputMonitor.recordNotificationSent()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        ghosttyApp?.shutdown()
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

let closeAreaItem = NSMenuItem(
    title: "Close Area",
    action: #selector(AppDelegate.closeArea(_:)),
    keyEquivalent: "w"
)
closeAreaItem.keyEquivalentModifierMask = [.command, .shift]
viewMenu.addItem(closeAreaItem)

viewMenuItem.submenu = viewMenu

app.mainMenu = mainMenu

app.run()
