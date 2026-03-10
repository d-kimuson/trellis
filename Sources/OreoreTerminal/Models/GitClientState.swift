import Foundation

/// Observable state for a git client panel.
/// Uses class (ObservableObject) for managing git process lifecycle.
public final class GitClientState: ObservableObject, Identifiable {
    public let id: UUID
    public let runner: GitRunner
    @Published public var repositoryPath: String
    @Published public var status: GitStatus?
    @Published public var branches: [String]
    @Published public var selectedFile: String?
    @Published public var diffText: String?
    @Published public var commitMessage: String
    @Published public var lastError: String?
    @Published public var isLoading: Bool

    public init(
        id: UUID = UUID(),
        repositoryPath: String = FileManager.default.currentDirectoryPath
    ) {
        self.id = id
        self.repositoryPath = repositoryPath
        self.runner = GitRunner(repositoryPath: repositoryPath)
        self.branches = []
        self.commitMessage = ""
        self.isLoading = false
        refresh()
    }

    /// Refresh status and branches.
    public func refresh() {
        isLoading = true
        lastError = nil

        switch runner.status() {
        case .success(let gitStatus):
            status = gitStatus
        case .failure(let error):
            lastError = describeError(error)
        }

        switch runner.listBranches() {
        case .success(let branchList):
            branches = branchList
        case .failure(let error):
            lastError = describeError(error)
        }

        isLoading = false
    }

    /// Stage a file.
    public func stage(file: String) {
        switch runner.stage(file: file) {
        case .success:
            refresh()
        case .failure(let error):
            lastError = describeError(error)
        }
    }

    /// Unstage a file.
    public func unstage(file: String) {
        switch runner.unstage(file: file) {
        case .success:
            refresh()
        case .failure(let error):
            lastError = describeError(error)
        }
    }

    /// Commit staged changes.
    public func commit() {
        guard !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastError = "Commit message cannot be empty"
            return
        }
        switch runner.commit(message: commitMessage) {
        case .success:
            commitMessage = ""
            refresh()
        case .failure(let error):
            lastError = describeError(error)
        }
    }

    /// Push to remote.
    public func push() {
        switch runner.push() {
        case .success:
            refresh()
        case .failure(let error):
            lastError = describeError(error)
        }
    }

    /// Pull from remote.
    public func pull() {
        switch runner.pull() {
        case .success:
            refresh()
        case .failure(let error):
            lastError = describeError(error)
        }
    }

    /// Checkout a branch.
    public func checkout(branch: String) {
        switch runner.checkout(branch: branch) {
        case .success:
            refresh()
        case .failure(let error):
            lastError = describeError(error)
        }
    }

    /// Load diff for a file.
    public func loadDiff(for file: String, staged: Bool) {
        selectedFile = file
        switch runner.diff(file: file, staged: staged) {
        case .success(let diff):
            diffText = diff
        case .failure(let error):
            lastError = describeError(error)
            diffText = nil
        }
    }

    private func describeError(_ error: GitError) -> String {
        switch error {
        case .processError(let message):
            return "Process error: \(message)"
        case .commandFailed(let exitCode, let stderr):
            return "Git failed (exit \(exitCode)): \(stderr)"
        }
    }
}
