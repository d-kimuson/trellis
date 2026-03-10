import Foundation
import XCTest
@testable import OreoreTerminal

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
        let state = FileTreeState(rootPath: NSTemporaryDirectory())
        let content = PanelContent.fileTree(state)
        XCTAssertNil(content.terminalSession)
    }

    func testTerminalSessionReturnsNilForGitClient() {
        let state = GitClientState(repositoryPath: NSTemporaryDirectory())
        let content = PanelContent.gitClient(state)
        XCTAssertNil(content.terminalSession)
    }

    // MARK: - tabTitle

    func testTabTitleForTerminal() {
        let session = TerminalSession(title: "Terminal 1")
        let content = PanelContent.terminal(session)
        XCTAssertEqual(content.tabTitle, "Terminal 1")
    }

    func testTabTitleForBrowser() {
        let state = BrowserState(url: URL(string: "https://example.com/page")!)
        let content = PanelContent.browser(state)
        XCTAssertEqual(content.tabTitle, "example.com")
    }

    func testTabTitleForFileTree() {
        let state = FileTreeState(rootPath: "/Users/test/project")
        let content = PanelContent.fileTree(state)
        XCTAssertEqual(content.tabTitle, "project")
    }

    // MARK: - iconName

    func testIconNameForAllTypes() {
        let terminal = PanelContent.terminal(TerminalSession(title: "t"))
        XCTAssertEqual(terminal.iconName, "terminal")

        let browser = PanelContent.browser(BrowserState())
        XCTAssertEqual(browser.iconName, "globe")

        let fileTree = PanelContent.fileTree(FileTreeState(rootPath: NSTemporaryDirectory()))
        XCTAssertEqual(fileTree.iconName, "folder")

        let git = PanelContent.gitClient(GitClientState(repositoryPath: NSTemporaryDirectory()))
        XCTAssertEqual(git.iconName, "arrow.triangle.branch")
    }

    // MARK: - Switch exhaustiveness

    /// This test verifies that all PanelContent cases are handled.
    /// If a new case is added without updating this test, it will fail to compile.
    func testAllCasesHandled() {
        let contents: [PanelContent] = [
            .terminal(TerminalSession(title: "t")),
            .browser(BrowserState()),
            .fileTree(FileTreeState(rootPath: NSTemporaryDirectory())),
            .gitClient(GitClientState(repositoryPath: NSTemporaryDirectory())),
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
            case .gitClient:
                XCTAssertNil(content.terminalSession)
            }
        }
    }
}
