import AppKit
import SwiftUI

/// File tree panel showing directory contents with expand/collapse.
struct FileTreePanelView: View {
    var state: FileTreeState
    /// Current working directory of the representative terminal session in the area.
    /// Passed as the initial directory when no root has been selected yet.
    var workspaceCwd: String?
    var settings: AppSettings
    var onFocused: (() -> Void)?

    var body: some View {
        VSplitView {
            treePane
                .frame(minHeight: 100)

            if let content = state.selectedFileContent, let path = state.selectedFilePath {
                filePreviewPane(path: path, content: content)
                    .frame(minHeight: 80)
            }
        }
        .simultaneousGesture(TapGesture().onEnded {
            onFocused?()
        })
    }

    // MARK: - Tree Pane

    private var treePane: some View {
        VStack(spacing: 0) {
            toolbar

            if let rootNode = state.rootNode {
                GeometryReader { geo in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(rootNode.children) { child in
                                FileNodeRow(
                                    node: child,
                                    state: state,
                                    depth: 0,
                                    settings: settings
                                )
                            }
                        }
                        .padding(.vertical, 4)
                        .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
                    }
                }
            } else {
                emptyState
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            Image(systemName: "folder")
                .foregroundColor(.secondary)

            if let rootPath = state.rootPath {
                Text(URL(fileURLWithPath: rootPath).lastPathComponent)
                    .font(.system(size: settings.panelFontSize))
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("No directory")
                    .font(.system(size: settings.panelFontSize))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(
                action: { state.openDirectoryPicker(initialDirectory: workspaceCwd) },
                label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.caption)
                }
            )
            .buttonStyle(.borderless)
            .help("Open Directory")

        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("Open a directory to browse files")
                .font(.caption)
                .foregroundColor(.secondary)
            Button("Open Directory") {
                state.openDirectoryPicker(initialDirectory: workspaceCwd)
            }
            .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - File Preview Pane

    private func filePreviewPane(path: String, content: String) -> some View {
        VStack(spacing: 0) {
            previewHeader(path: path)
            if state.isPreviewSearchVisible {
                previewSearchBar
            }
            previewBody(path: path, content: content)
        }
    }

    private func previewHeader(path: String) -> some View {
        HStack {
            Text(URL(fileURLWithPath: path).lastPathComponent)
                .font(.system(size: settings.panelFontSize, design: .monospaced))
                .lineLimit(1)
            if state.selectedFileDiff != nil {
                Spacer()
                previewTabPicker
            }
            Spacer()
            Button(action: { state.isPreviewSearchVisible.toggle() }) {
                Image(systemName: "magnifyingglass").font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Find (Cmd+F)")
            Button(action: state.clearPreview) {
                Image(systemName: "xmark").font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var previewSearchBar: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.caption)
            TextField("Find...", text: Bindable(state).previewSearchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: settings.panelFontSize, design: .monospaced))
                .onSubmit { /* Enter does nothing for now; live search updates on type */ }
            Button(action: { state.isPreviewSearchVisible = false; state.previewSearchQuery = "" }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
    }

    private func previewBody(path: String, content: String) -> some View {
        Group {
            if state.selectedPreviewTab == .diff, let diff = state.selectedFileDiff {
                SyntaxHighlightWebView(
                    code: diff,
                    filePath: path,
                    fontSize: settings.panelFontSize,
                    isDiff: true,
                    searchQuery: state.previewSearchQuery,
                    onFindRequested: { state.isPreviewSearchVisible = true }
                )
            } else {
                SyntaxHighlightWebView(
                    code: content,
                    filePath: path,
                    fontSize: settings.panelFontSize,
                    searchQuery: state.previewSearchQuery,
                    onFindRequested: { state.isPreviewSearchVisible = true }
                )
            }
        }
    }

    private var previewTabPicker: some View {
        HStack(spacing: 0) {
            tabButton(label: "content", tab: .content)
            tabButton(label: "diff", tab: .diff)
        }
        .font(.system(size: settings.panelFontSize - 1, design: .monospaced))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func tabButton(label: String, tab: PreviewTab) -> some View {
        let isSelected = state.selectedPreviewTab == tab
        return Button(
            action: { state.selectedPreviewTab = tab },
            label: {
                Text(label)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            }
        )
        .buttonStyle(.plain)
    }
}

/// A single row in the file tree, recursively rendering children for directories.
private struct FileNodeRow: View {
    let node: FileNode
    var state: FileTreeState
    let depth: Int
    var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Use plain view + onTapGesture instead of Button to allow .draggable() to work.
            // Button consumes the drag gesture, preventing file dragging.
            HStack(spacing: 4) {
                // Indentation
                Spacer()
                    .frame(width: CGFloat(depth) * 16)

                // Disclosure indicator for directories
                if node.isDirectory {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                } else {
                    Spacer()
                        .frame(width: 12)
                }

                // Icon
                Image(systemName: node.isDirectory ? "folder.fill" : fileIcon(for: node.name))
                    .foregroundColor(node.isDirectory ? .accentColor : .secondary)
                    .font(.caption)

                // Name
                Text(node.name)
                    .font(.system(size: settings.panelFontSize, design: .monospaced))
                    .foregroundColor(nameColor)
                    .lineLimit(1)

                Spacer()

                // Git status badge (files only, right-aligned)
                if let badge = gitBadge {
                    Text(badge.label)
                        .font(.system(size: settings.panelFontSize - 2, weight: .medium, design: .monospaced))
                        .foregroundColor(badge.color)
                        .padding(.trailing, 2)
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .onTapGesture { handleTap() }
            .draggable(URL(fileURLWithPath: node.path))
            .background(
                state.selectedFilePath == node.path
                    ? Color.accentColor.opacity(0.15)
                    : Color.clear
            )
            .contextMenu {
                Button("Copy Relative Path") {
                    copyToPasteboard(relativePath)
                }
                Button("Copy Absolute Path") {
                    copyToPasteboard(node.path)
                }
                if !node.isDirectory {
                    Button("Copy File Contents") {
                        if let data = FileManager.default.contents(atPath: node.path),
                           let content = String(data: data, encoding: .utf8) {
                            copyToPasteboard(content)
                        }
                    }
                }
                Divider()
                Button("Open in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [URL(fileURLWithPath: node.path)]
                    )
                }
            }

            // Children (if expanded)
            if node.isDirectory && isExpanded {
                ForEach(node.children) { child in
                    FileNodeRow(
                        node: child,
                        state: state,
                        depth: depth + 1,
                        settings: settings
                    )
                }
            }
        }
    }

    private var isExpanded: Bool {
        state.expandedDirectories.contains(node.id)
    }

    private var nameColor: Color {
        if node.isDirectory {
            return state.dirtyDirectoryPaths.contains(node.path)
                ? Color(red: 0.9, green: 0.6, blue: 0.1)
                : .primary
        }
        switch state.gitStatusMap[node.path] {
        case .untracked, .added: return .green
        case .modified:          return Color(red: 0.9, green: 0.6, blue: 0.1)
        case .deleted:           return .red
        case nil:                return .primary
        }
    }

    private var gitBadge: (label: String, color: Color)? {
        guard !node.isDirectory else { return nil }
        switch state.gitStatusMap[node.path] {
        case .untracked: return ("U", .green)
        case .modified:  return ("M", Color(red: 0.9, green: 0.6, blue: 0.1))
        case .added:     return ("A", .green)
        case .deleted:   return ("D", .red)
        case nil:        return nil
        }
    }

    private var relativePath: String {
        guard let root = state.rootPath else { return node.name }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        if node.path.hasPrefix(prefix) {
            return String(node.path.dropFirst(prefix.count))
        }
        return node.name
    }

    private func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    private func handleTap() {
        if node.isDirectory {
            state.toggleExpanded(node.id)
        } else {
            state.selectFile(at: node.path)
        }
    }

    private func fileIcon(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "ts", "jsx", "tsx": return "doc.text"
        case "json", "yaml", "yml", "toml": return "gearshape"
        case "md", "txt", "rtf": return "doc.plaintext"
        case "png", "jpg", "jpeg", "gif", "svg": return "photo"
        case "py": return "doc.text"
        case "rb": return "doc.text"
        case "sh", "zsh", "bash": return "terminal"
        default: return "doc"
        }
    }
}
