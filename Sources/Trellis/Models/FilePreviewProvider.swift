import Foundation
import Observation
import WebKit

/// Manages file preview state and async content loading.
/// Independently testable without FileTreeState.
@Observable
public final class FilePreviewProvider {
    public var selectedFilePath: String?
    public var selectedFileContent: String?
    public var selectedFileDiff: String?
    public var selectedPreviewTab: PreviewTab = .content
    public var isPreviewSearchVisible: Bool = false
    public var previewSearchQuery: String = ""
    public var previewSearchMatchCount: Int = 0
    public var previewSearchCurrentIndex: Int = 0
    @ObservationIgnored public weak var previewWebView: WKWebView?

    @ObservationIgnored private var selectFileTask: Task<Void, Never>?

    public init() {}

    /// Reset preview state for a new file selection.
    public func resetForSelection(path: String) {
        selectedFilePath = path
        selectedFileDiff = nil
        selectedPreviewTab = .content
        isPreviewSearchVisible = false
        previewSearchQuery = ""
        previewSearchMatchCount = 0
        previewSearchCurrentIndex = 0
        selectedFileContent = nil
    }

    /// Load the content of a file asynchronously.
    /// Calls onContentReady on the main actor with the loaded path and content when complete.
    /// If the file is unreadable or too large (>64KB), content is nil.
    public func loadContent(
        at path: String,
        onContentReady: @escaping @MainActor (String, String?) -> Void
    ) {
        selectFileTask?.cancel()
        selectFileTask = Task.detached {
            let content: String?
            if let data = FileManager.default.contents(atPath: path),
               data.count <= 64 * 1024,
               let text = String(data: data, encoding: .utf8) {
                content = text
            } else {
                content = nil
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                onContentReady(path, content)
            }
        }
    }

    public func clearPreview() {
        selectedFilePath = nil
        selectedFileContent = nil
        selectedFileDiff = nil
        selectedPreviewTab = .content
        isPreviewSearchVisible = false
        previewSearchQuery = ""
        previewSearchMatchCount = 0
        previewSearchCurrentIndex = 0
    }

    public func navigateNext() {
        previewWebView?.evaluateJavaScript("__findNext()", completionHandler: nil)
    }

    public func navigatePrevious() {
        previewWebView?.evaluateJavaScript("__findPrev()", completionHandler: nil)
    }

    public func cancel() {
        selectFileTask?.cancel()
        selectFileTask = nil
    }

    /// Wait for in-flight content loading to complete (for testing).
    func awaitLoad() async {
        await selectFileTask?.value
    }
}
