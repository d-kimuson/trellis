import AppKit
import SwiftUI
import WebKit

/// WKWebView subclass that forwards standard editing key equivalents (Cmd+C, Cmd+A).
/// WKWebView does not override performKeyEquivalent for these, so they fall through
/// to the system beep without this override.
private final class EditableWKWebView: WKWebView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers {
        case "c":
            NSApp.sendAction(#selector(NSText.copy(_:)), to: self, from: nil)
            return true
        case "a":
            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: self, from: nil)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}

/// WKWebView-based syntax highlight view using highlight.js (OSS: https://highlightjs.org/).
/// Resources/highlight/highlight.min.js must be present in the app bundle.
struct SyntaxHighlightWebView: NSViewRepresentable {
    let code: String
    let filePath: String
    let fontSize: CGFloat
    /// When true, renders the code as a GitHub-style diff using diff2html.
    var isDiff: Bool = false

    final class Coordinator {
        var cachedCode: String = ""
        var cachedFilePath: String = ""
        var cachedFontSize: CGFloat = 0
        var cachedIsDiff: Bool = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let webView = EditableWKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        let html = buildHTML()
        webView.loadHTMLString(html, baseURL: nil)
        let coordinator = context.coordinator
        coordinator.cachedCode = code
        coordinator.cachedFilePath = filePath
        coordinator.cachedFontSize = fontSize
        coordinator.cachedIsDiff = isDiff
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        guard code != coordinator.cachedCode
            || filePath != coordinator.cachedFilePath
            || fontSize != coordinator.cachedFontSize
            || isDiff != coordinator.cachedIsDiff
        else { return }
        webView.loadHTMLString(buildHTML(), baseURL: nil)
        coordinator.cachedCode = code
        coordinator.cachedFilePath = filePath
        coordinator.cachedFontSize = fontSize
        coordinator.cachedIsDiff = isDiff
    }

    // MARK: - Private

    private var language: String {
        let ext = (filePath as NSString).pathExtension.lowercased()
        return Self.languageForExtension(ext)
    }

    private func buildHTML() -> String {
        if isDiff, let d2h = Self.cachedDiff2htmlResources {
            return diff2htmlHTML(js: d2h.js, css: d2h.css)
        }
        guard let resources = Self.cachedHighlightResources else {
            return plainTextHTML()
        }
        return highlightedHTML(js: resources.js, lightCSS: resources.lightCSS, darkCSS: resources.darkCSS)
    }

    private func diff2htmlHTML(js: String, css: String) -> String {
        let size = Int(fontSize)
        let mono = "'SF Mono', 'Menlo', 'Monaco', monospace"
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <style>
        \(css)
        \(diff2htmlOverrideCSS(mono: mono, size: size))
        </style>
        </head>
        <body class="d2h-auto-color-scheme">
        <script>\(js)</script>
        <script>
        \(diff2htmlRenderJS(escaped: escapeJS(code)))
        </script>
        </body>
        </html>
        """
    }

    private func diff2htmlOverrideCSS(mono: String, size: Int) -> String {
        """
        * { box-sizing: border-box; }
        body { margin: 0; background: transparent; font-family: \(mono); font-size: \(size)px; }
        .d2h-file-header { display: none; }
        .d2h-file-wrapper { border: none; border-radius: 0; margin: 0; }
        .d2h-diff-table { font-family: \(mono); font-size: \(size)px; border-collapse: collapse; }
        .d2h-file-diff { overflow-x: auto; }
        .d2h-code-linenumber, .d2h-code-side-linenumber {
            position: sticky; left: 0; z-index: 1;
            font-family: \(mono); font-size: \(size)px;
            background: inherit; }
        .d2h-auto-color-scheme {
          --d2h-bg-color:#ffffff; --d2h-border-color:#d0d7de;
          --d2h-line-border-color:#d0d7de; --d2h-dim-color:#636c76;
          --d2h-ins-bg-color:#e6ffec; --d2h-ins-border-color:#acf2bd;
          --d2h-ins-highlight-bg-color:#abf2bc; --d2h-del-bg-color:#ffebe9;
          --d2h-del-border-color:#ffc1ba; --d2h-del-highlight-bg-color:#ff818266;
          --d2h-change-del-color:#fff5b1; --d2h-change-ins-color:#dcffe4;
          --d2h-info-bg-color:#ddf4ff; --d2h-info-border-color:#54aeff66;
          --d2h-empty-placeholder-bg-color:#f6f8fa;
          --d2h-empty-placeholder-border-color:#d0d7de; }
        @media (prefers-color-scheme: dark) {
          .d2h-auto-color-scheme {
            --d2h-color:#e6edf3; --d2h-bg-color:#0d1117;
            --d2h-border-color:#30363d; --d2h-line-border-color:#21262d;
            --d2h-dim-color:#6e7681; --d2h-ins-bg-color:#033a16;
            --d2h-ins-border-color:#196c2e; --d2h-ins-highlight-bg-color:#2ea04366;
            --d2h-ins-label-color:#3fb950; --d2h-del-bg-color:#67060c;
            --d2h-del-border-color:#8e1519; --d2h-del-highlight-bg-color:#f8514966;
            --d2h-del-label-color:#f85149; --d2h-change-del-color:rgba(210,153,34,.2);
            --d2h-change-ins-color:rgba(46,160,67,.25); --d2h-info-bg-color:#0c2d6b;
            --d2h-info-border-color:#388bfd66; --d2h-empty-placeholder-bg-color:#161b22;
            --d2h-empty-placeholder-border-color:#30363d; } }
        """
    }

    private func diff2htmlRenderJS(escaped: String) -> String {
        """
        var diff = "\(escaped)";
        var html = Diff2Html.html(diff, { drawFileList: false, matching: 'lines',
                                          outputFormat: 'line-by-line' });
        document.body.innerHTML = html;
        """
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

    private func escapeJS(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    // MARK: - Resource loading

    private struct HighlightResources {
        let js: String
        let lightCSS: String
        let darkCSS: String
    }

    private struct Diff2HtmlResources {
        let js: String
        let css: String
    }

    private static let cachedHighlightResources: HighlightResources? = {
        guard
            let js = loadBundleResource(name: "highlight.min", ext: "js", subdirectory: "highlight"),
            let lightCSS = loadBundleResource(name: "github-light.min", ext: "css", subdirectory: "highlight"),
            let darkCSS = loadBundleResource(name: "github-dark.min", ext: "css", subdirectory: "highlight")
        else { return nil }
        return HighlightResources(js: js, lightCSS: lightCSS, darkCSS: darkCSS)
    }()

    private static let cachedDiff2htmlResources: Diff2HtmlResources? = {
        guard
            let js = loadBundleResource(name: "diff2html.min", ext: "js", subdirectory: "diff2html"),
            let css = loadBundleResource(name: "diff2html.min", ext: "css", subdirectory: "diff2html")
        else { return nil }
        return Diff2HtmlResources(js: js, css: css)
    }()

    private static func loadBundleResource(name: String, ext: String, subdirectory: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdirectory)
        else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Language detection

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
