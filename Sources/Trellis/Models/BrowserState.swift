import Foundation
import Observation

/// Navigation action to be consumed by WebViewRepresentable.
public enum BrowserNavigationAction {
    case back
    case forward
    case reload
    case stop
    case openDevTools
}

/// Observable state for a browser panel.
@Observable
public final class BrowserState: Identifiable {
    public let id: UUID
    public var currentURL: URL
    public var canGoBack: Bool
    public var canGoForward: Bool
    public var isLoading: Bool
    /// Direct action dispatch. Set by WebViewRepresentable.Coordinator on makeNSView.
    /// Call this instead of setting pendingAction to avoid lost/double-fire races.
    public var performAction: ((BrowserNavigationAction) -> Void)?

    public init(
        id: UUID = UUID(),
        url: URL = URL(string: "https://www.google.com")!,
        canGoBack: Bool = false,
        canGoForward: Bool = false,
        isLoading: Bool = false
    ) {
        self.id = id
        self.currentURL = url
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.isLoading = isLoading
    }
}
