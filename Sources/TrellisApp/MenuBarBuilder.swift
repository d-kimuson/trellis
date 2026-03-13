import AppKit
#if SWIFT_PACKAGE
import Trellis
#endif

func buildMainMenu(keyBindings: KeyBindingMap = .defaults) -> NSMenu {
    let mainMenu = NSMenu()

    // App menu
    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)
    appMenuItem.submenu = buildAppMenu(keyBindings: keyBindings)

    // Edit menu (standard text editing actions for TextFields / find bar)
    let editMenuItem = NSMenuItem()
    mainMenu.addItem(editMenuItem)
    editMenuItem.submenu = buildEditMenu()

    // View menu
    let viewMenuItem = NSMenuItem()
    mainMenu.addItem(viewMenuItem)
    viewMenuItem.submenu = buildViewMenu(keyBindings: keyBindings)

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

private func buildAppMenu(keyBindings: KeyBindingMap) -> NSMenu {
    let appMenu = NSMenu()
    appMenu.addItem(
        withTitle: "About Trellis",
        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
        keyEquivalent: ""
    )
    appMenu.addItem(NSMenuItem.separator())

    let settingsCombo = keyBindings.combo(for: .openSettings)
    let settingsItem = NSMenuItem(
        title: "Settings...",
        action: #selector(AppDelegate.openSettings(_:)),
        keyEquivalent: settingsCombo?.menuKeyEquivalent ?? ","
    )
    settingsItem.keyEquivalentModifierMask = settingsCombo?.menuModifierMask ?? [.command]
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

private func addMenuItem(
    to menu: NSMenu,
    title: String,
    action: Selector,
    bindableAction: BindableAction,
    keyBindings: KeyBindingMap
) {
    let combo = keyBindings.combo(for: bindableAction)
    let item = NSMenuItem(
        title: title,
        action: action,
        keyEquivalent: combo?.menuKeyEquivalent ?? ""
    )
    if let combo {
        item.keyEquivalentModifierMask = combo.menuModifierMask
    }
    menu.addItem(item)
}

private func buildViewMenu(keyBindings: KeyBindingMap) -> NSMenu {
    let viewMenu = NSMenu(title: "View")

    addMenuItem(to: viewMenu, title: "Reset Font Size",
                action: #selector(AppDelegate.resetFontSize(_:)),
                bindableAction: .resetFontSize, keyBindings: keyBindings)

    addMenuItem(to: viewMenu, title: "Increase Font Size",
                action: #selector(AppDelegate.increaseFontSize(_:)),
                bindableAction: .increaseFontSize, keyBindings: keyBindings)

    addMenuItem(to: viewMenu, title: "Decrease Font Size",
                action: #selector(AppDelegate.decreaseFontSize(_:)),
                bindableAction: .decreaseFontSize, keyBindings: keyBindings)

    viewMenu.addItem(NSMenuItem.separator())

    addMenuItem(to: viewMenu, title: "Split Horizontal",
                action: #selector(AppDelegate.splitHorizontal(_:)),
                bindableAction: .splitHorizontal, keyBindings: keyBindings)

    addMenuItem(to: viewMenu, title: "Split Vertical",
                action: #selector(AppDelegate.splitVertical(_:)),
                bindableAction: .splitVertical, keyBindings: keyBindings)

    viewMenu.addItem(NSMenuItem.separator())

    addMenuItem(to: viewMenu, title: "Close Tab",
                action: #selector(AppDelegate.closeTab(_:)),
                bindableAction: .closeTab, keyBindings: keyBindings)

    addMenuItem(to: viewMenu, title: "Close Area",
                action: #selector(AppDelegate.closeArea(_:)),
                bindableAction: .closeArea, keyBindings: keyBindings)

    viewMenu.addItem(NSMenuItem.separator())

    addMenuItem(to: viewMenu, title: "Toggle Sidebar",
                action: #selector(AppDelegate.toggleSidebar(_:)),
                bindableAction: .toggleSidebar, keyBindings: keyBindings)

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
