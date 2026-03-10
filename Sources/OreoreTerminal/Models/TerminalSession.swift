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

    /// Working directory to use when creating the ghostty surface.
    public let initialWorkingDirectory: String?

    // Opaque pointer to ghostty surface - managed by GhosttyNSView
    var surface: ghostty_surface_t?

    /// The NSView hosting this session's terminal surface.
    /// Stored here so SwiftUI layout changes don't destroy and recreate it.
    var nsView: GhosttyNSView?

    /// Called when the terminal view receives mouse focus (clicked).
    var onFocused: (() -> Void)?

    /// Called when the shell process exits and the surface should be closed.
    var onProcessExited: (() -> Void)?

    public init(title: String = "Terminal", workingDirectory: String? = nil) {
        self.id = UUID()
        self.title = title
        self.isActive = true
        self.initialWorkingDirectory = workingDirectory
    }

    /// Detect the git branch at the given directory in background.
    func updateGitBranch(at directory: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let branch = Self.detectGitBranch(at: directory)
            DispatchQueue.main.async {
                self?.gitBranch = branch
            }
        }
    }

    /// Run `git rev-parse --abbrev-ref HEAD` to get the current branch name.
    private static func detectGitBranch(at directory: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory, "rev-parse", "--abbrev-ref", "HEAD"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
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
        isActive = false
        nsView?.destroySurface()
        nsView = nil
    }

    deinit {
        nsView?.destroySurface()
        nsView = nil
    }
}
