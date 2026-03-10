import Foundation
import GhosttyKit

/// Represents a single terminal session with an associated libghostty surface.
public final class TerminalSession: Identifiable, ObservableObject {
    public let id: UUID
    @Published public var title: String
    @Published public var isActive: Bool

    // Opaque pointer to ghostty surface - managed by GhosttyNSView
    var surface: ghostty_surface_t?

    public init(title: String = "Terminal") {
        self.id = UUID()
        self.title = title
        self.isActive = true
    }

    /// Mark session as inactive. Surface free is handled by GhosttyNSView only.
    func close() {
        isActive = false
    }

    deinit {
        // Don't free surface here - GhosttyNSView owns the lifecycle
        surface = nil
    }
}
