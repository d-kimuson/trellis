import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: WorkspaceStore

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
                            onRename: { newName in
                                store.renameWorkspace(at: index, to: newName)
                            }
                        )
                        .tag(index)
                        .contextMenu {
                            Button("Rename") {
                                // Rename is handled by double-click inline editing
                                // This is a placeholder for discoverability
                            }
                            Button("Delete", role: .destructive) {
                                store.removeWorkspace(at: index)
                            }
                            .disabled(store.workspaces.count <= 1)
                        }
                    }
                }

                if let workspace = store.activeWorkspace {
                    Section("Areas & Tabs") {
                        ForEach(workspace.allAreas) { area in
                            AreaSidebarRow(area: area, isActiveArea: area.id == workspace.activeAreaId)
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            // Bottom toolbar
            HStack {
                Button(
                    action: {
                        if let workspace = store.activeWorkspace,
                           let areaId = workspace.activeAreaId {
                            store.addTab(to: areaId)
                        }
                    },
                    label: { Image(systemName: "plus") }
                )
                .buttonStyle(.borderless)
                .help("New Terminal Tab")

                Button(
                    action: { store.addWorkspace() },
                    label: { Image(systemName: "square.grid.2x2") }
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
    let onRename: (String) -> Void

    @State private var isEditing = false
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
            } else {
                Text(workspace.name)
                    .lineLimit(1)
                    .fontWeight(isActive ? .semibold : .regular)
                    .onTapGesture(count: 2) {
                        editingName = workspace.name
                        isEditing = true
                    }
            }
        }
    }
}

// MARK: - Area Sidebar Row

private struct AreaSidebarRow: View {
    let area: Area
    let isActiveArea: Bool

    var body: some View {
        DisclosureGroup {
            ForEach(area.tabs) { tab in
                if let session = tab.content.terminalSession {
                    HStack {
                        Image(systemName: "terminal")
                            .foregroundColor(.secondary)
                        Text(session.title)
                            .lineLimit(1)
                    }
                }
            }
        } label: {
            HStack {
                Image(systemName: "rectangle")
                    .foregroundColor(isActiveArea ? .accentColor : .secondary)
                Text("Area (\(area.tabs.count) tab\(area.tabs.count == 1 ? "" : "s"))")
                    .lineLimit(1)
                    .fontWeight(isActiveArea ? .semibold : .regular)
            }
        }
    }
}
