import Foundation
import XCTest
@testable import OreoreTerminal

final class LayoutNodeTests: XCTestCase {

    // MARK: - Helpers

    private func makeSession(_ title: String = "test") -> TerminalSession {
        TerminalSession(title: title)
    }

    private func makeArea(_ title: String = "test") -> Area {
        let session = makeSession(title)
        let tab = Tab(content: .terminal(session))
        return Area(tabs: [tab])
    }

    // MARK: - Identity

    func testLeafNodeHasAreaId() {
        let area = makeArea()
        let node = LayoutNode.leaf(area)
        XCTAssertEqual(node.id, area.id)
    }

    func testSplitNodeHasOwnId() {
        let splitId = UUID()
        let node = LayoutNode.split(
            id: splitId,
            direction: .vertical,
            first: .leaf(makeArea()),
            second: .leaf(makeArea()),
            ratio: 0.5
        )
        XCTAssertEqual(node.id, splitId)
    }

    // MARK: - allAreas

    func testAllAreasForLeafReturnsSingleArea() {
        let area = makeArea()
        let node = LayoutNode.leaf(area)
        XCTAssertEqual(node.allAreas.count, 1)
        XCTAssertEqual(node.allAreas.first?.id, area.id)
    }

    func testAllAreasForSplitReturnsBothAreas() {
        let a1 = makeArea("a1")
        let a2 = makeArea("a2")
        let node = LayoutNode.split(
            id: UUID(),
            direction: .vertical,
            first: .leaf(a1),
            second: .leaf(a2),
            ratio: 0.5
        )
        XCTAssertEqual(node.allAreas.count, 2)
        XCTAssertEqual(node.allAreas[0].id, a1.id)
        XCTAssertEqual(node.allAreas[1].id, a2.id)
    }

    // MARK: - findArea

    func testFindAreaReturnsMatchingArea() {
        let area = makeArea()
        let node = LayoutNode.leaf(area)
        XCTAssertEqual(node.findArea(id: area.id)?.id, area.id)
    }

    func testFindAreaReturnsNilForUnknownId() {
        let node = LayoutNode.leaf(makeArea())
        XCTAssertNil(node.findArea(id: UUID()))
    }

    func testFindAreaInNestedSplit() {
        let a1 = makeArea("a1")
        let a2 = makeArea("a2")
        let a3 = makeArea("a3")
        let node = LayoutNode.split(
            id: UUID(),
            direction: .vertical,
            first: .leaf(a1),
            second: .split(
                id: UUID(),
                direction: .horizontal,
                first: .leaf(a2),
                second: .leaf(a3),
                ratio: 0.5
            ),
            ratio: 0.5
        )
        XCTAssertEqual(node.findArea(id: a3.id)?.id, a3.id)
    }

    // MARK: - splittingArea

    func testSplittingAreaCreatesSplitNode() {
        let a1 = makeArea("a1")
        let a2 = makeArea("a2")
        let root = LayoutNode.leaf(a1)

        let result = root.splittingArea(areaId: a1.id, direction: .vertical, newArea: a2)

        guard case .split(_, let dir, let first, let second, let ratio) = result else {
            XCTFail("Expected split node")
            return
        }
        XCTAssertEqual(dir, .vertical)
        XCTAssertEqual(ratio, 0.5)

        guard case .leaf(let firstArea) = first else {
            XCTFail("Expected leaf first child")
            return
        }
        XCTAssertEqual(firstArea.id, a1.id)

        guard case .leaf(let secondArea) = second else {
            XCTFail("Expected leaf second child")
            return
        }
        XCTAssertEqual(secondArea.id, a2.id)
    }

    func testSplittingNonMatchingAreaIsNoOp() {
        let a1 = makeArea("a1")
        let a2 = makeArea("a2")
        let root = LayoutNode.leaf(a1)

        let result = root.splittingArea(areaId: UUID(), direction: .horizontal, newArea: a2)

        guard case .leaf(let area) = result else {
            XCTFail("Expected unchanged leaf node")
            return
        }
        XCTAssertEqual(area.id, a1.id)
    }

    // MARK: - removingArea

    func testRemovingAreaPromotesSibling() {
        let a1 = makeArea("a1")
        let a2 = makeArea("a2")
        let root = LayoutNode.leaf(a1)
            .splittingArea(areaId: a1.id, direction: .vertical, newArea: a2)

        let result = root.removingArea(areaId: a1.id)

        guard case .leaf(let remaining) = result else {
            XCTFail("Expected sibling promoted to leaf")
            return
        }
        XCTAssertEqual(remaining.id, a2.id)
    }

    func testRemovingSecondPromotesFirst() {
        let a1 = makeArea("a1")
        let a2 = makeArea("a2")
        let root = LayoutNode.leaf(a1)
            .splittingArea(areaId: a1.id, direction: .horizontal, newArea: a2)

        let result = root.removingArea(areaId: a2.id)

        guard case .leaf(let remaining) = result else {
            XCTFail("Expected first child promoted")
            return
        }
        XCTAssertEqual(remaining.id, a1.id)
    }

    func testDeepTreeRemoval() {
        let a1 = makeArea("a1")
        let a2 = makeArea("a2")
        let a3 = makeArea("a3")

        // Build: a1 | (a2 / a3)
        var root = LayoutNode.leaf(a1)
            .splittingArea(areaId: a1.id, direction: .vertical, newArea: a2)
        root = root.splittingArea(areaId: a2.id, direction: .horizontal, newArea: a3)

        // Remove a2 → should be: a1 | a3
        let result = root.removingArea(areaId: a2.id)

        guard case .split(_, .vertical, let first, let second, _) = result else {
            XCTFail("Expected top-level vertical split")
            return
        }
        guard case .leaf(let firstArea) = first else {
            XCTFail("Expected leaf first child")
            return
        }
        XCTAssertEqual(firstArea.id, a1.id)
        guard case .leaf(let secondArea) = second else {
            XCTFail("Expected a3 promoted after a2 removal")
            return
        }
        XCTAssertEqual(secondArea.id, a3.id)
    }

    // MARK: - updatingRatio

    func testUpdatingRatioChangesTarget() {
        let a1 = makeArea("a1")
        let a2 = makeArea("a2")
        let root = LayoutNode.leaf(a1)
            .splittingArea(areaId: a1.id, direction: .vertical, newArea: a2)

        guard case .split(let splitId, _, _, _, _) = root else {
            XCTFail("Expected split node")
            return
        }

        let updated = root.updatingRatio(splitId: splitId, ratio: 0.3)

        guard case .split(_, _, _, _, let newRatio) = updated else {
            XCTFail("Expected split node after update")
            return
        }
        XCTAssertEqual(newRatio, 0.3)
    }

    func testUpdatingRatioDoesNotAffectOtherSplits() {
        let a1 = makeArea("a1")
        let a2 = makeArea("a2")
        let a3 = makeArea("a3")

        var root = LayoutNode.leaf(a1)
            .splittingArea(areaId: a1.id, direction: .vertical, newArea: a2)
        root = root.splittingArea(areaId: a2.id, direction: .horizontal, newArea: a3)

        guard case .split(let topId, _, _, _, _) = root else {
            XCTFail("Expected split")
            return
        }

        let updated = root.updatingRatio(splitId: topId, ratio: 0.7)

        guard case .split(_, _, _, let second, let topRatio) = updated else {
            XCTFail("Expected split")
            return
        }
        XCTAssertEqual(topRatio, 0.7)

        // Inner split should still be 0.5
        guard case .split(_, _, _, _, let innerRatio) = second else {
            XCTFail("Expected inner split")
            return
        }
        XCTAssertEqual(innerRatio, 0.5)
    }

    // MARK: - updatingArea

    func testUpdatingAreaTransformsMatchingArea() {
        let session = makeSession("s1")
        let tab = Tab(content: .terminal(session))
        let area = Area(tabs: [tab])
        let root = LayoutNode.leaf(area)

        let newSession = makeSession("s2")
        let newTab = Tab(content: .terminal(newSession))

        let updated = root.updatingArea(areaId: area.id) { area in
            area.addingTab(newTab)
        }

        guard case .leaf(let updatedArea) = updated else {
            XCTFail("Expected leaf")
            return
        }
        XCTAssertEqual(updatedArea.tabs.count, 2)
        XCTAssertEqual(updatedArea.activeTabIndex, 1)
    }
}

// MARK: - Area Tests

final class AreaTests: XCTestCase {

    private func makeSession(_ title: String = "test") -> TerminalSession {
        TerminalSession(title: title)
    }

    private func makeTab(_ title: String = "test") -> Tab {
        Tab(content: .terminal(makeSession(title)))
    }

    func testActiveTabReturnsCorrectTab() {
        let t1 = makeTab("t1")
        let t2 = makeTab("t2")
        let area = Area(tabs: [t1, t2], activeTabIndex: 1)
        XCTAssertEqual(area.activeTab?.id, t2.id)
    }

    func testActiveTabReturnsNilForEmptyArea() {
        let area = Area(tabs: [], activeTabIndex: 0)
        XCTAssertNil(area.activeTab)
    }

    func testAddingTabAppendsAndActivates() {
        let t1 = makeTab("t1")
        let t2 = makeTab("t2")
        let area = Area(tabs: [t1])

        let updated = area.addingTab(t2)
        XCTAssertEqual(updated.tabs.count, 2)
        XCTAssertEqual(updated.activeTabIndex, 1)
        XCTAssertEqual(updated.activeTab?.id, t2.id)
    }

    func testRemovingTabReturnsNilWhenLastTabRemoved() {
        let t1 = makeTab("t1")
        let area = Area(tabs: [t1])

        let result = area.removingTab(at: 0)
        XCTAssertNil(result)
    }

    func testRemovingTabAdjustsActiveIndex() {
        let t1 = makeTab("t1")
        let t2 = makeTab("t2")
        let t3 = makeTab("t3")
        let area = Area(tabs: [t1, t2, t3], activeTabIndex: 2)

        let result = area.removingTab(at: 2)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.tabs.count, 2)
        XCTAssertEqual(result?.activeTabIndex, 1)
    }

    func testRemovingMiddleTabKeepsActiveIndexValid() {
        let t1 = makeTab("t1")
        let t2 = makeTab("t2")
        let t3 = makeTab("t3")
        let area = Area(tabs: [t1, t2, t3], activeTabIndex: 1)

        let result = area.removingTab(at: 1)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.tabs.count, 2)
        XCTAssertEqual(result?.activeTabIndex, 1) // clamped to count-1
    }

    func testSelectingTabUpdatesActiveIndex() {
        let t1 = makeTab("t1")
        let t2 = makeTab("t2")
        let area = Area(tabs: [t1, t2], activeTabIndex: 0)

        let updated = area.selectingTab(at: 1)
        XCTAssertEqual(updated.activeTabIndex, 1)
    }

    func testSelectingTabOutOfRangeIsNoOp() {
        let t1 = makeTab("t1")
        let area = Area(tabs: [t1], activeTabIndex: 0)

        let updated = area.selectingTab(at: 5)
        XCTAssertEqual(updated.activeTabIndex, 0)
    }

    func testRemovingTabOutOfRangeReturnsNil() {
        let t1 = makeTab("t1")
        let area = Area(tabs: [t1], activeTabIndex: 0)

        XCTAssertNil(area.removingTab(at: -1))
        XCTAssertNil(area.removingTab(at: 1))
    }

    // MARK: - insertingTab

    func testInsertingTabAtBeginning() {
        let t1 = makeTab("t1")
        let t2 = makeTab("t2")
        let area = Area(tabs: [t1])

        let updated = area.insertingTab(t2, at: 0)
        XCTAssertEqual(updated.tabs.count, 2)
        XCTAssertEqual(updated.tabs[0].id, t2.id)
        XCTAssertEqual(updated.tabs[1].id, t1.id)
        XCTAssertEqual(updated.activeTabIndex, 0) // inserted tab becomes active
    }

    func testInsertingTabAtEnd() {
        let t1 = makeTab("t1")
        let t2 = makeTab("t2")
        let area = Area(tabs: [t1])

        let updated = area.insertingTab(t2, at: 1)
        XCTAssertEqual(updated.tabs.count, 2)
        XCTAssertEqual(updated.tabs[1].id, t2.id)
        XCTAssertEqual(updated.activeTabIndex, 1)
    }

    func testInsertingTabClampedIndex() {
        let t1 = makeTab("t1")
        let t2 = makeTab("t2")
        let area = Area(tabs: [t1])

        let updated = area.insertingTab(t2, at: 100)
        XCTAssertEqual(updated.tabs.count, 2)
        XCTAssertEqual(updated.tabs[1].id, t2.id)
    }

    // MARK: - removingTabById

    func testRemovingTabByIdRemovesCorrectTab() {
        let t1 = makeTab("t1")
        let t2 = makeTab("t2")
        let t3 = makeTab("t3")
        let area = Area(tabs: [t1, t2, t3], activeTabIndex: 0)

        let (updatedArea, removedTab) = area.removingTabById(t2.id)
        XCTAssertNotNil(updatedArea)
        XCTAssertEqual(updatedArea?.tabs.count, 2)
        XCTAssertEqual(removedTab?.id, t2.id)
    }

    func testRemovingTabByIdReturnsNilAreaWhenLastTab() {
        let t1 = makeTab("t1")
        let area = Area(tabs: [t1])

        let (updatedArea, removedTab) = area.removingTabById(t1.id)
        XCTAssertNil(updatedArea)
        XCTAssertEqual(removedTab?.id, t1.id)
    }

    func testRemovingTabByIdWithUnknownIdReturnsNil() {
        let t1 = makeTab("t1")
        let area = Area(tabs: [t1])

        let (updatedArea, removedTab) = area.removingTabById(UUID())
        XCTAssertNil(updatedArea)
        XCTAssertNil(removedTab)
    }
}
