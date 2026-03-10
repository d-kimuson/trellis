import SwiftUI

public struct ContentView: View {
    @ObservedObject var store: WorkspaceStore

    public init(store: WorkspaceStore) {
        self._store = ObservedObject(wrappedValue: store)
    }

    public var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .frame(minWidth: 160, idealWidth: 200)
        } detail: {
            if let workspace = store.activeWorkspace {
                AreaLayoutView(
                    node: workspace.layout,
                    ghosttyApp: store.ghosttyApp,
                    store: store
                )
            } else {
                Text("No workspace")
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 800, minHeight: 500)
    }
}
