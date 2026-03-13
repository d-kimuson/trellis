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

    // MARK: - writeScrollbackFile permissions

    func testWriteScrollbackFileHasOwnerOnlyPermissions() {
        let id = UUID()
        let path = SnapshotStore.writeScrollbackFile("secret content", id: id)
        XCTAssertNotNil(path)
        if let path {
            defer { try? FileManager.default.removeItem(atPath: path) }
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            let perms = attrs?[.posixPermissions] as? Int
            XCTAssertEqual(perms, 0o600, "Scrollback temp file must be owner-only (0600)")
        }
    }

    // MARK: - cleanUpStaleTempFiles

    func testCleanUpStaleTempFilesRemovesOldFiles() throws {
        let id = UUID()
        let tmpDir = NSTemporaryDirectory()
        let path = tmpDir + "trellis-sb-\(id.uuidString).txt"
        try "old content".write(toFile: path, atomically: true, encoding: .utf8)
        let twoHoursAgo = Date().addingTimeInterval(-7200)
        try FileManager.default.setAttributes([.modificationDate: twoHoursAgo], ofItemAtPath: path)

        SnapshotStore.cleanUpStaleTempFiles(olderThan: 3600)

        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testCleanUpStaleTempFilesKeepsRecentFiles() throws {
        let id = UUID()
        let tmpDir = NSTemporaryDirectory()
        let path = tmpDir + "trellis-sb-\(id.uuidString).txt"
        try "recent content".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        SnapshotStore.cleanUpStaleTempFiles(olderThan: 3600)

        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    func testCleanUpStaleTempFilesIgnoresNonTrellisFiles() throws {
        let tmpDir = NSTemporaryDirectory()
        let path = tmpDir + "other-app-\(UUID().uuidString).txt"
        try "other content".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let twoHoursAgo = Date().addingTimeInterval(-7200)
        try FileManager.default.setAttributes([.modificationDate: twoHoursAgo], ofItemAtPath: path)

        SnapshotStore.cleanUpStaleTempFiles(olderThan: 3600)

        XCTAssertTrue(FileManager.default.fileExists(atPath: path), "Non-trellis files must not be removed")
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

    // MARK: - readRunningCommand

    func testReadRunningCommandReturnsNilForMissingFile() {
        let id = UUID()
        XCTAssertNil(SnapshotStore.readRunningCommand(sessionId: id))
    }

    func testReadRunningCommandReturnsContentWhenFileExists() throws {
        let id = UUID()
        // Shell integration writes to /tmp (not NSTemporaryDirectory)
        let path = "/tmp/trellis-running-\(id.uuidString).txt"
        try "make build".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let result = SnapshotStore.readRunningCommand(sessionId: id)
        XCTAssertEqual(result, "make build")
    }

    func testReadRunningCommandTrimsWhitespace() throws {
        let id = UUID()
        let path = "/tmp/trellis-running-\(id.uuidString).txt"
        try "npm test\n".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let result = SnapshotStore.readRunningCommand(sessionId: id)
        XCTAssertEqual(result, "npm test")
    }

    func testReadRunningCommandReturnsNilForEmptyFile() throws {
        let id = UUID()
        let path = "/tmp/trellis-running-\(id.uuidString).txt"
        try "".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        XCTAssertNil(SnapshotStore.readRunningCommand(sessionId: id))
    }

    // MARK: - cleanUpStaleTempFiles: running command files

    func testCleanUpStaleTempFilesRemovesOldRunningCommandFiles() throws {
        let id = UUID()
        // Running-command files are written by the shell to /tmp
        let path = "/tmp/trellis-running-\(id.uuidString).txt"
        try "old command".write(toFile: path, atomically: true, encoding: .utf8)
        let twoHoursAgo = Date().addingTimeInterval(-7200)
        try FileManager.default.setAttributes([.modificationDate: twoHoursAgo], ofItemAtPath: path)

        SnapshotStore.cleanUpStaleTempFiles(olderThan: 3600)

        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testCleanUpStaleTempFilesKeepsRecentRunningCommandFiles() throws {
        let id = UUID()
        let path = "/tmp/trellis-running-\(id.uuidString).txt"
        try "recent command".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        SnapshotStore.cleanUpStaleTempFiles(olderThan: 3600)

        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    // MARK: - appendRunningCommandNotice

    func testAppendRunningCommandNoticeReturnsOriginalWhenNoCommand() {
        let result = SnapshotStore.appendRunningCommandNotice(scrollback: "hello", runningCommand: nil)
        XCTAssertEqual(result, "hello")
    }

    func testAppendRunningCommandNoticeReturnsOriginalWhenEmptyCommand() {
        let result = SnapshotStore.appendRunningCommandNotice(scrollback: "hello", runningCommand: "")
        XCTAssertEqual(result, "hello")
    }

    func testAppendRunningCommandNoticeAppendsNotice() {
        let result = SnapshotStore.appendRunningCommandNotice(scrollback: "hello", runningCommand: "make build")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("make build"))
        XCTAssertTrue(result!.hasPrefix("hello\n"))
    }

    func testAppendRunningCommandNoticeWorksWithNilScrollback() {
        let result = SnapshotStore.appendRunningCommandNotice(scrollback: nil, runningCommand: "make build")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("make build"))
    }

    func testAppendRunningCommandNoticeReturnsNilWhenBothNil() {
        let result = SnapshotStore.appendRunningCommandNotice(scrollback: nil, runningCommand: nil)
        XCTAssertNil(result)
    }
}
