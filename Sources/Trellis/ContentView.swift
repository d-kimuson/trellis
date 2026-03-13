import SwiftUI

public struct ContentView: View {
    var store: WorkspaceStore
    @ObservedObject var notificationStore: NotificationStore
    @ObservedObject var settings: AppSettings
    @State private var showSidebar = true
    @State private var showNotifications = false
    @State private var showSettings = false
    @State private var sidebarWidth: CGFloat = 200

    public init(
        store: WorkspaceStore,
        notificationStore: NotificationStore,
        settings: AppSettings = AppSettings.shared
    ) {
        self.store = store
        self._notificationStore = ObservedObject(wrappedValue: notificationStore)
        self._settings = ObservedObject(wrappedValue: settings)
    }

    public var body: some View {
        HStack(spacing: 0) {
            // ActivityBar
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

                // Settings gear
                settingsButton

                Spacer()
            }
            .frame(width: 32)
            .background(Color(nsColor: .windowBackgroundColor))
            .simultaneousGesture(TapGesture().onEnded {
                store.deactivateAllAreas()
            })

            // Sidebar — always in tree, animated width to avoid view destruction issues
            SidebarView(store: store, notificationStore: notificationStore)
                .frame(width: showSidebar ? sidebarWidth : 0)
                .clipped()
                .simultaneousGesture(TapGesture().onEnded {
                    store.deactivateAllAreas()
                })

            if showSidebar {
                SidebarResizeHandle(sidebarWidth: $sidebarWidth)
            }

            // Main content
            if let workspace = store.activeWorkspace {
                AreaLayoutView(
                    node: workspace.layout,
                    ghosttyApp: store.ghosttyApp,
                    store: store,
                    notificationStore: notificationStore
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
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            showSettings = true
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: settings) {
                store.ghosttyApp.applySettings(settings)
            }
        }
    }

    // MARK: - Settings Button

    private var settingsButton: some View {
        Image(systemName: "gearshape")
            .font(.system(size: 14))
            .foregroundColor(.secondary)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
            .onTapGesture { showSettings = true }
            .help("Settings")
            .padding(.horizontal, 4)
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
