import Foundation
import XCTest
@testable import Trellis

final class TerminalSessionTests: XCTestCase {

    // MARK: - close()

    func testCloseMarksSessionInactive() {
        let session = TerminalSession(title: "Test")
        XCTAssertTrue(session.isActive)
        session.close()
        XCTAssertFalse(session.isActive)
    }

    func testSessionCanBeReleasedAfterClose() {
        // Verify no assertion fires when close() is called before deallocation.
        var session: TerminalSession? = TerminalSession(title: "Test")
        session?.close()
        session = nil
        // If we reach here without an assertion failure, the test passes.
    }

    // MARK: - tabTitle

    func testTabTitleFallsBackToTitle() {
        let session = TerminalSession(title: "my-term")
        XCTAssertEqual(session.tabTitle, "my-term")
    }

    func testTabTitleUsesPwdLastComponent() {
        let session = TerminalSession(title: "Terminal")
        session.pwd = "/Users/test/project"
        XCTAssertEqual(session.tabTitle, "project")
    }

    // MARK: - shortPwd

    func testShortPwdReturnsNilWithoutPwd() {
        let session = TerminalSession(title: "Test")
        XCTAssertNil(session.shortPwd)
    }

    func testShortPwdReplaceHomeWithTilde() {
        let session = TerminalSession(title: "Test")
        let home = NSHomeDirectory()
        session.pwd = home + "/repos/trellis"
        XCTAssertEqual(session.shortPwd, "~/repos/trellis")
    }

    func testShortPwdForHomeIsJustTilde() {
        let session = TerminalSession(title: "Test")
        session.pwd = NSHomeDirectory()
        XCTAssertEqual(session.shortPwd, "~")
    }
}
