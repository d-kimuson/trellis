@testable import Trellis
import XCTest

final class ShellQuotingTests: XCTestCase {
    func testSimplePath() {
        XCTAssertEqual(shellQuotePath("src/main.swift"), "src/main.swift")
    }

    func testPathWithSpaces() {
        XCTAssertEqual(shellQuotePath("my project/file.txt"), "'my project/file.txt'")
    }

    func testPathWithSingleQuote() {
        XCTAssertEqual(shellQuotePath("it's a file"), "'it'\\''s a file'")
    }

    func testPathWithParentheses() {
        XCTAssertEqual(shellQuotePath("docs (copy)/file"), "'docs (copy)/file'")
    }

    func testPathWithDollarSign() {
        XCTAssertEqual(shellQuotePath("$HOME/file"), "'$HOME/file'")
    }

    func testEmptyPath() {
        XCTAssertEqual(shellQuotePath(""), "''")
    }

    func testPathWithMultipleSpecialChars() {
        XCTAssertEqual(shellQuotePath("a b&c|d"), "'a b&c|d'")
    }

    func testAlreadySafePath() {
        XCTAssertEqual(shellQuotePath("src/Models/FileNode.swift"), "src/Models/FileNode.swift")
    }

    func testPathWithHyphenAndUnderscore() {
        XCTAssertEqual(shellQuotePath("my-file_name.txt"), "my-file_name.txt")
    }

    func testPathWithDot() {
        XCTAssertEqual(shellQuotePath(".hidden/file"), ".hidden/file")
    }

    // MARK: - relativePath

    func testRelativePathSimple() {
        XCTAssertEqual(
            relativeFilePath(filePath: "/Users/me/project/src/main.swift", base: "/Users/me/project"),
            "src/main.swift"
        )
    }

    func testRelativePathBaseWithTrailingSlash() {
        XCTAssertEqual(
            relativeFilePath(filePath: "/Users/me/project/src/main.swift", base: "/Users/me/project/"),
            "src/main.swift"
        )
    }

    func testRelativePathSameDirectory() {
        XCTAssertEqual(
            relativeFilePath(filePath: "/Users/me/project/file.txt", base: "/Users/me/project"),
            "file.txt"
        )
    }

    func testRelativePathNoCommonPrefix() {
        XCTAssertEqual(
            relativeFilePath(filePath: "/other/path/file.txt", base: "/Users/me/project"),
            "/other/path/file.txt"
        )
    }

    func testRelativePathNilBase() {
        XCTAssertEqual(
            relativeFilePath(filePath: "/Users/me/project/file.txt", base: nil),
            "/Users/me/project/file.txt"
        )
    }

    // MARK: - formatDroppedPaths

    func testFormatSinglePath() {
        let result = formatDroppedPaths(
            filePaths: ["/Users/me/project/src/main.swift"],
            base: "/Users/me/project"
        )
        XCTAssertEqual(result, "src/main.swift")
    }

    func testFormatMultiplePaths() {
        let result = formatDroppedPaths(
            filePaths: [
                "/Users/me/project/src/main.swift",
                "/Users/me/project/src/util.swift",
            ],
            base: "/Users/me/project"
        )
        XCTAssertEqual(result, "src/main.swift src/util.swift")
    }

    func testFormatMultiplePathsWithSpaces() {
        let result = formatDroppedPaths(
            filePaths: [
                "/Users/me/project/my file.txt",
                "/Users/me/project/normal.txt",
            ],
            base: "/Users/me/project"
        )
        XCTAssertEqual(result, "'my file.txt' normal.txt")
    }
}
