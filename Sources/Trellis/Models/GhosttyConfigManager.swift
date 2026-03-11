import Foundation

/// Manages Trellis-owned settings inside the ghostty config file.
///
/// Trellis writes a clearly delimited section into `~/.config/ghostty/config`:
///
///     # --- Trellis managed (do not edit this section manually) ---
///     font-size = 14
///     font-family = Menlo
///     font-family = HiraginoSans-W3
///     # --- End Trellis managed ---
///
/// The rest of the file (if any) is left untouched.
public enum GhosttyConfigManager {
    private static let sectionStart = "# --- Trellis managed (do not edit this section manually) ---"
    private static let sectionEnd = "# --- End Trellis managed ---"

    static var configURL: URL {
        let xdgConfig = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
            .map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config")
        return xdgConfig.appendingPathComponent("ghostty/config")
    }

    /// Write (or update) the Trellis section in the ghostty config file.
    public static func apply(_ settings: AppSettings) {
        let url = configURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let updated = upsertSection(in: existing, settings: settings)
        try? updated.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Private

    private static func buildSection(_ settings: AppSettings) -> String {
        var lines: [String] = [sectionStart]

        lines.append("font-size = \(Int(settings.fontSize.rounded()))")

        if !settings.fontFamily.isEmpty {
            lines.append("font-family = \(settings.fontFamily)")
        }

        lines.append(sectionEnd)
        return lines.joined(separator: "\n")
    }

    private static func upsertSection(in text: String, settings: AppSettings) -> String {
        let section = buildSection(settings)

        // If the section already exists, replace it
        if let startRange = text.range(of: sectionStart),
           let endRange = text.range(of: sectionEnd, range: startRange.upperBound..<text.endIndex) {
            var result = text
            // Include the newline after sectionEnd if present
            let replaceEnd = text.index(after: endRange.upperBound) <= text.endIndex
                && text[endRange.upperBound] == "\n"
                ? text.index(after: endRange.upperBound)
                : endRange.upperBound
            result.replaceSubrange(startRange.lowerBound..<replaceEnd, with: section + "\n")
            return result
        }

        // Append the section
        let separator = text.isEmpty || text.hasSuffix("\n") ? "" : "\n"
        return text + separator + section + "\n"
    }
}
