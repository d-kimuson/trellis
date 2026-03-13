import Combine
import SwiftUI

/// Manages workspaces, areas, tabs, and terminal sessions.
/// Successor to SessionStore.
@Observable
@MainActor
public final class WorkspaceStore {
    public let ghosttyApp: GhosttyAppWrapper
    public var workspaces: [Workspace]
    public var activeWorkspaceIndex: Int
    private var nextTerminalCounter: Int = 1
    @ObservationIgnored private var autosaveTimer: Timer?
    /// Subscriptions forwarding terminal session changes to WorkspaceStore observation tracking.
    @ObservationIgnored private var sessionCancellables: Set<AnyCancellable> = []

    /// Optional reference to the in-app notification store for marking read on focus.
    public weak var notificationStore: NotificationStore?

    public init(ghosttyApp: GhosttyAppWrapper, loadSnapshots: Bool = true) {
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

        // Forward terminal session changes (pwd, branch) to WorkspaceStore observation tracking
        // so views observing the store (SidebarView, AreaPanelView, etc.) re-render on OSC 7.
        rebuildSessionSubscriptions(for: workspaces)
        startObservingWorkspaces(knownSessionIds: Set(allSessions.map(\.id)))
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

    /// Previously subscribed to TerminalSession.objectWillChange to forward changes.
    /// Now that TerminalSession is @Observable, SwiftUI views track session properties
    /// directly via fine-grained observation — no manual forwarding needed.
    /// Kept as a no-op until all ObservableObject types are migrated (H-1d).
    func rebuildSessionSubscriptions(for workspaces: [Workspace]) {
        sessionCancellables = []
        debugLog("[SESSION] rebuildSessionSubscriptions: no-op (TerminalSession is @Observable)")
    }

    /// Observes `workspaces` changes using @Observable tracking.
    /// Rebuilds session subscriptions only when the set of session IDs changes (structural change).
    func startObservingWorkspaces(knownSessionIds: Set<UUID>) {
        withObservationTracking {
            _ = workspaces
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let newSessionIds = Set(allSessions.map(\.id))
                if newSessionIds != knownSessionIds {
                    rebuildSessionSubscriptions(for: workspaces)
                }
                startObservingWorkspaces(knownSessionIds: newSessionIds)
            }
        }
    }

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
