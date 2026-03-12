import Foundation
import XCTest
@testable import Trellis

@MainActor
final class AppSettingsTests: XCTestCase {

    private func makeSettings() -> AppSettings {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        return AppSettings(defaults: defaults)
    }

    // MARK: - Default values

    func testDefaultFontSizeIs13() {
        let settings = makeSettings()
        XCTAssertEqual(settings.fontSize, 13)
    }

    func testDefaultFontFamilyIsEmpty() {
        let settings = makeSettings()
        XCTAssertEqual(settings.fontFamily, "")
    }

    func testDefaultPanelFontSizeIs13() {
        let settings = makeSettings()
        XCTAssertEqual(settings.panelFontSize, 13)
    }

    func testDefaultIpcServerEnabledIsFalse() {
        let settings = makeSettings()
        XCTAssertFalse(settings.ipcServerEnabled)
    }

    // MARK: - Persistence

    func testFontSizeIsPersisted() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!

        let settings1 = AppSettings(defaults: defaults)
        settings1.fontSize = 18

        let settings2 = AppSettings(defaults: defaults)
        XCTAssertEqual(settings2.fontSize, 18)
    }

    func testFontFamilyIsPersisted() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!

        let settings1 = AppSettings(defaults: defaults)
        settings1.fontFamily = "Menlo"

        let settings2 = AppSettings(defaults: defaults)
        XCTAssertEqual(settings2.fontFamily, "Menlo")
    }

    func testPanelFontSizeIsPersisted() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!

        let settings1 = AppSettings(defaults: defaults)
        settings1.panelFontSize = 16

        let settings2 = AppSettings(defaults: defaults)
        XCTAssertEqual(settings2.panelFontSize, 16)
    }

    func testIpcServerEnabledIsPersisted() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!

        let settings1 = AppSettings(defaults: defaults)
        settings1.ipcServerEnabled = true

        let settings2 = AppSettings(defaults: defaults)
        XCTAssertTrue(settings2.ipcServerEnabled)
    }

    // MARK: - Isolation

    func testSeparateInstancesAreIsolated() {
        let settings1 = makeSettings()
        let settings2 = makeSettings()

        settings1.fontSize = 20
        XCTAssertEqual(settings2.fontSize, 13)
    }
}
