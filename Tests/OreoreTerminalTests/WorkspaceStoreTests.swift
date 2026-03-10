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

    func testInitialWorkspaceHasOneAreaWithOneTab() {
        let store = makeStore()
        guard let workspace = store.activeWorkspace else {
            XCTFail("Expected active workspace")
            return
        }
        let areas = workspace.allAreas
        XCTAssertEqual(areas.count, 1)
        XCTAssertEqual(areas.first?.tabs.count, 1)
        XCTAssertNotNil(areas.first?.activeTab?.content.terminalSession)
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
        XCTAssertEqual(area?.tabs.count, 2)
        XCTAssertEqual(area?.activeTabIndex, 1)
    }

    func testCloseTabRemovesTab() {
        let store = makeStore()
        guard let areaId = store.activeWorkspace?.activeAreaId else {
            XCTFail("Expected active area")
            return
        }

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

    // MARK: - All Sessions

    func testAllSessionsReturnsAllTerminals() {
        let store = makeStore()
        guard let areaId = store.activeWorkspace?.activeAreaId else {
            XCTFail("Expected active area")
            return
        }

        store.addTab(to: areaId)
        store.splitArea(areaId: areaId, direction: .vertical)

        // 1 original + 1 added tab + 1 from split = 3
        XCTAssertEqual(store.allSessions.count, 3)
    }
}
