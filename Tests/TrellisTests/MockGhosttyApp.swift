import AppKit
import GhosttyKit
@testable import Trellis

/// Lightweight mock that satisfies GhosttyAppProviding without initializing libghostty.
@MainActor
final class MockGhosttyApp: GhosttyAppProviding {
    var focusedSurface: ghostty_surface_t?
    var onDesktopNotification: ((String, String, Bool, TerminalSession?) -> Void)?
    weak var store: WorkspaceStore?

    func createSurface(
        for view: NSView,
        userdata: UnsafeMutableRawPointer?,
        workingDirectory: String?,
        envVars: [String: String]
    ) -> ghostty_surface_t? { nil }

    func terminalColumns(surface: ghostty_surface_t) -> Int { 80 }
    func readScrollback(surface: ghostty_surface_t) -> String? { nil }

    func registerSession(surface: ghostty_surface_t, session: TerminalSession) {}
    func unregisterSession(surface: ghostty_surface_t) {}
    func lookupSession(surface: ghostty_surface_t) -> TerminalSession? { nil }

    func defocusAllSurfaces(except focused: ghostty_surface_t) {}
    func defocusAllSurfaces() {}

    func surface(for session: TerminalSession) -> ghostty_surface_t? { nil }
    func surfaceView(for session: TerminalSession) -> (any TerminalSurfaceView)? { nil }
    func setSurfaceView(_ view: any TerminalSurfaceView, for session: TerminalSession) {}
    func closeSession(_ session: TerminalSession) {}

    func shutdown() {}
    func increaseFontSize() {}
    func decreaseFontSize() {}
    func resetFontSize() {}
    func applySettings(_ settings: AppSettings) {}
    func sendText(_ text: String, to session: TerminalSession) -> Bool { false }
}
