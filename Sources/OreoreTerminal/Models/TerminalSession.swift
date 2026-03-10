import AppKit
import GhosttyKit

/// Represents a single terminal session with an associated libghostty surface.
/// Owns the GhosttyNSView so it survives SwiftUI view hierarchy rebuilds.
public final class TerminalSession: Identifiable, ObservableObject {
    public let id: UUID
    @Published public var title: String
    @Published public var isActive: Bool

    // Opaque pointer to ghostty surface - managed by GhosttyNSView
    var surface: ghostty_surface_t?

    /// The NSView hosting this session's terminal surface.
    /// Stored here so SwiftUI layout changes don't destroy and recreate it.
    var nsView: GhosttyNSView?

    public init(title: String = "Terminal") {
        self.id = UUID()
        self.title = title
        self.isActive = true
    }

    /// Mark session as inactive and free the surface.
    func close() {
        isActive = false
        nsView?.destroySurface()
        nsView = nil
    }

    deinit {
        nsView?.destroySurface()
        nsView = nil
    }
}
