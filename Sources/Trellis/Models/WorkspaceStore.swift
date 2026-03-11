import SwiftUI

/// Manages workspaces, areas, tabs, and terminal sessions.
/// Successor to SessionStore.
public final class WorkspaceStore: ObservableObject {
    public let ghosttyApp: GhosttyAppWrapper
    @Published public var workspaces: [Workspace]
    @Published public var activeWorkspaceIndex: Int
    private var nextTerminalCounter: Int = 1
    private var autosaveTimer: Timer?

    /// Optional reference to the in-app notification store for marking read on focus.
    public weak var notificationStore: NotificationStore?

    public init(ghosttyApp: GhosttyAppWrapper, loadSnapshots: Bool = true) {
        self.ghosttyApp = ghosttyApp

        // Copy bundled shell-integration scripts to the stable app-support path
        if loadSnapshots { SnapshotStore.installShellIntegration() }

        // Restore pinned workspaces from the last snapshot
        let snapshots = loadSnapshots ? SnapshotStore.load() : []
        let pinned = snapshots.filter(\.isPinned).map { Self.makeRestoredWorkspace(from: $0) }

        // Default temp workspace
        let area = Area(tabs: [])
        let layout = LayoutNode.leaf(area)
        let defaultWorkspace = Workspace(
            name: "Workspace \(pinned.count + 1)",
            layout: layout,
            activeAreaId: area.id
        )

        self.workspaces = pinned + [defaultWorkspace]
        self.activeWorkspaceIndex = pinned.isEmpty ? 0 : pinned.count

        // Autosave pinned workspaces every 8 seconds
        let timer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { [weak self] _ in
            self?.saveSnapshot()
        }
        RunLoop.main.add(timer, forMode: .common)
        autosaveTimer = timer
    }

    deinit {
        autosaveTimer?.invalidate()
    }

    // MARK: - Computed Properties

    public var activeWorkspace: Workspace? {
        guard activeWorkspaceIndex >= 0, activeWorkspaceIndex < workspaces.count else { return nil }
        return workspaces[activeWorkspaceIndex]
    }

    public var pinnedWorkspaces: [Workspace] { workspaces.filter(\.isPinned) }
    public var tempWorkspaces: [Workspace] { workspaces.filter { !$0.isPinned } }

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
        let cwd = activeTerminalPwd(in: areaId, workspace: workspace)
        let session = TerminalSession(title: "Terminal \(nextTerminalNumber())", workingDirectory: cwd)
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

    private func closeTab(in areaId: UUID, at tabIndex: Int, workspaceIndex: Int) {
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

    // MARK: - Layout Operations

    /// Update split ratio.
    public func updateRatio(splitId: UUID, ratio: Double) {
        guard var workspace = activeWorkspace else { return }
        workspace.layout = workspace.layout.updatingRatio(splitId: splitId, ratio: ratio)
        workspaces[activeWorkspaceIndex] = workspace
    }

    // MARK: - Focus (Notification Click)

    /// Focus the workspace/area/tab that contains the given session.
    /// Returns true if the session was found and focused.
    @discardableResult
    public func focusSession(id sessionId: UUID) -> Bool {
        for (wsIndex, workspace) in workspaces.enumerated() {
            for area in workspace.allAreas {
                for (tabIndex, tab) in area.tabs.enumerated() {
                    guard tab.content.terminalSession?.id == sessionId else { continue }
                    activeWorkspaceIndex = wsIndex
                    workspaces[wsIndex].activeAreaId = area.id
                    workspaces[wsIndex].layout = workspaces[wsIndex].layout.updatingArea(areaId: area.id) { a in
                        a.selectingTab(at: tabIndex)
                    }
                    notificationStore?.markAsRead(sessionId: sessionId)
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Queries

    /// All terminal session IDs belonging to the given workspace.
    /// Used by the sidebar to compute per-workspace notification badges.
    public func sessionIds(forWorkspace index: Int) -> [UUID] {
        guard index >= 0, index < workspaces.count else { return [] }
        return workspaces[index].allAreas.flatMap { area in
            area.tabs.compactMap { $0.content.terminalSession?.id }
        }
    }

    // MARK: - Area Activation

    /// Activate an area (e.g. when the user clicks on a terminal surface).
    public func activateArea(_ areaId: UUID) {
        guard var workspace = activeWorkspace else { return }
        guard workspace.activeAreaId != areaId else { return }
        guard let area = workspace.layout.findArea(id: areaId) else { return }
        workspace.activeAreaId = areaId
        workspaces[activeWorkspaceIndex] = workspace
        let sessionIds = area.tabs.compactMap { $0.content.terminalSession?.id }
        notificationStore?.markAsRead(sessionIds: sessionIds)
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

    // MARK: - Helpers

    /// Returns the pwd of the active terminal in the given area, if available.
    private func activeTerminalPwd(in areaId: UUID, workspace: Workspace?) -> String? {
        guard let area = workspace?.layout.findArea(id: areaId),
              let session = area.activeTab?.content.terminalSession else { return nil }
        return session.pwd
    }

    private func nextTerminalNumber() -> Int {
        let terminalNumber = nextTerminalCounter
        nextTerminalCounter += 1
        return terminalNumber
    }

    // MARK: - Snapshot Save / Restore

    /// Save snapshots of all pinned workspaces to disk.
    public func saveSnapshot() {
        let snapshots = workspaces.filter(\.isPinned).map { makeSnapshot($0) }
        SnapshotStore.save(snapshots)
    }

    private func makeSnapshot(_ workspace: Workspace) -> WorkspaceSnapshot {
        let areaSnapshots = workspace.allAreas.map { area -> AreaSnapshot in
            let tabSnapshots = area.tabs.map { tab -> TabSnapshot in
                switch tab.content {
                case .terminal(let session):
                    let scrollback = session.surface.flatMap { surface in
                        ghosttyApp.readScrollback(surface: surface).map { SnapshotStore.truncate($0) }
                    }
                    return TabSnapshot(
                        tabId: tab.id,
                        type: "terminal",
                        cwd: session.pwd,
                        scrollback: scrollback,
                        browserURL: nil,
                        fileTreePath: nil
                    )
                case .browser(let state):
                    return TabSnapshot(
                        tabId: tab.id,
                        type: "browser",
                        cwd: nil,
                        scrollback: nil,
                        browserURL: state.currentURL.absoluteString,
                        fileTreePath: nil
                    )
                case .fileTree(let state):
                    return TabSnapshot(
                        tabId: tab.id,
                        type: "fileTree",
                        cwd: nil,
                        scrollback: nil,
                        browserURL: nil,
                        fileTreePath: state.rootPath
                    )
                }
            }
            return AreaSnapshot(areaId: area.id, tabs: tabSnapshots, activeTabIndex: area.activeTabIndex)
        }
        return WorkspaceSnapshot(
            schemaVersion: 1,
            id: workspace.id,
            name: workspace.name,
            isPinned: workspace.isPinned,
            areas: areaSnapshots,
            savedAt: Date()
        )
    }

    /// Restore a workspace from a snapshot.
    /// MVP: restores only the first area; split layouts are not persisted.
    private static func makeRestoredWorkspace(from snapshot: WorkspaceSnapshot) -> Workspace {
        guard let areaSnapshot = snapshot.areas.first else {
            let area = Area(tabs: [])
            return Workspace(
                id: snapshot.id, name: snapshot.name,
                layout: .leaf(area), activeAreaId: area.id, isPinned: true
            )
        }

        let tabs: [Tab] = areaSnapshot.tabs.compactMap { tab in
            switch tab.type {
            case "terminal":
                let envVars: [String: String] = tab.scrollback.map { scrollback in
                    SnapshotStore.prepareRestoreEnv(scrollback: scrollback, sessionId: tab.tabId)
                } ?? [:]
                let session = TerminalSession(
                    title: "Terminal",
                    workingDirectory: tab.cwd,
                    envVars: envVars
                )
                return Tab(id: tab.tabId, content: .terminal(session))
            case "browser":
                let url = tab.browserURL.flatMap { URL(string: $0) }
                    ?? URL(string: "https://www.google.com")!
                return Tab(id: tab.tabId, content: .browser(BrowserState(url: url)))
            case "fileTree":
                return Tab(id: tab.tabId, content: .fileTree(FileTreeState(rootPath: tab.fileTreePath)))
            default:
                return nil
            }
        }

        let area = Area(
            id: areaSnapshot.areaId,
            tabs: tabs,
            activeTabIndex: max(0, min(areaSnapshot.activeTabIndex, max(0, tabs.count - 1)))
        )
        return Workspace(
            id: snapshot.id, name: snapshot.name,
            layout: .leaf(area), activeAreaId: area.id, isPinned: true
        )
    }
}
