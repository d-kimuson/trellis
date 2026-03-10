import SwiftUI

public struct ContentView: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var notificationStore: NotificationStore
    @State private var showSidebar = true
    @State private var showNotifications = false
    @State private var sidebarWidth: CGFloat = 200

    public init(store: WorkspaceStore, notificationStore: NotificationStore) {
        self._store = ObservedObject(wrappedValue: store)
        self._notificationStore = ObservedObject(wrappedValue: notificationStore)
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

                // Notification bell
                notificationBell

                Spacer()
            }
            .frame(width: 32)
            .background(Color(nsColor: .windowBackgroundColor))

            // Sidebar — always in tree, animated width to avoid view destruction issues
            SidebarView(store: store, notificationStore: notificationStore)
                .frame(width: showSidebar ? sidebarWidth : 0)
                .clipped()

            if showSidebar {
                SidebarResizeHandle(sidebarWidth: $sidebarWidth)
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

    // MARK: - Notification Bell

    private var notificationBell: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: notificationStore.unreadCount > 0 ? "bell.badge.fill" : "bell")
                .font(.system(size: 14))
                .foregroundColor(notificationStore.unreadCount > 0 ? .accentColor : .secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .onTapGesture { showNotifications.toggle() }
                .help("Notifications")

            if notificationStore.unreadCount > 0 {
                Text("\(notificationStore.unreadCount)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 3)
                    .background(Capsule().fill(Color.red))
                    .offset(x: 4, y: -2)
            }
        }
        .popover(isPresented: $showNotifications, arrowEdge: .trailing) {
            NotificationListView(
                notificationStore: notificationStore,
                store: store,
                isPresented: $showNotifications
            )
        }
    }
}
