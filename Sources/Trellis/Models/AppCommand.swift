import Foundation

/// A command that can be executed from the command palette.
public struct AppCommand: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let icon: String
    public let keywords: [String]

    public init(id: String, title: String, icon: String, keywords: [String] = []) {
        self.id = id
        self.title = title
        self.icon = icon
        self.keywords = keywords
    }

    /// Returns true if the command matches the given query (case-insensitive).
    public func matches(_ query: String) -> Bool {
        if query.isEmpty { return true }
        let lower = query.lowercased()
        if title.lowercased().contains(lower) { return true }
        return keywords.contains { $0.lowercased().contains(lower) }
    }
}

// MARK: - Built-in Commands

extension AppCommand {
    public static let allCommands: [AppCommand] = [
        // Workspace
        AppCommand(id: "workspace.new", title: "New Workspace", icon: "plus.square",
                   keywords: ["workspace", "create", "add"]),
        AppCommand(id: "workspace.close", title: "Close Workspace", icon: "xmark.square",
                   keywords: ["workspace", "remove", "delete"]),

        // Tab
        AppCommand(id: "tab.newTerminal", title: "New Terminal Tab", icon: "terminal",
                   keywords: ["tab", "terminal", "shell"]),
        AppCommand(id: "tab.newBrowser", title: "New Browser Tab", icon: "globe",
                   keywords: ["tab", "browser", "web"]),
        AppCommand(id: "tab.newFileTree", title: "New File Tree Tab", icon: "folder",
                   keywords: ["tab", "file", "tree", "explorer"]),
        AppCommand(id: "tab.close", title: "Close Tab", icon: "xmark",
                   keywords: ["tab", "close"]),

        // Area / Layout
        AppCommand(id: "area.splitHorizontal", title: "Split Horizontal", icon: "rectangle.split.1x2",
                   keywords: ["split", "horizontal", "layout"]),
        AppCommand(id: "area.splitVertical", title: "Split Vertical", icon: "rectangle.split.2x1",
                   keywords: ["split", "vertical", "layout"]),
        AppCommand(id: "area.close", title: "Close Area", icon: "rectangle.badge.xmark",
                   keywords: ["area", "close", "pane"]),

        // UI
        AppCommand(id: "ui.toggleSidebar", title: "Toggle Sidebar", icon: "sidebar.leading",
                   keywords: ["sidebar", "toggle", "show", "hide"]),
        AppCommand(id: "ui.openSettings", title: "Open Settings", icon: "gearshape",
                   keywords: ["settings", "preferences", "config"]),

        // Font
        AppCommand(id: "font.increase", title: "Increase Font Size", icon: "textformat.size.larger",
                   keywords: ["font", "size", "zoom", "bigger"]),
        AppCommand(id: "font.decrease", title: "Decrease Font Size", icon: "textformat.size.smaller",
                   keywords: ["font", "size", "zoom", "smaller"]),
        AppCommand(id: "font.reset", title: "Reset Font Size", icon: "textformat.size",
                   keywords: ["font", "size", "reset", "default"]),
    ]
}
