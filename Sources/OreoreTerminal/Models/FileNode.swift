import Foundation

/// Represents a node in a file system tree.
public enum FileNode: Identifiable, Equatable {
    case file(id: UUID, name: String, path: String)
    case directory(id: UUID, name: String, path: String, children: [FileNode])

    public var id: UUID {
        switch self {
        case .file(let id, _, _):
            return id
        case .directory(let id, _, _, _):
            return id
        }
    }

    public var name: String {
        switch self {
        case .file(_, let name, _):
            return name
        case .directory(_, let name, _, _):
            return name
        }
    }

    public var path: String {
        switch self {
        case .file(_, _, let path):
            return path
        case .directory(_, _, let path, _):
            return path
        }
    }

    public var isDirectory: Bool {
        if case .directory = self { return true }
        return false
    }

    public var children: [FileNode] {
        switch self {
        case .file:
            return []
        case .directory(_, _, _, let children):
            return children
        }
    }

    /// Build a FileNode tree from a directory path.
    /// Filters entries matching basic .gitignore patterns.
    public static func buildTree(
        at path: String,
        ignoredPatterns: [String] = [],
        fileManager: FileManager = .default
    ) -> FileNode? {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir) else {
            return nil
        }

        if !isDir.boolValue {
            return .file(id: UUID(), name: name, path: path)
        }

        let contents: [String]
        do {
            contents = try fileManager.contentsOfDirectory(atPath: path)
        } catch {
            return .directory(id: UUID(), name: name, path: path, children: [])
        }

        let children = contents
            .filter { !shouldIgnore(name: $0, patterns: ignoredPatterns) }
            .sorted { lhs, rhs in
                // Directories first, then alphabetical
                let lhsPath = (path as NSString).appendingPathComponent(lhs)
                let rhsPath = (path as NSString).appendingPathComponent(rhs)
                var lhsIsDir: ObjCBool = false
                var rhsIsDir: ObjCBool = false
                fileManager.fileExists(atPath: lhsPath, isDirectory: &lhsIsDir)
                fileManager.fileExists(atPath: rhsPath, isDirectory: &rhsIsDir)
                if lhsIsDir.boolValue != rhsIsDir.boolValue {
                    return lhsIsDir.boolValue
                }
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
            .compactMap { child -> FileNode? in
                let childPath = (path as NSString).appendingPathComponent(child)
                return buildTree(
                    at: childPath,
                    ignoredPatterns: ignoredPatterns,
                    fileManager: fileManager
                )
            }

        return .directory(id: UUID(), name: name, path: path, children: children)
    }

    /// Parse a .gitignore file and return basic patterns.
    /// Only handles simple patterns: exact names, wildcard extensions (*.ext), directory patterns (name/).
    public static func parseGitignore(at path: String) -> [String] {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return []
        }
        return content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// Check if a file/directory name should be ignored based on patterns.
    static func shouldIgnore(name: String, patterns: [String]) -> Bool {
        // Always ignore hidden files starting with .
        if name.hasPrefix(".") {
            return true
        }

        for pattern in patterns {
            // Directory pattern: "name/"
            if pattern.hasSuffix("/") {
                let dirName = String(pattern.dropLast())
                if name == dirName {
                    return true
                }
            }
            // Wildcard extension: "*.ext"
            else if pattern.hasPrefix("*.") {
                let ext = String(pattern.dropFirst(2))
                if name.hasSuffix(".\(ext)") {
                    return true
                }
            }
            // Exact match
            else if name == pattern {
                return true
            }
        }
        return false
    }
}
