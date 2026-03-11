import Foundation

/// App-level settings persisted to UserDefaults.
/// Font settings are also written to the ghostty config file on apply.
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    // MARK: - Font (written to ghostty config)

    @Published public var fontFamily: String {
        didSet { UserDefaults.standard.set(fontFamily, forKey: Keys.fontFamily) }
    }

    @Published public var fontSize: Double {
        didSet { UserDefaults.standard.set(fontSize, forKey: Keys.fontSize) }
    }

    // MARK: - Panel Font Size (applies to non-terminal panels like file tree)

    @Published public var panelFontSize: Double {
        didSet { UserDefaults.standard.set(panelFontSize, forKey: Keys.panelFontSize) }
    }

    // MARK: - IPC Server

    @Published public var ipcServerEnabled: Bool {
        didSet { UserDefaults.standard.set(ipcServerEnabled, forKey: Keys.ipcServerEnabled) }
    }

    // MARK: - Init

    private init() {
        let storedSize = UserDefaults.standard.double(forKey: Keys.fontSize)
        fontSize = storedSize > 0 ? storedSize : 13
        fontFamily = UserDefaults.standard.string(forKey: Keys.fontFamily) ?? ""
        let storedPanelSize = UserDefaults.standard.double(forKey: Keys.panelFontSize)
        panelFontSize = storedPanelSize > 0 ? storedPanelSize : 13
        ipcServerEnabled = UserDefaults.standard.bool(forKey: Keys.ipcServerEnabled)
    }

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let fontFamily = "trellis.fontFamily"
        static let fontSize = "trellis.fontSize"
        static let panelFontSize = "trellis.panelFontSize"
        static let ipcServerEnabled = "trellis.ipcServerEnabled"
    }
}
