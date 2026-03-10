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
            // Sidebar toggle column
            VStack {
                Spacer().frame(height: 8)
                Image(systemName: "sidebar.leading")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) { showSidebar.toggle() }
                    }
                    .help("Toggle Sidebar")
                    .padding(.horizontal, 4)

                Spacer()
            }
            .frame(width: 32)
            .background(Color(nsColor: .windowBackgroundColor))

            // Sidebar — always in tree, animated width to avoid view destruction issues
            SidebarView(store: store)
                .frame(width: showSidebar ? sidebarWidth : 0)
                .clipped()

            if showSidebar {
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
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { showSidebar.toggle() }
        }
    }
}
