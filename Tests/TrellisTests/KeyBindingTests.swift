import Foundation
import XCTest
@testable import Trellis

final class KeyBindingTests: XCTestCase {

    // MARK: - KeyCombo parsing

    func testParseSingleModifierAndKey() {
        let combo = KeyCombo.parse("cmd+d")
        XCTAssertEqual(combo, KeyCombo(modifiers: [.command], key: "d"))
    }

    func testParseTwoModifiers() {
        let combo = KeyCombo.parse("cmd+shift+d")
        XCTAssertEqual(combo, KeyCombo(modifiers: [.command, .shift], key: "d"))
    }

    func testParseThreeModifiers() {
        let combo = KeyCombo.parse("cmd+ctrl+shift+f")
        XCTAssertEqual(combo, KeyCombo(modifiers: [.command, .control, .shift], key: "f"))
    }

    func testParseOptionModifier() {
        let combo = KeyCombo.parse("opt+a")
        XCTAssertEqual(combo, KeyCombo(modifiers: [.option], key: "a"))
    }

    func testParseAltAlias() {
        let combo = KeyCombo.parse("alt+a")
        XCTAssertEqual(combo, KeyCombo(modifiers: [.option], key: "a"))
    }

    func testParseCaseInsensitive() {
        let combo = KeyCombo.parse("Cmd+Shift+D")
        XCTAssertEqual(combo, KeyCombo(modifiers: [.command, .shift], key: "d"))
    }

    func testParseInvalidReturnsNil() {
        XCTAssertNil(KeyCombo.parse(""))
        XCTAssertNil(KeyCombo.parse("cmd"))      // no key
        XCTAssertNil(KeyCombo.parse("d"))         // no modifier
        XCTAssertNil(KeyCombo.parse("cmd+"))      // trailing +
    }

    func testParseSpecialKeys() {
        XCTAssertEqual(KeyCombo.parse("cmd+plus"), KeyCombo(modifiers: [.command], key: "+"))
        XCTAssertEqual(KeyCombo.parse("cmd+minus"), KeyCombo(modifiers: [.command], key: "-"))
        XCTAssertEqual(KeyCombo.parse("cmd+equal"), KeyCombo(modifiers: [.command], key: "="))
        XCTAssertEqual(KeyCombo.parse("cmd+comma"), KeyCombo(modifiers: [.command], key: ","))
    }

    // MARK: - KeyCombo serialization

    func testSerializeSingleModifier() {
        let combo = KeyCombo(modifiers: [.command], key: "d")
        XCTAssertEqual(combo.serialize(), "cmd+d")
    }

    func testSerializeTwoModifiers() {
        let combo = KeyCombo(modifiers: [.command, .shift], key: "d")
        XCTAssertEqual(combo.serialize(), "cmd+shift+d")
    }

    func testSerializeSpecialKeys() {
        let combo = KeyCombo(modifiers: [.command], key: "+")
        XCTAssertEqual(combo.serialize(), "cmd+plus")
    }

    // MARK: - KeyCombo round-trip

    func testRoundTrip() {
        let inputs = ["cmd+d", "cmd+shift+d", "cmd+ctrl+f", "opt+a", "cmd+plus", "cmd+minus"]
        for input in inputs {
            let combo = KeyCombo.parse(input)
            XCTAssertNotNil(combo, "Failed to parse: \(input)")
            XCTAssertEqual(combo?.serialize(), input, "Round-trip failed for: \(input)")
        }
    }

    // MARK: - BindableAction

    func testBindableActionFromString() {
        XCTAssertEqual(BindableAction(rawValue: "split_horizontal"), .splitHorizontal)
        XCTAssertEqual(BindableAction(rawValue: "toggle_sidebar"), .toggleSidebar)
        XCTAssertEqual(BindableAction(rawValue: "close_tab"), .closeTab)
    }

    func testBindableActionSerialize() {
        XCTAssertEqual(BindableAction.splitHorizontal.rawValue, "split_horizontal")
        XCTAssertEqual(BindableAction.toggleSidebar.rawValue, "toggle_sidebar")
    }

    // MARK: - KeyBindingMap

    func testLookupByCombo() {
        let bindings = KeyBindingMap(bindings: [
            KeyBinding(combo: KeyCombo(modifiers: [.command], key: "d"), action: .splitHorizontal),
            KeyBinding(combo: KeyCombo(modifiers: [.command, .shift], key: "d"), action: .splitVertical),
        ])
        XCTAssertEqual(
            bindings.action(for: KeyCombo(modifiers: [.command], key: "d")),
            .splitHorizontal
        )
        XCTAssertEqual(
            bindings.action(for: KeyCombo(modifiers: [.command, .shift], key: "d")),
            .splitVertical
        )
    }

    func testLookupMissingReturnsNil() {
        let bindings = KeyBindingMap(bindings: [])
        XCTAssertNil(bindings.action(for: KeyCombo(modifiers: [.command], key: "z")))
    }

    func testComboForAction() {
        let bindings = KeyBindingMap(bindings: [
            KeyBinding(combo: KeyCombo(modifiers: [.command], key: "b"), action: .toggleSidebar),
        ])
        XCTAssertEqual(
            bindings.combo(for: .toggleSidebar),
            KeyCombo(modifiers: [.command], key: "b")
        )
    }

    // MARK: - Config format parsing

    func testParseKeybindConfigLine() {
        let binding = KeyBinding.parse("cmd+d=split_horizontal")
        XCTAssertEqual(binding?.combo, KeyCombo(modifiers: [.command], key: "d"))
        XCTAssertEqual(binding?.action, .splitHorizontal)
    }

    func testParseKeybindConfigLineWithSpaces() {
        let binding = KeyBinding.parse("cmd+shift+d = split_vertical")
        XCTAssertEqual(binding?.combo, KeyCombo(modifiers: [.command, .shift], key: "d"))
        XCTAssertEqual(binding?.action, .splitVertical)
    }

    func testParseInvalidKeybindConfigLine() {
        XCTAssertNil(KeyBinding.parse("invalid"))
        XCTAssertNil(KeyBinding.parse("cmd+d=unknown_action"))
        XCTAssertNil(KeyBinding.parse("=split_horizontal"))
    }

    func testSerializeKeybindConfigLine() {
        let binding = KeyBinding(
            combo: KeyCombo(modifiers: [.command], key: "d"),
            action: .splitHorizontal
        )
        XCTAssertEqual(binding.serialize(), "cmd+d=split_horizontal")
    }

    // MARK: - Default bindings

    func testDefaultBindingsIncludeCommonShortcuts() {
        let defaults = KeyBindingMap.defaults
        XCTAssertEqual(defaults.action(for: KeyCombo(modifiers: [.command], key: "d")), .splitHorizontal)
        XCTAssertEqual(defaults.action(for: KeyCombo(modifiers: [.command, .shift], key: "d")), .splitVertical)
        XCTAssertEqual(defaults.action(for: KeyCombo(modifiers: [.command], key: "b")), .toggleSidebar)
        XCTAssertEqual(defaults.action(for: KeyCombo(modifiers: [.command], key: "w")), .closeTab)
        XCTAssertEqual(defaults.action(for: KeyCombo(modifiers: [.command, .shift], key: "w")), .closeArea)
    }

    // MARK: - Merge user bindings over defaults

    func testUserBindingsOverrideDefaults() {
        let userBindings = [
            KeyBinding(combo: KeyCombo(modifiers: [.command], key: "d"), action: .closeTab),
        ]
        let merged = KeyBindingMap.defaults.merging(userBindings)
        XCTAssertEqual(
            merged.action(for: KeyCombo(modifiers: [.command], key: "d")),
            .closeTab
        )
        // Other defaults still present
        XCTAssertEqual(
            merged.action(for: KeyCombo(modifiers: [.command], key: "b")),
            .toggleSidebar
        )
    }
}
