import Foundation

// MARK: - Tab Operations

extension WorkspaceStore {

    /// Add a new terminal tab to the given area.
    public func addTab(to areaId: UUID) {
        addTerminalTab(to: areaId)
    }

    /// Add a terminal tab to the given area.
    public func addTerminalTab(to areaId: UUID) {
        let cwd = activeTerminalPwd(in: areaId, workspace: activeWorkspace)
        let session = TerminalSession(title: "Terminal \(nextTerminalNumber())", workingDirectory: cwd)
        addTabWithContent(to: areaId, content: .terminal(session))
    }

    /// Add a browser tab to the given area.
    public func addBrowserTab(to areaId: UUID, url: URL? = nil) {
        let state = BrowserState(url: url ?? URL(string: "https://www.google.com")!)
        addTabWithContent(to: areaId, content: .browser(state))
    }

    /// Add a file tree tab to the given area.
    public func addFileTreeTab(to areaId: UUID, path: String? = nil) {
        let state = FileTreeState(rootPath: path)
        addTabWithContent(to: areaId, content: .fileTree(state))
    }

    /// Add a tab with the given content to the specified area.
    private func addTabWithContent(to areaId: UUID, content: PanelContent) {
        guard var workspace = activeWorkspace else { return }
        let newTab = Tab(content: content)

        workspace.layout = workspace.layout.updatingArea(areaId: areaId) { area in
            area.addingTab(newTab)
        }
        workspaces[activeWorkspaceIndex] = workspace
    }

    /// Close a tab at the given index in the given area.
    /// If it's the last tab in a multi-area layout, close the area.
    /// If it's the last tab in the last area, keep the empty area visible.
    public func closeTab(in areaId: UUID, at tabIndex: Int) {
        closeTab(in: areaId, at: tabIndex, workspaceIndex: activeWorkspaceIndex)
    }

    func closeTab(in areaId: UUID, at tabIndex: Int, workspaceIndex: Int) {
        guard workspaceIndex >= 0, workspaceIndex < workspaces.count else { return }
        var workspace = workspaces[workspaceIndex]
        guard let area = workspace.layout.findArea(id: areaId) else { return }
        guard tabIndex >= 0, tabIndex < area.tabs.count else { return }

        // Close the terminal session
        if let session = area.tabs[tabIndex].content.terminalSession {
            session.close()
        }

        if let updatedArea = area.removingTab(at: tabIndex) {
            if updatedArea.tabs.isEmpty {
                // Last tab removed
                let allAreas = workspace.layout.allAreas
                if allAreas.count > 1 {
                    // Multi-area: remove the empty area entirely
                    workspace.layout = workspace.layout.removingArea(areaId: areaId)
                    if workspace.activeAreaId == areaId {
                        workspace.activeAreaId = workspace.layout.allAreas.first?.id
                    }
                } else {
                    // Single area: keep the empty area visible
                    workspace.layout = workspace.layout.updatingArea(areaId: areaId) { _ in
                        updatedArea
                    }
                }
            } else {
                workspace.layout = workspace.layout.updatingArea(areaId: areaId) { _ in
                    updatedArea
                }
            }

            workspaces[workspaceIndex] = workspace
        }
    }

    /// Select a tab in the given area.
    public func selectTab(in areaId: UUID, at tabIndex: Int) {
        guard var workspace = activeWorkspace else { return }
        let sessionId = workspace.layout.findArea(id: areaId)?.tabs[tabIndex].content.terminalSession?.id
        workspace.layout = workspace.layout.updatingArea(areaId: areaId) { area in
            area.selectingTab(at: tabIndex)
        }
        workspace.activeAreaId = areaId
        workspaces[activeWorkspaceIndex] = workspace
        if let sessionId {
            notificationStore?.markAsRead(sessionId: sessionId)
        }
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

        if let updatedSource = remainingSource, !updatedSource.tabs.isEmpty {
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
        direction: SplitDirection,
        insertBefore: Bool = false
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
            newArea: newArea,
            insertBefore: insertBefore
        )

        if let updatedSource = remainingSource, !updatedSource.tabs.isEmpty {
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

    // MARK: - Process Exit Handling

    /// Close the tab containing the given terminal session (called when the shell process exits).
    public func closeTerminalSession(_ session: TerminalSession) {
        for (wsIndex, workspace) in workspaces.enumerated() {
            for area in workspace.allAreas {
                if let tabIndex = area.tabs.firstIndex(where: { $0.content.terminalSession?.id == session.id }) {
                    closeTab(in: area.id, at: tabIndex, workspaceIndex: wsIndex)
                    return
                }
            }
        }
    }
}
