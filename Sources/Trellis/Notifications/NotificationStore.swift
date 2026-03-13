import Foundation

/// An in-app notification entry tied to a specific terminal panel (session).
public struct AppNotification: Identifiable {
    public let id: UUID
    public let title: String
    public let body: String
    /// The terminal session (panel) that generated this notification.
    public let sessionId: UUID
    /// The workspace name at the time the notification was generated.
    public let workspaceName: String?
    public let timestamp: Date
    public var isRead: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        body: String,
        sessionId: UUID,
        workspaceName: String? = nil,
        timestamp: Date = Date(),
        isRead: Bool = false
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.sessionId = sessionId
        self.workspaceName = workspaceName
        self.timestamp = timestamp
        self.isRead = isRead
    }
}

/// Manages in-app notification state, separate from OS desktop notifications.
@MainActor
@Observable
public final class NotificationStore {
    public var notifications: [AppNotification] = []

    /// Maximum number of notifications to keep.
    private let maxCount = 100

    public init() {}

    // MARK: - Add

    public func add(title: String, body: String, sessionId: UUID, workspaceName: String? = nil) {
        let notification = AppNotification(
            title: title,
            body: body,
            sessionId: sessionId,
            workspaceName: workspaceName
        )
        notifications.insert(notification, at: 0)
        if notifications.count > maxCount {
            notifications.removeLast(notifications.count - maxCount)
        }
    }

    // MARK: - Read State

    /// Mark all notifications for a given session as read.
    public func markAsRead(sessionId: UUID) {
        for index in notifications.indices where notifications[index].sessionId == sessionId {
            notifications[index].isRead = true
        }
    }

    /// Mark all notifications for the given set of sessions as read.
    public func markAsRead(sessionIds: [UUID]) {
        let idSet = Set(sessionIds)
        for index in notifications.indices where idSet.contains(notifications[index].sessionId) {
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

    /// Unread count for a set of session IDs (used to compute workspace-level badge).
    public func unreadCount(forSessionIds sessionIds: [UUID]) -> Int {
        let idSet = Set(sessionIds)
        return notifications.count(where: { !$0.isRead && idSet.contains($0.sessionId) })
    }

    public func unreadCount(forSession sessionId: UUID) -> Int {
        notifications.count(where: { !$0.isRead && $0.sessionId == sessionId })
    }
}
