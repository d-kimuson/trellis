import SwiftUI
import WebKit

/// NSViewRepresentable wrapper around WKWebView.
struct WebViewRepresentable: NSViewRepresentable {
    @ObservedObject var state: BrowserState
    var onFocused: (() -> Void)?

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        // Private API: "developerExtrasEnabled" is an undocumented WebKit preference key.
        // Enables right-click "Inspect Element" + programmatic inspector open.
        // Safe to fail silently via KVC if removed in future macOS versions.
        webView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        // Wire direct action dispatch — bypasses SwiftUI update cycle to avoid lost/double-fire.
        state.performAction = { [weak coordinator = context.coordinator] action in
            coordinator?.perform(action)
        }
        webView.load(URLRequest(url: state.currentURL))
        context.coordinator.setupMouseMonitor(webView: webView)
        context.coordinator.setupKeyboardMonitor(webView: webView)
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
        Coordinator(state: state, onFocused: onFocused)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.state.performAction = nil
        coordinator.removeMouseMonitor()
        coordinator.removeKeyboardMonitor()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let state: BrowserState
        let onFocused: (() -> Void)?
        var lastNavigatedURL: URL?
        weak var webView: WKWebView?
        private let eventMonitor = BrowserEventMonitor.shared

        init(state: BrowserState, onFocused: (() -> Void)?) {
            self.state = state
            self.onFocused = onFocused
            self.lastNavigatedURL = state.currentURL
        }

        func perform(_ action: BrowserNavigationAction) {
            switch action {
            case .back: webView?.goBack()
            case .forward: webView?.goForward()
            case .reload: webView?.reload()
            case .stop: webView?.stopLoading()
            case .openDevTools: openDevTools()
            }
        }

        // MARK: - Private API Usage

        /// Opens the Web Inspector panel using WKWebView private `_inspector` API.
        ///
        /// **Private API**: Uses `_inspector` selector and `show` on the returned object.
        /// May break on future macOS versions; will be rejected by App Store review.
        /// The `responds(to:)` guards ensure a safe no-op fallback if selectors are removed.
        /// Falls back to right-click "Inspect Element" when unavailable.
        ///
        /// Verified on: macOS 14 (Sonoma), macOS 15 (Sequoia). Re-verify after major releases.
        private func openDevTools() {
            guard let webView else { return }
            let inspectorSel = Selector(("_inspector"))
            guard webView.responds(to: inspectorSel),
                  let inspector = webView.perform(inspectorSel)?.takeUnretainedValue() as? NSObject
            else { return }
            let showSel = Selector(("show"))
            if inspector.responds(to: showSel) {
                inspector.perform(showSel)
            }
        }

        deinit {
            eventMonitor.removeAll(for: self)
        }

        func setupKeyboardMonitor(webView: WKWebView) {
            // F12 (keyCode 111) opens DevTools when the WebView is focused.
            eventMonitor.addKeyboardHandler(for: self) { [weak self, weak webView] event in
                guard let webView, event.keyCode == 111 else { return event }
                let responder = webView.window?.firstResponder
                let isWebViewFocused: Bool
                if let view = responder as? NSView {
                    isWebViewFocused = view === webView || view.isDescendant(of: webView)
                } else {
                    isWebViewFocused = false
                }
                if isWebViewFocused {
                    self?.perform(.openDevTools)
                    return nil
                }
                return event
            }
        }

        func removeKeyboardMonitor() {
            eventMonitor.removeKeyboardHandler(for: self)
        }

        func setupMouseMonitor(webView: WKWebView) {
            eventMonitor.addMouseHandler(for: self) { [weak self, weak webView] event in
                guard let webView = webView else { return event }
                let point = webView.convert(event.locationInWindow, from: nil)
                if webView.bounds.contains(point) {
                    self?.onFocused?()
                }
                return event
            }
        }

        func removeMouseMonitor() {
            eventMonitor.removeMouseHandler(for: self)
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
            Button { state.performAction?(.back) } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .disabled(!state.canGoBack)
            .help("Back")

            Button { state.performAction?(.forward) } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .disabled(!state.canGoForward)
            .help("Forward")

            Button {
                state.performAction?(state.isLoading ? .stop : .reload)
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

            Button { state.performAction?(.openDevTools) } label: {
                Image(systemName: "hammer")
            }
            .buttonStyle(.borderless)
            .help("Open DevTools (F12)")
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
