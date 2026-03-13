import Foundation

/// A simple TOML-subset config file: flat key-value pairs with comments.
///
/// Supports: strings (`"..."`), integers, floats, and booleans.
/// Preserves comments and blank lines on round-trip.
public struct ConfigFile: Sendable {

    /// A single line in the config file (either a key-value pair or a non-data line).
    enum Entry: Sendable {
        case keyValue(key: String, value: Value)
        case comment(String)   // includes "#" prefix
        case blank
    }

    public enum Value: Sendable, Equatable {
        case string(String)
        case integer(Int)
        case double(Double)
        case bool(Bool)
    }

    var entries: [Entry]

    public static let empty = ConfigFile(entries: [])

    // MARK: - Parse

    public static func parse(_ text: String) -> ConfigFile {
        guard !text.isEmpty else { return .empty }
        let lines = text.components(separatedBy: "\n")
        var entries: [Entry] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                entries.append(.blank)
                continue
            }
            if trimmed.hasPrefix("#") {
                entries.append(.comment(line))
                continue
            }

            if let eqIndex = trimmed.firstIndex(of: "=") {
                let key = trimmed[trimmed.startIndex..<eqIndex]
                    .trimmingCharacters(in: .whitespaces)
                var rawValue = trimmed[trimmed.index(after: eqIndex)...]
                    .trimmingCharacters(in: .whitespaces)

                // Strip inline comment (not inside quotes)
                if !rawValue.hasPrefix("\"") {
                    if let hashIndex = rawValue.firstIndex(of: "#") {
                        rawValue = rawValue[rawValue.startIndex..<hashIndex]
                            .trimmingCharacters(in: .whitespaces)
                    }
                }

                let value = parseValue(String(rawValue))
                entries.append(.keyValue(key: key, value: value))
            }
        }
        return ConfigFile(entries: entries)
    }

    private static func parseValue(_ raw: String) -> Value {
        // Quoted string
        if raw.hasPrefix("\"") && raw.hasSuffix("\"") && raw.count >= 2 {
            let inner = String(raw.dropFirst().dropLast())
            return .string(inner)
        }
        // Boolean
        if raw == "true" { return .bool(true) }
        if raw == "false" { return .bool(false) }
        // Number
        if raw.contains("."), let d = Double(raw) {
            return .double(d)
        }
        if let i = Int(raw) {
            return .integer(i)
        }
        // Fallback: treat as unquoted string
        return .string(raw)
    }

    // MARK: - Accessors

    public func string(forKey key: String) -> String? {
        for entry in entries {
            if case .keyValue(let k, let v) = entry, k == key {
                switch v {
                case .string(let s): return s
                default: return nil
                }
            }
        }
        return nil
    }

    public func double(forKey key: String) -> Double? {
        for entry in entries {
            if case .keyValue(let k, let v) = entry, k == key {
                switch v {
                case .double(let d): return d
                case .integer(let i): return Double(i)
                default: return nil
                }
            }
        }
        return nil
    }

    public func bool(forKey key: String) -> Bool? {
        for entry in entries {
            if case .keyValue(let k, let v) = entry, k == key {
                if case .bool(let b) = v { return b }
            }
        }
        return nil
    }

    /// Returns all values for a given key (for keys that can appear multiple times, e.g. `keybind`).
    public func strings(forKey key: String) -> [String] {
        entries.compactMap { entry in
            if case .keyValue(let k, let v) = entry, k == key {
                switch v {
                case .string(let s): return s
                default: return nil
                }
            }
            return nil
        }
    }

    /// Replaces all entries for a given key with the provided values.
    public mutating func setAll(_ values: [String], forKey key: String) {
        // Remove existing entries for this key
        entries.removeAll { entry in
            if case .keyValue(let k, _) = entry, k == key { return true }
            return false
        }
        // Append new entries
        for value in values {
            entries.append(.keyValue(key: key, value: .string(value)))
        }
    }

    // MARK: - Mutators

    public mutating func set(_ value: Value, forKey key: String) {
        for i in entries.indices {
            if case .keyValue(let k, _) = entries[i], k == key {
                entries[i] = .keyValue(key: key, value: value)
                return
            }
        }
        entries.append(.keyValue(key: key, value: value))
    }

    // MARK: - Serialize

    public func serialize() -> String {
        entries.map { entry in
            switch entry {
            case .keyValue(let key, let value):
                return "\(key) = \(serializeValue(value))"
            case .comment(let text):
                return text
            case .blank:
                return ""
            }
        }.joined(separator: "\n")
    }

    private func serializeValue(_ value: Value) -> String {
        switch value {
        case .string(let s): return "\"\(s)\""
        case .integer(let i): return "\(i)"
        case .double(let d): return "\(d)"
        case .bool(let b): return b ? "true" : "false"
        }
    }

    // MARK: - File I/O

    public static func load(from url: URL) throws -> ConfigFile {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .empty
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        return parse(text)
    }

    public func save(to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try serialize().write(to: url, atomically: true, encoding: .utf8)
    }
}
