import Foundation
import XCTest
@testable import Trellis

@MainActor
final class NotificationStoreTests: XCTestCase {

    // MARK: - add

    func testAddNotificationAppendsToFront() {
        let store = NotificationStore()
        let sessionId = UUID()
        store.add(title: "A", body: "body A", sessionId: sessionId)
        store.add(title: "B", body: "body B", sessionId: sessionId)
        XCTAssertEqual(store.notifications.first?.title, "B")
        XCTAssertEqual(store.notifications.last?.title, "A")
    }

    func testAddNotificationSetsCorrectFields() {
        let store = NotificationStore()
        let sessionId = UUID()
        store.add(title: "Test Title", body: "Test Body", sessionId: sessionId, workspaceName: "Dev")
        let n = store.notifications.first
        XCTAssertEqual(n?.title, "Test Title")
        XCTAssertEqual(n?.body, "Test Body")
        XCTAssertEqual(n?.sessionId, sessionId)
        XCTAssertEqual(n?.workspaceName, "Dev")
        XCTAssertFalse(n?.isRead ?? true, "New notifications should be unread")
    }

    func testAddNotificationDefaultsWorkspaceNameToNil() {
        let store = NotificationStore()
        store.add(title: "A", body: "B", sessionId: UUID())
        XCTAssertNil(store.notifications.first?.workspaceName)
    }

    func testAddNotificationDoesNotExceedMaxCount() {
        let store = NotificationStore()
        let sessionId = UUID()
        for i in 0..<110 {
            store.add(title: "Notif \(i)", body: "", sessionId: sessionId)
        }
        XCTAssertLessThanOrEqual(store.notifications.count, 100)
    }

    func testAddAt101DropsOldestEntry() {
        let store = NotificationStore()
        let sessionId = UUID()
        // Add 100 entries: oldest = "Old 0" (last in array), newest = "Old 99" (first)
        for i in 0..<100 {
            store.add(title: "Old \(i)", body: "", sessionId: sessionId)
        }
        // Add one more — "Old 0" (oldest) should be dropped
        store.add(title: "New", body: "", sessionId: sessionId)
        XCTAssertEqual(store.notifications.count, 100)
        XCTAssertEqual(store.notifications.first?.title, "New")
        XCTAssertFalse(store.notifications.map(\.title).contains("Old 0"),
                       "Oldest notification should be evicted when cap is exceeded")
    }

    func testAddExactlyMaxCountDoesNotDrop() {
        let store = NotificationStore()
        let sessionId = UUID()
        for i in 0..<100 {
            store.add(title: "Notif \(i)", body: "", sessionId: sessionId)
        }
        XCTAssertEqual(store.notifications.count, 100)
    }

    // MARK: - markAsRead(sessionId:)

    func testMarkAsReadBySessionIdMarksOnlyThatSession() {
        let store = NotificationStore()
        let id1 = UUID()
        let id2 = UUID()
        store.add(title: "A", body: "", sessionId: id1)
        store.add(title: "B", body: "", sessionId: id1)
        store.add(title: "C", body: "", sessionId: id2)

        store.markAsRead(sessionId: id1)

        XCTAssertTrue(
            store.notifications.filter { $0.sessionId == id1 }.allSatisfy(\.isRead),
            "All notifications for id1 should be read"
        )
        XCTAssertTrue(
            store.notifications.filter { $0.sessionId == id2 }.allSatisfy { !$0.isRead },
            "Notifications for id2 should remain unread"
        )
    }

    func testMarkAsReadBySessionIdOnUnknownIdDoesNothing() {
        let store = NotificationStore()
        let sessionId = UUID()
        store.add(title: "A", body: "", sessionId: sessionId)
        store.markAsRead(sessionId: UUID())
        XCTAssertFalse(store.notifications.first!.isRead)
    }

    // MARK: - markAsRead(sessionIds:)

    func testMarkAsReadBySessionIdsMarksMultipleSessions() {
        let store = NotificationStore()
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()
        store.add(title: "A", body: "", sessionId: id1)
        store.add(title: "B", body: "", sessionId: id2)
        store.add(title: "C", body: "", sessionId: id3)

        store.markAsRead(sessionIds: [id1, id2])

        XCTAssertTrue(store.notifications.filter { $0.sessionId == id1 }.allSatisfy(\.isRead))
        XCTAssertTrue(store.notifications.filter { $0.sessionId == id2 }.allSatisfy(\.isRead))
        XCTAssertTrue(store.notifications.filter { $0.sessionId == id3 }.allSatisfy { !$0.isRead })
    }

    func testMarkAsReadByEmptySessionIdsDoesNothing() {
        let store = NotificationStore()
        let sessionId = UUID()
        store.add(title: "A", body: "", sessionId: sessionId)
        store.markAsRead(sessionIds: [])
        XCTAssertFalse(store.notifications.first!.isRead)
    }

    // MARK: - markAsRead(id:)

    func testMarkAsReadByIdMarksOnlySpecificNotification() {
        let store = NotificationStore()
        let sessionId = UUID()
        store.add(title: "A", body: "", sessionId: sessionId) // ends up at index 1 (last)
        store.add(title: "B", body: "", sessionId: sessionId) // ends up at index 0 (first)

        // Mark "A" (which is last)
        let targetId = store.notifications.last!.id
        store.markAsRead(id: targetId)

        XCTAssertTrue(store.notifications.last!.isRead, "The targeted notification should be read")
        XCTAssertFalse(store.notifications.first!.isRead, "Other notifications should remain unread")
    }

    func testMarkAsReadByUnknownIdDoesNothing() {
        let store = NotificationStore()
        let sessionId = UUID()
        store.add(title: "A", body: "", sessionId: sessionId)
        store.markAsRead(id: UUID())
        XCTAssertFalse(store.notifications.first!.isRead)
    }

    // MARK: - markAllAsRead

    func testMarkAllAsReadMarksEverything() {
        let store = NotificationStore()
        store.add(title: "A", body: "", sessionId: UUID())
        store.add(title: "B", body: "", sessionId: UUID())
        store.add(title: "C", body: "", sessionId: UUID())

        store.markAllAsRead()

        XCTAssertTrue(store.notifications.allSatisfy(\.isRead))
    }

    func testMarkAllAsReadOnEmptyStoreDoesNotCrash() {
        let store = NotificationStore()
        store.markAllAsRead()
        XCTAssertEqual(store.notifications.count, 0)
    }

    func testMarkAllAsReadThenAddCreatesUnreadNotification() {
        let store = NotificationStore()
        store.add(title: "A", body: "", sessionId: UUID())
        store.markAllAsRead()

        store.add(title: "B", body: "", sessionId: UUID())
        XCTAssertFalse(store.notifications.first!.isRead, "Newly added notification should be unread")
    }

    // MARK: - unreadCount (global)

    func testUnreadCountStartsAtZero() {
        let store = NotificationStore()
        XCTAssertEqual(store.unreadCount, 0)
    }

    func testUnreadCountIncrementsOnAdd() {
        let store = NotificationStore()
        store.add(title: "A", body: "", sessionId: UUID())
        XCTAssertEqual(store.unreadCount, 1)
        store.add(title: "B", body: "", sessionId: UUID())
        XCTAssertEqual(store.unreadCount, 2)
    }

    func testUnreadCountDecrementsOnMarkRead() {
        let store = NotificationStore()
        let sessionId = UUID()
        store.add(title: "A", body: "", sessionId: sessionId)
        store.add(title: "B", body: "", sessionId: sessionId)
        store.markAsRead(sessionId: sessionId)
        XCTAssertEqual(store.unreadCount, 0)
    }

    func testUnreadCountReflectsPartialRead() {
        let store = NotificationStore()
        let id1 = UUID()
        let id2 = UUID()
        store.add(title: "A", body: "", sessionId: id1)
        store.add(title: "B", body: "", sessionId: id2)
        store.markAsRead(sessionId: id1)
        XCTAssertEqual(store.unreadCount, 1)
    }

    // MARK: - unreadCount(forSessionIds:)

    func testUnreadCountForSessionIdsCountsCorrectly() {
        let store = NotificationStore()
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()
        store.add(title: "A", body: "", sessionId: id1)
        store.add(title: "B", body: "", sessionId: id2)
        store.add(title: "C", body: "", sessionId: id3)

        XCTAssertEqual(store.unreadCount(forSessionIds: [id1, id2]), 2)
    }

    func testUnreadCountForSessionIdsExcludesReadNotifications() {
        let store = NotificationStore()
        let id1 = UUID()
        let id2 = UUID()
        store.add(title: "A", body: "", sessionId: id1)
        store.add(title: "B", body: "", sessionId: id2)
        store.markAsRead(sessionId: id1)

        XCTAssertEqual(store.unreadCount(forSessionIds: [id1, id2]), 1)
    }

    func testUnreadCountForSessionIdsWithEmptyArrayReturnsZero() {
        let store = NotificationStore()
        store.add(title: "A", body: "", sessionId: UUID())
        XCTAssertEqual(store.unreadCount(forSessionIds: []), 0)
    }

    func testUnreadCountForSessionIdsExcludesOtherSessions() {
        let store = NotificationStore()
        let queried = UUID()
        let other = UUID()
        store.add(title: "A", body: "", sessionId: other)
        XCTAssertEqual(store.unreadCount(forSessionIds: [queried]), 0)
    }

    // MARK: - unreadCount(forSession:)

    func testUnreadCountForSessionCountsOnlyThatSession() {
        let store = NotificationStore()
        let id1 = UUID()
        let id2 = UUID()
        store.add(title: "A", body: "", sessionId: id1)
        store.add(title: "B", body: "", sessionId: id1)
        store.add(title: "C", body: "", sessionId: id2)

        XCTAssertEqual(store.unreadCount(forSession: id1), 2)
        XCTAssertEqual(store.unreadCount(forSession: id2), 1)
    }

    func testUnreadCountForSessionAfterMarkRead() {
        let store = NotificationStore()
        let sessionId = UUID()
        store.add(title: "A", body: "", sessionId: sessionId)
        store.markAsRead(sessionId: sessionId)
        XCTAssertEqual(store.unreadCount(forSession: sessionId), 0)
    }

    func testUnreadCountForUnknownSessionReturnsZero() {
        let store = NotificationStore()
        XCTAssertEqual(store.unreadCount(forSession: UUID()), 0)
    }

    // MARK: - Notification identity

    func testEachAddedNotificationHasUniqueId() {
        let store = NotificationStore()
        let sessionId = UUID()
        for _ in 0..<5 {
            store.add(title: "T", body: "B", sessionId: sessionId)
        }
        let ids = store.notifications.map(\.id)
        XCTAssertEqual(Set(ids).count, 5, "Each notification should have a unique ID")
    }
}
