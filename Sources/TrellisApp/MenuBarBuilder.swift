import AppKit
#if SWIFT_PACKAGE
import Trellis
#endif

func buildMainMenu() -> NSMenu {
    let mainMenu = NSMenu()

    // App menu
    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)
    appMenuItem.submenu = buildAppMenu()

    // Edit menu (standard text editing actions for TextFields / find bar)
    let editMenuItem = NSMenuItem()
    mainMenu.addItem(editMenuItem)
    editMenuItem.submenu = buildEditMenu()

    // View menu
    let viewMenuItem = NSMenuItem()
    mainMenu.addItem(viewMenuItem)
    viewMenuItem.submenu = buildViewMenu()

    return mainMenu
}

private func buildEditMenu() -> NSMenu {
    let editMenu = NSMenu(title: "Edit")

    editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

    return editMenu
}

private func buildAppMenu() -> NSMenu {
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
    return appMenu
}

private func buildViewMenu() -> NSMenu {
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

    viewMenu.addItem(NSMenuItem.separator())

    let toggleFullScreenItem = NSMenuItem(
        title: "Enter Full Screen",
        action: #selector(NSWindow.toggleFullScreen(_:)),
        keyEquivalent: "f"
    )
    toggleFullScreenItem.keyEquivalentModifierMask = [.command, .control]
    viewMenu.addItem(toggleFullScreenItem)

    return viewMenu
}
