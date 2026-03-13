import SwiftUI

/// UI actions dispatched from menus, keyboard shortcuts, and command palette.
public enum UIAction: Equatable {
    case toggleSidebar
    case openSettings
    case toggleCommandPalette
}

/// Manages workspaces, areas, tabs, and terminal sessions.
/// Successor to SessionStore.
@Observable
@MainActor
public final class WorkspaceStore {
    public let ghosttyApp: any GhosttyAppProviding
    public var workspaces: [Workspace]
    public var activeWorkspaceIndex: Int
    private var nextTerminalCounter: Int = 1
    @ObservationIgnored private var autosaveTimer: Timer?

    /// Optional reference to the in-app notification store for marking read on focus.
    public weak var notificationStore: NotificationStore?

    /// Pending UI action for ContentView to observe and consume.
    public var pendingUIAction: UIAction?

    public func dispatch(_ action: UIAction) {
        pendingUIAction = action
    }

    public init(ghosttyApp: any GhosttyAppProviding, loadSnapshots: Bool = true) {
        self.ghosttyApp = ghosttyApp

        // Copy bundled shell-integration scripts to the stable app-support path
        if loadSnapshots { SnapshotStore.installShellIntegration() }

        // Remove stale scrollback temp files left over from a previous run
        // (safety net in case the shell integration script did not clean up)
        if loadSnapshots { SnapshotStore.cleanUpStaleTempFiles() }

        // Restore pinned workspaces from the last snapshot
        let snapshots = loadSnapshots ? SnapshotStore.load() : []
        let pinned = snapshots.filter(\.isPinned).map { Self.makeRestoredWorkspace(from: $0) }

        if pinned.isEmpty {
            // No pinned workspaces — start with a default empty workspace
            let area = Area(tabs: [])
            let layout = LayoutNode.leaf(area)
            let defaultWorkspace = Workspace(name: "Workspace 1", layout: layout, activeAreaId: area.id)
            self.workspaces = [defaultWorkspace]
            self.activeWorkspaceIndex = 0
        } else {
            self.workspaces = pinned
            self.activeWorkspaceIndex = 0
        }

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

    // MARK: - Helpers

    /// Returns the pwd of the active terminal in the given area, if available.
    func activeTerminalPwd(in areaId: UUID, workspace: Workspace?) -> String? {
        guard let area = workspace?.layout.findArea(id: areaId),
              let session = area.activeTab?.content.terminalSession else { return nil }
        return session.pwd
    }

    func nextTerminalNumber() -> Int {
        let terminalNumber = nextTerminalCounter
        nextTerminalCounter += 1
        return terminalNumber
    }
}
