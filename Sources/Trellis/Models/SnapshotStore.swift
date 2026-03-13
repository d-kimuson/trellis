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
            // Restrict to owner-only read/write; workspaces.json may contain scrollback
            // with sensitive terminal output (passwords, API keys, etc.)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
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
        var lineArray = Array(lines.suffix(maxScrollbackLines))
        // Trim trailing blank lines and terminal teardown artifacts (direnv messages,
        // zsh PROMPT_SP markers) to prevent garbage appearing at the top of the replayed buffer.
        while let last = lineArray.last {
            let trimmed = last.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || isTerminalTeardownLine(trimmed) {
                lineArray.removeLast()
            } else {
                break
            }
        }
        let joined = lineArray.joined(separator: "\n")
        guard joined.count > maxScrollbackChars else { return joined }
        return String(joined.suffix(maxScrollbackChars))
    }

    /// Returns true for lines that are artifacts of shell/tool teardown and should not
    /// be replayed (e.g. direnv lifecycle messages, zsh partial-line markers).
    private static func isTerminalTeardownLine(_ trimmed: String) -> Bool {
        // direnv prints "direnv: unloading" when the shell exits a direnv-managed dir.
        // May be prefixed by zsh PROMPT_SP '%' with no space (e.g. "%direnv: unloading").
        // Use hasPrefix (not contains) to avoid removing meaningful lines that merely
        // contain the substring (e.g. "Process log: direnv: unloading some module").
        if trimmed.hasPrefix("direnv: unloading") || trimmed.hasPrefix("%direnv: unloading") {
            return true
        }
        // zsh PROMPT_SP: when previous output lacks a trailing newline, zsh prints '%'
        // (or a Unicode PROMPT_SP character) padded to the terminal width.
        // Match a line whose non-whitespace content is only '%' characters.
        let nonSpace = trimmed.filter { !$0.isWhitespace }
        if !nonSpace.isEmpty && nonSpace.allSatisfy({ $0 == "%" }) { return true }
        return false
    }

    /// Write scrollback content to a temp file; returns the file path on success.
    /// The file is created with owner-only permissions (0600) to prevent other
    /// users on the same machine from reading potentially sensitive terminal output.
    static func writeScrollbackFile(_ content: String, id: UUID) -> String? {
        let path = NSTemporaryDirectory() + "trellis-sb-\(id.uuidString).txt"
        guard (try? content.write(toFile: path, atomically: true, encoding: .utf8)) != nil else {
            return nil
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        return path
    }

    /// Remove stale scrollback temp files (trellis-sb-*.txt) older than `age` seconds.
    /// Called at app startup as a safety net in case the shell integration script did not run
    /// (e.g. the shell crashed before sourcing the integration script).
    ///
    /// trellis-sb-* files live in NSTemporaryDirectory (written by the app).
    /// trellis-running-* files live in /tmp (written by the shell integration).
    static func cleanUpStaleTempFiles(olderThan age: TimeInterval = 3600) {
        let fm = FileManager.default
        let now = Date()

        func cleanDir(_ dir: String, matching prefix: (String) -> Bool) {
            guard let files = try? fm.contentsOfDirectory(atPath: dir) else { return }
            for file in files where prefix(file) && file.hasSuffix(".txt") {
                let path = dir + file
                guard let attrs = try? fm.attributesOfItem(atPath: path),
                      let modDate = attrs[.modificationDate] as? Date else { continue }
                if now.timeIntervalSince(modDate) > age {
                    try? fm.removeItem(atPath: path)
                }
            }
        }

        // Scrollback files (written by app)
        cleanDir(NSTemporaryDirectory()) { $0.hasPrefix("trellis-sb-") }
        // Running-command files (written by shell integration at /tmp)
        cleanDir("/tmp/") { $0.hasPrefix("trellis-running-") }
    }

    // MARK: - Running Command Tracking

    /// Read the running command for a session from its temp file.
    /// Returns nil if no command is running (file absent or empty).
    ///
    /// Shell integration writes to /tmp (not NSTemporaryDirectory) because the shell
    /// does not know the app's per-session temp dir. Read from /tmp to match.
    static func readRunningCommand(sessionId: UUID) -> String? {
        let path = "/tmp/trellis-running-\(sessionId.uuidString).txt"
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Append a notice about an interrupted command to scrollback content.
    /// Returns the modified scrollback, or nil if both inputs are nil/empty.
    static func appendRunningCommandNotice(scrollback: String?, runningCommand: String?) -> String? {
        guard let cmd = runningCommand, !cmd.isEmpty else { return scrollback }
        // Yellow ANSI text so it stands out but isn't alarming
        let notice = "\n\u{001B}[33m[trellis] interrupted: \(cmd)\u{001B}[0m"
        if let sb = scrollback {
            return sb + notice
        }
        return notice
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
    static func prepareRestoreEnv(
        scrollback: String,
        sessionId: UUID,
        terminalCols: Int? = nil
    ) -> [String: String] {
        guard !scrollback.isEmpty else { return [:] }

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        if shell.hasSuffix("zsh") {
            return prepareZshRestoreEnv(scrollback: scrollback, sessionId: sessionId,
                                        terminalCols: terminalCols)
        }

        // Non-zsh fallback: env var picked up by the bundled integration script
        guard let path = writeScrollbackFile(scrollback, id: sessionId) else { return [:] }
        var env = ["TRELLIS_RESTORE_SCROLLBACK_FILE": path]
        if let cols = terminalCols, cols > 0 { env["TRELLIS_TERMINAL_COLS"] = String(cols) }
        return env
    }

    private static func prepareZshRestoreEnv(
        scrollback: String,
        sessionId: UUID,
        terminalCols: Int?
    ) -> [String: String] {
        guard let sbPath = writeScrollbackFile(scrollback, id: sessionId) else { return [:] }

        let integrationDir = shellIntegrationDir
        let zshenvPath = (integrationDir as NSString).appendingPathComponent(".zshenv")

        // Only use ZDOTDIR injection when the integration scripts are installed
        guard FileManager.default.fileExists(atPath: zshenvPath) else {
            var env = ["TRELLIS_RESTORE_SCROLLBACK_FILE": sbPath]
            if let cols = terminalCols, cols > 0 { env["TRELLIS_TERMINAL_COLS"] = String(cols) }
            return env
        }

        // Save the user's current ZDOTDIR so .zshenv can restore it
        let userZdotdir = ProcessInfo.processInfo.environment["ZDOTDIR"]

        var env: [String: String] = [
            "ZDOTDIR": integrationDir,
            "TRELLIS_SHELL_INTEGRATION_DIR": integrationDir,
            "TRELLIS_RESTORE_SCROLLBACK_FILE": sbPath
        ]
        if let cols = terminalCols, cols > 0 { env["TRELLIS_TERMINAL_COLS"] = String(cols) }
        if let userZdotdir { env["TRELLIS_ZSH_ZDOTDIR"] = userZdotdir }
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
