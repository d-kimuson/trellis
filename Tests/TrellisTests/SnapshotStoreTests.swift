import Foundation
import XCTest
@testable import Trellis

final class SnapshotStoreTests: XCTestCase {

    // MARK: - truncate: Line Limit

    func testTruncateKeepsAtMost4000Lines() {
        let tooManyLines = (1...5000).map { "line \($0)" }.joined(separator: "\n")
        let result = SnapshotStore.truncate(tooManyLines)
        let count = result.components(separatedBy: "\n").count
        XCTAssertLessThanOrEqual(count, SnapshotStore.maxScrollbackLines)
    }

    func testTruncateUnder4000LinesKeepsAll() {
        let input = (1...100).map { "line \($0)" }.joined(separator: "\n")
        let result = SnapshotStore.truncate(input)
        XCTAssertEqual(result.components(separatedBy: "\n").count, 100)
    }

    func testTruncatePreservesLatestContentWhenLineLimitExceeded() {
        let tooManyLines = (1...5000).map { "line \($0)" }.joined(separator: "\n")
        let result = SnapshotStore.truncate(tooManyLines)
        XCTAssertTrue(result.hasSuffix("line 5000"))
        // "line 1" (the very first line) should have been dropped in favour of later lines
        let firstLine = result.components(separatedBy: "\n").first ?? ""
        XCTAssertNotEqual(firstLine, "line 1", "The earliest line should have been truncated")
    }

    // MARK: - truncate: Trailing Blank Lines

    func testTruncateRemovesTrailingBlankLines() {
        let input = "hello\nworld\n\n\n"
        let result = SnapshotStore.truncate(input)
        XCTAssertEqual(result, "hello\nworld")
    }

    func testTruncateSingleLineNoTrailingBlank() {
        let input = "hello"
        let result = SnapshotStore.truncate(input)
        XCTAssertEqual(result, "hello")
    }

    func testTruncateEmptyStringReturnsEmpty() {
        let result = SnapshotStore.truncate("")
        XCTAssertEqual(result, "")
    }

    func testTruncateAllBlankLinesReturnsEmpty() {
        let input = "\n\n\n\n"
        let result = SnapshotStore.truncate(input)
        XCTAssertEqual(result, "")
    }

    func testTruncatePreservesBlankLinesInMiddle() {
        let input = "hello\n\nworld"
        let result = SnapshotStore.truncate(input)
        XCTAssertEqual(result, "hello\n\nworld")
    }

    func testTruncateRemovesWhitespaceOnlyTrailingLine() {
        let input = "hello\n   "
        let result = SnapshotStore.truncate(input)
        XCTAssertEqual(result, "hello")
    }

    // MARK: - truncate: direnv: unloading (teardown detection)

    func testTruncateRemovesDirenvUnloadingAtEnd() {
        let input = "hello\nworld\ndirenv: unloading"
        let result = SnapshotStore.truncate(input)
        XCTAssertEqual(result, "hello\nworld")
    }

    func testTruncateRemovesDirenvUnloadingWithPercentPrefix() {
        // zsh PROMPT_SP may prefix "%" before direnv message on same line
        let input = "hello\n%direnv: unloading"
        let result = SnapshotStore.truncate(input)
        XCTAssertEqual(result, "hello")
    }

    func testTruncateRemovesDirenvAfterBlankLines() {
        let input = "hello\n\ndirenv: unloading\n\n"
        let result = SnapshotStore.truncate(input)
        XCTAssertEqual(result, "hello")
    }

    func testTruncateKeepsDirenvUnloadingInMiddle() {
        // "direnv: unloading" only removed from trailing position, not mid-buffer
        let input = "direnv: unloading\nhello\nworld"
        let result = SnapshotStore.truncate(input)
        XCTAssertEqual(result, "direnv: unloading\nhello\nworld")
    }

    // MARK: - truncate: zsh PROMPT_SP ('%' only lines)

    func testTruncateRemovesSinglePercentLine() {
        let input = "hello\n%"
        let result = SnapshotStore.truncate(input)
        XCTAssertEqual(result, "hello")
    }

    func testTruncateRemovesMultiplePercentLine() {
        let input = "hello\n%%%"
        let result = SnapshotStore.truncate(input)
        XCTAssertEqual(result, "hello")
    }

    func testTruncateRemovesStackedPercentAndBlankLines() {
        let input = "hello\n%\n\n%%%\n"
        let result = SnapshotStore.truncate(input)
        XCTAssertEqual(result, "hello")
    }

    func testTruncateKeepsMixedContentWithPercent() {
        // A line with non-'%' characters is not a teardown marker
        let input = "hello\n%world"
        let result = SnapshotStore.truncate(input)
        XCTAssertEqual(result, "hello\n%world")
    }

    func testTruncateKeepsLineWithPercentAndLetter() {
        let input = "100% done"
        let result = SnapshotStore.truncate(input)
        XCTAssertEqual(result, "100% done")
    }

    // MARK: - truncate: Char Limit

    func testTruncateEnforcesCharLimit() {
        let longLine = String(repeating: "a", count: 1000)
        let manyLines = (1...450).map { _ in longLine }.joined(separator: "\n")
        let result = SnapshotStore.truncate(manyLines)
        XCTAssertLessThanOrEqual(result.count, SnapshotStore.maxScrollbackChars)
    }

    func testTruncateUnderCharLimitUnchanged() {
        let input = String(repeating: "a", count: 1000)
        let result = SnapshotStore.truncate(input)
        XCTAssertEqual(result.count, 1000)
    }

    func testTruncateCharLimitPreservesLatestContent() {
        let longLine = String(repeating: "a", count: 1000)
        let marker = "MARKER_END"
        let body = (1...450).map { _ in longLine }.joined(separator: "\n")
        let input = body + "\n" + marker
        let result = SnapshotStore.truncate(input)
        XCTAssertTrue(result.hasSuffix(marker))
    }

    // MARK: - Suspected Bugs (commented out)

    func testTruncateDoesNotRemoveMeaningfulDirenvLines() {
        // A line that contains but does not start with "direnv: unloading" is
        // meaningful user output and must not be removed.
        let input = "Process log: direnv: unloading some module"
        let result = SnapshotStore.truncate(input)
        XCTAssertEqual(result, "Process log: direnv: unloading some module")
    }

    // MARK: - writeScrollbackFile

    func testWriteScrollbackFileCreatesReadableFile() {
        let id = UUID()
        let content = "hello scrollback\nline 2"
        let path = SnapshotStore.writeScrollbackFile(content, id: id)
        XCTAssertNotNil(path)
        if let path {
            defer { try? FileManager.default.removeItem(atPath: path) }
            let read = try? String(contentsOfFile: path, encoding: .utf8)
            XCTAssertEqual(read, content)
        }
    }

    func testWriteScrollbackFileReturnsDistinctPathsForDifferentUUIDs() {
        let id1 = UUID()
        let id2 = UUID()
        let path1 = SnapshotStore.writeScrollbackFile("a", id: id1)
        let path2 = SnapshotStore.writeScrollbackFile("b", id: id2)
        defer {
            path1.map { try? FileManager.default.removeItem(atPath: $0) }
            path2.map { try? FileManager.default.removeItem(atPath: $0) }
        }
        XCTAssertNotEqual(path1, path2)
    }

    func testWriteScrollbackFileContainsUUIDInPath() {
        let id = UUID()
        let path = SnapshotStore.writeScrollbackFile("hello", id: id)
        defer { path.map { try? FileManager.default.removeItem(atPath: $0) } }
        XCTAssertNotNil(path)
        if let path {
            XCTAssertTrue(path.contains(id.uuidString))
        }
    }

    // MARK: - prepareRestoreEnv

    func testPrepareRestoreEnvEmptyScrollbackReturnsEmptyDict() {
        let env = SnapshotStore.prepareRestoreEnv(scrollback: "", sessionId: UUID())
        XCTAssertTrue(env.isEmpty)
    }

    func testPrepareRestoreEnvSetsScrollbackFileKey() {
        let env = SnapshotStore.prepareRestoreEnv(scrollback: "hello", sessionId: UUID())
        XCTAssertNotNil(
            env["TRELLIS_RESTORE_SCROLLBACK_FILE"],
            "TRELLIS_RESTORE_SCROLLBACK_FILE must be set for non-empty scrollback"
        )
    }

    func testPrepareRestoreEnvScrollbackFileIsReadable() {
        let content = "restored content"
        let env = SnapshotStore.prepareRestoreEnv(scrollback: content, sessionId: UUID())
        if let path = env["TRELLIS_RESTORE_SCROLLBACK_FILE"] {
            defer { try? FileManager.default.removeItem(atPath: path) }
            let read = try? String(contentsOfFile: path, encoding: .utf8)
            XCTAssertEqual(read, content)
        } else {
            XCTFail("Expected TRELLIS_RESTORE_SCROLLBACK_FILE to be set")
        }
    }

    func testPrepareRestoreEnvWithPositiveColsSetsColsKey() {
        let env = SnapshotStore.prepareRestoreEnv(
            scrollback: "hello",
            sessionId: UUID(),
            terminalCols: 80
        )
        XCTAssertEqual(env["TRELLIS_TERMINAL_COLS"], "80")
    }

    func testPrepareRestoreEnvWithZeroColsDoesNotSetColsKey() {
        let env = SnapshotStore.prepareRestoreEnv(
            scrollback: "hello",
            sessionId: UUID(),
            terminalCols: 0
        )
        XCTAssertNil(env["TRELLIS_TERMINAL_COLS"])
    }

    func testPrepareRestoreEnvWithNegativeColsDoesNotSetColsKey() {
        let env = SnapshotStore.prepareRestoreEnv(
            scrollback: "hello",
            sessionId: UUID(),
            terminalCols: -1
        )
        XCTAssertNil(env["TRELLIS_TERMINAL_COLS"])
    }

    func testPrepareRestoreEnvWithNilColsDoesNotSetColsKey() {
        let env = SnapshotStore.prepareRestoreEnv(
            scrollback: "hello",
            sessionId: UUID(),
            terminalCols: nil
        )
        XCTAssertNil(env["TRELLIS_TERMINAL_COLS"])
    }
}
