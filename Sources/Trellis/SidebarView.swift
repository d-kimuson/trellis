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
                // "Pinned" sub-label — always visible, non-interactive
                Label("Pinned", systemImage: "pin.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .selectionDisabled()
                    .moveDisabled(true)
                    .deleteDisabled(true)

                // All workspaces in one ForEach — onMove handles cross-boundary pin/unpin
                ForEach(store.workspaces) { workspace in
                    let globalIndex = store.workspaces.firstIndex(where: { $0.id == workspace.id }) ?? 0
                    let isFirstTemp = !workspace.isPinned &&
                        store.workspaces.first(where: { !$0.isPinned })?.id == workspace.id &&
                        !store.pinnedWorkspaces.isEmpty
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
                        showCloseButton: hoveredIndex == globalIndex,
                        showTopDivider: isFirstTemp,
                        onRename: { newName in store.renameWorkspace(at: globalIndex, to: newName) },
                        onClose: { requestClose(at: globalIndex) },
                        sessionBranch: rep?.gitBranch,
                        sessionShortPwd: rep?.shortPwd
                    )
                    .tag(globalIndex)
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
    let showTopDivider: Bool
    let onRename: (String) -> Void
    let onClose: () -> Void
    var sessionBranch: String? = nil
    var sessionShortPwd: String? = nil

    @State private var editingName: String = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Divider before the first temp workspace
            if showTopDivider {
                Divider()
                    .padding(.bottom, 6)
            }

            VStack(alignment: .leading, spacing: 4) {
                // Title row
                HStack {
                    if workspace.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }

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

                // Session info (branch, cwd) — values come from WorkspaceCardWithSession observer
                if sessionBranch != nil || sessionShortPwd != nil {
                    VStack(alignment: .leading, spacing: 2) {
                        if let branch = sessionBranch {
                            Label(branch, systemImage: "arrow.triangle.branch")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        if let shortPwd = sessionShortPwd {
                            Label(shortPwd, systemImage: "folder")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}
