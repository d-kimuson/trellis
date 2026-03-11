import XCTest
@testable import OreoreTerminal

final class GhosttyFontSizeChangeTests: XCTestCase {

    func testIncreaseBindingAction() {
        XCTAssertEqual(
            GhosttyFontSizeChange.increase(1).bindingAction,
            "increase_font_size:1"
        )
    }

    func testDecreaseBindingAction() {
        XCTAssertEqual(
            GhosttyFontSizeChange.decrease(1).bindingAction,
            "decrease_font_size:1"
        )
    }

    func testResetBindingAction() {
        XCTAssertEqual(
            GhosttyFontSizeChange.reset.bindingAction,
            "reset_font_size"
        )
    }
}
