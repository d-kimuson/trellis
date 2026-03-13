import Foundation
import XCTest
@testable import Trellis

final class ConfigFileTests: XCTestCase {

    // MARK: - Parse empty / blank

    func testParseEmptyStringReturnsNoKeyValues() {
        let config = ConfigFile.parse("")
        XCTAssertNil(config.string(forKey: "anything"))
    }

    func testParseBlankLinesAndCommentsOnly() {
        let text = "# This is a comment\n\n# Another comment"
        let config = ConfigFile.parse(text)
        XCTAssertNil(config.string(forKey: "anything"))
        XCTAssertNil(config.double(forKey: "anything"))
    }

    // MARK: - Parse string values

    func testParseQuotedString() {
        let config = ConfigFile.parse(#"name = "Trellis""#)
        XCTAssertEqual(config.string(forKey: "name"), "Trellis")
    }

    func testParseEmptyQuotedString() {
        let config = ConfigFile.parse(#"name = """#)
        XCTAssertEqual(config.string(forKey: "name"), "")
    }

    // MARK: - Parse numeric values

    func testParseInteger() {
        let config = ConfigFile.parse("font-size = 14")
        XCTAssertEqual(config.double(forKey: "font-size"), 14)
    }

    func testParseFloat() {
        let config = ConfigFile.parse("font-size = 13.5")
        XCTAssertEqual(config.double(forKey: "font-size"), 13.5)
    }

    // MARK: - Parse boolean values

    func testParseBoolTrue() {
        let config = ConfigFile.parse("enabled = true")
        XCTAssertEqual(config.bool(forKey: "enabled"), true)
    }

    func testParseBoolFalse() {
        let config = ConfigFile.parse("enabled = false")
        XCTAssertEqual(config.bool(forKey: "enabled"), false)
    }

    // MARK: - Missing keys

    func testStringForMissingKeyReturnsNil() {
        let config = ConfigFile.parse("")
        XCTAssertNil(config.string(forKey: "missing"))
    }

    func testDoubleForMissingKeyReturnsNil() {
        let config = ConfigFile.parse("")
        XCTAssertNil(config.double(forKey: "missing"))
    }

    func testBoolForMissingKeyReturnsNil() {
        let config = ConfigFile.parse("")
        XCTAssertNil(config.bool(forKey: "missing"))
    }

    // MARK: - Comments and whitespace preserved in serialize

    func testSerializePreservesComments() {
        let text = """
        # General settings
        font-size = 13
        """
        var config = ConfigFile.parse(text)
        config.set(.integer(14), forKey: "font-size")
        let output = config.serialize()
        XCTAssertTrue(output.contains("# General settings"))
        XCTAssertTrue(output.contains("font-size = 14"))
    }

    // MARK: - Serialize round-trip

    func testRoundTrip() {
        let text = """
        # Config
        font-family = "Menlo"
        font-size = 14
        enabled = true
        """
        let config = ConfigFile.parse(text)
        let output = config.serialize()
        let reparsed = ConfigFile.parse(output)
        XCTAssertEqual(reparsed.string(forKey: "font-family"), "Menlo")
        XCTAssertEqual(reparsed.double(forKey: "font-size"), 14)
        XCTAssertEqual(reparsed.bool(forKey: "enabled"), true)
    }

    // MARK: - Set new key

    func testSetNewKeyAppendsToEnd() {
        var config = ConfigFile.parse("font-size = 13")
        config.set(.string("Menlo"), forKey: "font-family")
        let output = config.serialize()
        XCTAssertTrue(output.contains(#"font-family = "Menlo""#))
    }

    // MARK: - Inline comments

    func testParseIgnoresInlineComments() {
        let config = ConfigFile.parse("font-size = 14 # points")
        XCTAssertEqual(config.double(forKey: "font-size"), 14)
    }

    // MARK: - Whitespace around equals

    func testParseToleratesVariousWhitespace() {
        let config = ConfigFile.parse("key=42")
        XCTAssertEqual(config.double(forKey: "key"), 42)
    }

    // MARK: - File I/O

    func testLoadAndSaveToFile() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let url = tmpDir.appendingPathComponent("config.toml")

        var config = ConfigFile.empty
        config.set(.string("Menlo"), forKey: "font-family")
        config.set(.integer(14), forKey: "font-size")
        config.set(.bool(true), forKey: "ipc-enabled")
        try config.save(to: url)

        let loaded = try ConfigFile.load(from: url)
        XCTAssertEqual(loaded.string(forKey: "font-family"), "Menlo")
        XCTAssertEqual(loaded.double(forKey: "font-size"), 14)
        XCTAssertEqual(loaded.bool(forKey: "ipc-enabled"), true)
    }

    // MARK: - Multi-value keys

    func testStringsForKeyReturnsAllValues() {
        let text = """
        keybind = "cmd+d=split_horizontal"
        keybind = "cmd+shift+d=split_vertical"
        """
        let config = ConfigFile.parse(text)
        let values = config.strings(forKey: "keybind")
        XCTAssertEqual(values.count, 2)
        XCTAssertTrue(values.contains("cmd+d=split_horizontal"))
        XCTAssertTrue(values.contains("cmd+shift+d=split_vertical"))
    }

    func testSetAllReplacesExistingEntries() {
        var config = ConfigFile.parse(#"keybind = "cmd+d=split_horizontal""#)
        config.setAll(["cmd+b=toggle_sidebar"], forKey: "keybind")
        let values = config.strings(forKey: "keybind")
        XCTAssertEqual(values, ["cmd+b=toggle_sidebar"])
    }

    func testLoadNonexistentFileReturnsEmpty() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("nonexistent.toml")
        let config = try ConfigFile.load(from: url)
        XCTAssertNil(config.string(forKey: "anything"))
    }
}
