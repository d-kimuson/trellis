import Testing

@testable import Trellis

@Suite("DiffReviewFormatter")
struct DiffReviewFormatterTests {
    @Test("single line comment formats correctly")
    func singleLineComment() {
        let comments = [
            DiffReviewComment(lineNumber: 405, text: "このファイルもう不要そう")
        ]
        let result = DiffReviewFormatter.format(
            filePath: "Sources/Trellis/GhosttyApp.swift",
            comments: comments
        )
        #expect(result == """
        Sources/Trellis/GhosttyApp.swift:L405
        このファイルもう不要そう
        """)
    }

    @Test("multiple comments separated by blank line")
    func multipleComments() {
        let comments = [
            DiffReviewComment(lineNumber: 12, text: "この変数名わかりにくい"),
            DiffReviewComment(lineNumber: 45, text: "ここのロジック見直したい")
        ]
        let result = DiffReviewFormatter.format(
            filePath: "Sources/Trellis/Models/Workspace.swift",
            comments: comments
        )
        #expect(result == """
        Sources/Trellis/Models/Workspace.swift:L12
        この変数名わかりにくい

        Sources/Trellis/Models/Workspace.swift:L45
        ここのロジック見直したい
        """)
    }

    @Test("empty comments returns empty string")
    func emptyComments() {
        let result = DiffReviewFormatter.format(
            filePath: "foo.swift",
            comments: []
        )
        #expect(result.isEmpty)
    }

    @Test("comments are sorted by line number")
    func sortedByLineNumber() {
        let comments = [
            DiffReviewComment(lineNumber: 100, text: "second"),
            DiffReviewComment(lineNumber: 10, text: "first")
        ]
        let result = DiffReviewFormatter.format(
            filePath: "file.swift",
            comments: comments
        )
        #expect(result == """
        file.swift:L10
        first

        file.swift:L100
        second
        """)
    }
}
