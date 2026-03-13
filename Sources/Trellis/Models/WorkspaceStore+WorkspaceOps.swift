import Foundation

// MARK: - Workspace Operations

extension WorkspaceStore {

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
        if workspaces[index].isPinned { saveSnapshot() }
    }

    /// Remove a workspace at the given index. The last workspace cannot be removed.
    public func removeWorkspace(at index: Int) {
        guard workspaces.count > 1 else { return }
        guard index >= 0, index < workspaces.count else { return }

        // Close all sessions in the workspace being removed
        let workspace = workspaces[index]
        let wasPinned = workspace.isPinned
        for area in workspace.allAreas {
            for tab in area.tabs {
                if let session = tab.content.terminalSession {
                    ghosttyApp.closeSession(session)
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

        if wasPinned { saveSnapshot() }
    }

    // MARK: - Pin / Unpin

    public func pinWorkspace(id: UUID) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        let activeId = workspaces[activeWorkspaceIndex].id
        workspaces[index].isPinned = true
        // Re-sort: pinned first, temp after (preserving relative order in each group)
        workspaces = workspaces.filter(\.isPinned) + workspaces.filter { !$0.isPinned }
        if let newIndex = workspaces.firstIndex(where: { $0.id == activeId }) {
            activeWorkspaceIndex = newIndex
        }
        saveSnapshot()
    }

    public func unpinWorkspace(id: UUID) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        let activeId = workspaces[activeWorkspaceIndex].id
        workspaces[index].isPinned = false
        workspaces = workspaces.filter(\.isPinned) + workspaces.filter { !$0.isPinned }
        if let newIndex = workspaces.firstIndex(where: { $0.id == activeId }) {
            activeWorkspaceIndex = newIndex
        }
        saveSnapshot()
    }

    // MARK: - Workspace Reordering

    /// Reorder within the pinned section (offsets are local to that section).
    public func movePinnedWorkspace(fromOffsets: IndexSet, toOffset: Int) {
        let activeId = workspaces[activeWorkspaceIndex].id
        workspaces.move(fromOffsets: fromOffsets, toOffset: toOffset)
        if let newIndex = workspaces.firstIndex(where: { $0.id == activeId }) {
            activeWorkspaceIndex = newIndex
        }
    }

    /// Reorder within the temp section (offsets are local to that section).
    public func moveTempWorkspace(fromOffsets: IndexSet, toOffset: Int) {
        let activeId = workspaces[activeWorkspaceIndex].id
        let pinnedCount = pinnedWorkspaces.count
        let globalFrom = IndexSet(fromOffsets.map { $0 + pinnedCount })
        let globalTo = toOffset + pinnedCount
        workspaces.move(fromOffsets: globalFrom, toOffset: globalTo)
        if let newIndex = workspaces.firstIndex(where: { $0.id == activeId }) {
            activeWorkspaceIndex = newIndex
        }
    }

    /// Move workspaces for drag-and-drop reordering.
    public func moveWorkspace(fromOffsets: IndexSet, toOffset: Int) {
        let activeId = workspaces[activeWorkspaceIndex].id
        workspaces.move(fromOffsets: fromOffsets, toOffset: toOffset)
        if let newIndex = workspaces.firstIndex(where: { $0.id == activeId }) {
            activeWorkspaceIndex = newIndex
        }
    }

    /// Move across the pinned/temp boundary, updating isPinned based on the new position.
    ///
    /// Items that land in indices `0..<newPinnedCount` become pinned;
    /// items at `newPinnedCount...` become unpinned. `newPinnedCount` is derived
    /// by checking whether each moved item crossed the original boundary.
    public func moveWorkspaceCrossBoundary(fromOffsets: IndexSet, toOffset: Int) {
        let originalPinnedCount = pinnedWorkspaces.count
        let activeId = workspaces[activeWorkspaceIndex].id

        // Record each moved item's id and whether it was pinned before the move
        let movedEntries: [(id: UUID, wasPinned: Bool)] = fromOffsets.map { idx in
            (id: workspaces[idx].id, wasPinned: idx < originalPinnedCount)
        }

        workspaces.move(fromOffsets: fromOffsets, toOffset: toOffset)

        // After the move, compute the new pinned count
        var newPinnedCount = originalPinnedCount
        for entry in movedEntries {
            guard let newIdx = workspaces.firstIndex(where: { $0.id == entry.id }) else { continue }
            let isNowInPinnedZone = newIdx < originalPinnedCount
            if entry.wasPinned && !isNowInPinnedZone { newPinnedCount -= 1 }
            else if !entry.wasPinned && isNowInPinnedZone { newPinnedCount += 1 }
        }

        for i in workspaces.indices {
            workspaces[i].isPinned = i < newPinnedCount
        }

        if let newIndex = workspaces.firstIndex(where: { $0.id == activeId }) {
            activeWorkspaceIndex = newIndex
        }
        saveSnapshot()
    }
}
