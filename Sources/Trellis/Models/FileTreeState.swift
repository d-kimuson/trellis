import AppKit
import CoreServices
import Foundation

/// Tab selection for the file preview pane.
public enum PreviewTab: Equatable {
    case content
    case diff
}

/// Observable state for a file tree panel.
/// Uses class (ObservableObject) for file system watcher resource ownership.
public final class FileTreeState: ObservableObject, Identifiable {
    public let id: UUID
    @Published public var rootPath: String?
    @Published public var rootNode: FileNode?
    @Published public var expandedDirectories: Set<UUID>
    @Published public var selectedFilePath: String?
    @Published public var selectedFileContent: String?
    @Published public var selectedFileDiff: String?
    @Published public var selectedPreviewTab: PreviewTab = .content
    @Published public var gitStatusMap: [String: GitFileStatus] = [:]
    @Published public var dirtyDirectoryPaths: Set<String> = []

    private var ignoredPatterns: [String] = []
    private var eventStream: FSEventStreamRef?
    private var eventStreamInfo: UnsafeMutableRawPointer?
    private var debounceWork: DispatchWorkItem?
    private var gitStatusProcess: Process?
    private var gitDiffProcess: Process?

    public init(
        id: UUID = UUID(),
        rootPath: String? = nil
    ) {
        self.id = id
        self.rootPath = rootPath
        self.expandedDirectories = []
        if rootPath != nil {
            reload()
            startWatching()
        }
    }

    /// Reload the file tree from disk, restoring expanded directory contents.
    public func reload() {
        guard let rootPath else {
            rootNode = nil
            return
        }
        let gitignorePath = (rootPath as NSString).appendingPathComponent(".gitignore")
        ignoredPatterns = FileNode.parseGitignore(at: gitignorePath)
        // Re-expand directories that were open before the reload, processing parents
        // before children so nested expansions are restored correctly.
        // A flat loop over Set<UUID> has undefined iteration order, which caused
        // child nodes to be processed before their parent was expanded — making
        // them invisible in the shallow tree and silently skipped.
        rootNode = FileNode.buildTree(at: rootPath, ignoredPatterns: ignoredPatterns)
            .map { restoreExpanded(in: $0) }
        reloadGitStatus()
    }

    /// Change root directory and reload.
    public func changeRoot(to path: String) {
        cancelGitStatus()
        cancelGitDiff()
        stopWatching()
        rootPath = path
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

    /// Select a file and load its content for preview.
    /// If the file has a git diff, also fetches it and switches to the diff tab.
    public func selectFile(at path: String) {
        selectedFilePath = path
        selectedFileDiff = nil
        selectedPreviewTab = .content

        // Read up to 64KB to avoid loading huge files
        guard let data = FileManager.default.contents(atPath: path),
              data.count <= 64 * 1024,
              let content = String(data: data, encoding: .utf8) else {
            selectedFileContent = nil
            return
        }
        selectedFileContent = content

        // Fetch diff only for tracked files with a non-untracked status
        let status = gitStatusMap[path]
        if status != nil && status != .untracked {
            fetchGitDiff(for: path)
        }
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
    private func restoreExpanded(in node: FileNode) -> FileNode {
        guard case .directory(let id, let name, let path, var children) = node else {
            return node
        }
        if expandedDirectories.contains(id) && children.isEmpty {
            children = FileNode.loadChildren(at: path, ignoredPatterns: ignoredPatterns)
        }
        let updatedChildren = children.map { restoreExpanded(in: $0) }
        return .directory(id: id, name: name, path: path, children: updatedChildren)
    }

    /// Load children for a directory node if they haven't been loaded yet (empty children array).
    private func loadChildrenIfNeeded(for nodeId: UUID) {
        guard let root = rootNode else { return }

        guard let node = findNode(id: nodeId, in: root),
              node.isDirectory,
              node.children.isEmpty else { return }

        let children = FileNode.loadChildren(at: node.path, ignoredPatterns: ignoredPatterns)
        rootNode = root.replacingChildren(ofNodeId: nodeId, with: children)
    }

    private func findNode(id: UUID, in node: FileNode) -> FileNode? {
        if node.id == id { return node }
        for child in node.children {
            if let found = findNode(id: id, in: child) {
                return found
            }
        }
        return nil
    }

    // MARK: - File System Watching

    private func startWatching() {
        guard let rootPath else { return }

        // C callback — must be a free function or static closure.
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let state = Unmanaged<FileTreeState>.fromOpaque(info).takeUnretainedValue()
            state.debouncedReload()
        }

        // passRetained increments ARC so self stays alive while the stream is active.
        // The retained pointer is released in stopWatching after the stream is fully torn down.
        let retained = Unmanaged.passRetained(self).toOpaque()
        var context = FSEventStreamContext(
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
            &context,
            [rootPath] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,  // seconds latency
            flags
        ) else {
            Unmanaged<FileTreeState>.fromOpaque(retained).release()
            return
        }

        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream)
        eventStream = stream
        eventStreamInfo = retained
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
        // Release the retained reference taken in startWatching.
        // Must happen after FSEventStreamRelease to guarantee no more callbacks fire.
        if let info = eventStreamInfo {
            Unmanaged<FileTreeState>.fromOpaque(info).release()
            eventStreamInfo = nil
        }
    }

    deinit {
        cancelGitStatus()
        cancelGitDiff()
        stopWatching()
    }

    // MARK: - Git Status

    private func reloadGitStatus() {
        guard let rootPath else {
            gitStatusMap = [:]
            dirtyDirectoryPaths = []
            return
        }
        cancelGitStatus()
        let root = rootPath
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
        guard let rootPath else { return }
        cancelGitDiff()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", rootPath, "diff", "HEAD", "--", path]
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
}
