import AppKit
import GhosttyKit

// MARK: - Broadcast Input

extension GhosttyNSView {
    /// Broadcasts a key event to all other terminal surfaces in the active workspace.
    func broadcastKey(_ key: ghostty_input_key_s) {
        guard let store = ghosttyApp.store,
              store.activeWorkspace?.isBroadcastEnabled == true else { return }
        for otherSession in store.activeWorkspace?.allTerminalSessions ?? []
        where otherSession.id != session.id {
            if let otherView = ghosttyApp.surfaceView(for: otherSession) as? GhosttyNSView,
               let otherSurface = otherView.surface {
                _ = ghostty_surface_key(otherSurface, key)
            }
        }
    }

    /// Broadcasts text to all other terminal surfaces in the active workspace.
    func broadcastText(_ text: String) {
        guard let store = ghosttyApp.store,
              store.activeWorkspace?.isBroadcastEnabled == true else { return }
        for otherSession in store.activeWorkspace?.allTerminalSessions ?? []
        where otherSession.id != session.id {
            if let otherView = ghosttyApp.surfaceView(for: otherSession) as? GhosttyNSView,
               let otherSurface = otherView.surface {
                text.withCString { cstr in
                    ghostty_surface_text(otherSurface, cstr, UInt(text.utf8.count))
                }
            }
        }
    }
}
