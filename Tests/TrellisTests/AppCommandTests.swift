import XCTest
@testable import Trellis

final class AppCommandTests: XCTestCase {

    // MARK: - matches(_:)

    func testEmptyQueryMatchesAll() {
        let cmd = AppCommand(id: "test", title: "Foo", icon: "star")
        XCTAssertTrue(cmd.matches(""))
    }

    func testMatchesTitleCaseInsensitive() {
        let cmd = AppCommand(id: "test", title: "New Terminal Tab", icon: "terminal")
        XCTAssertTrue(cmd.matches("terminal"))
        XCTAssertTrue(cmd.matches("TERMINAL"))
        XCTAssertTrue(cmd.matches("new"))
    }

    func testMatchesKeyword() {
        let cmd = AppCommand(id: "test", title: "Split Horizontal", icon: "star",
                             keywords: ["layout", "pane"])
        XCTAssertTrue(cmd.matches("pane"))
        XCTAssertTrue(cmd.matches("LAYOUT"))
    }

    func testNoMatchReturnsFlase() {
        let cmd = AppCommand(id: "test", title: "Open Settings", icon: "gear",
                             keywords: ["preferences"])
        XCTAssertFalse(cmd.matches("terminal"))
    }

    func testPartialTitleMatch() {
        let cmd = AppCommand(id: "test", title: "New Browser Tab", icon: "globe")
        XCTAssertTrue(cmd.matches("brow"))
    }

    // MARK: - allCommands

    func testAllCommandsHaveUniqueIds() {
        let ids = AppCommand.allCommands.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Duplicate command IDs found")
    }

    func testAllCommandsHaveNonEmptyTitles() {
        for cmd in AppCommand.allCommands {
            XCTAssertFalse(cmd.title.isEmpty, "Command \(cmd.id) has empty title")
        }
    }
}
