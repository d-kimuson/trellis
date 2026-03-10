import Foundation
import XCTest
@testable import OreoreTerminal

final class WorkspaceStoreTests: XCTestCase {

    private func makeStore() -> WorkspaceStore {
        let ghosttyApp = GhosttyAppWrapper()
        return WorkspaceStore(ghosttyApp: ghosttyApp)
    }

    // MARK: - Initial State

    func testInitialStateHasOneWorkspace() {
        let store = makeStore()
        XCTAssertEqual(store.workspaces.count, 1)
        XCTAssertEqual(store.activeWorkspaceIndex, 0)
    }

    func testInitialWorkspaceHasOneEmptyArea() {
        let store = makeStore()
        guard let workspace = store.activeWorkspace else {
            XCTFail("Expected active workspace")
            return
        }
        let areas = workspace.allAreas
        XCTAssertEqual(areas.count, 1)
        XCTAssertEqual(areas.first?.tabs.count, 0)
        XCTAssertNil(areas.first?.activeTab)
    }

    // MARK: - Workspace Operations

    func testAddWorkspaceIncreasesCount() {
        let store = makeStore()
        store.addWorkspace()
        XCTAssertEqual(store.workspaces.count, 2)
        XCTAssertEqual(store.activeWorkspaceIndex, 1)
    }

    func testSelectWorkspaceChangesActiveIndex() {
        let store = makeStore()
        store.addWorkspace()
        store.selectWorkspace(at: 0)
        XCTAssertEqual(store.activeWorkspaceIndex, 0)
    }

    func testSelectWorkspaceOutOfRangeIsNoOp() {
        let store = makeStore()
        store.selectWorkspace(at: 5)
        XCTAssertEqual(store.activeWorkspaceIndex, 0)
    }

    // MARK: - Area Operations

    func testSplitAreaCreatesNewArea() {
        let store = makeStore()
        guard let areaId = store.activeWorkspace?.activeAreaId else {
            XCTFail("Expected active area")
            return
        }

        store.splitArea(areaId: areaId, direction: .vertical)

        let areas = store.activeWorkspace?.allAreas ?? []
        XCTAssertEqual(areas.count, 2)
    }

    func testCloseAreaWhenMultipleAreasRemovesOne() {
        let store = makeStore()
        guard let areaId = store.activeWorkspace?.activeAreaId else {
            XCTFail("Expected active area")
            return
        }

        store.splitArea(areaId: areaId, direction: .vertical)
        let areasBeforeClose = store.activeWorkspace?.allAreas ?? []
        XCTAssertEqual(areasBeforeClose.count, 2)

        // Close the original area
        store.closeArea(areaId: areaId)
        let areasAfterClose = store.activeWorkspace?.allAreas ?? []
        XCTAssertEqual(areasAfterClose.count, 1)
    }

    func testCloseLastAreaCreatesNewOne() {
        let store = makeStore()
        guard let areaId = store.activeWorkspace?.activeAreaId else {
            XCTFail("Expected active area")
            return
        }

        store.closeArea(areaId: areaId)

        // Should still have one area (recreated)
        let areas = store.activeWorkspace?.allAreas ?? []
        XCTAssertEqual(areas.count, 1)
        // But it should be a different area
        XCTAssertNotEqual(areas.first?.id, areaId)
    }

    // MARK: - Tab Operations

    func testAddTabIncreasesTabCount() {
        let store = makeStore()
        guard let areaId = store.activeWorkspace?.activeAreaId else {
            XCTFail("Expected active area")
            return
        }

        store.addTab(to: areaId)

        let area = store.activeWorkspace?.layout.findArea(id: areaId)
        XCTAssertEqual(area?.tabs.count, 1)
        XCTAssertEqual(area?.activeTabIndex, 0)
    }

    func testCloseTabRemovesTab() {
        let store = makeStore()
        guard let areaId = store.activeWorkspace?.activeAreaId else {
            XCTFail("Expected active area")
            return
        }

        store.addTab(to: areaId)
        store.addTab(to: areaId)
        store.closeTab(in: areaId, at: 0)

        let area = store.activeWorkspace?.layout.findArea(id: areaId)
        XCTAssertEqual(area?.tabs.count, 1)
    }

    func testCloseLastTabClosesArea() {
        let store = makeStore()
        guard let areaId = store.activeWorkspace?.activeAreaId else {
            XCTFail("Expected active area")
            return
        }

        store.addTab(to: areaId)
        // Add a split first so closing the area doesn't recreate
        store.splitArea(areaId: areaId, direction: .vertical)
        store.closeTab(in: areaId, at: 0)

        // The original area should be gone
        let area = store.activeWorkspace?.layout.findArea(id: areaId)
        XCTAssertNil(area)
        XCTAssertEqual(store.activeWorkspace?.allAreas.count, 1)
    }

    func testSelectTabChangesActiveTab() {
        let store = makeStore()
        guard let areaId = store.activeWorkspace?.activeAreaId else {
            XCTFail("Expected active area")
            return
        }

        store.addTab(to: areaId)
        store.addTab(to: areaId)
        store.selectTab(in: areaId, at: 0)

        let area = store.activeWorkspace?.layout.findArea(id: areaId)
        XCTAssertEqual(area?.activeTabIndex, 0)
    }

    // MARK: - Ratio

    func testUpdateRatioChangesLayout() {
        let store = makeStore()
        guard let areaId = store.activeWorkspace?.activeAreaId else {
            XCTFail("Expected active area")
            return
        }

        store.splitArea(areaId: areaId, direction: .vertical)

        guard case .split(let splitId, _, _, _, _) = store.activeWorkspace?.layout else {
            XCTFail("Expected split layout")
            return
        }

        store.updateRatio(splitId: splitId, ratio: 0.3)

        guard case .split(_, _, _, _, let ratio) = store.activeWorkspace?.layout else {
            XCTFail("Expected split layout")
            return
        }
        XCTAssertEqual(ratio, 0.3)
    }

    // MARK: - Rename Workspace

    func testRenameWorkspaceChangesName() {
        let store = makeStore()
        store.renameWorkspace(at: 0, to: "My Workspace")
        XCTAssertEqual(store.workspaces[0].name, "My Workspace")
    }

    func testRenameWorkspaceOutOfRangeIsNoOp() {
        let store = makeStore()
        store.renameWorkspace(at: 5, to: "Nope")
        XCTAssertEqual(store.workspaces[0].name, "Workspace 1")
    }

    // MARK: - Remove Workspace

    func testRemoveWorkspaceRemovesIt() {
        let store = makeStore()
        store.addWorkspace()
        XCTAssertEqual(store.workspaces.count, 2)

        store.removeWorkspace(at: 0)
        XCTAssertEqual(store.workspaces.count, 1)
    }

    func testRemoveLastWorkspaceIsNoOp() {
        let store = makeStore()
        store.removeWorkspace(at: 0)
        XCTAssertEqual(store.workspaces.count, 1)
    }

    func testRemoveWorkspaceAdjustsActiveIndex() {
        let store = makeStore()
        store.addWorkspace()
        store.addWorkspace()
        // Active is now 2 (last one)
        store.selectWorkspace(at: 1)
        // Active is now 1
        store.removeWorkspace(at: 0)
        // After removing index 0, active should adjust to 0
        XCTAssertEqual(store.activeWorkspaceIndex, 0)
        XCTAssertEqual(store.workspaces.count, 2)
    }

    func testRemoveActiveWorkspaceSetsActiveToValidIndex() {
        let store = makeStore()
        store.addWorkspace()
        store.addWorkspace()
        store.selectWorkspace(at: 2)
        store.removeWorkspace(at: 2)
        // Active was 2, removed it, should clamp to 1
        XCTAssertEqual(store.activeWorkspaceIndex, 1)
    }

    // MARK: - Split / Close Active Area

    func testSplitActiveAreaSplitsCurrentArea() {
        let store = makeStore()
        let originalAreaId = store.activeWorkspace?.activeAreaId

        store.splitActiveArea(direction: .horizontal)

        let areas = store.activeWorkspace?.allAreas ?? []
        XCTAssertEqual(areas.count, 2)
        // Active area should be the new one (not original)
        XCTAssertNotEqual(store.activeWorkspace?.activeAreaId, originalAreaId)
    }

    func testSplitActiveAreaWithNoActiveAreaIsNoOp() {
        let store = makeStore()
        // Force invalid state
        store.workspaces = []
        store.splitActiveArea(direction: .vertical)
        // No crash = pass
    }

    func testCloseActiveAreaClosesCurrentArea() {
        let store = makeStore()
        guard let areaId = store.activeWorkspace?.activeAreaId else {
            XCTFail("Expected active area")
            return
        }
        store.splitArea(areaId: areaId, direction: .vertical)
        let areasAfterSplit = store.activeWorkspace?.allAreas ?? []
        XCTAssertEqual(areasAfterSplit.count, 2)

        store.closeActiveArea()

        let areasAfterClose = store.activeWorkspace?.allAreas ?? []
        XCTAssertEqual(areasAfterClose.count, 1)
    }

    // MARK: - Move Tab (D&D: inter-area move)

    func testMoveTabBetweenAreas() {
        let store = makeStore()
        guard let area1Id = store.activeWorkspace?.activeAreaId else {
            XCTFail("Expected active area")
            return
        }

        // Add a second tab to area1 so it survives losing one tab
        store.addTab(to: area1Id)
        store.addTab(to: area1Id)

        // Split to create area2
        store.splitArea(areaId: area1Id, direction: .vertical)
        let areas = store.activeWorkspace?.allAreas ?? []
        XCTAssertEqual(areas.count, 2)

        let area1 = store.activeWorkspace!.layout.findArea(id: area1Id)!
        let area2 = areas.first(where: { $0.id != area1Id })!
        let tabToMove = area1.tabs[0]

        store.moveTab(tabId: tabToMove.id, from: area1Id, to: area2.id, at: 0)

        let updatedArea1 = store.activeWorkspace!.layout.findArea(id: area1Id)
        let updatedArea2 = store.activeWorkspace!.layout.findArea(id: area2.id)

        // area1 should have 1 tab (had 2, moved 1)
        XCTAssertEqual(updatedArea1?.tabs.count, 1)
        // area2 should have 2 tabs (had 1, received 1)
        XCTAssertEqual(updatedArea2?.tabs.count, 2)
        // The moved tab should be at index 0 in area2
        XCTAssertEqual(updatedArea2?.tabs[0].id, tabToMove.id)
    }

    func testMoveLastTabRemovesSourceArea() {
        let store = makeStore()
        guard let area1Id = store.activeWorkspace?.activeAreaId else {
            XCTFail("Expected active area")
            return
        }

        store.addTab(to: area1Id)
        // Split to create area2
        store.splitArea(areaId: area1Id, direction: .vertical)
        let areas = store.activeWorkspace?.allAreas ?? []
        XCTAssertEqual(areas.count, 2)

        let area1 = store.activeWorkspace!.layout.findArea(id: area1Id)!
        let area2 = areas.first(where: { $0.id != area1Id })!
        let tabToMove = area1.tabs[0]

        // Move the only tab from area1 to area2
        store.moveTab(tabId: tabToMove.id, from: area1Id, to: area2.id, at: 1)

        // area1 should be gone
        XCTAssertNil(store.activeWorkspace?.layout.findArea(id: area1Id))
        // Only area2 remains
        XCTAssertEqual(store.activeWorkspace?.allAreas.count, 1)
        // area2 should have 2 tabs
        let updatedArea2 = store.activeWorkspace!.layout.findArea(id: area2.id)
        XCTAssertEqual(updatedArea2?.tabs.count, 2)
    }

    func testMoveTabToSameAreaIsNoOp() {
        let store = makeStore()
        guard let areaId = store.activeWorkspace?.activeAreaId else {
            XCTFail("Expected active area")
            return
        }
        store.addTab(to: areaId)
        store.addTab(to: areaId)

        let area = store.activeWorkspace!.layout.findArea(id: areaId)!
        let tabId = area.tabs[0].id

        store.moveTab(tabId: tabId, from: areaId, to: areaId, at: 1)

        // Should still have 2 tabs, no crash
        let updated = store.activeWorkspace!.layout.findArea(id: areaId)
        XCTAssertEqual(updated?.tabs.count, 2)
    }

    // MARK: - Move Tab to New Area (D&D: area split)

    func testMoveTabToNewAreaCreatesNewSplit() {
        let store = makeStore()
        guard let area1Id = store.activeWorkspace?.activeAreaId else {
            XCTFail("Expected active area")
            return
        }

        // Add second tab so area1 survives
        store.addTab(to: area1Id)
        store.addTab(to: area1Id)

        // Split to create area2
        store.splitArea(areaId: area1Id, direction: .vertical)
        let areas = store.activeWorkspace?.allAreas ?? []
        let area2 = areas.first(where: { $0.id != area1Id })!

        let area1 = store.activeWorkspace!.layout.findArea(id: area1Id)!
        let tabToMove = area1.tabs[0]

        store.moveTabToNewArea(
            tabId: tabToMove.id,
            from: area1Id,
            adjacentTo: area2.id,
            direction: .horizontal
        )

        // area1 should have 1 tab
        let updatedArea1 = store.activeWorkspace!.layout.findArea(id: area1Id)
        XCTAssertEqual(updatedArea1?.tabs.count, 1)

        // Should now have 3 areas total
        XCTAssertEqual(store.activeWorkspace?.allAreas.count, 3)

        // The new area should have the moved tab
        let allAreas = store.activeWorkspace!.allAreas
        let newArea = allAreas.first(where: { $0.id != area1Id && $0.id != area2.id })
        XCTAssertNotNil(newArea)
        XCTAssertEqual(newArea?.tabs.count, 1)
        XCTAssertEqual(newArea?.tabs[0].id, tabToMove.id)
    }

    func testMoveLastTabToNewAreaRemovesSourceArea() {
        let store = makeStore()
        guard let area1Id = store.activeWorkspace?.activeAreaId else {
            XCTFail("Expected active area")
            return
        }

        store.addTab(to: area1Id)
        // Split to create area2
        store.splitArea(areaId: area1Id, direction: .vertical)
        let areas = store.activeWorkspace?.allAreas ?? []
        let area2 = areas.first(where: { $0.id != area1Id })!

        let area1 = store.activeWorkspace!.layout.findArea(id: area1Id)!
        let tabToMove = area1.tabs[0]

        store.moveTabToNewArea(
            tabId: tabToMove.id,
            from: area1Id,
            adjacentTo: area2.id,
            direction: .vertical
        )

        // area1 should be gone (had only 1 tab)
        XCTAssertNil(store.activeWorkspace?.layout.findArea(id: area1Id))
        // Should have 2 areas: area2 and the new area
        XCTAssertEqual(store.activeWorkspace?.allAreas.count, 2)
    }

    // MARK: - All Sessions

    func testAllSessionsReturnsAllTerminals() {
        let store = makeStore()
        guard let areaId = store.activeWorkspace?.activeAreaId else {
            XCTFail("Expected active area")
            return
        }

        store.addTab(to: areaId)
        store.addTab(to: areaId)
        store.splitArea(areaId: areaId, direction: .vertical)

        // 2 added tabs + 1 from split = 3
        XCTAssertEqual(store.allSessions.count, 3)
    }

    func testTerminalNumbersDoNotReuseClosedTabs() {
        let store = makeStore()
        guard let areaId = store.activeWorkspace?.activeAreaId else {
            XCTFail("Expected active area")
            return
        }

        store.addTerminalTab(to: areaId)
        store.addTerminalTab(to: areaId)
        store.addTerminalTab(to: areaId)
        store.closeTab(in: areaId, at: 2)
        store.addTerminalTab(to: areaId)

        let titles = store.activeWorkspace?
            .layout
            .findArea(id: areaId)?
            .tabs
            .compactMap { $0.content.terminalSession?.title }

        XCTAssertEqual(titles, ["Terminal 1", "Terminal 2", "Terminal 4"])
    }

    func testCloseTerminalSessionInInactiveWorkspacePreservesActiveWorkspace() {
        let store = makeStore()
        guard let firstAreaId = store.activeWorkspace?.activeAreaId else {
            XCTFail("Expected active area")
            return
        }

        store.addTerminalTab(to: firstAreaId)
        store.addWorkspace()

        let secondWorkspaceIndex = 1
        guard let secondAreaId = store.workspaces[secondWorkspaceIndex].activeAreaId,
              let session = store.workspaces[secondWorkspaceIndex]
              .layout
              .findArea(id: secondAreaId)?
              .tabs
              .first?
              .content
              .terminalSession else {
            XCTFail("Expected terminal session in second workspace")
            return
        }

        store.selectWorkspace(at: 0)
        store.closeTerminalSession(session)

        XCTAssertEqual(store.activeWorkspaceIndex, 0)
        XCTAssertEqual(store.workspaces[secondWorkspaceIndex].layout.findArea(id: secondAreaId)?.tabs.count, 0)
        XCTAssertFalse(session.isActive)
    }

    // MARK: - Focus Area (Notification Click)

    func testFocusAreaSwitchesWorkspaceAndArea() {
        let store = makeStore()
        store.addWorkspace()
        // Now at workspace index 1
        let area1Id = store.activeWorkspace!.activeAreaId!
        store.splitArea(areaId: area1Id, direction: .vertical)
        let area2 = store.activeWorkspace!.allAreas.first(where: { $0.id != area1Id })!

        // Switch to workspace 0
        store.selectWorkspace(at: 0)
        XCTAssertEqual(store.activeWorkspaceIndex, 0)

        // Focus area in workspace 1
        let result = store.focusArea(workspaceIndex: 1, areaId: area2.id)

        XCTAssertTrue(result)
        XCTAssertEqual(store.activeWorkspaceIndex, 1)
        XCTAssertEqual(store.activeWorkspace?.activeAreaId, area2.id)
    }

    func testFocusAreaWithInvalidWorkspaceReturnsFalse() {
        let store = makeStore()
        let result = store.focusArea(workspaceIndex: 99, areaId: UUID())
        XCTAssertFalse(result)
        XCTAssertEqual(store.activeWorkspaceIndex, 0)
    }

    func testFocusAreaWithInvalidAreaReturnsFalse() {
        let store = makeStore()
        let result = store.focusArea(workspaceIndex: 0, areaId: UUID())
        XCTAssertFalse(result)
    }
}
