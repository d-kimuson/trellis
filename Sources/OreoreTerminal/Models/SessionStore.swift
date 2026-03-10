import SwiftUI

/// Manages all terminal sessions and the panel layout.
final class SessionStore: ObservableObject {
    let ghosttyApp: GhosttyAppWrapper
    @Published var sessions: [TerminalSession] = []
    @Published var rootPanel: PanelNode
    @Published var selectedSessionId: UUID?

    init(ghosttyApp: GhosttyAppWrapper) {
        self.ghosttyApp = ghosttyApp

        // Start with one session
        let initialSession = TerminalSession(title: "Terminal 1")
        self.sessions = [initialSession]
        self.rootPanel = .terminal(initialSession)
        self.selectedSessionId = initialSession.id
    }

    func createSession() -> TerminalSession {
        let session = TerminalSession(title: "Terminal \(sessions.count + 1)")
        sessions.append(session)
        selectedSessionId = session.id
        return session
    }

    func closeSession(_ session: TerminalSession) {
        session.close()
        sessions.removeAll { $0.id == session.id }
        rootPanel = rootPanel.removing(sessionId: session.id)

        // If no sessions remain, create a new one
        if sessions.isEmpty {
            let newSession = createSession()
            rootPanel = .terminal(newSession)
        }
    }

    /// Split the panel containing the given session
    func split(_ session: TerminalSession, direction: SplitDirection) {
        let newSession = createSession()
        rootPanel = rootPanel.splitting(
            sessionId: session.id,
            direction: direction,
            newSession: newSession
        )
    }
}
