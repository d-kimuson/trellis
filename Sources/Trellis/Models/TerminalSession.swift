import AppKit
import GhosttyKit

/// Represents a single terminal session with an associated libghostty surface.
/// Owns the GhosttyNSView so it survives SwiftUI view hierarchy rebuilds.
public final class TerminalSession: Identifiable, ObservableObject {
    public let id: UUID
    @Published public var title: String
    @Published public var isActive: Bool

    /// Current working directory reported by the shell (via OSC 7).
    @Published public var pwd: String?

    /// Git branch name at the current working directory (detected automatically).
    @Published public var gitBranch: String?

    /// URL pending user action (open / dismiss). Set by ghostty OPEN_URL action.
    @Published public var pendingURL: String?

    /// URL currently under the mouse cursor. Set by ghostty MOUSE_OVER_LINK action.
    /// Nil when the cursor is not hovering over a link.
    var hoveredURL: String?

    /// Working directory to use when creating the ghostty surface.
    public let initialWorkingDirectory: String?

    /// Additional environment variables to set when creating the ghostty surface.
    public let initialEnvVars: [String: String]

    // Opaque pointer to ghostty surface - managed by GhosttyNSView
    var surface: ghostty_surface_t?

    /// The NSView hosting this session's terminal surface.
    /// Stored here so SwiftUI layout changes don't destroy and recreate it.
    var nsView: GhosttyNSView?

    /// Called when the terminal view receives mouse focus (clicked).
    var onFocused: (() -> Void)?

    /// Called when the shell process exits and the surface should be closed.
    var onProcessExited: (() -> Void)?

    private var gitProcess: Process?

    public init(title: String = "Terminal", workingDirectory: String? = nil, envVars: [String: String] = [:]) {
        self.id = UUID()
        self.title = title
        self.isActive = true
        self.initialWorkingDirectory = workingDirectory
        self.initialEnvVars = envVars
    }

    /// Detect the git branch at the given directory in background.
    /// Must be called on the main actor to ensure thread-safe access to gitProcess.
    @MainActor
    func updateGitBranch(at directory: String) {
        gitProcess?.terminate()
        gitProcess = nil

        guard let process = Self.detectGitBranch(at: directory, completion: { [weak self] process, branch in
            DispatchQueue.main.async {
                guard let self, self.gitProcess === process else { return }
                self.gitBranch = branch
                self.gitProcess = nil
            }
        }) else {
            gitBranch = nil
            return
        }

        gitProcess = process
    }

    /// Run `git rev-parse --abbrev-ref HEAD` to get the current branch name.
    private static func detectGitBranch(
        at directory: String,
        completion: @escaping (Process, String?) -> Void
    ) -> Process? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory, "rev-parse", "--abbrev-ref", "HEAD"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { process in
            let branch: String?

            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                branch = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                branch = nil
            }

            completion(process, branch)
        }

        do {
            try process.run()
            return process
        } catch {
            return nil
        }
    }

    /// Display title for the tab bar.
    /// Uses the last path component of pwd when available, otherwise falls back to title.
    public var tabTitle: String {
        if let pwd = pwd {
            let lastComponent = URL(fileURLWithPath: pwd).lastPathComponent
            return lastComponent.isEmpty ? "/" : lastComponent
        }
        return title
    }

    /// Shortened display name of the current working directory.
    public var shortPwd: String? {
        guard let pwd else { return nil }
        let home = NSHomeDirectory()
        if pwd == home {
            return "~"
        }
        if pwd.hasPrefix(home + "/") {
            return "~/" + String(pwd.dropFirst(home.count + 1))
        }
        return pwd
    }

    /// Mark session as inactive and free the surface.
    func close() {
        gitProcess?.terminate()
        gitProcess = nil
        isActive = false
        nsView?.destroySurface()
        nsView = nil
    }

    deinit {
        gitProcess?.terminate()
        gitProcess = nil
        nsView?.destroySurface()
        nsView = nil
    }
}
