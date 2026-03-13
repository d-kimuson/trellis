import AppKit

/// Abstracts the terminal surface view so TerminalSession doesn't depend on GhosttyKit.
/// GhosttyNSView conforms to this protocol.
public protocol TerminalSurfaceView: AnyObject {
    /// The underlying NSView for AppKit integration (firstResponder management, etc.).
    var nsView: NSView { get }

    /// Tear down the terminal surface and free associated resources.
    func destroySurface()
}
