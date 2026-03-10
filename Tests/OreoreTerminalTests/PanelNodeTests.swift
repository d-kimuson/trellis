import Foundation
import XCTest
@testable import OreoreTerminal

final class PanelNodeTests: XCTestCase {

    private func makeSession(_ title: String = "test") -> TerminalSession {
        TerminalSession(title: title)
    }

    func testTerminalNodeHasSessionId() {
        let session = makeSession()
        let node = PanelNode.terminal(session)
        XCTAssertEqual(node.id, session.id)
    }

    func testSplittingCreatesSplitNode() {
        let s1 = makeSession("s1")
        let s2 = makeSession("s2")
        let root = PanelNode.terminal(s1)

        let result = root.splitting(sessionId: s1.id, direction: .vertical, newSession: s2)

        guard case .split(_, let dir, let first, let second, let ratio) = result else {
            XCTFail("Expected split node")
            return
        }
        XCTAssertEqual(dir, .vertical)
        XCTAssertEqual(ratio, 0.5)

        guard case .terminal(let firstSession) = first else {
            XCTFail("Expected terminal first child")
            return
        }
        XCTAssertEqual(firstSession.id, s1.id)

        guard case .terminal(let secondSession) = second else {
            XCTFail("Expected terminal second child")
            return
        }
        XCTAssertEqual(secondSession.id, s2.id)
    }

    func testSplittingNonMatchingIsNoOp() {
        let s1 = makeSession("s1")
        let s2 = makeSession("s2")
        let root = PanelNode.terminal(s1)

        let result = root.splitting(sessionId: UUID(), direction: .horizontal, newSession: s2)

        guard case .terminal(let session) = result else {
            XCTFail("Expected unchanged terminal node")
            return
        }
        XCTAssertEqual(session.id, s1.id)
    }

    func testRemovingPromotesSibling() {
        let s1 = makeSession("s1")
        let s2 = makeSession("s2")
        let root = PanelNode.terminal(s1)
            .splitting(sessionId: s1.id, direction: .vertical, newSession: s2)

        let result = root.removing(sessionId: s1.id)

        guard case .terminal(let remaining) = result else {
            XCTFail("Expected sibling promoted to terminal")
            return
        }
        XCTAssertEqual(remaining.id, s2.id)
    }

    func testRemovingSecondPromotesFirst() {
        let s1 = makeSession("s1")
        let s2 = makeSession("s2")
        let root = PanelNode.terminal(s1)
            .splitting(sessionId: s1.id, direction: .horizontal, newSession: s2)

        let result = root.removing(sessionId: s2.id)

        guard case .terminal(let remaining) = result else {
            XCTFail("Expected first child promoted")
            return
        }
        XCTAssertEqual(remaining.id, s1.id)
    }

    func testUpdatingRatioChangesTarget() {
        let s1 = makeSession("s1")
        let s2 = makeSession("s2")
        let root = PanelNode.terminal(s1)
            .splitting(sessionId: s1.id, direction: .vertical, newSession: s2)

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

    func testDeepTreeSplitAndRemove() {
        let s1 = makeSession("s1")
        let s2 = makeSession("s2")
        let s3 = makeSession("s3")

        // Build: s1 | (s2 / s3)
        var root = PanelNode.terminal(s1)
            .splitting(sessionId: s1.id, direction: .vertical, newSession: s2)
        root = root.splitting(sessionId: s2.id, direction: .horizontal, newSession: s3)

        // Remove s2 from the nested split → should be: s1 | s3
        let result = root.removing(sessionId: s2.id)

        guard case .split(_, .vertical, let first, let second, _) = result else {
            XCTFail("Expected top-level vertical split")
            return
        }
        guard case .terminal(let firstSession) = first else {
            XCTFail("Expected terminal first child")
            return
        }
        XCTAssertEqual(firstSession.id, s1.id)
        guard case .terminal(let secondSession) = second else {
            XCTFail("Expected s3 promoted after s2 removal")
            return
        }
        XCTAssertEqual(secondSession.id, s3.id)
    }
}
