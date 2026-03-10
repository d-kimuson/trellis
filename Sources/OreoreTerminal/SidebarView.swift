import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: WorkspaceStore
    @State private var renamingIndex: Int?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: Binding<Int?>(
                get: { store.activeWorkspaceIndex },
                set: { index in
                    if let index {
                        store.selectWorkspace(at: index)
                    }
                }
            )) {
                Section("Workspaces") {
                    ForEach(Array(store.workspaces.enumerated()), id: \.element.id) { index, workspace in
                        WorkspaceRow(
                            workspace: workspace,
                            isActive: index == store.activeWorkspaceIndex,
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
                }
            }
            .listStyle(.sidebar)

            Divider()

            // Bottom toolbar
            HStack {
                Button(
                    action: { store.addWorkspace() },
                    label: { Image(systemName: "plus") }
                )
                .buttonStyle(.borderless)
                .help("New Workspace")

                Spacer()
            }
            .padding(8)
        }
    }
}

// MARK: - Workspace Row

private struct WorkspaceRow: View {
    let workspace: Workspace
    let isActive: Bool
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
        }
    }
}
