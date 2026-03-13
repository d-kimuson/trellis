import AppKit
import CoreServices
import Foundation
import Observation

/// Tab selection for the file preview pane.
public enum PreviewTab: Equatable {
    case content
    case diff
}

/// Observable state for a file tree panel.
/// Uses class for file system watcher resource ownership.
@Observable
public final class FileTreeState: Identifiable {
    public let id: UUID
    public var rootPath: String?
    public var rootNode: FileNode?
    public var expandedDirectories: Set<UUID>
    public var selectedFilePath: String?
    public var selectedFileContent: String?
    public var selectedFileDiff: String?
    public var selectedPreviewTab: PreviewTab = .content
    public var isPreviewSearchVisible: Bool = false
    public var previewSearchQuery: String = ""
    public var gitStatusMap: [String: GitFileStatus] = [:]
    public var dirtyDirectoryPaths: Set<String> = []
    public var isGitDiffFilterEnabled: Bool = false
    public let reviewBridge = DiffReviewBridge()

    @ObservationIgnored private(set) var gitRootPath: String?
    @ObservationIgnored private var ignoredPatterns: [String] = []
    @ObservationIgnored private var eventStream: FSEventStreamRef?
    @ObservationIgnored private var eventStreamInfo: UnsafeMutableRawPointer?
    @ObservationIgnored private var debounceWork: DispatchWorkItem?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var selectFileTask: Task<Void, Never>?
    @ObservationIgnored private var loadChildrenTask: Task<Void, Never>?
    @ObservationIgnored private var gitStatusProcess: Process?
    @ObservationIgnored private var gitDiffProcess: Process?

    public init(
        id: UUID = UUID(),
        rootPath: String? = nil
    ) {
        self.id = id
        self.rootPath = rootPath
        self.expandedDirectories = []
        if let rootPath {
            gitRootPath = FileTreeState.detectGitRoot(for: rootPath)
            reloadSync()
            startWatching()
        }
    }

    /// Synchronous reload for initial load (no UI mounted yet, so no freeze risk).
    private func reloadSync() {
        guard let rootPath else {
            rootNode = nil
            return
        }
        let gitignorePath = (rootPath as NSString).appendingPathComponent(".gitignore")
        ignoredPatterns = FileNode.parseGitignore(at: gitignorePath)
        rootNode = FileNode.buildTree(at: rootPath, ignoredPatterns: ignoredPatterns)
            .map { Self.restoreExpanded(in: $0, expandedIds: expandedDirectories, ignoredPatterns: ignoredPatterns) }
        reloadGitStatus()
    }

    /// Detect the git repository root for the given path.
    /// Returns nil if the path is not inside a git repository.
    public static func detectGitRoot(for path: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", path, "rev-parse", "--show-toplevel"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Reload the file tree from disk, restoring expanded directory contents.
    /// I/O runs on a background thread to avoid blocking the main thread.
    public func reload() {
        guard let rootPath else {
            rootNode = nil
            return
        }
        let gitignorePath = (rootPath as NSString).appendingPathComponent(".gitignore")
        let patterns = FileNode.parseGitignore(at: gitignorePath)
        ignoredPatterns = patterns
        let expandedIds = expandedDirectories

        reloadTask?.cancel()
        reloadTask = Task.detached { [weak self] in
            let tree = FileNode.buildTree(at: rootPath, ignoredPatterns: patterns)
                .map { Self.restoreExpanded(in: $0, expandedIds: expandedIds, ignoredPatterns: patterns) }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self else { return }
                self.rootNode = tree
                self.reloadGitStatus()
            }
        }
    }

    /// Wait for in-flight reload to complete (for testing).
    func awaitReload() async {
        await reloadTask?.value
    }

    /// Change root directory and reload.
    public func changeRoot(to path: String) {
        cancelGitStatus()
        cancelGitDiff()
        stopWatching()
        rootPath = path
        gitRootPath = FileTreeState.detectGitRoot(for: path)
        BookmarkStore.save(url: URL(fileURLWithPath: path))
        expandedDirectories = []
        selectedFilePath = nil
        selectedFileContent = nil
        selectedFileDiff = nil
        selectedPreviewTab = .content
        reload()
        startWatching()
    }

    /// Toggle expansion state of a directory node.
    /// On first expand, lazily loads the directory's children.
    public func toggleExpanded(_ nodeId: UUID) {
        if expandedDirectories.contains(nodeId) {
            expandedDirectories.remove(nodeId)
        } else {
            expandedDirectories.insert(nodeId)
            loadChildrenIfNeeded(for: nodeId)
        }
    }

    /// Clear the file preview selection.
    public func clearPreview() {
        selectedFilePath = nil
        selectedFileContent = nil
        selectedFileDiff = nil
        selectedPreviewTab = .content
        isPreviewSearchVisible = false
        previewSearchQuery = ""
    }

    /// Select a file and load its content for preview.
    /// File reading runs on a background thread to avoid blocking the main thread.
    /// If the file has a git diff, also fetches it and switches to the diff tab.
    public func selectFile(at path: String) {
        selectedFilePath = path
        selectedFileDiff = nil
        selectedPreviewTab = .content
        isPreviewSearchVisible = false
        previewSearchQuery = ""
        selectedFileContent = nil

        selectFileTask?.cancel()
        selectFileTask = Task.detached { [weak self] in
            // Read up to 64KB to avoid loading huge files
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
                guard let self, self.selectedFilePath == path else { return }
                self.selectedFileContent = content

                // Fetch diff only for tracked files with a non-untracked status
                let status = self.gitStatusMap[path]
                if status != nil && status != .untracked {
                    self.fetchGitDiff(for: path)
                }
            }
        }
    }

    /// Wait for in-flight file selection to complete (for testing).
    func awaitSelectFile() async {
        await selectFileTask?.value
    }

    /// Open a directory picker and set the root path.
    /// - Parameter initialDirectory: Directory to show initially in the panel.
    ///   Falls back to the current root if already set.
    public func openDirectoryPicker(initialDirectory: String? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a directory to browse"
        panel.prompt = "Open"

        // Prefer the already-open root; otherwise use the caller-supplied initial directory.
        if let dir = rootPath ?? initialDirectory {
            panel.directoryURL = URL(fileURLWithPath: dir)
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        changeRoot(to: url.path)
    }

    // MARK: - Lazy Loading

    /// Recursively restore expanded directories top-down in a freshly-built shallow tree.
    /// Processing top-down ensures that a parent's children are loaded before we attempt
    /// to expand any of its children, which was the root cause of the nested-expansion bug.
    /// Static so it can run on a background thread without capturing self.
    private static func restoreExpanded(
        in node: FileNode,
        expandedIds: Set<UUID>,
        ignoredPatterns: [String],
        depth: Int = 0
    ) -> FileNode {
        guard case .directory(let id, let name, let path, var children) = node else {
            return node
        }
        guard depth < FileNode.maxTraversalDepth else { return node }
        if expandedIds.contains(id) && children.isEmpty {
            children = FileNode.loadChildren(at: path, ignoredPatterns: ignoredPatterns)
        }
        let updatedChildren = children.map {
            restoreExpanded(in: $0, expandedIds: expandedIds, ignoredPatterns: ignoredPatterns, depth: depth + 1)
        }
        return .directory(id: id, name: name, path: path, children: updatedChildren)
    }

    /// Load children for a directory node if they haven't been loaded yet (empty children array).
    /// I/O runs on a background thread.
    private func loadChildrenIfNeeded(for nodeId: UUID) {
        guard let root = rootNode else { return }

        guard let node = findNode(id: nodeId, in: root),
              node.isDirectory,
              node.children.isEmpty else { return }

        let path = node.path
        let patterns = ignoredPatterns

        loadChildrenTask = Task.detached { [weak self] in
            let children = FileNode.loadChildren(at: path, ignoredPatterns: patterns)

            await MainActor.run {
                guard let self, let currentRoot = self.rootNode else { return }
                self.rootNode = currentRoot.replacingChildren(ofNodeId: nodeId, with: children)
            }
        }
    }

    /// Wait for in-flight child loading to complete (for testing).
    func awaitLoadChildren() async {
        await loadChildrenTask?.value
    }

    private func findNode(id: UUID, in node: FileNode, depth: Int = 0) -> FileNode? {
        if node.id == id { return node }
        guard depth < FileNode.maxTraversalDepth else { return nil }
        for child in node.children {
            if let found = findNode(id: id, in: child, depth: depth + 1) {
                return found
            }
        }
        return nil
    }

    // MARK: - File System Watching

    /// Weak wrapper passed to FSEventStream callback via Unmanaged.passRetained.
    /// The callback accesses FileTreeState through a weak reference, so if
    /// the state is deallocated before the stream is torn down, the callback
    /// safely sees nil and does nothing — eliminating the race between
    /// FSEventStream delivery and FileTreeState deinit.
    private final class FSEventContext {
        weak var state: FileTreeState?
        init(_ state: FileTreeState) { self.state = state }
    }

    @ObservationIgnored private var eventContext: FSEventContext?

    private func startWatching() {
        guard let rootPath else { return }

        // C callback — must be a free function or static closure.
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let context = Unmanaged<FSEventContext>.fromOpaque(info).takeUnretainedValue()
            context.state?.debouncedReload()
        }

        // Retain the weak-wrapper context so it stays alive while the stream is active.
        // The wrapper is released in stopWatching after the stream is fully torn down.
        let context = FSEventContext(self)
        let retained = Unmanaged.passRetained(context).toOpaque()
        var streamContext = FSEventStreamContext(
            version: 0,
            info: retained,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagWatchRoot
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &streamContext,
            [rootPath] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,  // seconds latency
            flags
        ) else {
            Unmanaged<FSEventContext>.fromOpaque(retained).release()
            return
        }

        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream)
        eventStream = stream
        eventStreamInfo = retained
        eventContext = context
    }

    /// Debounce FS events to avoid reload storms.
    private func debouncedReload() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.reload()
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func stopWatching() {
        debounceWork?.cancel()
        debounceWork = nil
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
        }
        // Release the retained FSEventContext wrapper taken in startWatching.
        // Must happen after FSEventStreamRelease to guarantee no more callbacks fire.
        if let info = eventStreamInfo {
            Unmanaged<FSEventContext>.fromOpaque(info).release()
            eventStreamInfo = nil
        }
        // Nil out the weak reference so any in-flight debounced work (which uses
        // [weak self]) will also see the context as disconnected.
        eventContext?.state = nil
        eventContext = nil
    }

    deinit {
        reloadTask?.cancel()
        selectFileTask?.cancel()
        loadChildrenTask?.cancel()
        cancelGitStatus()
        cancelGitDiff()
        stopWatching()
    }

    // MARK: - Git Status

    private func reloadGitStatus() {
        guard let gitRoot = gitRootPath else {
            gitStatusMap = [:]
            dirtyDirectoryPaths = []
            return
        }
        cancelGitStatus()
        let root = gitRoot
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", root, "status", "--porcelain"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] proc in
            let output: String? = proc.terminationStatus == 0
                ? String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
                : nil
            DispatchQueue.main.async {
                guard let self, self.gitStatusProcess === proc else { return }
                if let output {
                    let map = GitFileStatus.parse(porcelainOutput: output, root: root)
                    self.gitStatusMap = map
                    self.dirtyDirectoryPaths = GitFileStatus.dirtyDirectories(from: map, root: root)
                } else {
                    self.gitStatusMap = [:]
                    self.dirtyDirectoryPaths = []
                }
                self.gitStatusProcess = nil
            }
        }
        try? process.run()
        gitStatusProcess = process
    }

    private func cancelGitStatus() {
        gitStatusProcess?.terminate()
        gitStatusProcess = nil
    }

    // MARK: - Git Diff

    private func fetchGitDiff(for path: String) {
        guard let gitRoot = gitRootPath else { return }
        cancelGitDiff()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", gitRoot, "diff", "--histogram", "HEAD", "--", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let targetPath = path
        process.terminationHandler = { [weak self] proc in
            let output: String? = proc.terminationStatus == 0
                ? String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
                : nil
            DispatchQueue.main.async {
                guard let self, self.gitDiffProcess === proc else { return }
                self.gitDiffProcess = nil
                guard let diff = output, !diff.isEmpty,
                      self.selectedFilePath == targetPath else { return }
                self.selectedFileDiff = diff
                self.selectedPreviewTab = .diff
            }
        }
        try? process.run()
        gitDiffProcess = process
    }

    private func cancelGitDiff() {
        gitDiffProcess?.terminate()
        gitDiffProcess = nil
    }

    // MARK: - Review

    /// Relative path of the selected file from the git root (or root path).
    public var selectedFileRelativePath: String? {
        guard let filePath = selectedFilePath else { return nil }
        let root = gitRootPath ?? rootPath
        guard let root else { return URL(fileURLWithPath: filePath).lastPathComponent }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        if filePath.hasPrefix(prefix) {
            return String(filePath.dropFirst(prefix.count))
        }
        return URL(fileURLWithPath: filePath).lastPathComponent
    }

    /// Copy review comments to clipboard.
    public func copyReview() {
        guard let relativePath = selectedFileRelativePath else { return }
        reviewBridge.copyReview(filePath: relativePath)
    }

    /// Compute the filtered tree based on the git diff filter.
    /// Returns the original tree if the filter is not active.
    public func filteredRootNode() -> FileNode? {
        if isGitDiffFilterEnabled {
            let changedPaths = Set(gitStatusMap.keys)
            return rootNode?.filteredByPaths(changedPaths)
        }
        return rootNode
    }

}
