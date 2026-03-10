import Foundation

/// Observable state for a file tree panel.
/// Uses class (ObservableObject) for file system watcher resource ownership.
public final class FileTreeState: ObservableObject, Identifiable {
    public let id: UUID
    @Published public var rootPath: String
    @Published public var rootNode: FileNode?
    @Published public var expandedDirectories: Set<UUID>

    private var watcherSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var debounceWork: DispatchWorkItem?

    public init(
        id: UUID = UUID(),
        rootPath: String = NSHomeDirectory()
    ) {
        self.id = id
        self.rootPath = rootPath
        self.expandedDirectories = []
        reload()
        startWatching()
    }

    /// Reload the file tree from disk.
    public func reload() {
        let gitignorePath = (rootPath as NSString).appendingPathComponent(".gitignore")
        let patterns = FileNode.parseGitignore(at: gitignorePath)
        rootNode = FileNode.buildTree(at: rootPath, ignoredPatterns: patterns)
    }

    /// Change root directory and reload.
    public func changeRoot(to path: String) {
        stopWatching()
        rootPath = path
        expandedDirectories = []
        reload()
        startWatching()
    }

    /// Toggle expansion state of a directory node.
    public func toggleExpanded(_ nodeId: UUID) {
        if expandedDirectories.contains(nodeId) {
            expandedDirectories.remove(nodeId)
        } else {
            expandedDirectories.insert(nodeId)
        }
    }

    // MARK: - File System Watching

    private func startWatching() {
        fileDescriptor = open(rootPath, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.debouncedReload()
        }

        source.setCancelHandler { [weak self] in
            guard let self, self.fileDescriptor >= 0 else { return }
            close(self.fileDescriptor)
            self.fileDescriptor = -1
        }

        source.resume()
        watcherSource = source
    }

    /// Debounce FS events to avoid reload storms.
    private func debouncedReload() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.reload()
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func stopWatching() {
        debounceWork?.cancel()
        debounceWork = nil
        watcherSource?.cancel()
        watcherSource = nil
    }

    deinit {
        stopWatching()
    }
}
