import SwiftUI
import WebKit

/// NSViewRepresentable wrapper around WKWebView.
struct WebViewRepresentable: NSViewRepresentable {
    @ObservedObject var state: BrowserState

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: state.currentURL))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Only navigate if URL changed externally (e.g., URL bar submission)
        if context.coordinator.lastNavigatedURL != state.currentURL {
            context.coordinator.lastNavigatedURL = state.currentURL
            webView.load(URLRequest(url: state.currentURL))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let state: BrowserState
        var lastNavigatedURL: URL?

        init(state: BrowserState) {
            self.state = state
            self.lastNavigatedURL = state.currentURL
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            state.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            state.isLoading = false
            state.canGoBack = webView.canGoBack
            state.canGoForward = webView.canGoForward
            if let url = webView.url {
                state.currentURL = url
                lastNavigatedURL = url
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            state.isLoading = false
            state.canGoBack = webView.canGoBack
            state.canGoForward = webView.canGoForward
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            state.isLoading = false
        }
    }
}

/// Browser panel with URL bar and navigation controls.
struct BrowserPanelView: View {
    @ObservedObject var state: BrowserState
    @State private var urlText: String = ""
    @State private var webViewId = UUID()

    var body: some View {
        VStack(spacing: 0) {
            navigationBar
            WebViewRepresentable(state: state)
                .id(webViewId)
        }
        .onAppear {
            urlText = state.currentURL.absoluteString
        }
        .onChange(of: state.currentURL) { _, newURL in
            urlText = newURL.absoluteString
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 4) {
            Button(action: goBack) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .disabled(!state.canGoBack)
            .help("Back")

            Button(action: goForward) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .disabled(!state.canGoForward)
            .help("Forward")

            Button(action: reload) {
                Image(systemName: state.isLoading ? "xmark" : "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(state.isLoading ? "Stop" : "Reload")

            TextField("URL", text: $urlText)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    navigateToURL()
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func goBack() {
        // Trigger navigation by updating state
        // The WKWebView handles actual back navigation
        webViewId = UUID()
    }

    private func goForward() {
        webViewId = UUID()
    }

    private func reload() {
        // Force reload by changing the view ID
        webViewId = UUID()
    }

    private func navigateToURL() {
        var urlString = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "https://\(urlString)"
        }
        if let url = URL(string: urlString) {
            state.currentURL = url
        }
    }
}
