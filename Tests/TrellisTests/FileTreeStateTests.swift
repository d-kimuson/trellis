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
    func testReloadRestoresNestedExpandedDirectories() {
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

        // Expand tmp → qa becomes visible
        guard let tmpNode = findNode(named: "tmp", in: state.rootNode!) else {
            return XCTFail("tmp not found after expanding docs")
        }
        state.toggleExpanded(tmpNode.id)

        // Expand qa → file.txt becomes visible
        guard let qaNode = findNode(named: "qa", in: state.rootNode!) else {
            return XCTFail("qa not found after expanding tmp")
        }
        state.toggleExpanded(qaNode.id)

        // Verify qa's children are loaded before reload (re-fetch since FileNode is a value type)
        guard let qaAfterExpand = findNode(named: "qa", in: state.rootNode!) else {
            return XCTFail("qa not found after expanding it")
        }
        XCTAssertFalse(qaAfterExpand.children.isEmpty, "qa should have children before reload")

        // Simulate reload (e.g. triggered by FSEvent)
        state.reload()

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

    func testReloadRestoresSingleExpandedDirectory() {
        let sub = makePath("sub")
        mkdir(sub)
        touch(makePath("sub", "readme.txt"))

        let state = FileTreeState(rootPath: tempDir)

        guard let subNode = state.rootNode?.children.first(where: { $0.name == "sub" }) else {
            return XCTFail("sub not found")
        }
        state.toggleExpanded(subNode.id)
        // Re-fetch since FileNode is a value type
        guard let subAfterExpand = state.rootNode?.children.first(where: { $0.name == "sub" }) else {
            return XCTFail("sub not found after expand")
        }
        XCTAssertFalse(subAfterExpand.children.isEmpty)

        state.reload()

        guard let subAfter = state.rootNode?.children.first(where: { $0.name == "sub" }) else {
            return XCTFail("sub not found after reload")
        }
        XCTAssertFalse(subAfter.children.isEmpty, "children should be restored after reload")
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
