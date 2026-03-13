import SwiftUI

struct SidebarView: View {
    var store: WorkspaceStore
    var notificationStore: NotificationStore
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
            // Pinned section — only shown when there are pinned workspaces
            if !store.pinnedWorkspaces.isEmpty {
                Section {
                    ForEach(store.pinnedWorkspaces) { workspace in
                        workspaceRow(workspace: workspace)
                    }
                    .onMove { from, to in store.movePinnedWorkspace(fromOffsets: from, toOffset: to) }
                } header: {
                    sectionHeader("Pinned", pinned: true)
                }
                .collapsible(false)
            }

            // Temporary workspaces section — always shown so the "+" button is reachable
            Section {
                ForEach(store.tempWorkspaces) { workspace in
                    workspaceRow(workspace: workspace)
                }
                .onMove { from, to in store.moveTempWorkspace(fromOffsets: from, toOffset: to) }
            } header: {
                sectionHeader("Workspaces")
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

    @ViewBuilder
    private func workspaceRow(workspace: Workspace) -> some View {
        let globalIndex = store.workspaces.firstIndex(where: { $0.id == workspace.id }) ?? 0
        let rep = workspace.representativeSession
        WorkspaceCard(
            workspace: workspace,
            isActive: globalIndex == store.activeWorkspaceIndex,
            unreadCount: notificationStore.unreadCount(
                forSessionIds: store.sessionIds(forWorkspace: globalIndex)
            ),
            isEditing: Binding(
                get: { renamingIndex == globalIndex },
                set: { editing in renamingIndex = editing ? globalIndex : nil }
            ),
            showActionButtons: hoveredIndex == globalIndex,
            onRename: { newName in store.renameWorkspace(at: globalIndex, to: newName) },
            onClose: { requestClose(at: globalIndex) },
            onTogglePin: {
                if workspace.isPinned {
                    store.unpinWorkspace(id: workspace.id)
                } else {
                    store.pinWorkspace(id: workspace.id)
                }
            },
            sessionBranch: rep?.gitBranch,
            sessionShortPwd: rep?.shortPwd
        )
        .tag(globalIndex)
        .listRowSeparator(.hidden)
        .padding(.vertical, 2)
        .onHover { hoveredIndex = $0 ? globalIndex : nil }
        .contextMenu {
            Button("Rename") { renamingIndex = globalIndex }
            Divider()
            if workspace.isPinned {
                Button("Unpin") { store.unpinWorkspace(id: workspace.id) }
            } else {
                Button("Pin") { store.pinWorkspace(id: workspace.id) }
            }
        }
    }

    private func sectionHeader(_ title: String, pinned: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .textCase(nil)
            Spacer()
            Button(action: {
                store.addWorkspace()
                if pinned {
                    let newId = store.workspaces.last!.id
                    store.pinWorkspace(id: newId)
                }
            }) {
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
    let showActionButtons: Bool
    let onRename: (String) -> Void
    let onClose: () -> Void
    let onTogglePin: () -> Void
    var sessionBranch: String? = nil
    var sessionShortPwd: String? = nil

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

                if showActionButtons {
                    // Pin / unpin toggle
                    Image(systemName: workspace.isPinned ? "pin.slash" : "pin")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.primary.opacity(0.08))
                        )
                        .help(workspace.isPinned ? "Unpin" : "Pin")
                        .onTapGesture { onTogglePin() }

                    // Close button
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.primary.opacity(0.08))
                        )
                        .onTapGesture { onClose() }
                }
            }
            .padding(.vertical, 4)

            // Session info (branch, cwd)
            if sessionBranch != nil || sessionShortPwd != nil {
                VStack(alignment: .leading, spacing: 2) {
                    if let branch = sessionBranch {
                        Label(branch, systemImage: "arrow.triangle.branch")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    if let shortPwd = sessionShortPwd {
                        Label(shortPwd, systemImage: "folder")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .inset(by: -4)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}
