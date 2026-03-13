import Foundation

/// Characters that are safe in shell arguments without quoting.
/// Includes alphanumerics, hyphen, underscore, dot, slash, colon, at, plus, percent, comma, tilde.
private let shellSafeCharacters = CharacterSet.alphanumerics.union(
    CharacterSet(charactersIn: "-_./:@+%,~")
)

/// Quote a file path for safe use in a shell command.
/// Returns the path unchanged if it contains only safe characters.
/// Otherwise wraps in single quotes, escaping embedded single quotes.
public func shellQuotePath(_ path: String) -> String {
    if path.isEmpty { return "''" }
    if path.unicodeScalars.allSatisfy({ shellSafeCharacters.contains($0) }) {
        return path
    }
    // Single-quote the path, escaping any embedded single quotes: ' → '\''
    let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
    return "'\(escaped)'"
}

/// Compute a relative path from a base directory.
/// Returns the absolute path if there is no common prefix.
public func relativeFilePath(filePath: String, base: String?) -> String {
    guard let base else { return filePath }
    let prefix = base.hasSuffix("/") ? base : base + "/"
    if filePath.hasPrefix(prefix) {
        return String(filePath.dropFirst(prefix.count))
    }
    return filePath
}

/// Format multiple file paths for shell input.
/// Each path is made relative to the base and shell-quoted, then joined with spaces.
public func formatDroppedPaths(filePaths: [String], base: String?) -> String {
    filePaths
        .map { shellQuotePath(relativeFilePath(filePath: $0, base: base)) }
        .joined(separator: " ")
}
