import SwiftUI

public struct ContentView: View {
    @ObservedObject var store: WorkspaceStore
    @State private var showSidebar = true
    private let sidebarWidth: CGFloat = 200

    public init(store: WorkspaceStore) {
        self._store = ObservedObject(wrappedValue: store)
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Sidebar toggle button (fixed position)
            VStack {
                Button(
                    action: { withAnimation(.easeInOut(duration: 0.2)) { showSidebar.toggle() } },
                    label: {
                        Image(systemName: "sidebar.leading")
                            .font(.system(size: 14))
                    }
                )
                .buttonStyle(.borderless)
                .padding(8)

                Spacer()
            }
            .frame(width: 32)
            .background(Color(nsColor: .windowBackgroundColor))

            if showSidebar {
                SidebarView(store: store)
                    .frame(width: sidebarWidth)
                    .transition(.move(edge: .leading))

                Divider()
            }

            // Main content
            if let workspace = store.activeWorkspace {
                AreaLayoutView(
                    node: workspace.layout,
                    ghosttyApp: store.ghosttyApp,
                    store: store
                )
            } else {
                Text("No workspace")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 800, minHeight: 500)
    }
}
