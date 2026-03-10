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
    /// Only reads one level deep (shallow). Use `loadChildren` to expand subdirectories on demand.
    public static func buildTree(
        at path: String,
        ignoredPatterns: [String] = [],
        fileManager: FileManager = .default
    ) -> FileNode? {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        let stableId = stableUUID(for: path)

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir) else {
            return nil
        }

        if !isDir.boolValue {
            return .file(id: stableId, name: name, path: path)
        }

        let children = listChildren(at: path, ignoredPatterns: ignoredPatterns, fileManager: fileManager)
        return .directory(id: stableId, name: name, path: path, children: children)
    }

    /// Load immediate children of a directory path (one level only).
    /// Subdirectories are returned with empty children arrays.
    public static func loadChildren(
        at path: String,
        ignoredPatterns: [String] = [],
        fileManager: FileManager = .default
    ) -> [FileNode] {
        listChildren(at: path, ignoredPatterns: ignoredPatterns, fileManager: fileManager)
    }

    /// Replace the children of a specific directory node (by ID) in the tree.
    public func replacingChildren(ofNodeId targetId: UUID, with newChildren: [FileNode]) -> FileNode {
        switch self {
        case .file:
            return self
        case .directory(let id, let name, let path, let children):
            if id == targetId {
                return .directory(id: id, name: name, path: path, children: newChildren)
            }
            let updatedChildren = children.map { $0.replacingChildren(ofNodeId: targetId, with: newChildren) }
            return .directory(id: id, name: name, path: path, children: updatedChildren)
        }
    }

    // MARK: - Private

    private static func listChildren(
        at path: String,
        ignoredPatterns: [String],
        fileManager: FileManager
    ) -> [FileNode] {
        let contents: [String]
        do {
            contents = try fileManager.contentsOfDirectory(atPath: path)
        } catch {
            return []
        }

        return contents
            .filter { !shouldIgnore(name: $0, patterns: ignoredPatterns) }
            .sorted { lhs, rhs in
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
                var childIsDir: ObjCBool = false
                guard fileManager.fileExists(atPath: childPath, isDirectory: &childIsDir) else {
                    return nil
                }
                let childId = stableUUID(for: childPath)
                let childName = URL(fileURLWithPath: childPath).lastPathComponent
                if childIsDir.boolValue {
                    return .directory(id: childId, name: childName, path: childPath, children: [])
                }
                return .file(id: childId, name: childName, path: childPath)
            }
    }

    /// Generate a stable UUID from a file path so SwiftUI identity is preserved across reloads.
    static func stableUUID(for path: String) -> UUID {
        let data = Data(path.utf8)
        var hash = [UInt8](repeating: 0, count: 16)
        let bytes = [UInt8](data)
        for (index, byte) in bytes.enumerated() {
            hash[index % 16] ^= byte
        }
        // Set UUID version 5 bits
        hash[6] = (hash[6] & 0x0F) | 0x50
        hash[8] = (hash[8] & 0x3F) | 0x80
        let uuid = NSUUID(uuidBytes: hash) as UUID
        return uuid
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
