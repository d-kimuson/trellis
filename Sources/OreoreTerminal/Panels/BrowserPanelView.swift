import SwiftUI
import WebKit

/// NSViewRepresentable wrapper around WKWebView.
struct WebViewRepresentable: NSViewRepresentable {
    @ObservedObject var state: BrowserState
    var onFocused: (() -> Void)?

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: state.currentURL))
        context.coordinator.setupMouseMonitor(webView: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Process one-shot navigation actions (back, forward, reload, stop)
        if let action = state.pendingAction {
            DispatchQueue.main.async { state.pendingAction = nil }
            switch action {
            case .back:
                webView.goBack()
            case .forward:
                webView.goForward()
            case .reload:
                webView.reload()
            case .stop:
                webView.stopLoading()
            }
            return
        }

        // Only navigate if URL changed externally (e.g., URL bar submission)
        if context.coordinator.lastNavigatedURL != state.currentURL {
            context.coordinator.lastNavigatedURL = state.currentURL
            webView.load(URLRequest(url: state.currentURL))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state, onFocused: onFocused)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.removeMouseMonitor()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let state: BrowserState
        let onFocused: (() -> Void)?
        var lastNavigatedURL: URL?
        private var mouseMonitor: Any?

        init(state: BrowserState, onFocused: (() -> Void)?) {
            self.state = state
            self.onFocused = onFocused
            self.lastNavigatedURL = state.currentURL
        }

        deinit {
            removeMouseMonitor()
        }

        func setupMouseMonitor(webView: WKWebView) {
            mouseMonitor = NSEvent.addLocalMonitorForEvents(
                matching: .leftMouseDown
            ) { [weak self, weak webView] event in
                guard let webView = webView else { return event }
                let point = webView.convert(event.locationInWindow, from: nil)
                if webView.bounds.contains(point) {
                    self?.onFocused?()
                }
                return event
            }
        }

        func removeMouseMonitor() {
            if let monitor = mouseMonitor {
                NSEvent.removeMonitor(monitor)
                mouseMonitor = nil
            }
        }

        func webView(
            _ webView: WKWebView,
            didStartProvisionalNavigation navigation: WKNavigation!
        ) {
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

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
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
    var onFocused: (() -> Void)?
    @State private var urlText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            navigationBar
            WebViewRepresentable(state: state, onFocused: onFocused)
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
            Button { state.pendingAction = .back } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .disabled(!state.canGoBack)
            .help("Back")

            Button { state.pendingAction = .forward } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .disabled(!state.canGoForward)
            .help("Forward")

            Button {
                state.pendingAction = state.isLoading ? .stop : .reload
            } label: {
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
