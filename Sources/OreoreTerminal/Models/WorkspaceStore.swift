import SwiftUI

/// Manages workspaces, areas, tabs, and terminal sessions.
/// Successor to SessionStore.
public final class WorkspaceStore: ObservableObject {
    public let ghosttyApp: GhosttyAppWrapper
    @Published public var workspaces: [Workspace]
    @Published public var activeWorkspaceIndex: Int

    public init(ghosttyApp: GhosttyAppWrapper) {
        self.ghosttyApp = ghosttyApp

        // Start with one workspace containing one area with one terminal tab
        let initialSession = TerminalSession(title: "Terminal 1")
        let tab = Tab(content: .terminal(initialSession))
        let area = Area(tabs: [tab])
        let layout = LayoutNode.leaf(area)
        let workspace = Workspace(name: "Workspace 1", layout: layout, activeAreaId: area.id)

        self.workspaces = [workspace]
        self.activeWorkspaceIndex = 0
    }

    // MARK: - Computed Properties

    public var activeWorkspace: Workspace? {
        guard activeWorkspaceIndex >= 0, activeWorkspaceIndex < workspaces.count else { return nil }
        return workspaces[activeWorkspaceIndex]
    }

    /// All terminal sessions across all workspaces.
    public var allSessions: [TerminalSession] {
        workspaces.flatMap { workspace in
            workspace.allAreas.flatMap { area in
                area.tabs.compactMap { tab in
                    tab.content.terminalSession
                }
            }
        }
    }

    // MARK: - Workspace Operations

    public func addWorkspace() {
        let session = TerminalSession(title: "Terminal \(nextTerminalNumber())")
        let tab = Tab(content: .terminal(session))
        let area = Area(tabs: [tab])
        let layout = LayoutNode.leaf(area)
        let workspace = Workspace(
            name: "Workspace \(workspaces.count + 1)",
            layout: layout,
            activeAreaId: area.id
        )
        workspaces.append(workspace)
        activeWorkspaceIndex = workspaces.count - 1
    }

    public func selectWorkspace(at index: Int) {
        guard index >= 0, index < workspaces.count else { return }
        activeWorkspaceIndex = index
    }

    /// Rename a workspace at the given index.
    public func renameWorkspace(at index: Int, to name: String) {
        guard index >= 0, index < workspaces.count else { return }
        workspaces[index].name = name
    }

    /// Remove a workspace at the given index. The last workspace cannot be removed.
    public func removeWorkspace(at index: Int) {
        guard workspaces.count > 1 else { return }
        guard index >= 0, index < workspaces.count else { return }

        // Close all sessions in the workspace being removed
        let workspace = workspaces[index]
        for area in workspace.allAreas {
            for tab in area.tabs {
                if let session = tab.content.terminalSession {
                    session.close()
                }
            }
        }

        workspaces.remove(at: index)

        // Adjust activeWorkspaceIndex
        if activeWorkspaceIndex >= workspaces.count {
            activeWorkspaceIndex = workspaces.count - 1
        } else if activeWorkspaceIndex > index {
            activeWorkspaceIndex -= 1
        }
    }

    // MARK: - Active Area Operations

    /// Split the active area in the active workspace.
    public func splitActiveArea(direction: SplitDirection) {
        guard let workspace = activeWorkspace,
              let areaId = workspace.activeAreaId else { return }
        splitArea(areaId: areaId, direction: direction)
    }

    /// Close the active area in the active workspace.
    public func closeActiveArea() {
        guard let workspace = activeWorkspace,
              let areaId = workspace.activeAreaId else { return }
        closeArea(areaId: areaId)
    }

    // MARK: - Area Operations

    /// Split the area containing the given areaId in the active workspace.
    public func splitArea(areaId: UUID, direction: SplitDirection) {
        guard var workspace = activeWorkspace else { return }
        let session = TerminalSession(title: "Terminal \(nextTerminalNumber())")
        let tab = Tab(content: .terminal(session))
        let newArea = Area(tabs: [tab])

        workspace.layout = workspace.layout.splittingArea(
            areaId: areaId,
            direction: direction,
            newArea: newArea
        )
        workspace.activeAreaId = newArea.id
        workspaces[activeWorkspaceIndex] = workspace
    }

    /// Close an area. If it's the last area, close all sessions and create a fresh one.
    public func closeArea(areaId: UUID) {
        guard var workspace = activeWorkspace else { return }

        // Close all sessions in the area being removed
        if let area = workspace.layout.findArea(id: areaId) {
            for tab in area.tabs {
                if let session = tab.content.terminalSession {
                    session.close()
                }
            }
        }

        let allAreas = workspace.layout.allAreas
        if allAreas.count <= 1 {
            // Last area — recreate a fresh one
            let session = TerminalSession(title: "Terminal \(nextTerminalNumber())")
            let tab = Tab(content: .terminal(session))
            let newArea = Area(tabs: [tab])
            workspace.layout = .leaf(newArea)
            workspace.activeAreaId = newArea.id
        } else {
            workspace.layout = workspace.layout.removingArea(areaId: areaId)
            // If active area was removed, select the first remaining area
            if workspace.activeAreaId == areaId {
                workspace.activeAreaId = workspace.layout.allAreas.first?.id
            }
        }
        workspaces[activeWorkspaceIndex] = workspace
    }

    // MARK: - Tab Operations

    /// Add a new terminal tab to the given area.
    public func addTab(to areaId: UUID) {
        guard var workspace = activeWorkspace else { return }
        let session = TerminalSession(title: "Terminal \(nextTerminalNumber())")
        let newTab = Tab(content: .terminal(session))

        workspace.layout = workspace.layout.updatingArea(areaId: areaId) { area in
            area.addingTab(newTab)
        }
        workspaces[activeWorkspaceIndex] = workspace
    }

    /// Close a tab at the given index in the given area.
    /// If it's the last tab, close the area.
    public func closeTab(in areaId: UUID, at tabIndex: Int) {
        guard var workspace = activeWorkspace else { return }
        guard let area = workspace.layout.findArea(id: areaId) else { return }
        guard tabIndex >= 0, tabIndex < area.tabs.count else { return }

        // Close the terminal session
        if let session = area.tabs[tabIndex].content.terminalSession {
            session.close()
        }

        if let updatedArea = area.removingTab(at: tabIndex) {
            workspace.layout = workspace.layout.updatingArea(areaId: areaId) { _ in
                updatedArea
            }
            workspaces[activeWorkspaceIndex] = workspace
        } else {
            // Last tab removed — close the area
            closeArea(areaId: areaId)
        }
    }

    /// Select a tab in the given area.
    public func selectTab(in areaId: UUID, at tabIndex: Int) {
        guard var workspace = activeWorkspace else { return }
        workspace.layout = workspace.layout.updatingArea(areaId: areaId) { area in
            area.selectingTab(at: tabIndex)
        }
        workspace.activeAreaId = areaId
        workspaces[activeWorkspaceIndex] = workspace
    }

    // MARK: - Drag & Drop Operations

    /// Move a tab from one area to another at a specific insertion index.
    /// If the source area becomes empty, it is automatically removed.
    public func moveTab(tabId: UUID, from sourceAreaId: UUID, to targetAreaId: UUID, at insertIndex: Int) {
        guard var workspace = activeWorkspace else { return }

        // Same-area reorder: remove then insert
        if sourceAreaId == targetAreaId {
            guard let area = workspace.layout.findArea(id: sourceAreaId) else { return }
            let (remaining, removedTab) = area.removingTabById(tabId)
            guard let tab = removedTab, let updatedArea = remaining else { return }
            let finalArea = updatedArea.insertingTab(tab, at: insertIndex)
            workspace.layout = workspace.layout.updatingArea(areaId: sourceAreaId) { _ in finalArea }
            workspaces[activeWorkspaceIndex] = workspace
            return
        }

        // Cross-area move
        guard let sourceArea = workspace.layout.findArea(id: sourceAreaId),
              let targetArea = workspace.layout.findArea(id: targetAreaId) else { return }

        let (remainingSource, removedTab) = sourceArea.removingTabById(tabId)
        guard let tab = removedTab else { return }

        // Insert into target
        let updatedTarget = targetArea.insertingTab(tab, at: insertIndex)
        workspace.layout = workspace.layout.updatingArea(areaId: targetAreaId) { _ in updatedTarget }

        if let updatedSource = remainingSource {
            // Source area still has tabs
            workspace.layout = workspace.layout.updatingArea(areaId: sourceAreaId) { _ in updatedSource }
        } else {
            // Source area is empty — remove it
            let allAreas = workspace.layout.allAreas
            if allAreas.count > 1 {
                workspace.layout = workspace.layout.removingArea(areaId: sourceAreaId)
            }
            if workspace.activeAreaId == sourceAreaId {
                workspace.activeAreaId = targetAreaId
            }
        }

        workspaces[activeWorkspaceIndex] = workspace
    }

    /// Move a tab to a new area adjacent to a target area, creating a split.
    /// If the source area becomes empty, it is automatically removed.
    public func moveTabToNewArea(
        tabId: UUID,
        from sourceAreaId: UUID,
        adjacentTo targetAreaId: UUID,
        direction: SplitDirection
    ) {
        guard var workspace = activeWorkspace else { return }
        guard let sourceArea = workspace.layout.findArea(id: sourceAreaId) else { return }

        let (remainingSource, removedTab) = sourceArea.removingTabById(tabId)
        guard let tab = removedTab else { return }

        // Create a new area with just the moved tab
        let newArea = Area(tabs: [tab])

        // Split the target area to place the new area adjacent
        workspace.layout = workspace.layout.splittingArea(
            areaId: targetAreaId,
            direction: direction,
            newArea: newArea
        )

        if let updatedSource = remainingSource {
            // Source still has tabs
            workspace.layout = workspace.layout.updatingArea(areaId: sourceAreaId) { _ in updatedSource }
        } else {
            // Source is empty — remove it
            workspace.layout = workspace.layout.removingArea(areaId: sourceAreaId)
            if workspace.activeAreaId == sourceAreaId {
                workspace.activeAreaId = newArea.id
            }
        }

        workspace.activeAreaId = newArea.id
        workspaces[activeWorkspaceIndex] = workspace
    }

    // MARK: - Layout Operations

    /// Update split ratio.
    public func updateRatio(splitId: UUID, ratio: Double) {
        guard var workspace = activeWorkspace else { return }
        workspace.layout = workspace.layout.updatingRatio(splitId: splitId, ratio: ratio)
        workspaces[activeWorkspaceIndex] = workspace
    }

    // MARK: - Helpers

    private func nextTerminalNumber() -> Int {
        allSessions.count + 1
    }
}
