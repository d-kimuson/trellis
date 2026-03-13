import XCTest
@testable import Trellis

final class SyntaxHighlightWebViewTests: XCTestCase {

    // MARK: - languageForExtension

    func testKnownLanguageExtensions() {
        let cases: [(String, String)] = [
            ("swift", "swift"),
            ("js", "javascript"),
            ("jsx", "javascript"),
            ("ts", "typescript"),
            ("tsx", "typescript"),
            ("py", "python"),
            ("rb", "ruby"),
            ("sh", "bash"),
            ("bash", "bash"),
            ("zsh", "bash"),
            ("json", "json"),
            ("yaml", "yaml"),
            ("yml", "yaml"),
            ("toml", "toml"),
            ("md", "markdown"),
            ("html", "html"),
            ("css", "css"),
            ("rs", "rust"),
            ("go", "go"),
            ("java", "java"),
            ("c", "c"),
            ("cpp", "cpp"),
            ("h", "cpp"),
            ("cs", "csharp"),
            ("kt", "kotlin"),
            ("sql", "sql"),
            ("xml", "xml"),
            ("plist", "xml"),
            ("zig", "zig")
        ]
        for (ext, expected) in cases {
            XCTAssertEqual(
                SyntaxHighlightWebView.languageForExtension(ext),
                expected,
                "Extension '\(ext)' should map to '\(expected)'"
            )
        }
    }

    func testUnknownExtensionReturnsEmpty() {
        XCTAssertEqual(SyntaxHighlightWebView.languageForExtension("xyz"), "")
        XCTAssertEqual(SyntaxHighlightWebView.languageForExtension(""), "")
        XCTAssertEqual(SyntaxHighlightWebView.languageForExtension("bin"), "")
    }

    // MARK: - escapeJS

    func testEscapeJSBasic() {
        XCTAssertEqual(SyntaxHighlightWebView.escapeJS("hello"), "hello")
        XCTAssertEqual(SyntaxHighlightWebView.escapeJS("back\\slash"), "back\\\\slash")
        XCTAssertEqual(SyntaxHighlightWebView.escapeJS("say \"hi\""), "say \\\"hi\\\"")
        XCTAssertEqual(SyntaxHighlightWebView.escapeJS("line1\nline2"), "line1\\nline2")
        XCTAssertEqual(SyntaxHighlightWebView.escapeJS("line1\rline2"), "line1\\rline2")
    }

    func testEscapeJSScriptTag() {
        XCTAssertEqual(SyntaxHighlightWebView.escapeJS("</script>"), "<\\/script>")
        XCTAssertEqual(SyntaxHighlightWebView.escapeJS("</SCRIPT>"), "<\\/script>")
        XCTAssertEqual(SyntaxHighlightWebView.escapeJS("foo</script>bar"), "foo<\\/script>bar")
        XCTAssertEqual(SyntaxHighlightWebView.escapeJS("nested</script></script>"), "nested<\\/script><\\/script>")
    }

}
