import Foundation

/// Observable state for a browser panel.
/// Uses class (ObservableObject) because WKWebView owns resources.
public final class BrowserState: ObservableObject, Identifiable {
    public let id: UUID
    @Published public var currentURL: URL
    @Published public var canGoBack: Bool
    @Published public var canGoForward: Bool
    @Published public var isLoading: Bool

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
