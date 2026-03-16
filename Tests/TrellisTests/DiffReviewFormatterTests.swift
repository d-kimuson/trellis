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

    @Test("review JS falls back to line-num1 when line-num2 is empty")
    func jsContainsFallbackLogic() {
        let js = DiffReviewScripts.js
        #expect(js.contains("__getLineNum"))
        #expect(js.contains("line-num2"))
        #expect(js.contains("line-num1"))
    }

    @Test("review CSS includes add button styles")
    func cssContainsAddButton() {
        let css = DiffReviewScripts.css
        #expect(css.contains(".review-add-btn"))
        #expect(css.contains("d2h-code-linenumber:hover .review-add-btn"))
    }

    @Test("review JS injects add buttons into line number cells")
    func jsInjectsAddButtons() {
        let js = DiffReviewScripts.js
        #expect(js.contains("__injectAddButtons"))
        #expect(js.contains("review-add-btn"))
    }
}
