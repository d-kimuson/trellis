import Foundation

/// Represents the status of a file in a git repository.
public enum GitFileStatus: Equatable {
    case modified
    case added
    case deleted
    case renamed
    case untracked
    case unknown(String)

    public init(statusCode: Character) {
        switch statusCode {
        case "M":
            self = .modified
        case "A":
            self = .added
        case "D":
            self = .deleted
        case "R":
            self = .renamed
        case "?":
            self = .untracked
        default:
            self = .unknown(String(statusCode))
        }
    }

    public var displayName: String {
        switch self {
        case .modified: return "Modified"
        case .added: return "Added"
        case .deleted: return "Deleted"
        case .renamed: return "Renamed"
        case .untracked: return "Untracked"
        case .unknown(let code): return "Unknown(\(code))"
        }
    }
}

/// A file entry in git status output.
public struct GitFileEntry: Identifiable, Equatable {
    public let id: UUID
    public let path: String
    public let indexStatus: GitFileStatus
    public let workTreeStatus: GitFileStatus
    public let isStaged: Bool

    public init(
        id: UUID = UUID(),
        path: String,
        indexStatus: GitFileStatus,
        workTreeStatus: GitFileStatus,
        isStaged: Bool
    ) {
        self.id = id
        self.path = path
        self.indexStatus = indexStatus
        self.workTreeStatus = workTreeStatus
        self.isStaged = isStaged
    }
}

/// The overall git status for a repository.
public struct GitStatus: Equatable {
    public let branch: String
    public let files: [GitFileEntry]

    public init(branch: String, files: [GitFileEntry]) {
        self.branch = branch
        self.files = files
    }

    public var stagedFiles: [GitFileEntry] {
        files.filter { $0.isStaged }
    }

    public var unstagedFiles: [GitFileEntry] {
        files.filter { !$0.isStaged }
    }
}

/// Executes git commands via Process.
/// Methods return Result to handle errors gracefully.
public struct GitRunner {
    public let repositoryPath: String

    public init(repositoryPath: String) {
        self.repositoryPath = repositoryPath
    }

    // MARK: - Command Building

    /// Build command arguments for a git subcommand.
    public func buildArguments(for subcommand: String, args: [String] = []) -> [String] {
        ["-C", repositoryPath, subcommand] + args
    }

    // MARK: - Git Operations

    /// Get the current branch name.
    public func currentBranch() -> Result<String, GitError> {
        let args = buildArguments(for: "rev-parse", args: ["--abbrev-ref", "HEAD"])
        return run(args: args).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// Get the git status.
    public func status() -> Result<GitStatus, GitError> {
        let branchResult = currentBranch()
        let branch: String
        switch branchResult {
        case .success(let name):
            branch = name
        case .failure(let error):
            return .failure(error)
        }

        let args = buildArguments(for: "status", args: ["--porcelain=v1"])
        return run(args: args).map { output in
            let files = parseStatusOutput(output)
            return GitStatus(branch: branch, files: files)
        }
    }

    /// Get diff for a specific file.
    public func diff(file: String, staged: Bool = false) -> Result<String, GitError> {
        var diffArgs = staged ? ["--cached"] : []
        diffArgs.append("--")
        diffArgs.append(file)
        let args = buildArguments(for: "diff", args: diffArgs)
        return run(args: args)
    }

    /// Stage a file.
    public func stage(file: String) -> Result<Void, GitError> {
        let args = buildArguments(for: "add", args: ["--", file])
        return run(args: args).map { _ in }
    }

    /// Unstage a file.
    public func unstage(file: String) -> Result<Void, GitError> {
        let args = buildArguments(for: "restore", args: ["--staged", "--", file])
        return run(args: args).map { _ in }
    }

    /// Create a commit with the given message.
    public func commit(message: String) -> Result<Void, GitError> {
        let args = buildArguments(for: "commit", args: ["-m", message])
        return run(args: args).map { _ in }
    }

    /// Push to remote.
    public func push() -> Result<String, GitError> {
        let args = buildArguments(for: "push")
        return run(args: args)
    }

    /// Pull from remote.
    public func pull() -> Result<String, GitError> {
        let args = buildArguments(for: "pull")
        return run(args: args)
    }

    /// List branches.
    public func listBranches() -> Result<[String], GitError> {
        let args = buildArguments(for: "branch", args: ["--format=%(refname:short)"])
        return run(args: args).map { output in
            output.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
    }

    /// Checkout a branch.
    public func checkout(branch: String) -> Result<Void, GitError> {
        let args = buildArguments(for: "checkout", args: [branch])
        return run(args: args).map { _ in }
    }

    // MARK: - Parsing

    /// Parse `git status --porcelain=v1` output into GitFileEntry array.
    public func parseStatusOutput(_ output: String) -> [GitFileEntry] {
        output.components(separatedBy: .newlines)
            .filter { $0.count >= 3 }
            .compactMap { line -> [GitFileEntry]? in
                let indexChar = line[line.startIndex]
                let workChar = line[line.index(after: line.startIndex)]
                let filePath = String(line.dropFirst(3))

                var entries: [GitFileEntry] = []

                // Staged changes (index column)
                if indexChar != " " && indexChar != "?" {
                    entries.append(GitFileEntry(
                        path: filePath,
                        indexStatus: GitFileStatus(statusCode: indexChar),
                        workTreeStatus: GitFileStatus(statusCode: workChar),
                        isStaged: true
                    ))
                }

                // Unstaged changes (work tree column) or untracked
                if workChar != " " {
                    let status: GitFileStatus = indexChar == "?" ? .untracked : GitFileStatus(statusCode: workChar)
                    entries.append(GitFileEntry(
                        path: filePath,
                        indexStatus: GitFileStatus(statusCode: indexChar),
                        workTreeStatus: status,
                        isStaged: false
                    ))
                }

                return entries.isEmpty ? nil : entries
            }
            .flatMap { $0 }
    }

    // MARK: - Process Execution

    private func run(args: [String]) -> Result<String, GitError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .failure(.processError(error.localizedDescription))
        }

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            return .failure(.commandFailed(
                exitCode: process.terminationStatus,
                stderr: errorOutput
            ))
        }

        return .success(output)
    }
}

/// Errors from git command execution.
public enum GitError: Error, Equatable {
    case processError(String)
    case commandFailed(exitCode: Int32, stderr: String)
}
