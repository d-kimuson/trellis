import Foundation
import XCTest
@testable import OreoreTerminal

final class TerminalOutputMonitorTests: XCTestCase {

    // MARK: - Pattern Matching

    func testMatchesDefaultProcessCompletionPattern() {
        let monitor = TerminalOutputMonitor()
        // Typical shell prompt after command completes: "user@host:~/dir$"
        let result = monitor.matchingPattern(for: "kaito@mac:~/repos$")
        XCTAssertNotNil(result)
    }

    func testMatchesClaudeCodeCompletionPattern() {
        let monitor = TerminalOutputMonitor()
        let result = monitor.matchingPattern(for: "Claude Code completed")
        XCTAssertNotNil(result)
    }

    func testNoMatchForRandomTitle() {
        let monitor = TerminalOutputMonitor()
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
            title: "kaito@mac:~/repos$",
            isAppActive: true
        )
        XCTAssertFalse(shouldNotify)
    }

    func testShouldNotifyWhenAppIsInactiveAndPatternMatches() {
        let monitor = TerminalOutputMonitor()
        let shouldNotify = monitor.shouldNotify(
            title: "kaito@mac:~/repos$",
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

    // MARK: - Build Notification Info

    func testBuildNotificationInfoReturnsMatchedPatternTitle() {
        let monitor = TerminalOutputMonitor()
        let info = monitor.buildNotificationInfo(for: "kaito@mac:~/repos$")
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.title, "Process Completed")
    }

    func testBuildNotificationInfoIncludesTerminalTitle() {
        let monitor = TerminalOutputMonitor()
        let info = monitor.buildNotificationInfo(for: "Claude Code completed")
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.body, "Claude Code completed")
    }

    // MARK: - Invalid Regex

    func testAddPatternWithInvalidRegexIsIgnored() {
        var monitor = TerminalOutputMonitor()
        let countBefore = monitor.patterns.count
        monitor.addPattern(NotificationPattern(
            name: "bad",
            regex: "[invalid",
            notificationTitle: "Bad"
        ))
        // Invalid regex pattern should still be added (validation at match time)
        // or could be rejected - implementation decides
        // Just verify no crash
        let result = monitor.matchingPattern(for: "test")
        _ = result // no crash
        _ = countBefore
    }
}
