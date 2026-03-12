import Foundation

/// The content type displayed in a panel.
public enum PanelContent {
    case terminal(TerminalSession)
    case browser(BrowserState)
    case fileTree(FileTreeState)

    public var terminalSession: TerminalSession? {
        switch self {
        case .terminal(let session):
            return session
        case .browser, .fileTree:
            return nil
        }
    }

    /// Display title for tab bar.
    public var tabTitle: String {
        switch self {
        case .terminal(let session):
            return session.tabTitle
        case .browser(let state):
            return state.currentURL.host ?? "Browser"
        case .fileTree(let state):
            if let rootPath = state.rootPath {
                return URL(fileURLWithPath: rootPath).lastPathComponent
            }
            return "Files"
        }
    }

    /// SF Symbol name for the panel type.
    public var iconName: String {
        switch self {
        case .terminal:
            return "terminal"
        case .browser:
            return "globe"
        case .fileTree:
            return "folder"
        }
    }
}

/// A tab within an Area, holding a single panel.
public struct Tab: Identifiable {
    public let id: UUID
    public let content: PanelContent

    public init(id: UUID = UUID(), content: PanelContent) {
        self.id = id
        self.content = content
    }
}

/// A rectangular region that holds a list of tabs with one active tab.
public struct Area: Identifiable {
    public let id: UUID
    public var tabs: [Tab]
    public var activeTabIndex: Int

    public init(id: UUID = UUID(), tabs: [Tab], activeTabIndex: Int = 0) {
        self.id = id
        self.tabs = tabs
        self.activeTabIndex = activeTabIndex
    }

    /// The currently active tab, if any.
    public var activeTab: Tab? {
        guard activeTabIndex >= 0, activeTabIndex < tabs.count else { return nil }
        return tabs[activeTabIndex]
    }

    /// Returns a new Area with an additional tab appended and made active.
    public func addingTab(_ tab: Tab) -> Area {
        var newTabs = tabs
        newTabs.append(tab)
        return Area(id: id, tabs: newTabs, activeTabIndex: newTabs.count - 1)
    }

    /// Returns a new Area with the tab at the given index removed.
    /// Adjusts activeTabIndex as needed.
    public func removingTab(at index: Int) -> Area? {
        guard index >= 0, index < tabs.count else { return nil }
        var newTabs = tabs
        newTabs.remove(at: index)
        if newTabs.isEmpty {
            // Return empty area (no tabs) instead of nil
            return Area(id: id, tabs: [], activeTabIndex: 0)
        }
        let newActiveIndex = min(activeTabIndex, newTabs.count - 1)
        return Area(id: id, tabs: newTabs, activeTabIndex: newActiveIndex)
    }

    /// Returns a new Area with a different active tab index.
    public func selectingTab(at index: Int) -> Area {
        guard index >= 0, index < tabs.count else { return self }
        return Area(id: id, tabs: tabs, activeTabIndex: index)
    }

    /// Returns a new Area with a tab inserted at the given index (clamped to bounds).
    /// The inserted tab becomes the active tab.
    public func insertingTab(_ tab: Tab, at index: Int) -> Area {
        var newTabs = tabs
        let clampedIndex = min(max(index, 0), newTabs.count)
        newTabs.insert(tab, at: clampedIndex)
        return Area(id: id, tabs: newTabs, activeTabIndex: clampedIndex)
    }

    /// Removes a tab by its ID.
    /// Returns (updatedArea, removedTab). updatedArea is nil if the area becomes empty
    /// or the tab was not found. removedTab is nil if the tab was not found.
    public func removingTabById(_ tabId: UUID) -> (area: Area?, removedTab: Tab?) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else {
            return (nil, nil)
        }
        let removedTab = tabs[index]
        let updatedArea = removingTab(at: index)
        return (updatedArea, removedTab)
    }
}
