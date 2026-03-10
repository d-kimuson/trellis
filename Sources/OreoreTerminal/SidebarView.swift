import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: WorkspaceStore

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(Array(store.workspaces.enumerated()), id: \.element.id) { _, workspace in
                    Section(workspace.name) {
                        ForEach(workspace.allAreas) { area in
                            ForEach(area.tabs) { tab in
                                if let session = tab.content.terminalSession {
                                    HStack {
                                        Image(systemName: "terminal")
                                            .foregroundColor(.secondary)
                                        Text(session.title)
                                            .lineLimit(1)
                                    }
                                    .tag(session.id)
                                }
                            }
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
