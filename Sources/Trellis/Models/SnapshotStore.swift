import Foundation

/// Persists workspace snapshots to ~/Library/Application Support/Trellis/workspaces.json.
enum SnapshotStore {
    static let maxScrollbackLines = 4000
    static let maxScrollbackChars = 400_000

    private static var saveURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("Trellis/workspaces.json")
    }

    static func save(_ snapshots: [WorkspaceSnapshot]) {
        let url = saveURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snapshots) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func load() -> [WorkspaceSnapshot] {
        let url = saveURL
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([WorkspaceSnapshot].self, from: data)) ?? []
    }

    /// Truncate scrollback to the policy limits.
    static func truncate(_ scrollback: String) -> String {
        let lines = scrollback.components(separatedBy: "\n")
        let limited = lines.suffix(maxScrollbackLines)
        let joined = limited.joined(separator: "\n")
        guard joined.count > maxScrollbackChars else { return joined }
        return String(joined.suffix(maxScrollbackChars))
    }

    /// Write scrollback content to a temp file; returns the file path on success.
    static func writeScrollbackFile(_ content: String, id: UUID) -> String? {
        let path = NSTemporaryDirectory() + "trellis-sb-\(id.uuidString).txt"
        guard (try? content.write(toFile: path, atomically: true, encoding: .utf8)) != nil else {
            return nil
        }
        return path
    }

    /// Copy bundled shell-integration scripts to the stable app-support directory.
    /// Returns the directory path, or nil if the bundle resource is missing.
    @discardableResult
    static func installShellIntegration() -> String? {
        guard let bundlePath = Bundle.main.resourcePath else { return nil }
        let src = (bundlePath as NSString).appendingPathComponent("shell-integration")
        guard FileManager.default.fileExists(atPath: src) else { return nil }

        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dst = appSupport.appendingPathComponent("Trellis/shell-integration").path

        try? FileManager.default.createDirectory(
            atPath: dst,
            withIntermediateDirectories: true
        )

        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(atPath: src)) ?? []
        for file in files {
            let srcFile = (src as NSString).appendingPathComponent(file)
            let dstFile = (dst as NSString).appendingPathComponent(file)
            // Always overwrite to pick up updates after app upgrades.
            try? fm.removeItem(atPath: dstFile)
            try? fm.copyItem(atPath: srcFile, toPath: dstFile)
        }
        return dst
    }
}
