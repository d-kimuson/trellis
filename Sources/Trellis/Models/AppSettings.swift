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

    // MARK: - Init

    private init() {
        let storedSize = UserDefaults.standard.double(forKey: Keys.fontSize)
        fontSize = storedSize > 0 ? storedSize : 13
        fontFamily = UserDefaults.standard.string(forKey: Keys.fontFamily) ?? ""
    }

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let fontFamily = "trellis.fontFamily"
        static let fontSize = "trellis.fontSize"
    }
}
