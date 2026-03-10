import SwiftUI

/// File tree panel showing directory contents with expand/collapse.
struct FileTreePanelView: View {
    @ObservedObject var state: FileTreeState

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            if let rootNode = state.rootNode {
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
                }
            } else {
                VStack {
                    Spacer()
                    Text("No directory loaded")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            Image(systemName: "folder")
                .foregroundColor(.secondary)

            Text(URL(fileURLWithPath: state.rootPath).lastPathComponent)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

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
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

/// A single row in the file tree, recursively rendering children for directories.
private struct FileNodeRow: View {
    let node: FileNode
    @ObservedObject var state: FileTreeState
    let depth: Int

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
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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
            // Copy path to clipboard
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(node.path, forType: .string)
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
