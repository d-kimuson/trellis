import Foundation
import Observation

/// App-level settings persisted to a TOML config file (`~/.config/trellis/config.toml`).
/// Font settings are also written to the ghostty config file on apply.
@Observable
@MainActor
public final class AppSettings {
    public static let shared = AppSettings()

    @ObservationIgnored private let configURL: URL

    // MARK: - Font (written to ghostty config)

    public var fontFamily: String {
        didSet { save() }
    }

    public var fontSize: Double {
        didSet { save() }
    }

    // MARK: - Panel Font Size (applies to non-terminal panels like file tree)

    public var panelFontSize: Double {
        didSet { save() }
    }

    // MARK: - IPC Server

    public var ipcServerEnabled: Bool {
        didSet { save() }
    }

    // MARK: - Config location

    public static var defaultConfigURL: URL {
        let xdgConfig = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
            .map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config")
        return xdgConfig.appendingPathComponent("trellis/config.toml")
    }

    // MARK: - Init

    public init(configURL: URL? = nil) {
        let url = configURL ?? Self.defaultConfigURL
        self.configURL = url

        let config = (try? ConfigFile.load(from: url)) ?? .empty
        let storedSize = config.double(forKey: Keys.fontSize)
        fontSize = storedSize.map { $0 > 0 ? $0 : 13 } ?? 13
        fontFamily = config.string(forKey: Keys.fontFamily) ?? ""
        let storedPanelSize = config.double(forKey: Keys.panelFontSize)
        panelFontSize = storedPanelSize.map { $0 > 0 ? $0 : 13 } ?? 13
        ipcServerEnabled = config.bool(forKey: Keys.ipcServerEnabled) ?? false
    }

    // MARK: - Migration from UserDefaults

    /// Migrates settings from UserDefaults to the config file if the file does not exist yet.
    /// Call once at app startup.
    public static func migrateFromUserDefaultsIfNeeded(
        defaults: UserDefaults = .standard,
        configURL: URL? = nil
    ) {
        let url = configURL ?? defaultConfigURL
        guard !FileManager.default.fileExists(atPath: url.path) else { return }

        let hasLegacy = defaults.object(forKey: LegacyKeys.fontSize) != nil
            || defaults.object(forKey: LegacyKeys.fontFamily) != nil
            || defaults.object(forKey: LegacyKeys.panelFontSize) != nil
            || defaults.object(forKey: LegacyKeys.ipcServerEnabled) != nil
        guard hasLegacy else { return }

        var config = ConfigFile.empty
        let storedSize = defaults.double(forKey: LegacyKeys.fontSize)
        if storedSize > 0 {
            config.set(.double(storedSize), forKey: Keys.fontSize)
        }
        let family = defaults.string(forKey: LegacyKeys.fontFamily) ?? ""
        if !family.isEmpty {
            config.set(.string(family), forKey: Keys.fontFamily)
        }
        let panelSize = defaults.double(forKey: LegacyKeys.panelFontSize)
        if panelSize > 0 {
            config.set(.double(panelSize), forKey: Keys.panelFontSize)
        }
        if defaults.bool(forKey: LegacyKeys.ipcServerEnabled) {
            config.set(.bool(true), forKey: Keys.ipcServerEnabled)
        }
        try? config.save(to: url)
    }

    // MARK: - Private

    private func save() {
        var config = (try? ConfigFile.load(from: configURL)) ?? .empty
        config.set(.string(fontFamily), forKey: Keys.fontFamily)
        config.set(.double(fontSize), forKey: Keys.fontSize)
        config.set(.double(panelFontSize), forKey: Keys.panelFontSize)
        config.set(.bool(ipcServerEnabled), forKey: Keys.ipcServerEnabled)
        try? config.save(to: configURL)
    }

    // MARK: - Config keys

    private enum Keys {
        static let fontFamily = "font-family"
        static let fontSize = "font-size"
        static let panelFontSize = "panel-font-size"
        static let ipcServerEnabled = "ipc-server-enabled"
    }

    // MARK: - Legacy UserDefaults keys (for migration)

    private enum LegacyKeys {
        static let fontFamily = "trellis.fontFamily"
        static let fontSize = "trellis.fontSize"
        static let panelFontSize = "trellis.panelFontSize"
        static let ipcServerEnabled = "trellis.ipcServerEnabled"
    }
}
