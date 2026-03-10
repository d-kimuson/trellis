import Foundation

/// Represents a single terminal session with an associated libghostty surface.
final class TerminalSession: Identifiable, ObservableObject {
    let id: UUID
    @Published var title: String
    @Published var isActive: Bool

    // Opaque pointer to ghostty surface - managed by GhosttyNSView
    var surface: ghostty_surface_t?

    init(title: String = "Terminal") {
        self.id = UUID()
        self.title = title
        self.isActive = true
    }

    func close() {
        if let surface {
            ghostty_surface_free(surface)
        }
        surface = nil
        isActive = false
    }

    deinit {
        // Don't free surface here - GhosttyNSView owns the lifecycle
        surface = nil
    }
}
