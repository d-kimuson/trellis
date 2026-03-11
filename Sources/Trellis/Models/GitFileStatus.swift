import Foundation

/// Git working tree / index status for a single file.
public enum GitFileStatus: Equatable {
    case untracked  // ??
    case modified   // M in index or working tree
    case added      // A in index (staged new file)
    case deleted    // D in index or working tree
}

extension GitFileStatus {
    /// Parse one line of `git status --porcelain` output.
    /// Returns nil for lines that don't represent a meaningful status.
    /// `root` is the absolute repo root used to resolve relative paths.
    public static func parsePorcelainLine(_ line: String, root: String) -> (path: String, status: GitFileStatus)? {
        guard line.count >= 4 else { return nil }
        let x = line[line.startIndex]
        let y = line[line.index(line.startIndex, offsetBy: 1)]
        let rawPath = String(line.dropFirst(3))
        let filePath = rawPath.contains(" -> ")
            ? (rawPath.components(separatedBy: " -> ").last ?? rawPath)
            : rawPath
        let absPath = (root as NSString).appendingPathComponent(filePath)

        if x == "?" && y == "?" { return (absPath, .untracked) }
        if x == "D" || y == "D" { return (absPath, .deleted) }
        if x == "R" { return (absPath, .added) }
        if x == "A" { return (absPath, .added) }
        if x == "M" || y == "M" { return (absPath, .modified) }
        return nil
    }

    /// Parse full `git status --porcelain` output into a path→status dictionary.
    public static func parse(porcelainOutput: String, root: String) -> [String: GitFileStatus] {
        porcelainOutput
            .components(separatedBy: .newlines)
            .compactMap { parsePorcelainLine($0, root: root) }
            .reduce(into: [:]) { $0[$1.path] = $1.status }
    }

    /// Compute the set of directory paths that contain at least one dirty descendant.
    public static func dirtyDirectories(from statuses: [String: GitFileStatus], root: String) -> Set<String> {
        var result = Set<String>()
        for path in statuses.keys {
            var current = (path as NSString).deletingLastPathComponent
            while current.hasPrefix(root) && current != root {
                result.insert(current)
                current = (current as NSString).deletingLastPathComponent
            }
            if current == root { result.insert(root) }
        }
        return result
    }
}
