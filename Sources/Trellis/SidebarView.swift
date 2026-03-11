import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var notificationStore: NotificationStore
    @State private var renamingIndex: Int?
    @State private var hoveredIndex: Int?
    @State private var indexToClose: Int?
    @State private var showCloseConfirmation = false

    var body: some View {
        List(selection: Binding<Int?>(
            get: { store.activeWorkspaceIndex },
            set: { index in
                if let index {
                    store.selectWorkspace(at: index)
                }
            }
        )) {
            Section {
                ForEach(Array(store.workspaces.enumerated()), id: \.element.id) { index, workspace in
                    WorkspaceCard(
                        workspace: workspace,
                        isActive: index == store.activeWorkspaceIndex,
                        unreadCount: notificationStore.unreadCount(forSessionIds: store.sessionIds(forWorkspace: index)),
                        isEditing: Binding(
                            get: { renamingIndex == index },
                            set: { editing in
                                renamingIndex = editing ? index : nil
                            }
                        ),
                        showCloseButton: hoveredIndex == index,
                        onRename: { newName in
                            store.renameWorkspace(at: index, to: newName)
                        },
                        onClose: {
                            requestClose(at: index)
                        }
                    )
                    .tag(index)
                    .onHover { hovering in
                        hoveredIndex = hovering ? index : nil
                    }
                    .contextMenu {
                        Button("Rename") {
                            renamingIndex = index
                        }
                    }
                }
                .onMove { fromOffsets, toOffset in
                    store.moveWorkspace(fromOffsets: fromOffsets, toOffset: toOffset)
                }
            } header: {
                HStack {
                    Text("Workspaces")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button(action: { store.addWorkspace() }) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 20, height: 20)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.primary.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("New Workspace")
                }
                .padding(.trailing, 4)
                .padding(.bottom, 4)
            }
            .collapsible(false)
        }
        .listStyle(.sidebar)
        .confirmationDialog(
            "Close Workspace?",
            isPresented: $showCloseConfirmation,
            titleVisibility: .visible
        ) {
            Button("Close", role: .destructive) {
                if let idx = indexToClose {
                    store.removeWorkspace(at: idx)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This workspace has open panels. Close anyway?")
        }
    }

    private func requestClose(at index: Int) {
        guard store.workspaces.count > 1 else { return }
        let workspace = store.workspaces[index]
        let hasOpenPanels = workspace.allAreas.contains { !$0.tabs.isEmpty }
        if hasOpenPanels {
            indexToClose = index
            showCloseConfirmation = true
        } else {
            store.removeWorkspace(at: index)
        }
    }
}

// MARK: - Workspace Card

private struct WorkspaceCard: View {
    let workspace: Workspace
    let isActive: Bool
    let unreadCount: Int
    @Binding var isEditing: Bool
    let showCloseButton: Bool
    let onRename: (String) -> Void
    let onClose: () -> Void

    @State private var editingName: String = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Title row
            HStack {
                if isEditing {
                    TextField("Workspace name", text: $editingName, onCommit: {
                        let trimmed = editingName.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            onRename(trimmed)
                        }
                        isEditing = false
                    })
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .focused($isTextFieldFocused)
                    .onExitCommand {
                        isEditing = false
                    }
                    .onAppear {
                        editingName = workspace.name
                        DispatchQueue.main.async {
                            isTextFieldFocused = true
                        }
                    }
                } else {
                    Text(workspace.name)
                        .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                        .lineLimit(1)
                }

                Spacer()

                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor))
                }

                if showCloseButton {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 16, height: 16)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.primary.opacity(0.08))
                        )
                        .onTapGesture { onClose() }
                }
            }

            // Session info (branch, cwd)
            if let session = workspace.representativeSession {
                WorkspaceSessionInfo(session: session)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Workspace Session Info

/// Observes the representative terminal session to reactively show branch/cwd.
private struct WorkspaceSessionInfo: View {
    @ObservedObject var session: TerminalSession

    var body: some View {
        if session.pwd != nil || session.gitBranch != nil {
            VStack(alignment: .leading, spacing: 2) {
                if let branch = session.gitBranch {
                    Label(branch, systemImage: "arrow.triangle.branch")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                if let shortPwd = session.shortPwd {
                    Label(shortPwd, systemImage: "folder")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
