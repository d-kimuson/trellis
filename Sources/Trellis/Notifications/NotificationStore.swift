import Foundation

/// An in-app notification entry.
public struct AppNotification: Identifiable {
    public let id: UUID
    public let title: String
    public let body: String
    public let workspaceIndex: Int
    public let areaId: UUID
    public let timestamp: Date
    public var isRead: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        body: String,
        workspaceIndex: Int,
        areaId: UUID,
        timestamp: Date = Date(),
        isRead: Bool = false
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.workspaceIndex = workspaceIndex
        self.areaId = areaId
        self.timestamp = timestamp
        self.isRead = isRead
    }
}

/// Manages in-app notification state, separate from OS desktop notifications.
public final class NotificationStore: ObservableObject {
    @Published public var notifications: [AppNotification] = []

    /// Maximum number of notifications to keep.
    private let maxCount = 100

    public init() {}

    // MARK: - Add

    public func add(title: String, body: String, workspaceIndex: Int, areaId: UUID) {
        let notification = AppNotification(
            title: title,
            body: body,
            workspaceIndex: workspaceIndex,
            areaId: areaId
        )
        notifications.insert(notification, at: 0)
        if notifications.count > maxCount {
            notifications.removeLast(notifications.count - maxCount)
        }
    }

    // MARK: - Read State

    /// Mark all notifications for a given area as read.
    public func markAsRead(areaId: UUID) {
        for index in notifications.indices where notifications[index].areaId == areaId {
            notifications[index].isRead = true
        }
    }

    /// Mark a single notification as read.
    public func markAsRead(id: UUID) {
        guard let index = notifications.firstIndex(where: { $0.id == id }) else { return }
        notifications[index].isRead = true
    }

    public func markAllAsRead() {
        for index in notifications.indices {
            notifications[index].isRead = true
        }
    }

    // MARK: - Queries

    public var unreadCount: Int {
        notifications.count(where: { !$0.isRead })
    }

    public func unreadCount(forWorkspace index: Int) -> Int {
        notifications.count(where: { !$0.isRead && $0.workspaceIndex == index })
    }

    public func unreadCount(forArea areaId: UUID) -> Int {
        notifications.count(where: { !$0.isRead && $0.areaId == areaId })
    }
}
