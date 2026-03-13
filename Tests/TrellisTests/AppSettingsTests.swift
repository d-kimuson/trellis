import Foundation
import XCTest
@testable import Trellis

@MainActor
final class AppSettingsTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppSettingsTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    private func configURL() -> URL {
        tmpDir.appendingPathComponent("config.toml")
    }

    private func makeSettings() -> AppSettings {
        AppSettings(configURL: configURL())
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
        let url = configURL()
        let settings1 = AppSettings(configURL: url)
        settings1.fontSize = 18

        let settings2 = AppSettings(configURL: url)
        XCTAssertEqual(settings2.fontSize, 18)
    }

    func testFontFamilyIsPersisted() {
        let url = configURL()
        let settings1 = AppSettings(configURL: url)
        settings1.fontFamily = "Menlo"

        let settings2 = AppSettings(configURL: url)
        XCTAssertEqual(settings2.fontFamily, "Menlo")
    }

    func testPanelFontSizeIsPersisted() {
        let url = configURL()
        let settings1 = AppSettings(configURL: url)
        settings1.panelFontSize = 16

        let settings2 = AppSettings(configURL: url)
        XCTAssertEqual(settings2.panelFontSize, 16)
    }

    func testIpcServerEnabledIsPersisted() {
        let url = configURL()
        let settings1 = AppSettings(configURL: url)
        settings1.ipcServerEnabled = true

        let settings2 = AppSettings(configURL: url)
        XCTAssertTrue(settings2.ipcServerEnabled)
    }

    // MARK: - Isolation

    func testSeparateInstancesAreIsolated() {
        let url1 = tmpDir.appendingPathComponent("config1.toml")
        let url2 = tmpDir.appendingPathComponent("config2.toml")

        let settings1 = AppSettings(configURL: url1)
        let settings2 = AppSettings(configURL: url2)

        settings1.fontSize = 20
        XCTAssertEqual(settings2.fontSize, 13)
    }

    // MARK: - Config file content

    func testConfigFileIsTOML() throws {
        let url = configURL()
        let settings = AppSettings(configURL: url)
        settings.fontFamily = "JetBrains Mono"
        settings.fontSize = 15

        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.contains(#"font-family = "JetBrains Mono""#))
        XCTAssertTrue(content.contains("font-size = 15.0"))
    }

    // MARK: - Migration from UserDefaults

    func testMigrateFromUserDefaults() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(18.0, forKey: "trellis.fontSize")
        defaults.set("Menlo", forKey: "trellis.fontFamily")
        defaults.set(16.0, forKey: "trellis.panelFontSize")
        defaults.set(true, forKey: "trellis.ipcServerEnabled")

        let url = configURL()
        AppSettings.migrateFromUserDefaultsIfNeeded(defaults: defaults, configURL: url)

        let settings = AppSettings(configURL: url)
        XCTAssertEqual(settings.fontSize, 18)
        XCTAssertEqual(settings.fontFamily, "Menlo")
        XCTAssertEqual(settings.panelFontSize, 16)
        XCTAssertTrue(settings.ipcServerEnabled)

        defaults.removePersistentDomain(forName: suite)
    }

    func testMigrateSkipsWhenConfigExists() throws {
        let url = configURL()

        // Write existing config
        var config = ConfigFile.empty
        config.set(.double(20), forKey: "font-size")
        try config.save(to: url)

        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(14.0, forKey: "trellis.fontSize")

        AppSettings.migrateFromUserDefaultsIfNeeded(defaults: defaults, configURL: url)

        let settings = AppSettings(configURL: url)
        XCTAssertEqual(settings.fontSize, 20) // config file value preserved

        defaults.removePersistentDomain(forName: suite)
    }
}
