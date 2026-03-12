import Foundation
import XCTest
@testable import Trellis

final class PanelContentTests: XCTestCase {

    // MARK: - terminalSession accessor

    func testTerminalSessionReturnsSessionForTerminal() {
        let session = TerminalSession(title: "Test")
        let content = PanelContent.terminal(session)
        XCTAssertNotNil(content.terminalSession)
        XCTAssertEqual(content.terminalSession?.title, "Test")
    }

    func testTerminalSessionReturnsNilForBrowser() {
        let state = BrowserState()
        let content = PanelContent.browser(state)
        XCTAssertNil(content.terminalSession)
    }

    func testTerminalSessionReturnsNilForFileTree() {
        let state = FileTreeState()
        let content = PanelContent.fileTree(state)
        XCTAssertNil(content.terminalSession)
    }

    // MARK: - TerminalSession.tabTitle

    func testTerminalSessionTabTitleWithoutPwd() {
        let session = TerminalSession(title: "Terminal 1")
        XCTAssertEqual(session.tabTitle, "Terminal 1")
    }

    func testTerminalSessionTabTitleWithPwd() {
        let session = TerminalSession(title: "Terminal 1")
        session.pwd = "/Users/kaito/repos/trellis"
        XCTAssertEqual(session.tabTitle, "trellis")
    }

    func testTerminalSessionTabTitleWithRootPwd() {
        let session = TerminalSession(title: "Terminal 1")
        session.pwd = "/"
        XCTAssertEqual(session.tabTitle, "/")
    }

    // MARK: - tabTitle

    func testTabTitleForTerminal() {
        let session = TerminalSession(title: "Terminal 1")
        let content = PanelContent.terminal(session)
        XCTAssertEqual(content.tabTitle, "Terminal 1")
    }

    func testTabTitleForTerminalWithPwd() {
        let session = TerminalSession(title: "Terminal 1")
        session.pwd = "/Users/kaito/repos/trellis"
        let content = PanelContent.terminal(session)
        XCTAssertEqual(content.tabTitle, "trellis")
    }

    func testTabTitleForBrowser() {
        let state = BrowserState(url: URL(string: "https://example.com/page")!)
        let content = PanelContent.browser(state)
        XCTAssertEqual(content.tabTitle, "example.com")
    }

    func testTabTitleForFileTreeWithPath() {
        let state = FileTreeState(rootPath: "/Users/test/project")
        let content = PanelContent.fileTree(state)
        XCTAssertEqual(content.tabTitle, "project")
    }

    func testTabTitleForFileTreeWithoutPath() {
        let state = FileTreeState()
        let content = PanelContent.fileTree(state)
        XCTAssertEqual(content.tabTitle, "Files")
    }

    // MARK: - iconName

    func testIconNameForAllTypes() {
        let terminal = PanelContent.terminal(TerminalSession(title: "t"))
        XCTAssertEqual(terminal.iconName, "terminal")

        let browser = PanelContent.browser(BrowserState())
        XCTAssertEqual(browser.iconName, "globe")

        let fileTree = PanelContent.fileTree(FileTreeState())
        XCTAssertEqual(fileTree.iconName, "folder")
    }

    // MARK: - Switch exhaustiveness

    /// This test verifies that all PanelContent cases are handled.
    /// If a new case is added without updating this test, it will fail to compile.
    func testAllCasesHandled() {
        let contents: [PanelContent] = [
            .terminal(TerminalSession(title: "t")),
            .browser(BrowserState()),
            .fileTree(FileTreeState()),
        ]

        for content in contents {
            // Exhaustive switch - compile error if case missing
            switch content {
            case .terminal:
                XCTAssertNotNil(content.terminalSession)
            case .browser:
                XCTAssertNil(content.terminalSession)
            case .fileTree:
                XCTAssertNil(content.terminalSession)
            }
        }
    }
}
