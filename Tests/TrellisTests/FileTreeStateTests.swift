import Foundation
import XCTest
@testable import Trellis

/// Tests for FileTreeState reload logic.
/// FSEventStream and file-picker UI are excluded from these tests.
final class FileTreeStateTests: XCTestCase {

    // MARK: - Helpers

    private var tempDir: String!
    private let fileManager = FileManager.default

    override func setUp() {
        super.setUp()
        tempDir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("FileTreeStateTests_\(UUID().uuidString)")
        try? fileManager.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        super.tearDown()
        try? fileManager.removeItem(atPath: tempDir)
    }

    private func makePath(_ components: String...) -> String {
        components.reduce(tempDir) { ($0 as NSString).appendingPathComponent($1) }
    }

    private func mkdir(_ path: String) {
        try? fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    private func touch(_ path: String) {
        fileManager.createFile(atPath: path, contents: nil)
    }

    // MARK: - reload restores nested expanded directories

    /// Regression test for the bug where reload() iterating Set<UUID> in random order
    /// failed to restore deeply-nested expanded directories, because a child was processed
    /// before its parent (which had empty children in the freshly-built shallow tree).
    func testReloadRestoresNestedExpandedDirectories() async {
        // Structure: root/docs/tmp/qa/file.txt
        let docs = makePath("docs")
        let tmp  = makePath("docs", "tmp")
        let qa   = makePath("docs", "tmp", "qa")
        mkdir(docs); mkdir(tmp); mkdir(qa)
        touch(makePath("docs", "tmp", "qa", "file.txt"))

        let state = FileTreeState(rootPath: tempDir)

        // Expand docs → tmp becomes visible
        guard let docsNode = state.rootNode?.children.first(where: { $0.name == "docs" }) else {
            return XCTFail("docs not found in root")
        }
        state.toggleExpanded(docsNode.id)
        await state.awaitLoadChildren()

        // Expand tmp → qa becomes visible
        guard let tmpNode = findNode(named: "tmp", in: state.rootNode!) else {
            return XCTFail("tmp not found after expanding docs")
        }
        state.toggleExpanded(tmpNode.id)
        await state.awaitLoadChildren()

        // Expand qa → file.txt becomes visible
        guard let qaNode = findNode(named: "qa", in: state.rootNode!) else {
            return XCTFail("qa not found after expanding tmp")
        }
        state.toggleExpanded(qaNode.id)
        await state.awaitLoadChildren()

        // Verify qa's children are loaded before reload (re-fetch since FileNode is a value type)
        guard let qaAfterExpand = findNode(named: "qa", in: state.rootNode!) else {
            return XCTFail("qa not found after expanding it")
        }
        XCTAssertFalse(qaAfterExpand.children.isEmpty, "qa should have children before reload")

        // Simulate reload (e.g. triggered by FSEvent)
        state.reload()
        await state.awaitReload()

        // After reload, the nested expansion must be fully restored:
        // docs → tmp → qa → file.txt should all be accessible
        guard let qaAfter = findNode(named: "qa", in: state.rootNode!) else {
            return XCTFail("qa not found after reload")
        }
        XCTAssertFalse(
            qaAfter.children.isEmpty,
            "qa's children should be restored after reload; nested expansion was lost"
        )
        XCTAssertTrue(
            qaAfter.children.contains(where: { $0.name == "file.txt" }),
            "file.txt should be visible inside qa after reload"
        )
    }

    // MARK: - reload restores single expanded directory

    func testReloadRestoresSingleExpandedDirectory() async {
        let sub = makePath("sub")
        mkdir(sub)
        touch(makePath("sub", "readme.txt"))

        let state = FileTreeState(rootPath: tempDir)

        guard let subNode = state.rootNode?.children.first(where: { $0.name == "sub" }) else {
            return XCTFail("sub not found")
        }
        state.toggleExpanded(subNode.id)
        await state.awaitLoadChildren()
        // Re-fetch since FileNode is a value type
        guard let subAfterExpand = state.rootNode?.children.first(where: { $0.name == "sub" }) else {
            return XCTFail("sub not found after expand")
        }
        XCTAssertFalse(subAfterExpand.children.isEmpty)

        state.reload()
        await state.awaitReload()

        guard let subAfter = state.rootNode?.children.first(where: { $0.name == "sub" }) else {
            return XCTFail("sub not found after reload")
        }
        XCTAssertFalse(subAfter.children.isEmpty, "children should be restored after reload")
    }

    // MARK: - PreviewTab initial state

    func testSelectedPreviewTabDefaultsToContent() {
        let state = FileTreeState(rootPath: tempDir)
        XCTAssertEqual(state.selectedPreviewTab, .content)
    }

    func testSelectedFileDiffNilByDefault() {
        let state = FileTreeState(rootPath: tempDir)
        XCTAssertNil(state.selectedFileDiff)
    }

    // MARK: - Diff tab: file without git status has no diff tab

    func testSelectFileNotInGitStatusLeavesNoDiff() async {
        touch(makePath("plain.txt"))
        let state = FileTreeState(rootPath: tempDir)
        // gitStatusMap is empty (no git repo in tempDir), so no diff should be fetched
        state.selectFile(at: makePath("plain.txt"))
        await state.awaitSelectFile()
        XCTAssertNil(state.selectedFileDiff)
        XCTAssertEqual(state.selectedPreviewTab, .content)
    }

    // MARK: - PreviewTab manual switch

    func testManualTabSwitchToDiff() {
        let state = FileTreeState(rootPath: tempDir)
        state.selectedPreviewTab = .diff
        XCTAssertEqual(state.selectedPreviewTab, .diff)
    }

    func testManualTabSwitchBackToContent() {
        let state = FileTreeState(rootPath: tempDir)
        state.selectedPreviewTab = .diff
        state.selectedPreviewTab = .content
        XCTAssertEqual(state.selectedPreviewTab, .content)
    }

    // MARK: - Selecting new file resets diff state

    func testSelectingNewFileResetsDiffState() async {
        touch(makePath("a.txt"))
        touch(makePath("b.txt"))
        let state = FileTreeState(rootPath: tempDir)
        // Manually set a diff to simulate a previously loaded diff
        state.selectedFileDiff = "some diff"
        state.selectedPreviewTab = .diff

        // Select a new file (not in gitStatusMap → no diff)
        state.selectFile(at: makePath("b.txt"))
        await state.awaitSelectFile()

        XCTAssertNil(state.selectedFileDiff)
        XCTAssertEqual(state.selectedPreviewTab, .content)
    }

    // MARK: - stopWatching safety

    /// After deallocation (which triggers stopWatching), no pending reload should
    /// access the freed object. The weak-wrapper pattern in FSEventContext makes
    /// this safe: the callback sees nil and does nothing.
    func testDeallocAfterWatchingDoesNotCrash() {
        var state: FileTreeState? = FileTreeState(rootPath: tempDir)
        XCTAssertNotNil(state?.rootNode)
        // Deallocate while the FSEventStream is active — deinit calls stopWatching.
        state = nil
        // If we reach here, no use-after-free occurred.
    }

    /// After changeRoot (which calls stopWatching then startWatching), reload
    /// must operate on the new root without referencing stale state.
    func testReloadAfterChangeRootIsConsistent() async {
        let newDir = makePath("newRoot")
        mkdir(newDir)
        touch(makePath("newRoot", "hello.txt"))

        let state = FileTreeState(rootPath: tempDir)
        state.changeRoot(to: newDir)
        await state.awaitReload()
        state.reload()
        await state.awaitReload()

        XCTAssertEqual(state.rootPath, newDir)
        XCTAssertNotNil(state.rootNode)
        XCTAssertTrue(
            state.rootNode?.children.contains(where: { $0.name == "hello.txt" }) == true
        )
    }

    // MARK: - Git root detection

    func testDetectGitRootFromSubdirectory() throws {
        let gitRoot = makePath("repo")
        mkdir(gitRoot)
        let subDir = makePath("repo", "frontend")
        mkdir(subDir)

        // Initialize a git repo at gitRoot
        let initProc = Process()
        initProc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        initProc.arguments = ["init", gitRoot]
        initProc.standardOutput = FileHandle.nullDevice
        initProc.standardError = FileHandle.nullDevice
        try initProc.run()
        initProc.waitUntilExit()
        XCTAssertEqual(initProc.terminationStatus, 0)

        let detected = FileTreeState.detectGitRoot(for: subDir)
        // Resolve symlinks for macOS /private/var/folders vs /var/folders
        let resolvedGitRoot = (gitRoot as NSString).resolvingSymlinksInPath
        let resolvedDetected = detected.map { ($0 as NSString).resolvingSymlinksInPath }
        XCTAssertEqual(resolvedDetected, resolvedGitRoot)
    }

    func testDetectGitRootAtRepoRoot() throws {
        let gitRoot = makePath("repo2")
        mkdir(gitRoot)

        let initProc = Process()
        initProc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        initProc.arguments = ["init", gitRoot]
        initProc.standardOutput = FileHandle.nullDevice
        initProc.standardError = FileHandle.nullDevice
        try initProc.run()
        initProc.waitUntilExit()

        let detected = FileTreeState.detectGitRoot(for: gitRoot)
        let resolvedGitRoot = (gitRoot as NSString).resolvingSymlinksInPath
        let resolvedDetected = detected.map { ($0 as NSString).resolvingSymlinksInPath }
        XCTAssertEqual(resolvedDetected, resolvedGitRoot)
    }

    func testDetectGitRootOutsideRepoReturnsNil() {
        // tempDir is not inside a git repo (it's a unique temp directory)
        let isolated = makePath("nogit")
        mkdir(isolated)
        // We need a directory that's truly outside any git repo.
        // Since tempDir itself might be under a git repo, create a .git-less check.
        // Use the function and verify behavior - if tempDir happens to be in a git repo,
        // the result will be non-nil but != isolated, which is still correct behavior.
        let detected = FileTreeState.detectGitRoot(for: isolated)
        // If detected is non-nil, it should NOT equal isolated (isolated has no .git)
        if let detected {
            let resolvedIsolated = (isolated as NSString).resolvingSymlinksInPath
            let resolvedDetected = (detected as NSString).resolvingSymlinksInPath
            XCTAssertNotEqual(resolvedDetected, resolvedIsolated,
                "detectGitRoot should not return the directory itself when it has no .git")
        }
        // If nil, that's the expected case for a non-git directory
    }

    // MARK: - Depth limit safety

    /// toggleExpanded (which uses findNode internally) should not crash
    /// even when the tree is very deeply nested.
    func testToggleExpandedDoesNotCrashOnDeeplyNestedTree() async {
        // Create a directory structure deeper than maxTraversalDepth
        let depth = FileNode.maxTraversalDepth + 10
        var path = tempDir!
        for i in 0..<depth {
            path = (path as NSString).appendingPathComponent("d\(i)")
            mkdir(path)
        }
        touch((path as NSString).appendingPathComponent("leaf.txt"))

        let state = FileTreeState(rootPath: tempDir)

        // Expand directories as deep as possible — should not crash
        var current = state.rootNode
        for _ in 0..<depth {
            guard let dir = current?.children.first(where: { $0.isDirectory }) else { break }
            state.toggleExpanded(dir.id)
            await state.awaitLoadChildren()
            // Re-fetch from updated tree
            current = findNode(named: dir.name, in: state.rootNode!)
        }
        // Reaching here without a crash is the test passing
    }

    /// reload (which uses restoreExpanded internally) should not crash
    /// even when many directories are expanded deeply.
    func testReloadDoesNotCrashOnDeeplyNestedExpandedTree() async {
        let depth = FileNode.maxTraversalDepth + 10
        var path = tempDir!
        for i in 0..<depth {
            path = (path as NSString).appendingPathComponent("d\(i)")
            mkdir(path)
        }
        touch((path as NSString).appendingPathComponent("leaf.txt"))

        let state = FileTreeState(rootPath: tempDir)

        // Expand as deep as possible
        var current = state.rootNode
        for _ in 0..<depth {
            guard let dir = current?.children.first(where: { $0.isDirectory }) else { break }
            state.toggleExpanded(dir.id)
            await state.awaitLoadChildren()
            current = findNode(named: dir.name, in: state.rootNode!)
        }

        // reload should not crash even with deeply nested expansions
        state.reload()
        await state.awaitReload()
        XCTAssertNotNil(state.rootNode)
    }

    // MARK: - FileNode filtering by name

    func testFilteredByNameReturnsMatchingFiles() {
        let tree: FileNode = .directory(id: UUID(), name: "root", path: "/root", children: [
            .file(id: UUID(), name: "hello.swift", path: "/root/hello.swift"),
            .file(id: UUID(), name: "world.txt", path: "/root/world.txt"),
            .file(id: UUID(), name: "README.md", path: "/root/README.md"),
        ])
        let result = tree.filteredByName("swift")
        XCTAssertEqual(result?.children.count, 1)
        XCTAssertEqual(result?.children.first?.name, "hello.swift")
    }

    func testFilteredByNameIsCaseInsensitive() {
        let tree: FileNode = .directory(id: UUID(), name: "root", path: "/root", children: [
            .file(id: UUID(), name: "README.md", path: "/root/README.md"),
            .file(id: UUID(), name: "readme.txt", path: "/root/readme.txt"),
        ])
        let result = tree.filteredByName("readme")
        XCTAssertEqual(result?.children.count, 2)
    }

    func testFilteredByNamePreservesParentDirectories() {
        let tree: FileNode = .directory(id: UUID(), name: "root", path: "/root", children: [
            .directory(id: UUID(), name: "src", path: "/root/src", children: [
                .file(id: UUID(), name: "app.swift", path: "/root/src/app.swift"),
                .file(id: UUID(), name: "util.swift", path: "/root/src/util.swift"),
            ]),
            .directory(id: UUID(), name: "docs", path: "/root/docs", children: [
                .file(id: UUID(), name: "guide.md", path: "/root/docs/guide.md"),
            ]),
        ])
        let result = tree.filteredByName("swift")
        XCTAssertEqual(result?.children.count, 1) // only src
        XCTAssertEqual(result?.children.first?.name, "src")
        XCTAssertEqual(result?.children.first?.children.count, 2)
    }

    func testFilteredByNameReturnsNilWhenNoMatch() {
        let tree: FileNode = .directory(id: UUID(), name: "root", path: "/root", children: [
            .file(id: UUID(), name: "hello.swift", path: "/root/hello.swift"),
        ])
        let result = tree.filteredByName("xyz")
        XCTAssertNil(result)
    }

    func testFilteredByNameWithEmptyQueryReturnsOriginal() {
        let tree: FileNode = .directory(id: UUID(), name: "root", path: "/root", children: [
            .file(id: UUID(), name: "hello.swift", path: "/root/hello.swift"),
        ])
        let result = tree.filteredByName("")
        XCTAssertEqual(result, tree)
    }

    func testFilteredByNameMatchesDirectoryNames() {
        let tree: FileNode = .directory(id: UUID(), name: "root", path: "/root", children: [
            .directory(id: UUID(), name: "Sources", path: "/root/Sources", children: [
                .file(id: UUID(), name: "main.swift", path: "/root/Sources/main.swift"),
            ]),
            .file(id: UUID(), name: "README.md", path: "/root/README.md"),
        ])
        let result = tree.filteredByName("source")
        XCTAssertEqual(result?.children.count, 1)
        XCTAssertEqual(result?.children.first?.name, "Sources")
        // When directory name matches, include all children
        XCTAssertEqual(result?.children.first?.children.count, 1)
    }

    // MARK: - FileNode filtering by paths

    func testFilteredByPathsReturnsMatchingFiles() {
        let tree: FileNode = .directory(id: UUID(), name: "root", path: "/root", children: [
            .file(id: UUID(), name: "hello.swift", path: "/root/hello.swift"),
            .file(id: UUID(), name: "world.txt", path: "/root/world.txt"),
            .directory(id: UUID(), name: "src", path: "/root/src", children: [
                .file(id: UUID(), name: "app.swift", path: "/root/src/app.swift"),
            ]),
        ])
        let paths: Set<String> = ["/root/hello.swift", "/root/src/app.swift"]
        let result = tree.filteredByPaths(paths)
        XCTAssertEqual(result?.children.count, 2) // hello.swift and src/
        XCTAssertTrue(result?.children.contains(where: { $0.name == "hello.swift" }) == true)
        XCTAssertTrue(result?.children.contains(where: { $0.name == "src" }) == true)
    }

    func testFilteredByPathsReturnsNilWhenNoMatch() {
        let tree: FileNode = .directory(id: UUID(), name: "root", path: "/root", children: [
            .file(id: UUID(), name: "hello.swift", path: "/root/hello.swift"),
        ])
        let paths: Set<String> = ["/other/file.txt"]
        let result = tree.filteredByPaths(paths)
        XCTAssertNil(result)
    }

    func testFilteredByEmptyPathsReturnsNil() {
        let tree: FileNode = .directory(id: UUID(), name: "root", path: "/root", children: [
            .file(id: UUID(), name: "hello.swift", path: "/root/hello.swift"),
        ])
        let result = tree.filteredByPaths([])
        XCTAssertNil(result)
    }

    // MARK: - Git diff filter

    func testGitDiffFilterOffReturnsFull树() {
        touch(makePath("a.txt"))
        touch(makePath("b.txt"))
        let state = FileTreeState(rootPath: tempDir)
        state.isGitDiffFilterEnabled = false
        // gitStatusMap is empty → filter off should return full rootNode
        XCTAssertEqual(state.filteredRootNode()?.children.count, state.rootNode?.children.count)
    }

    func testGitDiffFilterOnWithNoChangesReturnsNil() {
        touch(makePath("a.txt"))
        let state = FileTreeState(rootPath: tempDir)
        // gitStatusMap is empty (not a git repo), filter on → no matches
        state.isGitDiffFilterEnabled = true
        XCTAssertNil(state.filteredRootNode())
    }

    func testGitDiffFilterOnShowsOnlyChangedFiles() {
        touch(makePath("changed.swift"))
        touch(makePath("clean.swift"))
        touch(makePath("new.txt"))
        let state = FileTreeState(rootPath: tempDir)
        // Simulate git status: changed.swift modified, new.txt untracked
        state.gitStatusMap = [
            makePath("changed.swift"): .modified,
            makePath("new.txt"): .untracked,
        ]
        state.isGitDiffFilterEnabled = true
        let result = state.filteredRootNode()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.children.count, 2)
        XCTAssertTrue(result?.children.contains(where: { $0.name == "changed.swift" }) == true)
        XCTAssertTrue(result?.children.contains(where: { $0.name == "new.txt" }) == true)
        XCTAssertFalse(result?.children.contains(where: { $0.name == "clean.swift" }) == true)
    }

    func testGitDiffFilterMaintainsDirectoryHierarchy() async {
        mkdir(makePath("src"))
        touch(makePath("src", "changed.swift"))
        touch(makePath("src", "clean.swift"))
        let state = FileTreeState(rootPath: tempDir)
        // Expand src so children are loaded
        guard let srcNode = state.rootNode?.children.first(where: { $0.name == "src" }) else {
            return XCTFail("src not found")
        }
        state.toggleExpanded(srcNode.id)
        await state.awaitLoadChildren()
        state.gitStatusMap = [makePath("src", "changed.swift"): .modified]
        state.isGitDiffFilterEnabled = true
        let result = state.filteredRootNode()
        // Only src directory should appear (contains changed.swift)
        XCTAssertEqual(result?.children.count, 1)
        XCTAssertEqual(result?.children.first?.name, "src")
        // Inside src, only changed.swift
        XCTAssertEqual(result?.children.first?.children.count, 1)
        XCTAssertEqual(result?.children.first?.children.first?.name, "changed.swift")
    }

    func testGitDiffFilterIgnoredWhenSearchQueryIsActive() {
        touch(makePath("foo.swift"))
        touch(makePath("bar.txt"))
        let state = FileTreeState(rootPath: tempDir)
        state.gitStatusMap = [makePath("foo.swift"): .modified]
        state.isGitDiffFilterEnabled = true
        // Active search query takes precedence
        state.treeSearchQuery = "bar"
        let result = state.filteredRootNode()
        XCTAssertEqual(result?.children.count, 1)
        XCTAssertEqual(result?.children.first?.name, "bar.txt")
    }

    // MARK: - Private helpers

    private func findNode(named name: String, in node: FileNode) -> FileNode? {
        if node.name == name { return node }
        for child in node.children {
            if let found = findNode(named: name, in: child) { return found }
        }
        return nil
    }
}
