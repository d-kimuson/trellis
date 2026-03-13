import Foundation
import XCTest
@testable import Trellis

final class FileNodeTests: XCTestCase {

    // MARK: - shouldIgnore

    func testShouldIgnoreAlwaysIgnoredDotEntries() {
        XCTAssertTrue(FileNode.shouldIgnore(name: ".git", patterns: []))
        XCTAssertTrue(FileNode.shouldIgnore(name: ".DS_Store", patterns: []))
        XCTAssertTrue(FileNode.shouldIgnore(name: ".svn", patterns: []))
        XCTAssertTrue(FileNode.shouldIgnore(name: ".hg", patterns: []))
    }

    func testShouldNotIgnoreDotFilesOutsideAlwaysIgnoredList() {
        XCTAssertFalse(FileNode.shouldIgnore(name: ".claude", patterns: []))
        XCTAssertFalse(FileNode.shouldIgnore(name: ".env", patterns: []))
        XCTAssertFalse(FileNode.shouldIgnore(name: ".envrc", patterns: []))
        XCTAssertFalse(FileNode.shouldIgnore(name: ".gitignore", patterns: []))
    }

    func testShouldIgnoreExactMatch() {
        XCTAssertTrue(FileNode.shouldIgnore(name: "node_modules", patterns: ["node_modules"]))
        XCTAssertFalse(FileNode.shouldIgnore(name: "src", patterns: ["node_modules"]))
    }

    func testShouldIgnoreDirectoryPattern() {
        XCTAssertTrue(FileNode.shouldIgnore(name: "build", patterns: ["build/"]))
        XCTAssertFalse(FileNode.shouldIgnore(name: "building", patterns: ["build/"]))
    }

    func testShouldIgnoreWildcardExtension() {
        XCTAssertTrue(FileNode.shouldIgnore(name: "file.o", patterns: ["*.o"]))
        XCTAssertTrue(FileNode.shouldIgnore(name: "test.log", patterns: ["*.log"]))
        XCTAssertFalse(FileNode.shouldIgnore(name: "file.swift", patterns: ["*.o"]))
    }

    func testShouldNotIgnoreNormalFiles() {
        XCTAssertFalse(FileNode.shouldIgnore(name: "main.swift", patterns: []))
        XCTAssertFalse(FileNode.shouldIgnore(name: "README.md", patterns: ["*.o"]))
    }

    // MARK: - parseGitignore

    func testParseGitignoreSkipsCommentsAndEmptyLines() {
        let tempDir = NSTemporaryDirectory()
        let gitignorePath = (tempDir as NSString).appendingPathComponent("test_gitignore_\(UUID().uuidString)")
        let content = """
        # Comment
        node_modules

        *.o
        build/

        # Another comment
        """
        try? content.write(toFile: gitignorePath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: gitignorePath) }

        let patterns = FileNode.parseGitignore(at: gitignorePath)
        XCTAssertEqual(patterns, ["node_modules", "*.o", "build/"])
    }

    func testParseGitignoreNonexistentFileReturnsEmpty() {
        let patterns = FileNode.parseGitignore(at: "/nonexistent/path/.gitignore")
        XCTAssertEqual(patterns, [])
    }

    // MARK: - FileNode properties

    func testFileNodeProperties() {
        let fileNode = FileNode.file(id: UUID(), name: "test.swift", path: "/tmp/test.swift")
        XCTAssertEqual(fileNode.name, "test.swift")
        XCTAssertEqual(fileNode.path, "/tmp/test.swift")
        XCTAssertFalse(fileNode.isDirectory)
        XCTAssertEqual(fileNode.children.count, 0)
    }

    func testDirectoryNodeProperties() {
        let child = FileNode.file(id: UUID(), name: "a.txt", path: "/tmp/dir/a.txt")
        let dirNode = FileNode.directory(id: UUID(), name: "dir", path: "/tmp/dir", children: [child])
        XCTAssertEqual(dirNode.name, "dir")
        XCTAssertTrue(dirNode.isDirectory)
        XCTAssertEqual(dirNode.children.count, 1)
    }

    // MARK: - buildTree (shallow)

    func testBuildTreeFromDirectory() {
        let tempDir = NSTemporaryDirectory()
        let testDir = (tempDir as NSString).appendingPathComponent("filetree_test_\(UUID().uuidString)")
        let fileManager = FileManager.default

        // Create test structure
        try? fileManager.createDirectory(atPath: testDir, withIntermediateDirectories: true)
        try? "hello".write(
            toFile: (testDir as NSString).appendingPathComponent("file.txt"),
            atomically: true,
            encoding: .utf8
        )
        let subDir = (testDir as NSString).appendingPathComponent("subdir")
        try? fileManager.createDirectory(atPath: subDir, withIntermediateDirectories: true)
        try? "world".write(
            toFile: (subDir as NSString).appendingPathComponent("nested.txt"),
            atomically: true,
            encoding: .utf8
        )

        defer { try? fileManager.removeItem(atPath: testDir) }

        let node = FileNode.buildTree(at: testDir, ignoredPatterns: [])
        XCTAssertNotNil(node)
        XCTAssertTrue(node!.isDirectory)
        // Should have 2 children: subdir and file.txt
        XCTAssertEqual(node!.children.count, 2)
        // Directories should come first
        XCTAssertTrue(node!.children[0].isDirectory)
        XCTAssertFalse(node!.children[1].isDirectory)
        // Subdirectory children should be empty (lazy loading)
        XCTAssertEqual(node!.children[0].children.count, 0)
    }

    func testBuildTreeFiltersIgnoredPatterns() {
        let tempDir = NSTemporaryDirectory()
        let testDir = (tempDir as NSString).appendingPathComponent("filetree_ignore_\(UUID().uuidString)")
        let fileManager = FileManager.default

        try? fileManager.createDirectory(atPath: testDir, withIntermediateDirectories: true)
        try? "a".write(
            toFile: (testDir as NSString).appendingPathComponent("keep.txt"),
            atomically: true,
            encoding: .utf8
        )
        try? "b".write(
            toFile: (testDir as NSString).appendingPathComponent("remove.o"),
            atomically: true,
            encoding: .utf8
        )

        defer { try? fileManager.removeItem(atPath: testDir) }

        let node = FileNode.buildTree(at: testDir, ignoredPatterns: ["*.o"])
        XCTAssertNotNil(node)
        XCTAssertEqual(node!.children.count, 1)
        XCTAssertEqual(node!.children[0].name, "keep.txt")
    }

    func testBuildTreeNonexistentPathReturnsNil() {
        let node = FileNode.buildTree(at: "/nonexistent/path/\(UUID().uuidString)")
        XCTAssertNil(node)
    }

    // MARK: - loadChildren (lazy)

    func testLoadChildrenReturnsDirectoryContents() {
        let tempDir = NSTemporaryDirectory()
        let testDir = (tempDir as NSString).appendingPathComponent("filetree_lazy_\(UUID().uuidString)")
        let fileManager = FileManager.default

        let subDir = (testDir as NSString).appendingPathComponent("subdir")
        try? fileManager.createDirectory(atPath: subDir, withIntermediateDirectories: true)
        try? "content".write(
            toFile: (subDir as NSString).appendingPathComponent("file.txt"),
            atomically: true,
            encoding: .utf8
        )

        defer { try? fileManager.removeItem(atPath: testDir) }

        let children = FileNode.loadChildren(at: subDir, ignoredPatterns: [])
        XCTAssertEqual(children.count, 1)
        XCTAssertEqual(children[0].name, "file.txt")
    }

    // MARK: - stableUUID

    func testStableUUIDIsDeterministic() {
        let path = "/Users/kaito/repos/trellis/Sources/main.swift"
        XCTAssertEqual(FileNode.stableUUID(for: path), FileNode.stableUUID(for: path))
    }

    func testStableUUIDNoCollisionForSwappedBlockPaths() {
        // XOR ハッシュでは 16バイトブロックを入れ替えると衝突する
        // "aaa...aaa" (16個) + "AAA...AAA" (16個) と
        // "AAA...AAA" (16個) + "aaa...aaa" (16個) は同じXORハッシュになる
        let path1 = "aaaaaaaaaaaaaaaaAAAAAAAAAAAAAAAA"
        let path2 = "AAAAAAAAAAAAAAAAaaaaaaaaaaaaaaaa"
        XCTAssertNotEqual(FileNode.stableUUID(for: path1), FileNode.stableUUID(for: path2))
    }

    func testStableUUIDDifferentPathsProduceDifferentUUIDs() {
        XCTAssertNotEqual(
            FileNode.stableUUID(for: "/foo/bar/baz"),
            FileNode.stableUUID(for: "/foo/bar/qux")
        )
    }

    func testStableUUIDVersionBitsAreSet() {
        let uuid = FileNode.stableUUID(for: "/some/path")
        // UUID v5: version nibble (bits 4-7 of byte 6) = 0x5
        let uuidBytes = withUnsafeBytes(of: uuid.uuid) { Array($0) }
        XCTAssertEqual(uuidBytes[6] >> 4, 0x5, "UUID version nibble should be 5")
        XCTAssertEqual(uuidBytes[8] >> 6, 0x2, "UUID variant bits should be 0b10")
    }

    // MARK: - replacingChildren

    func testReplacingChildrenStopsAtMaxDepth() {
        // Build a tree deeper than maxTraversalDepth
        let deepId = UUID()
        var tree = FileNode.directory(id: deepId, name: "deep", path: "/deep", children: [])

        // Wrap the target node in (maxTraversalDepth + 5) layers of directories
        let extraDepth = FileNode.maxTraversalDepth + 5
        for i in 0..<extraDepth {
            tree = FileNode.directory(
                id: UUID(), name: "level\(i)", path: "/level\(i)", children: [tree]
            )
        }

        let newChildren: [FileNode] = [
            .file(id: UUID(), name: "injected.txt", path: "/deep/injected.txt")
        ]

        // replacingChildren should NOT reach the deeply-buried node
        let updated = tree.replacingChildren(ofNodeId: deepId, with: newChildren)

        // Walk down to the deepest node — it should still have empty children
        var current = updated
        while !current.children.isEmpty {
            current = current.children[0]
        }
        XCTAssertEqual(current.id, deepId)
        XCTAssertTrue(current.children.isEmpty, "replacingChildren should stop before reaching nodes beyond maxTraversalDepth")
    }

    func testReplacingChildrenUpdatesTargetNode() {
        let childDirId = UUID()
        let root = FileNode.directory(
            id: UUID(),
            name: "root",
            path: "/root",
            children: [
                .directory(id: childDirId, name: "sub", path: "/root/sub", children: [])
            ]
        )

        let newChildren: [FileNode] = [
            .file(id: UUID(), name: "new.txt", path: "/root/sub/new.txt")
        ]

        let updated = root.replacingChildren(ofNodeId: childDirId, with: newChildren)
        XCTAssertEqual(updated.children[0].children.count, 1)
        XCTAssertEqual(updated.children[0].children[0].name, "new.txt")
    }
}
