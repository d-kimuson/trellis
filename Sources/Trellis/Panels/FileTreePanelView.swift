import SwiftUI

/// File tree panel showing directory contents with expand/collapse.
struct FileTreePanelView: View {
    @ObservedObject var state: FileTreeState
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VSplitView {
            treePane
                .frame(minHeight: 100)

            if let content = state.selectedFileContent, let path = state.selectedFilePath {
                filePreviewPane(path: path, content: content)
                    .frame(minHeight: 80)
            }
        }
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
                                    depth: 0
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
                action: { state.openDirectoryPicker() },
                label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.caption)
                }
            )
            .buttonStyle(.borderless)
            .help("Open Directory")

            if state.rootPath != nil {
                Button(
                    action: { state.reload() },
                    label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                )
                .buttonStyle(.borderless)
                .help("Refresh")
            }
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
                state.openDirectoryPicker()
            }
            .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - File Preview Pane

    private func filePreviewPane(path: String, content: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(.system(size: settings.panelFontSize, design: .monospaced))
                    .lineLimit(1)
                Spacer()
                Button(
                    action: {
                        state.selectedFilePath = nil
                        state.selectedFileContent = nil
                    },
                    label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                    }
                )
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))

            GeometryReader { geo in
                ScrollView([.horizontal, .vertical]) {
                    Text(content)
                        .font(.system(size: settings.panelFontSize, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
                }
            }
        }
    }
}

/// A single row in the file tree, recursively rendering children for directories.
private struct FileNodeRow: View {
    let node: FileNode
    @ObservedObject var state: FileTreeState
    let depth: Int
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: handleTap) {
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
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                state.selectedFilePath == node.path
                    ? Color.accentColor.opacity(0.15)
                    : Color.clear
            )

            // Children (if expanded)
            if node.isDirectory && isExpanded {
                ForEach(node.children) { child in
                    FileNodeRow(
                        node: child,
                        state: state,
                        depth: depth + 1
                    )
                }
            }
        }
    }

    private var isExpanded: Bool {
        state.expandedDirectories.contains(node.id)
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
