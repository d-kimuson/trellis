import Foundation
import XCTest
@testable import OreoreTerminal

final class GitRunnerTests: XCTestCase {

    // MARK: - Command Building

    func testBuildArgumentsForStatus() {
        let runner = GitRunner(repositoryPath: "/tmp/repo")
        let args = runner.buildArguments(for: "status", args: ["--porcelain=v1"])
        XCTAssertEqual(args, ["-C", "/tmp/repo", "status", "--porcelain=v1"])
    }

    func testBuildArgumentsForCommit() {
        let runner = GitRunner(repositoryPath: "/home/user/project")
        let args = runner.buildArguments(for: "commit", args: ["-m", "test message"])
        XCTAssertEqual(args, ["-C", "/home/user/project", "commit", "-m", "test message"])
    }

    func testBuildArgumentsForDiffStaged() {
        let runner = GitRunner(repositoryPath: "/repo")
        let args = runner.buildArguments(for: "diff", args: ["--cached", "--", "file.txt"])
        XCTAssertEqual(args, ["-C", "/repo", "diff", "--cached", "--", "file.txt"])
    }

    func testBuildArgumentsForCheckout() {
        let runner = GitRunner(repositoryPath: "/repo")
        let args = runner.buildArguments(for: "checkout", args: ["main"])
        XCTAssertEqual(args, ["-C", "/repo", "checkout", "main"])
    }

    func testBuildArgumentsForAdd() {
        let runner = GitRunner(repositoryPath: "/repo")
        let args = runner.buildArguments(for: "add", args: ["--", "file.swift"])
        XCTAssertEqual(args, ["-C", "/repo", "add", "--", "file.swift"])
    }

    func testBuildArgumentsForRestoreStaged() {
        let runner = GitRunner(repositoryPath: "/repo")
        let args = runner.buildArguments(for: "restore", args: ["--staged", "--", "file.swift"])
        XCTAssertEqual(args, ["-C", "/repo", "restore", "--staged", "--", "file.swift"])
    }

    func testBuildArgumentsNoExtraArgs() {
        let runner = GitRunner(repositoryPath: "/repo")
        let args = runner.buildArguments(for: "pull")
        XCTAssertEqual(args, ["-C", "/repo", "pull"])
    }

    // MARK: - Status Parsing

    func testParseStatusOutputModifiedFiles() {
        let runner = GitRunner(repositoryPath: "/repo")
        let output = " M Sources/file.swift\n"
        let files = runner.parseStatusOutput(output)

        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].path, "Sources/file.swift")
        XCTAssertEqual(files[0].workTreeStatus, .modified)
        XCTAssertFalse(files[0].isStaged)
    }

    func testParseStatusOutputStagedFiles() {
        let runner = GitRunner(repositoryPath: "/repo")
        let output = "M  Sources/file.swift\n"
        let files = runner.parseStatusOutput(output)

        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].path, "Sources/file.swift")
        XCTAssertEqual(files[0].indexStatus, .modified)
        XCTAssertTrue(files[0].isStaged)
    }

    func testParseStatusOutputUntrackedFiles() {
        let runner = GitRunner(repositoryPath: "/repo")
        let output = "?? new_file.txt\n"
        let files = runner.parseStatusOutput(output)

        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].path, "new_file.txt")
        XCTAssertEqual(files[0].workTreeStatus, .untracked)
        XCTAssertFalse(files[0].isStaged)
    }

    func testParseStatusOutputMixedStatus() {
        let runner = GitRunner(repositoryPath: "/repo")
        // File that is both staged and has unstaged changes
        let output = "MM Sources/file.swift\n"
        let files = runner.parseStatusOutput(output)

        XCTAssertEqual(files.count, 2)
        // First entry is staged
        XCTAssertTrue(files[0].isStaged)
        XCTAssertEqual(files[0].indexStatus, .modified)
        // Second entry is unstaged
        XCTAssertFalse(files[1].isStaged)
        XCTAssertEqual(files[1].workTreeStatus, .modified)
    }

    func testParseStatusOutputMultipleFiles() {
        let runner = GitRunner(repositoryPath: "/repo")
        let output = """
         M file1.swift
        A  file2.swift
        D  file3.swift
        ?? file4.txt

        """
        let files = runner.parseStatusOutput(output)

        XCTAssertEqual(files.count, 4)

        // file1: unstaged modified
        XCTAssertEqual(files[0].path, "file1.swift")
        XCTAssertFalse(files[0].isStaged)

        // file2: staged added
        XCTAssertEqual(files[1].path, "file2.swift")
        XCTAssertTrue(files[1].isStaged)
        XCTAssertEqual(files[1].indexStatus, .added)

        // file3: staged deleted
        XCTAssertEqual(files[2].path, "file3.swift")
        XCTAssertTrue(files[2].isStaged)
        XCTAssertEqual(files[2].indexStatus, .deleted)

        // file4: untracked
        XCTAssertEqual(files[3].path, "file4.txt")
        XCTAssertFalse(files[3].isStaged)
        XCTAssertEqual(files[3].workTreeStatus, .untracked)
    }

    func testParseStatusOutputEmptyString() {
        let runner = GitRunner(repositoryPath: "/repo")
        let files = runner.parseStatusOutput("")
        XCTAssertEqual(files.count, 0)
    }

    func testParseStatusOutputAddedFile() {
        let runner = GitRunner(repositoryPath: "/repo")
        let output = "A  brand_new.swift\n"
        let files = runner.parseStatusOutput(output)

        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].indexStatus, .added)
        XCTAssertTrue(files[0].isStaged)
    }

    func testParseStatusOutputDeletedFile() {
        let runner = GitRunner(repositoryPath: "/repo")
        let output = " D removed.swift\n"
        let files = runner.parseStatusOutput(output)

        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].workTreeStatus, .deleted)
        XCTAssertFalse(files[0].isStaged)
    }

    func testParseStatusOutputRenamedFile() {
        let runner = GitRunner(repositoryPath: "/repo")
        let output = "R  old.swift -> new.swift\n"
        let files = runner.parseStatusOutput(output)

        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].indexStatus, .renamed)
        XCTAssertTrue(files[0].isStaged)
    }

    // MARK: - GitFileStatus

    func testGitFileStatusDisplayNames() {
        XCTAssertEqual(GitFileStatus.modified.displayName, "Modified")
        XCTAssertEqual(GitFileStatus.added.displayName, "Added")
        XCTAssertEqual(GitFileStatus.deleted.displayName, "Deleted")
        XCTAssertEqual(GitFileStatus.renamed.displayName, "Renamed")
        XCTAssertEqual(GitFileStatus.untracked.displayName, "Untracked")
        XCTAssertEqual(GitFileStatus.unknown("X").displayName, "Unknown(X)")
    }

    func testGitFileStatusFromCode() {
        XCTAssertEqual(GitFileStatus(statusCode: "M"), .modified)
        XCTAssertEqual(GitFileStatus(statusCode: "A"), .added)
        XCTAssertEqual(GitFileStatus(statusCode: "D"), .deleted)
        XCTAssertEqual(GitFileStatus(statusCode: "R"), .renamed)
        XCTAssertEqual(GitFileStatus(statusCode: "?"), .untracked)
        XCTAssertEqual(GitFileStatus(statusCode: "X"), .unknown("X"))
    }

    // MARK: - GitStatus

    func testGitStatusStagedAndUnstagedFiles() {
        let staged = GitFileEntry(path: "a.swift", indexStatus: .modified, workTreeStatus: .modified, isStaged: true)
        let unstaged = GitFileEntry(path: "b.swift", indexStatus: .modified, workTreeStatus: .modified, isStaged: false)
        let status = GitStatus(branch: "main", files: [staged, unstaged])

        XCTAssertEqual(status.stagedFiles.count, 1)
        XCTAssertEqual(status.unstagedFiles.count, 1)
        XCTAssertEqual(status.stagedFiles[0].path, "a.swift")
        XCTAssertEqual(status.unstagedFiles[0].path, "b.swift")
    }
}
