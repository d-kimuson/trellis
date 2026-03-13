import AppKit
import Foundation

// MARK: - Modifier

public struct KeyModifier: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let command = KeyModifier(rawValue: 1 << 0)
    public static let shift   = KeyModifier(rawValue: 1 << 1)
    public static let control = KeyModifier(rawValue: 1 << 2)
    public static let option  = KeyModifier(rawValue: 1 << 3)

    /// Ordered list for consistent serialization.
    static let ordered: [(KeyModifier, String)] = [
        (.command, "cmd"),
        (.shift, "shift"),
        (.control, "ctrl"),
        (.option, "opt"),
    ]

    /// All known modifier name → value mappings (including aliases).
    static let nameMap: [String: KeyModifier] = [
        "cmd": .command, "command": .command,
        "shift": .shift,
        "ctrl": .control, "control": .control,
        "opt": .option, "option": .option, "alt": .option,
    ]
}

// MARK: - KeyCombo

public struct KeyCombo: Hashable, Sendable {
    public let modifiers: KeyModifier
    public let key: String  // lowercased single character or special name

    public init(modifiers: KeyModifier, key: String) {
        self.modifiers = modifiers
        self.key = key
    }

    // Special key name ↔ character mappings
    private static let specialKeys: [(name: String, char: String)] = [
        ("plus", "+"),
        ("minus", "-"),
        ("equal", "="),
        ("comma", ","),
    ]

    public static func parse(_ text: String) -> KeyCombo? {
        let parts = text.lowercased().split(separator: "+").map(String.init)
        guard parts.count >= 2 else { return nil }

        var modifiers = KeyModifier()
        var keyPart: String?

        for (i, part) in parts.enumerated() {
            if let mod = KeyModifier.nameMap[part] {
                modifiers.insert(mod)
            } else if i == parts.count - 1 {
                // Last part is the key
                keyPart = part
            } else {
                return nil  // Unknown modifier in non-last position
            }
        }

        guard let key = keyPart, !key.isEmpty else { return nil }
        guard !modifiers.isEmpty else { return nil }

        // Resolve special key names to characters
        let resolvedKey = specialKeys.first(where: { $0.name == key })?.char ?? key

        return KeyCombo(modifiers: modifiers, key: resolvedKey)
    }

    public func serialize() -> String {
        var parts: [String] = []
        for (mod, name) in KeyModifier.ordered {
            if modifiers.contains(mod) {
                parts.append(name)
            }
        }
        // Reverse-resolve characters to special names
        let keyName = KeyCombo.specialKeys.first(where: { $0.char == key })?.name ?? key
        parts.append(keyName)
        return parts.joined(separator: "+")
    }

    /// Human-readable display string using macOS symbols.
    public var displayString: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("\u{2303}") }
        if modifiers.contains(.option)  { parts.append("\u{2325}") }
        if modifiers.contains(.shift)   { parts.append("\u{21E7}") }
        if modifiers.contains(.command) { parts.append("\u{2318}") }

        let displayKey: String
        switch key {
        case "+": displayKey = "+"
        case "-": displayKey = "-"
        case "=": displayKey = "="
        case ",": displayKey = ","
        default: displayKey = key.uppercased()
        }
        parts.append(displayKey)
        return parts.joined()
    }
}

// MARK: - BindableAction

public enum BindableAction: String, CaseIterable, Sendable {
    case splitHorizontal = "split_horizontal"
    case splitVertical = "split_vertical"
    case closeTab = "close_tab"
    case closeArea = "close_area"
    case toggleSidebar = "toggle_sidebar"
    case openSettings = "open_settings"
    case toggleCommandPalette = "toggle_command_palette"
    case toggleFindBar = "toggle_find_bar"
    case increaseFontSize = "increase_font_size"
    case decreaseFontSize = "decrease_font_size"
    case resetFontSize = "reset_font_size"

    public var displayTitle: String {
        switch self {
        case .splitHorizontal: return "Split Horizontal"
        case .splitVertical: return "Split Vertical"
        case .closeTab: return "Close Tab"
        case .closeArea: return "Close Area"
        case .toggleSidebar: return "Toggle Sidebar"
        case .openSettings: return "Open Settings"
        case .toggleCommandPalette: return "Toggle Command Palette"
        case .toggleFindBar: return "Toggle Find Bar"
        case .increaseFontSize: return "Increase Font Size"
        case .decreaseFontSize: return "Decrease Font Size"
        case .resetFontSize: return "Reset Font Size"
        }
    }
}

// MARK: - KeyBinding

public struct KeyBinding: Sendable, Equatable {
    public let combo: KeyCombo
    public let action: BindableAction

    public init(combo: KeyCombo, action: BindableAction) {
        self.combo = combo
        self.action = action
    }

    /// Parse a "combo=action" string (e.g. "cmd+d=split_horizontal").
    public static func parse(_ text: String) -> KeyBinding? {
        let parts = text.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { return nil }

        let comboStr = parts[0].trimmingCharacters(in: .whitespaces)
        let actionStr = parts[1].trimmingCharacters(in: .whitespaces)

        guard let combo = KeyCombo.parse(comboStr) else { return nil }
        guard let action = BindableAction(rawValue: actionStr) else { return nil }

        return KeyBinding(combo: combo, action: action)
    }

    public func serialize() -> String {
        "\(combo.serialize())=\(action.rawValue)"
    }
}

// MARK: - KeyBindingMap

public struct KeyBindingMap: Sendable {
    private var comboToAction: [KeyCombo: BindableAction]

    public var bindings: [KeyBinding] {
        comboToAction.map { KeyBinding(combo: $0.key, action: $0.value) }
            .sorted { $0.action.rawValue < $1.action.rawValue }
    }

    public init(bindings: [KeyBinding]) {
        self.comboToAction = Dictionary(
            bindings.map { ($0.combo, $0.action) },
            uniquingKeysWith: { _, last in last }
        )
    }

    public func action(for combo: KeyCombo) -> BindableAction? {
        comboToAction[combo]
    }

    public func combo(for action: BindableAction) -> KeyCombo? {
        comboToAction.first(where: { $0.value == action })?.key
    }

    /// Creates a new map by applying user overrides on top of this map.
    public func merging(_ overrides: [KeyBinding]) -> KeyBindingMap {
        var merged = comboToAction
        for binding in overrides {
            // Remove any existing combo that was mapped to the same action
            for (existingCombo, existingAction) in merged {
                if existingAction == binding.action {
                    merged.removeValue(forKey: existingCombo)
                }
            }
            merged[binding.combo] = binding.action
        }
        return KeyBindingMap(comboToAction: merged)
    }

    private init(comboToAction: [KeyCombo: BindableAction]) {
        self.comboToAction = comboToAction
    }

    // MARK: - Defaults

    public static let defaults = KeyBindingMap(bindings: [
        KeyBinding(combo: KeyCombo(modifiers: [.command], key: "d"), action: .splitHorizontal),
        KeyBinding(combo: KeyCombo(modifiers: [.command, .shift], key: "d"), action: .splitVertical),
        KeyBinding(combo: KeyCombo(modifiers: [.command], key: "w"), action: .closeTab),
        KeyBinding(combo: KeyCombo(modifiers: [.command, .shift], key: "w"), action: .closeArea),
        KeyBinding(combo: KeyCombo(modifiers: [.command], key: "b"), action: .toggleSidebar),
        KeyBinding(combo: KeyCombo(modifiers: [.command], key: ","), action: .openSettings),
        KeyBinding(combo: KeyCombo(modifiers: [.command, .shift], key: "p"), action: .toggleCommandPalette),
        KeyBinding(combo: KeyCombo(modifiers: [.command], key: "f"), action: .toggleFindBar),
        KeyBinding(combo: KeyCombo(modifiers: [.command, .shift], key: "="), action: .increaseFontSize),
        KeyBinding(combo: KeyCombo(modifiers: [.command], key: "-"), action: .decreaseFontSize),
        KeyBinding(combo: KeyCombo(modifiers: [.command], key: "0"), action: .resetFontSize),
    ])
}

// MARK: - AppKit Conversions

extension KeyCombo {
    /// The key character for use with NSMenuItem.keyEquivalent.
    public var menuKeyEquivalent: String { key }

    /// The modifier mask for use with NSMenuItem.keyEquivalentModifierMask.
    public var menuModifierMask: NSEvent.ModifierFlags {
        var mask: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { mask.insert(.command) }
        if modifiers.contains(.shift)   { mask.insert(.shift) }
        if modifiers.contains(.control) { mask.insert(.control) }
        if modifiers.contains(.option)  { mask.insert(.option) }
        return mask
    }

    /// Creates a KeyCombo from an NSEvent's modifier flags and character.
    public static func from(event: NSEvent) -> KeyCombo? {
        let char = event.charactersIgnoringModifiers?.lowercased() ?? ""
        guard !char.isEmpty else { return nil }

        var modifiers = KeyModifier()
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.shift)   { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.option)  { modifiers.insert(.option) }

        guard !modifiers.isEmpty else { return nil }
        return KeyCombo(modifiers: modifiers, key: char)
    }
}
