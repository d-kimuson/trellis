import AppKit
import SwiftUI
import WebKit

/// WKWebView-based syntax highlight view using highlight.js (OSS: https://highlightjs.org/).
/// Resources/highlight/highlight.min.js must be present in the app bundle.
struct SyntaxHighlightWebView: NSViewRepresentable {
    let code: String
    let filePath: String
    let fontSize: CGFloat

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(buildHTML(), baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(buildHTML(), baseURL: nil)
    }

    // MARK: - Private

    private var language: String {
        let ext = (filePath as NSString).pathExtension.lowercased()
        return Self.languageForExtension(ext)
    }

    private func buildHTML() -> String {
        guard let resources = Self.loadHighlightResources() else {
            return plainTextHTML()
        }
        return highlightedHTML(js: resources.js, lightCSS: resources.lightCSS, darkCSS: resources.darkCSS)
    }

    private func highlightedHTML(js: String, lightCSS: String, darkCSS: String) -> String {
        let escaped = escapeHTML(code)
        let lang = language
        let size = Int(fontSize)
        let baseCSS = baseStyleCSS(size: size)
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <style>
        \(lightCSS)
        @media (prefers-color-scheme: dark) {
        \(darkCSS)
        }
        \(baseCSS)
        </style>
        </head>
        <body>
        <pre><code class="\(lang)">\(escaped)</code></pre>
        <script>\(js)</script>
        <script>hljs.highlightAll();</script>
        </body>
        </html>
        """
    }

    private func plainTextHTML() -> String {
        let size = Int(fontSize)
        return """
        <!DOCTYPE html>
        <html>
        <head><meta charset="UTF-8">
        <style>
        body { font-family: 'SF Mono', 'Menlo', monospace; font-size: \(size)px;
               padding: 8px; margin: 0; white-space: pre; }
        @media (prefers-color-scheme: dark) { body { color: #c9d1d9; background: #0d1117; } }
        </style>
        </head>
        <body>\(escapeHTML(code))</body>
        </html>
        """
    }

    private func baseStyleCSS(size: Int) -> String {
        """
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'SF Mono', 'Menlo', 'Monaco', monospace;
               font-size: \(size)px; background: transparent; }
        pre { margin: 0; padding: 8px; white-space: pre; overflow: visible; }
        pre code.hljs { padding: 0; font-size: \(size)px;
                        font-family: 'SF Mono', 'Menlo', 'Monaco', monospace;
                        background: transparent; }
        """
    }

    private func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Resource loading

    private struct HighlightResources {
        let js: String
        let lightCSS: String
        let darkCSS: String
    }

    private static func loadHighlightResources() -> HighlightResources? {
        guard
            let jsURL = Bundle.main.url(
                forResource: "highlight.min", withExtension: "js", subdirectory: "highlight"),
            let js = try? String(contentsOf: jsURL, encoding: .utf8),
            let lightURL = Bundle.main.url(
                forResource: "github-light.min", withExtension: "css", subdirectory: "highlight"),
            let lightCSS = try? String(contentsOf: lightURL, encoding: .utf8),
            let darkURL = Bundle.main.url(
                forResource: "github-dark.min", withExtension: "css", subdirectory: "highlight"),
            let darkCSS = try? String(contentsOf: darkURL, encoding: .utf8)
        else { return nil }
        return HighlightResources(js: js, lightCSS: lightCSS, darkCSS: darkCSS)
    }

    // MARK: - Language detection

    // swiftlint:disable:next type_body_length
    private static let extensionToLanguage: [String: String] = [
        "swift": "swift",
        "js": "javascript", "jsx": "javascript", "mjs": "javascript",
        "ts": "typescript", "tsx": "typescript",
        "py": "python",
        "rb": "ruby",
        "sh": "bash", "bash": "bash", "zsh": "bash",
        "json": "json",
        "yaml": "yaml", "yml": "yaml",
        "toml": "toml",
        "md": "markdown", "markdown": "markdown",
        "html": "html", "htm": "html",
        "css": "css",
        "rs": "rust",
        "go": "go",
        "java": "java",
        "c": "c",
        "cpp": "cpp", "cc": "cpp", "cxx": "cpp", "h": "cpp", "hpp": "cpp", "hxx": "cpp",
        "cs": "csharp",
        "kt": "kotlin", "kts": "kotlin",
        "sql": "sql",
        "xml": "xml", "plist": "xml",
        "zig": "zig"
    ]

    static func languageForExtension(_ ext: String) -> String {
        extensionToLanguage[ext] ?? ""
    }
}
