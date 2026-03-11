import Foundation
import XCTest
@testable import Trellis

/// Tests for WorkspaceStore pin/unpin, notification integration,
/// session ID queries, and active area maintenance edge cases.
final class WorkspacePinTests: XCTestCase {

    private func makeStore() -> WorkspaceStore {
        WorkspaceStore(ghosttyApp: GhosttyAppWrapper(), loadSnapshots: false)
    }

    // MARK: - Pin / Unpin Sort Order

    func testPinWorkspaceMovesPinnedBeforeTemp() {
        let store = makeStore()
        // ws[0] is the initial workspace (unpinned)
        store.addWorkspace() // ws[1]
        store.addWorkspace() // ws[2]

        let targetId = store.workspaces[1].id
        store.pinWorkspace(id: targetId)

        // Pinned workspace should now appear first
        XCTAssertTrue(store.workspaces[0].isPinned)
        XCTAssertEqual(store.workspaces[0].id, targetId)
    }

    func testPinWorkspacePreservesActiveWorkspace() {
        let store = makeStore()
        store.addWorkspace() // ws[1]
        let activeId = store.workspaces[store.activeWorkspaceIndex].id

        // Pin workspace[0] — triggers re-sort
        store.pinWorkspace(id: store.workspaces[0].id)

        XCTAssertEqual(store.workspaces[store.activeWorkspaceIndex].id, activeId,
                       "Active workspace ID should remain the same after pin + re-sort")
    }

    func testUnpinWorkspaceMovesTempAfterPinned() {
        let store = makeStore()
        // Pin the initial workspace
        let pinnedId = store.workspaces[0].id
        store.pinWorkspace(id: pinnedId)
        store.addWorkspace() // unpinned

        XCTAssertTrue(store.workspaces[0].isPinned)

        store.unpinWorkspace(id: pinnedId)

        // After unpin, no workspaces should be pinned (they all fall into temp section)
        XCTAssertFalse(store.workspaces.allSatisfy(\.isPinned))
        XCTAssertFalse(store.workspaces.first(where: { $0.id == pinnedId })?.isPinned ?? true,
                       "Unpinned workspace should have isPinned = false")
    }

    func testUnpinWorkspacePreservesActiveWorkspace() {
        let store = makeStore()
        let pinnedId = store.workspaces[0].id
        store.pinWorkspace(id: pinnedId)
        store.addWorkspace()
        let activeId = store.workspaces[store.activeWorkspaceIndex].id

        store.unpinWorkspace(id: pinnedId)

        XCTAssertEqual(store.workspaces[store.activeWorkspaceIndex].id, activeId,
                       "Active workspace ID should remain the same after unpin + re-sort")
    }

    func testPinnedWorkspacesProperty() {
        let store = makeStore()
        store.addWorkspace()
        let id0 = store.workspaces[0].id
        let id1 = store.workspaces[1].id
        store.pinWorkspace(id: id0)
        store.pinWorkspace(id: id1)

        XCTAssertEqual(store.pinnedWorkspaces.count, 2)
        XCTAssertTrue(store.pinnedWorkspaces.allSatisfy(\.isPinned))
    }

    func testTempWorkspacesProperty() {
        let store = makeStore()
        store.addWorkspace()

        // Neither is pinned by default
        XCTAssertEqual(store.tempWorkspaces.count, 2)
        XCTAssertTrue(store.tempWorkspaces.allSatisfy { !$0.isPinned })
    }

    // MARK: - sessionIds(forWorkspace:)

    func testSessionIdsForWorkspaceReturnsTerminalSessionIds() {
        let store = makeStore()
        guard let areaId = store.activeWorkspace?.activeAreaId else {
            XCTFail("Expected active area")
            return
        }
        store.addTerminalTab(to: areaId)
        store.addTerminalTab(to: areaId)

        let ids = store.sessionIds(forWorkspace: 0)
        XCTAssertEqual(ids.count, 2)
    }

    func testSessionIdsForWorkspaceExcludesBrowserTabs() {
        let store = makeStore()
        guard let areaId = store.activeWorkspace?.activeAreaId else {
            XCTFail("Expected active area")
            return
        }
        store.addBrowserTab(to: areaId)

        // Browser tabs don't have terminal sessions
        let ids = store.sessionIds(forWorkspace: 0)
        XCTAssertEqual(ids.count, 0)
    }

    func testSessionIdsForOutOfRangeIndexReturnsEmpty() {
        let store = makeStore()
        XCTAssertEqual(store.sessionIds(forWorkspace: 99), [])
    }

    func testSessionIdsForWorkspaceAcrossMultipleAreas() {
        let store = makeStore()
        guard let areaId = store.activeWorkspace?.activeAreaId else {
            XCTFail("Expected active area")
            return
        }
        store.addTerminalTab(to: areaId)
        store.splitArea(areaId: areaId, direction: .vertical) // adds 1 tab in new area

        // areaId has 1 tab, new area has 1 tab from split → 2 sessions total
        let ids = store.sessionIds(forWorkspace: 0)
        XCTAssertEqual(ids.count, 2)
    }

    // MARK: - Notification Integration: focusSession marks as read

    func testFocusSessionMarksNotificationsAsRead() {
        let store = makeStore()
        let notifStore = NotificationStore()
        store.notificationStore = notifStore

        guard let areaId = store.activeWorkspace?.activeAreaId else {
            XCTFail("Expected active area")
            return
        }
        store.addTerminalTab(to: areaId)
        let area = store.activeWorkspace!.layout.findArea(id: areaId)!
        let session = area.tabs[0].content.terminalSession!

        // Add unread notifications for that session
        notifStore.add(title: "Alert", body: "", sessionId: session.id)
        notifStore.add(title: "Alert 2", body: "", sessionId: session.id)
        XCTAssertEqual(notifStore.unreadCount, 2)

        store.focusSession(id: session.id)

        XCTAssertEqual(notifStore.unreadCount, 0, "focusSession should mark all session notifications as read")
    }

    // MARK: - Notification Integration: activateArea marks as read

    func testActivateAreaMarksNotificationsForAllTabsAsRead() {
        let store = makeStore()
        let notifStore = NotificationStore()
        store.notificationStore = notifStore

        guard let areaId = store.activeWorkspace?.activeAreaId else {
            XCTFail("Expected active area")
            return
        }
        store.addTerminalTab(to: areaId)
        store.addTerminalTab(to: areaId)

        let area = store.activeWorkspace!.layout.findArea(id: areaId)!
        let sessionIds = area.tabs.compactMap { $0.content.terminalSession?.id }
        for id in sessionIds {
            notifStore.add(title: "Notif", body: "", sessionId: id)
        }
        XCTAssertEqual(notifStore.unreadCount, 2)

        // Deactivate by splitting (so activateArea triggers the update)
        store.splitArea(areaId: areaId, direction: .vertical)
        // Now activate the original area
        store.activateArea(areaId)

        XCTAssertEqual(
            notifStore.unreadCount(forSessionIds: sessionIds), 0,
            "activateArea should mark all notifications for sessions in that area as read"
        )
    }

    // MARK: - activeAreaId maintenance: moveTabToNewArea always focuses new area

    func testMoveTabToNewAreaAlwaysFocusesNewArea() {
        let store = makeStore()
        guard let area1Id = store.activeWorkspace?.activeAreaId else {
            XCTFail("Expected active area")
            return
        }
        // Add two tabs so area1 survives losing one
        store.addTab(to: area1Id)
        store.addTab(to: area1Id)

        // Create area2 via split
        store.splitArea(areaId: area1Id, direction: .vertical)
        let areas = store.activeWorkspace!.allAreas
        let area2 = areas.first(where: { $0.id != area1Id })!

        let tabToMove = store.activeWorkspace!.layout.findArea(id: area1Id)!.tabs[0]
        store.moveTabToNewArea(
            tabId: tabToMove.id,
            from: area1Id,
            adjacentTo: area2.id,
            direction: .horizontal
        )

        let allAreas = store.activeWorkspace!.allAreas
        let newArea = allAreas.first(where: { $0.id != area1Id && $0.id != area2.id })!

        XCTAssertEqual(
            store.activeWorkspace?.activeAreaId, newArea.id,
            "After moveTabToNewArea, activeAreaId should point to the newly created area"
        )
    }

    // MARK: - activeAreaId maintenance: moveTab from active area to another

    func testMoveLastTabFromActiveAreaUpdatesActiveAreaId() {
        let store = makeStore()
        guard let area1Id = store.activeWorkspace?.activeAreaId else {
            XCTFail("Expected active area")
            return
        }
        store.addTab(to: area1Id)

        // Create area2 — this becomes active
        store.splitArea(areaId: area1Id, direction: .vertical)
        let area2Id = store.activeWorkspace!.activeAreaId!

        // Switch back to area1 and move its only tab to area2
        store.activateArea(area1Id)
        let tab = store.activeWorkspace!.layout.findArea(id: area1Id)!.tabs[0]
        store.moveTab(tabId: tab.id, from: area1Id, to: area2Id, at: 0)

        // area1 was source and became empty → removed
        XCTAssertNil(store.activeWorkspace?.layout.findArea(id: area1Id))

        // activeAreaId should have been updated (not pointing to removed area1)
        XCTAssertNotEqual(store.activeWorkspace?.activeAreaId, area1Id,
                          "activeAreaId must not reference a removed area")
    }

    // MARK: - moveWorkspaceCrossBoundary

    func testMoveCrossBoundaryFromTempToPinnedSection() {
        let store = makeStore()
        store.addWorkspace() // ws[1], unpinned

        // Pin ws[0] so there's a pinned section
        let pinnedId = store.workspaces[0].id
        store.pinWorkspace(id: pinnedId) // after sort: [pinned=ws0, temp=ws1]
        XCTAssertEqual(store.pinnedWorkspaces.count, 1)

        // Move ws[1] (temp, at global index 1) to position 0 (into pinned zone)
        store.moveWorkspaceCrossBoundary(fromOffsets: IndexSet([1]), toOffset: 0)

        // Now both should be pinned (the moved one crossed into the pinned zone)
        // Depending on boundary calculation, at least the moved ws1 should be pinned
        let movedWs = store.workspaces.first(where: { !$0.isPinned && $0.id != pinnedId })
        // movedWs should now be pinned (it crossed into index < originalPinnedCount=1)
        XCTAssertNil(movedWs, "Workspace moved into pinned zone should become pinned")
    }
}
