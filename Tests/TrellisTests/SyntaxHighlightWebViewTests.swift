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
}
