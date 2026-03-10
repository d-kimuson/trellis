import SwiftUI

/// Git client panel with branch info, staging, diff, and basic operations.
struct GitPanelView: View {
    @ObservedObject var state: GitClientState

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if state.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    fileListView
                        .frame(minWidth: 200)

                    diffView
                        .frame(minWidth: 200)
                }
            }

            if let error = state.lastError {
                errorBar(error)
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .foregroundColor(.secondary)

            if let status = state.status {
                branchPicker(currentBranch: status.branch)
            } else {
                Text("No repository")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(
                action: { state.pull() },
                label: {
                    Image(systemName: "arrow.down")
                        .font(.caption)
                }
            )
            .buttonStyle(.borderless)
            .help("Pull")

            Button(
                action: { state.push() },
                label: {
                    Image(systemName: "arrow.up")
                        .font(.caption)
                }
            )
            .buttonStyle(.borderless)
            .help("Push")

            Button(
                action: { state.refresh() },
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

    private func branchPicker(currentBranch: String) -> some View {
        Menu(
            content: {
                ForEach(state.branches, id: \.self) { branch in
                    Button(
                        action: { state.checkout(branch: branch) },
                        label: {
                            HStack {
                                Text(branch)
                                if branch == currentBranch {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    )
                }
            },
            label: {
                HStack(spacing: 2) {
                    Text(currentBranch)
                        .font(.caption)
                        .fontWeight(.semibold)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                }
            }
        )
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - File List

    private var fileListView: some View {
        VStack(spacing: 0) {
            if let status = state.status {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !status.stagedFiles.isEmpty {
                            sectionHeader("Staged Changes", count: status.stagedFiles.count)
                            ForEach(status.stagedFiles) { file in
                                fileRow(file: file, staged: true)
                            }
                        }

                        if !status.unstagedFiles.isEmpty {
                            sectionHeader("Changes", count: status.unstagedFiles.count)
                            ForEach(status.unstagedFiles) { file in
                                fileRow(file: file, staged: false)
                            }
                        }

                        if status.files.isEmpty {
                            Text("Working tree clean")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding()
                        }
                    }
                }

                Divider()
                commitBar
            } else {
                Text("Not a git repository")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text("\(title) (\(count))")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func fileRow(file: GitFileEntry, staged: Bool) -> some View {
        HStack(spacing: 4) {
            statusBadge(for: staged ? file.indexStatus : file.workTreeStatus)

            Text(file.path)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button(
                action: {
                    if staged {
                        state.unstage(file: file.path)
                    } else {
                        state.stage(file: file.path)
                    }
                },
                label: {
                    Image(systemName: staged ? "minus.circle" : "plus.circle")
                        .font(.caption)
                        .foregroundColor(staged ? .orange : .green)
                }
            )
            .buttonStyle(.borderless)
            .help(staged ? "Unstage" : "Stage")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            state.loadDiff(for: file.path, staged: staged)
        }
        .background(
            state.selectedFile == file.path
                ? Color.accentColor.opacity(0.1)
                : Color.clear
        )
    }

    private func statusBadge(for status: GitFileStatus) -> some View {
        Text(statusLetter(for: status))
            .font(.system(.caption2, design: .monospaced))
            .fontWeight(.bold)
            .foregroundColor(statusColor(for: status))
            .frame(width: 16)
    }

    private func statusLetter(for status: GitFileStatus) -> String {
        switch status {
        case .modified: return "M"
        case .added: return "A"
        case .deleted: return "D"
        case .renamed: return "R"
        case .untracked: return "?"
        case .unknown(let code): return code
        }
    }

    private func statusColor(for status: GitFileStatus) -> Color {
        switch status {
        case .modified: return .orange
        case .added: return .green
        case .deleted: return .red
        case .renamed: return .blue
        case .untracked: return .secondary
        case .unknown: return .secondary
        }
    }

    // MARK: - Commit Bar

    private var commitBar: some View {
        HStack(spacing: 4) {
            TextField("Commit message", text: $state.commitMessage)
                .textFieldStyle(.roundedBorder)
                .font(.caption)

            Button("Commit") {
                state.commit()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(
                state.commitMessage
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || (state.status?.stagedFiles.isEmpty ?? true)
            )
        }
        .padding(8)
    }

    // MARK: - Diff View

    private var diffView: some View {
        VStack(spacing: 0) {
            if let selectedFile = state.selectedFile {
                HStack {
                    Text(selectedFile)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor))
            }

            if let diff = state.diffText, !diff.isEmpty {
                ScrollView([.horizontal, .vertical]) {
                    Text(diff)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("Select a file to view diff")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Error Bar

    private func errorBar(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.red)
            Text(message)
                .font(.caption)
                .foregroundColor(.red)
                .lineLimit(2)
            Spacer()
            Button(
                action: { state.lastError = nil },
                label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
            )
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.red.opacity(0.1))
    }
}
