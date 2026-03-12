import AppKit
#if SWIFT_PACKAGE
import Trellis
#endif

func buildMainMenu() -> NSMenu {
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

    return mainMenu
}
