import Foundation
import XCTest
@testable import OreoreTerminal

final class TerminalOutputMonitorTests: XCTestCase {

    // MARK: - Pattern Matching

    func testMatchesShellPromptPattern() {
        let monitor = TerminalOutputMonitor()
        // Typical shell prompt title: "user@host:~/dir"
        let result = monitor.matchingPattern(for: "kaito@mac:~/repos")
        XCTAssertNotNil(result)
    }

    func testMatchesHomeDirPattern() {
        let monitor = TerminalOutputMonitor()
        let result = monitor.matchingPattern(for: "~/projects/myapp")
        XCTAssertNotNil(result)
    }

    func testMatchesAbsolutePathPattern() {
        let monitor = TerminalOutputMonitor()
        let result = monitor.matchingPattern(for: "/usr/local/bin")
        XCTAssertNotNil(result)
    }

    func testMatchesBashTitle() {
        let monitor = TerminalOutputMonitor()
        let result = monitor.matchingPattern(for: "bash")
        XCTAssertNotNil(result)
    }

    func testNoMatchForRunningCommand() {
        let monitor = TerminalOutputMonitor()
        // A running command name (no path separators, not a shell name)
        let result = monitor.matchingPattern(for: "vim main.swift")
        XCTAssertNil(result)
    }

    // MARK: - Custom Patterns

    func testAddCustomPattern() {
        var monitor = TerminalOutputMonitor()
        monitor.addPattern(NotificationPattern(
            name: "npm done",
            regex: "npm.*done",
            notificationTitle: "npm"
        ))
        let result = monitor.matchingPattern(for: "npm run build done")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "npm done")
    }

    func testRemovePattern() {
        var monitor = TerminalOutputMonitor()
        let defaultCount = monitor.patterns.count
        let patternToRemove = monitor.patterns[0]
        monitor.removePattern(id: patternToRemove.id)
        XCTAssertEqual(monitor.patterns.count, defaultCount - 1)
    }

    // MARK: - Notification Decision

    func testShouldNotNotifyWhenAppIsActive() {
        let monitor = TerminalOutputMonitor()
        let shouldNotify = monitor.shouldNotify(
            title: "kaito@mac:~/repos",
            isAppActive: true
        )
        XCTAssertFalse(shouldNotify)
    }

    func testShouldNotifyWhenAppIsInactiveAndPatternMatches() {
        let monitor = TerminalOutputMonitor()
        let shouldNotify = monitor.shouldNotify(
            title: "kaito@mac:~/repos",
            isAppActive: false
        )
        XCTAssertTrue(shouldNotify)
    }

    func testShouldNotNotifyWhenNoPatternMatches() {
        let monitor = TerminalOutputMonitor()
        let shouldNotify = monitor.shouldNotify(
            title: "vim main.swift",
            isAppActive: false
        )
        XCTAssertFalse(shouldNotify)
    }

    func testShouldNotNotifyWhenTitleUnchanged() {
        var monitor = TerminalOutputMonitor()
        monitor.recordTitle("kaito@mac:~/repos")
        let shouldNotify = monitor.shouldNotify(
            title: "kaito@mac:~/repos",
            isAppActive: false
        )
        XCTAssertFalse(shouldNotify)
    }

    func testShouldNotifyWhenTitleChanges() {
        var monitor = TerminalOutputMonitor()
        monitor.recordTitle("running: claude-code")
        let shouldNotify = monitor.shouldNotify(
            title: "kaito@mac:~/repos",
            isAppActive: false
        )
        XCTAssertTrue(shouldNotify)
    }

    func testCooldownPreventsSpam() {
        var monitor = TerminalOutputMonitor()
        monitor.recordNotificationSent()
        // Immediately after a notification, cooldown should prevent another
        let shouldNotify = monitor.shouldNotify(
            title: "kaito@mac:~/repos",
            isAppActive: false
        )
        XCTAssertFalse(shouldNotify)
    }

    // MARK: - Build Notification Info

    func testBuildNotificationInfoReturnsMatchedPatternTitle() {
        let monitor = TerminalOutputMonitor()
        let info = monitor.buildNotificationInfo(for: "kaito@mac:~/repos")
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.title, "Command Completed")
    }

    // MARK: - Invalid Regex

    func testAddPatternWithInvalidRegexDoesNotCrash() {
        var monitor = TerminalOutputMonitor()
        monitor.addPattern(NotificationPattern(
            name: "bad",
            regex: "[invalid",
            notificationTitle: "Bad"
        ))
        let result = monitor.matchingPattern(for: "test")
        XCTAssertNil(result)
    }
}
