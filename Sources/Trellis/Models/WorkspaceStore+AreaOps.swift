import AppKit
import Foundation

// MARK: - Area Operations

extension WorkspaceStore {

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
                    ghosttyApp.closeSession(session)
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

    // MARK: - Layout Operations

    /// Update split ratio.
    public func updateRatio(splitId: UUID, ratio: Double) {
        guard var workspace = activeWorkspace else { return }
        workspace.layout = workspace.layout.updatingRatio(splitId: splitId, ratio: ratio)
        workspaces[activeWorkspaceIndex] = workspace
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

    /// Deactivate all areas — no panel has focus.
    /// Resigns terminal first responder and defocuses all ghostty surfaces.
    public func deactivateAllAreas() {
        guard var workspace = activeWorkspace else { return }
        guard workspace.activeAreaId != nil else { return }
        workspace.activeAreaId = nil
        workspaces[activeWorkspaceIndex] = workspace
        ghosttyApp.defocusAllSurfaces()
        NSApp.keyWindow?.makeFirstResponder(nil)
    }
}
