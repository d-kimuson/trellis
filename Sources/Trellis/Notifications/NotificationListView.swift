import SwiftUI

/// Popover content showing the list of in-app notifications.
struct NotificationListView: View {
    var notificationStore: NotificationStore
    var store: WorkspaceStore
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if notificationStore.notifications.isEmpty {
                emptyState
            } else {
                notificationList
            }
        }
        .frame(width: 320, height: 400)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Notifications")
                .font(.headline)
            Spacer()
            if notificationStore.unreadCount > 0 {
                Button("Mark All Read") {
                    notificationStore.markAllAsRead()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bell.slash")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("No notifications")
                .foregroundColor(.secondary)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - List

    private var notificationList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(notificationStore.notifications) { notification in
                    NotificationRow(notification: notification) {
                        store.focusSession(id: notification.sessionId)
                        isPresented = false
                    }
                    Divider()
                }
            }
        }
    }
}

// MARK: - Row

private struct NotificationRow: View {
    let notification: AppNotification
    let onTap: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Unread indicator
            Circle()
                .fill(notification.isRead ? Color.clear : Color.accentColor)
                .frame(width: 8, height: 8)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(notification.title)
                        .font(.caption)
                        .fontWeight(notification.isRead ? .regular : .semibold)
                    if let workspaceName = notification.workspaceName {
                        Text(workspaceName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(3)
                    }
                }
                Text(notification.body)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                Text(notification.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.6))
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .background(notification.isRead ? Color.clear : Color.accentColor.opacity(0.05))
    }
}
