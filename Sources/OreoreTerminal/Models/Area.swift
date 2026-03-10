import Foundation

/// The content type displayed in a panel. Phase 1 supports terminal only.
public enum PanelContent {
    case terminal(TerminalSession)

    public var terminalSession: TerminalSession? {
        switch self {
        case .terminal(let session):
            return session
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
        if newTabs.isEmpty { return nil }
        let newActiveIndex = min(activeTabIndex, newTabs.count - 1)
        return Area(id: id, tabs: newTabs, activeTabIndex: newActiveIndex)
    }

    /// Returns a new Area with a different active tab index.
    public func selectingTab(at index: Int) -> Area {
        guard index >= 0, index < tabs.count else { return self }
        return Area(id: id, tabs: tabs, activeTabIndex: index)
    }
}
