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

    static var shellIntegrationDir: String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("Trellis/shell-integration").path
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

    // MARK: - Shell Restore Environment

    /// Build env vars that replay scrollback on session start — no user shell config needed.
    ///
    /// For zsh: uses ZDOTDIR injection. The installed .zshenv bootstrap restores the
    /// user's real ZDOTDIR, sources their .zshenv, then sources the Trellis integration
    /// script which cats TRELLIS_RESTORE_SCROLLBACK_FILE to stdout.
    ///
    /// For other shells: sets TRELLIS_RESTORE_SCROLLBACK_FILE only (requires the user
    /// to source trellis-bash-integration.bash from ~/.bashrc).
    static func prepareRestoreEnv(scrollback: String, sessionId: UUID) -> [String: String] {
        guard !scrollback.isEmpty else { return [:] }

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        if shell.hasSuffix("zsh") {
            return prepareZshRestoreEnv(scrollback: scrollback, sessionId: sessionId)
        }

        // Non-zsh fallback: env var picked up by the bundled integration script
        guard let path = writeScrollbackFile(scrollback, id: sessionId) else { return [:] }
        return ["TRELLIS_RESTORE_SCROLLBACK_FILE": path]
    }

    private static func prepareZshRestoreEnv(scrollback: String, sessionId: UUID) -> [String: String] {
        guard let sbPath = writeScrollbackFile(scrollback, id: sessionId) else { return [:] }

        let integrationDir = shellIntegrationDir
        let zshenvPath = (integrationDir as NSString).appendingPathComponent(".zshenv")

        // Only use ZDOTDIR injection when the integration scripts are installed
        guard FileManager.default.fileExists(atPath: zshenvPath) else {
            return ["TRELLIS_RESTORE_SCROLLBACK_FILE": sbPath]
        }

        // Save the user's current ZDOTDIR so .zshenv can restore it
        let userZdotdir = ProcessInfo.processInfo.environment["ZDOTDIR"]

        var env: [String: String] = [
            "ZDOTDIR": integrationDir,
            "TRELLIS_SHELL_INTEGRATION_DIR": integrationDir,
            "TRELLIS_RESTORE_SCROLLBACK_FILE": sbPath,
        ]
        if let userZdotdir {
            env["TRELLIS_ZSH_ZDOTDIR"] = userZdotdir
        }
        return env
    }

    // MARK: - Shell Integration Install

    /// Copy bundled shell-integration scripts to the stable app-support directory.
    /// Returns the directory path, or nil if the bundle resource is missing.
    @discardableResult
    static func installShellIntegration() -> String? {
        guard let bundlePath = Bundle.main.resourcePath else { return nil }
        let src = (bundlePath as NSString).appendingPathComponent("shell-integration")
        guard FileManager.default.fileExists(atPath: src) else { return nil }

        let dst = shellIntegrationDir
        try? FileManager.default.createDirectory(
            atPath: dst,
            withIntermediateDirectories: true
        )

        let fm = FileManager.default
        // Include dotfiles (.zshenv etc.)
        let files = (try? fm.contentsOfDirectory(atPath: src)) ?? []
        for file in files {
            let srcFile = (src as NSString).appendingPathComponent(file)
            let dstFile = (dst as NSString).appendingPathComponent(file)
            try? fm.removeItem(atPath: dstFile)
            try? fm.copyItem(atPath: srcFile, toPath: dstFile)
        }
        return dst
    }
}
