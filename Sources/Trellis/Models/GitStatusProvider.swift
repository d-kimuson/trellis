import Foundation
import Observation

/// Manages git status and diff retrieval for a working directory.
/// Independently testable without FileTreeState.
@Observable
public final class GitStatusProvider {
    public var statusMap: [String: GitFileStatus] = [:]
    public var dirtyDirectoryPaths: Set<String> = []

    @ObservationIgnored private var statusProcess: Process?
    @ObservationIgnored private var diffProcess: Process?

    public init() {}

    /// Reload git status for the given git root. Pass nil to clear status.
    public func reload(gitRoot: String?) {
        guard let root = gitRoot else {
            statusMap = [:]
            dirtyDirectoryPaths = []
            return
        }
        cancelStatus()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", root, "status", "--porcelain"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] proc in
            let output: String? = proc.terminationStatus == 0
                ? String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
                : nil
            DispatchQueue.main.async {
                guard let self, self.statusProcess === proc else { return }
                if let output {
                    let map = GitFileStatus.parse(porcelainOutput: output, root: root)
                    self.statusMap = map
                    self.dirtyDirectoryPaths = GitFileStatus.dirtyDirectories(from: map, root: root)
                } else {
                    self.statusMap = [:]
                    self.dirtyDirectoryPaths = []
                }
                self.statusProcess = nil
            }
        }
        try? process.run()
        statusProcess = process
    }

    /// Fetch the git diff for a specific file. Calls completion on the main thread with the diff
    /// string, or nil if unavailable.
    public func fetchDiff(for path: String, gitRoot: String, completion: @escaping (String?) -> Void) {
        cancelDiff()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", gitRoot, "diff", "--histogram", "HEAD", "--", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] proc in
            let output: String? = proc.terminationStatus == 0
                ? String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
                : nil
            DispatchQueue.main.async {
                guard let self, self.diffProcess === proc else { return }
                self.diffProcess = nil
                completion(output)
            }
        }
        try? process.run()
        diffProcess = process
    }

    public func cancelStatus() {
        statusProcess?.terminate()
        statusProcess = nil
    }

    public func cancelDiff() {
        diffProcess?.terminate()
        diffProcess = nil
    }

    public func cancel() {
        cancelStatus()
        cancelDiff()
    }
}
