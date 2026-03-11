import Foundation
import XCTest
@testable import Trellis

final class GitStatusTests: XCTestCase {

    // MARK: - parsePorcelainLine

    func testParsesUntracked() {
        let result = GitFileStatus.parsePorcelainLine("?? src/new.swift", root: "/repo")
        XCTAssertEqual(result?.path, "/repo/src/new.swift")
        XCTAssertEqual(result?.status, .untracked)
    }

    func testParsesModifiedInWorkingTree() {
        let result = GitFileStatus.parsePorcelainLine(" M src/existing.swift", root: "/repo")
        XCTAssertEqual(result?.path, "/repo/src/existing.swift")
        XCTAssertEqual(result?.status, .modified)
    }

    func testParsesModifiedInIndex() {
        let result = GitFileStatus.parsePorcelainLine("M  src/existing.swift", root: "/repo")
        XCTAssertEqual(result?.path, "/repo/src/existing.swift")
        XCTAssertEqual(result?.status, .modified)
    }

    func testParsesAdded() {
        let result = GitFileStatus.parsePorcelainLine("A  src/staged.swift", root: "/repo")
        XCTAssertEqual(result?.path, "/repo/src/staged.swift")
        XCTAssertEqual(result?.status, .added)
    }

    func testParsesDeletedInIndex() {
        let result = GitFileStatus.parsePorcelainLine("D  src/gone.swift", root: "/repo")
        XCTAssertEqual(result?.path, "/repo/src/gone.swift")
        XCTAssertEqual(result?.status, .deleted)
    }

    func testParsesDeletedInWorkingTree() {
        let result = GitFileStatus.parsePorcelainLine(" D src/gone.swift", root: "/repo")
        XCTAssertEqual(result?.path, "/repo/src/gone.swift")
        XCTAssertEqual(result?.status, .deleted)
    }

    func testParsesRename() {
        let result = GitFileStatus.parsePorcelainLine("R  old.swift -> new.swift", root: "/repo")
        XCTAssertEqual(result?.path, "/repo/new.swift")
    }

    func testReturnsNilForBlankLine() {
        XCTAssertNil(GitFileStatus.parsePorcelainLine("", root: "/repo"))
    }

    func testReturnsNilForShortLine() {
        XCTAssertNil(GitFileStatus.parsePorcelainLine("??", root: "/repo"))
    }

    func testReturnsNilForUnrecognizedStatus() {
        // Lines with only spaces in XY (clean tracked file) should return nil
        XCTAssertNil(GitFileStatus.parsePorcelainLine("   clean.swift", root: "/repo"))
    }

    // MARK: - parse (full output)

    func testParsesMultipleLines() {
        let output = """
        ?? newfile.swift
        M  staged.swift
         M working.swift
        """
        let result = GitFileStatus.parse(porcelainOutput: output, root: "/repo")
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result["/repo/newfile.swift"], .untracked)
        XCTAssertEqual(result["/repo/staged.swift"], .modified)
        XCTAssertEqual(result["/repo/working.swift"], .modified)
    }

    func testParsesEmptyOutput() {
        let result = GitFileStatus.parse(porcelainOutput: "", root: "/repo")
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - dirtyDirectories

    func testDirtyDirectoriesPropagatesToParents() {
        let statuses: [String: GitFileStatus] = [
            "/repo/src/Models/Foo.swift": .modified
        ]
        let dirty = GitFileStatus.dirtyDirectories(from: statuses, root: "/repo")
        XCTAssertTrue(dirty.contains("/repo/src/Models"))
        XCTAssertTrue(dirty.contains("/repo/src"))
        XCTAssertTrue(dirty.contains("/repo"))
    }

    func testEmptyStatusesProduceNoDirtyDirectories() {
        let dirty = GitFileStatus.dirtyDirectories(from: [:], root: "/repo")
        XCTAssertTrue(dirty.isEmpty)
    }

    func testDirtyDirectoriesDoesNotExceedRoot() {
        let statuses: [String: GitFileStatus] = ["/repo/file.swift": .untracked]
        let dirty = GitFileStatus.dirtyDirectories(from: statuses, root: "/repo")
        XCTAssertTrue(dirty.contains("/repo"))
        XCTAssertFalse(dirty.contains("/"))
    }

    func testMultipleFilesInSameDirectory() {
        let statuses: [String: GitFileStatus] = [
            "/repo/src/A.swift": .modified,
            "/repo/src/B.swift": .untracked
        ]
        let dirty = GitFileStatus.dirtyDirectories(from: statuses, root: "/repo")
        XCTAssertTrue(dirty.contains("/repo/src"))
        XCTAssertTrue(dirty.contains("/repo"))
    }
}
