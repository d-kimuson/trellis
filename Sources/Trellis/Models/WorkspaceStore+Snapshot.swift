import Foundation

// MARK: - Snapshot Save / Restore

extension WorkspaceStore {
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
                    let surf = session.surface
                    let scrollback: String? = surf.flatMap {
                        ghosttyApp.readScrollback(surface: $0).map { SnapshotStore.truncate($0) }
                    }
                    let cols: Int? = surf.map { ghosttyApp.terminalColumns(surface: $0) }
                    return TabSnapshot(
                        tabId: tab.id, type: "terminal",
                        cwd: session.pwd, scrollback: scrollback, terminalCols: cols,
                        browserURL: nil, fileTreePath: nil,
                        gitBranch: session.gitBranch
                    )
                case .browser(let state):
                    return TabSnapshot(
                        tabId: tab.id, type: "browser",
                        cwd: nil, scrollback: nil, terminalCols: nil,
                        browserURL: state.currentURL.absoluteString, fileTreePath: nil,
                        gitBranch: nil
                    )
                case .fileTree(let state):
                    return TabSnapshot(
                        tabId: tab.id, type: "fileTree",
                        cwd: nil, scrollback: nil, terminalCols: nil,
                        browserURL: nil, fileTreePath: state.rootPath,
                        gitBranch: nil
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
            layoutSnapshot: Self.makeLayoutSnapshot(workspace.layout),
            savedAt: Date()
        )
    }

    private static func makeLayoutSnapshot(_ node: LayoutNode) -> LayoutNodeSnapshot {
        switch node {
        case .leaf(let area):
            return .leaf(areaId: area.id)
        case .split(let id, let direction, let first, let second, let ratio):
            return .split(
                id: id,
                direction: direction == .vertical ? "vertical" : "horizontal",
                ratio: ratio,
                first: makeLayoutSnapshot(first),
                second: makeLayoutSnapshot(second)
            )
        }
    }

    static func makeRestoredWorkspace(from snapshot: WorkspaceSnapshot) -> Workspace {
        // Build area lookup: areaId → restored Area
        var areaLookup: [UUID: Area] = [:]
        for areaSnap in snapshot.areas {
            let tabs: [Tab] = areaSnap.tabs.compactMap { tab in
                switch tab.type {
                case "terminal":
                    let envVars: [String: String] = tab.scrollback.map { sb in
                        let env = SnapshotStore.prepareRestoreEnv(
                            scrollback: sb, sessionId: tab.tabId, terminalCols: tab.terminalCols)
                        debugLog("[RESTORE] tab \(tab.tabId) sb=\(sb.count)c cols=\(tab.terminalCols ?? 0)")
                        return env
                    } ?? [:]
                    let session = TerminalSession(title: "Terminal", workingDirectory: tab.cwd, envVars: envVars)
                    session.pwd = tab.cwd
                    session.gitBranch = tab.gitBranch
                    return Tab(id: tab.tabId, content: .terminal(session))
                case "browser":
                    let url = tab.browserURL.flatMap { URL(string: $0) } ?? URL(string: "https://www.google.com")!
                    return Tab(id: tab.tabId, content: .browser(BrowserState(url: url)))
                case "fileTree":
                    return Tab(id: tab.tabId, content: .fileTree(FileTreeState(rootPath: tab.fileTreePath)))
                default:
                    return nil
                }
            }
            let area = Area(
                id: areaSnap.areaId,
                tabs: tabs,
                activeTabIndex: max(0, min(areaSnap.activeTabIndex, max(0, tabs.count - 1)))
            )
            areaLookup[area.id] = area
        }

        // Restore the full layout tree, falling back to first area for old snapshots
        let layout: LayoutNode
        if let layoutSnap = snapshot.layoutSnapshot {
            layout = restoreLayoutNode(layoutSnap, areaLookup: areaLookup)
        } else if let firstSnap = snapshot.areas.first, let area = areaLookup[firstSnap.areaId] {
            layout = .leaf(area)
        } else {
            layout = .leaf(Area(tabs: []))
        }

        return Workspace(
            id: snapshot.id, name: snapshot.name,
            layout: layout, activeAreaId: snapshot.areas.first?.areaId, isPinned: true
        )
    }

    private static func restoreLayoutNode(_ snapshot: LayoutNodeSnapshot, areaLookup: [UUID: Area]) -> LayoutNode {
        switch snapshot {
        case .leaf(let areaId):
            return .leaf(areaLookup[areaId] ?? Area(tabs: []))
        case .split(let id, let direction, let ratio, let first, let second):
            let dir: SplitDirection = direction == "vertical" ? .vertical : .horizontal
            return .split(
                id: id,
                direction: dir,
                first: restoreLayoutNode(first, areaLookup: areaLookup),
                second: restoreLayoutNode(second, areaLookup: areaLookup),
                ratio: ratio
            )
        }
    }
}
