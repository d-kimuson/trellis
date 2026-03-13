import AppKit
import Foundation
import WebKit

/// Bridge between SwiftUI and the WKWebView for diff review comments.
/// The Coordinator of SyntaxHighlightWebView sets `webView` when the diff view is created.
/// The "Copy Review" button calls `copyReview(filePath:)` to collect comments from JS and
/// copy formatted text to the clipboard.
@Observable
public final class DiffReviewBridge {
    public weak var webView: WKWebView?
    public var hasComments: Bool = false

    public init() {}

    /// Collect review comments from JS and copy formatted text to clipboard.
    public func copyReview(filePath: String) {
        guard let webView else { return }
        webView.evaluateJavaScript("__getReviewComments()") { result, _ in
            guard let jsonString = result as? String,
                  let data = jsonString.data(using: .utf8),
                  let rawComments = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else { return }
            let comments = rawComments.compactMap { dict -> DiffReviewComment? in
                guard let line = dict["line"] as? Int,
                      let text = dict["text"] as? String,
                      !text.isEmpty
                else { return nil }
                return DiffReviewComment(lineNumber: line, text: text)
            }
            guard !comments.isEmpty else { return }
            let formatted = DiffReviewFormatter.format(filePath: filePath, comments: comments)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(formatted, forType: .string)
        }
    }
}
