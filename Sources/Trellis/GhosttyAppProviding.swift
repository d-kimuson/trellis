import AppKit
import GhosttyKit

/// Protocol abstracting the GhosttyAppWrapper interface.
/// Enables mock injection for tests that exercise WorkspaceStore logic
/// without requiring a live libghostty instance.
@MainActor
public protocol GhosttyAppProviding: AnyObject {
    var focusedSurface: ghostty_surface_t? { get set }
    var onDesktopNotification: ((String, String, Bool, TerminalSession?) -> Void)? { get set }
    var store: WorkspaceStore? { get set }

    func createSurface(
        for view: NSView,
        userdata: UnsafeMutableRawPointer?,
        workingDirectory: String?,
        envVars: [String: String]
    ) -> ghostty_surface_t?

    func terminalColumns(surface: ghostty_surface_t) -> Int
    func readScrollback(surface: ghostty_surface_t) -> String?

    func registerSession(surface: ghostty_surface_t, session: TerminalSession)
    func unregisterSession(surface: ghostty_surface_t)
    func lookupSession(surface: ghostty_surface_t) -> TerminalSession?

    func defocusAllSurfaces(except focused: ghostty_surface_t)
    func defocusAllSurfaces()

    /// Retrieve the ghostty surface associated with a session (session → surface reverse lookup).
    func surface(for session: TerminalSession) -> ghostty_surface_t?

    /// Retrieve the surface view associated with a session.
    func surfaceView(for session: TerminalSession) -> (any TerminalSurfaceView)?

    /// Register a surface view for a session.
    func setSurfaceView(_ view: any TerminalSurfaceView, for session: TerminalSession)

    /// Tear down the surface and view for a session. Called when the session is closed.
    func closeSession(_ session: TerminalSession)

    func shutdown()
    func increaseFontSize()
    func decreaseFontSize()
    func resetFontSize()
    func applySettings(_ settings: AppSettings)
    @discardableResult
    func sendText(_ text: String, to session: TerminalSession) -> Bool
}

// Default parameter values for protocol methods.
extension GhosttyAppProviding {
    public func createSurface(
        for view: NSView,
        userdata: UnsafeMutableRawPointer? = nil,
        workingDirectory: String? = nil,
        envVars: [String: String] = [:]
    ) -> ghostty_surface_t? {
        createSurface(for: view, userdata: userdata, workingDirectory: workingDirectory, envVars: envVars)
    }
}
