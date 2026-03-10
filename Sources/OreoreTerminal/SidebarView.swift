import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var notificationStore: NotificationStore
    @State private var renamingIndex: Int?

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
                    WorkspaceRow(
                        workspace: workspace,
                        isActive: index == store.activeWorkspaceIndex,
                        unreadCount: notificationStore.unreadCount(forWorkspace: index),
                        isEditing: Binding(
                            get: { renamingIndex == index },
                            set: { editing in
                                renamingIndex = editing ? index : nil
                            }
                        ),
                        onRename: { newName in
                            store.renameWorkspace(at: index, to: newName)
                        }
                    )
                    .tag(index)
                    .contextMenu {
                        Button("Rename") {
                            renamingIndex = index
                        }
                        Button("Delete", role: .destructive) {
                            store.removeWorkspace(at: index)
                        }
                        .disabled(store.workspaces.count <= 1)
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
    }
}

// MARK: - Workspace Row

private struct WorkspaceRow: View {
    let workspace: Workspace
    let isActive: Bool
    let unreadCount: Int
    @Binding var isEditing: Bool
    let onRename: (String) -> Void

    @State private var editingName: String = ""

    var body: some View {
        HStack {
            Image(systemName: "square.grid.2x2")
                .foregroundColor(isActive ? .accentColor : .secondary)

            if isEditing {
                TextField("Workspace name", text: $editingName, onCommit: {
                    let trimmed = editingName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        onRename(trimmed)
                    }
                    isEditing = false
                })
                .textFieldStyle(.plain)
                .onExitCommand {
                    isEditing = false
                }
                .onAppear {
                    editingName = workspace.name
                }
            } else {
                Text(workspace.name)
                    .lineLimit(1)
                    .fontWeight(isActive ? .semibold : .regular)
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
        }
    }
}
