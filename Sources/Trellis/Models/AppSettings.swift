import Foundation
import Observation

/// App-level settings persisted to UserDefaults.
/// Font settings are also written to the ghostty config file on apply.
@Observable
@MainActor
public final class AppSettings {
    public static let shared = AppSettings()

    @ObservationIgnored private let defaults: UserDefaults

    // MARK: - Font (written to ghostty config)

    public var fontFamily: String {
        didSet { defaults.set(fontFamily, forKey: Keys.fontFamily) }
    }

    public var fontSize: Double {
        didSet { defaults.set(fontSize, forKey: Keys.fontSize) }
    }

    // MARK: - Panel Font Size (applies to non-terminal panels like file tree)

    public var panelFontSize: Double {
        didSet { defaults.set(panelFontSize, forKey: Keys.panelFontSize) }
    }

    // MARK: - IPC Server

    public var ipcServerEnabled: Bool {
        didSet { defaults.set(ipcServerEnabled, forKey: Keys.ipcServerEnabled) }
    }

    // MARK: - Init

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedSize = defaults.double(forKey: Keys.fontSize)
        fontSize = storedSize > 0 ? storedSize : 13
        fontFamily = defaults.string(forKey: Keys.fontFamily) ?? ""
        let storedPanelSize = defaults.double(forKey: Keys.panelFontSize)
        panelFontSize = storedPanelSize > 0 ? storedPanelSize : 13
        ipcServerEnabled = defaults.bool(forKey: Keys.ipcServerEnabled)
    }

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let fontFamily = "trellis.fontFamily"
        static let fontSize = "trellis.fontSize"
        static let panelFontSize = "trellis.panelFontSize"
        static let ipcServerEnabled = "trellis.ipcServerEnabled"
    }
}
