import Foundation

// MARK: - Focus & Queries

extension WorkspaceStore {

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

    /// Returns the workspace name that contains the given session, or nil if not found.
    public func workspaceName(forSession sessionId: UUID) -> String? {
        for workspace in workspaces {
            for area in workspace.allAreas {
                if area.tabs.contains(where: { $0.content.terminalSession?.id == sessionId }) {
                    return workspace.name
                }
            }
        }
        return nil
    }

    /// All terminal session IDs belonging to the given workspace.
    /// Used by the sidebar to compute per-workspace notification badges.
    public func sessionIds(forWorkspace index: Int) -> [UUID] {
        guard index >= 0, index < workspaces.count else { return [] }
        return workspaces[index].allAreas.flatMap { area in
            area.tabs.compactMap { $0.content.terminalSession?.id }
        }
    }
}
