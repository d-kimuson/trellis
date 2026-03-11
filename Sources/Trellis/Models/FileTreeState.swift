import AppKit
import Foundation

/// Observable state for a file tree panel.
/// Uses class (ObservableObject) for file system watcher resource ownership.
public final class FileTreeState: ObservableObject, Identifiable {
    public let id: UUID
    @Published public var rootPath: String?
    @Published public var rootNode: FileNode?
    @Published public var expandedDirectories: Set<UUID>
    @Published public var selectedFilePath: String?
    @Published public var selectedFileContent: String?

    private var ignoredPatterns: [String] = []
    private var watcherSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var debounceWork: DispatchWorkItem?

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

    /// Reload the file tree from disk (shallow — only root's immediate children).
    public func reload() {
        guard let rootPath else {
            rootNode = nil
            return
        }
        let gitignorePath = (rootPath as NSString).appendingPathComponent(".gitignore")
        ignoredPatterns = FileNode.parseGitignore(at: gitignorePath)
        rootNode = FileNode.buildTree(at: rootPath, ignoredPatterns: ignoredPatterns)
    }

    /// Change root directory and reload.
    public func changeRoot(to path: String) {
        stopWatching()
        rootPath = path
        expandedDirectories = []
        selectedFilePath = nil
        selectedFileContent = nil
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
    public func selectFile(at path: String) {
        selectedFilePath = path
        // Read up to 64KB to avoid loading huge files
        guard let data = FileManager.default.contents(atPath: path),
              data.count <= 64 * 1024,
              let content = String(data: data, encoding: .utf8) else {
            selectedFileContent = nil
            return
        }
        selectedFileContent = content
    }

    /// Open a directory picker and set the root path.
    public func openDirectoryPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a directory to browse"
        panel.prompt = "Open"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        changeRoot(to: url.path)
    }

    // MARK: - Lazy Loading

    /// Load children for a directory node if they haven't been loaded yet (empty children array).
    private func loadChildrenIfNeeded(for nodeId: UUID) {
        guard let root = rootNode else { return }

        // Find the node and check if children are already loaded
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
