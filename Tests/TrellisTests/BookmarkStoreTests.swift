import Foundation
import XCTest
@testable import Trellis

final class BookmarkStoreTests: XCTestCase {

    private var tempDir: URL!
    private let testDefaultsKey = "trellis.fileTreeBookmarks"

    override func setUp() {
        super.setUp()
        // Use a fresh UserDefaults suite to isolate tests
        BookmarkStore.defaults = UserDefaults(suiteName: "BookmarkStoreTests.\(UUID().uuidString)")!

        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("BookmarkStoreTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        tempDir = URL(fileURLWithPath: path)
    }

    override func tearDown() {
        super.tearDown()
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - save and resolve

    func testSaveAndResolveReturnsSamePath() throws {
        BookmarkStore.save(url: tempDir)
        let resolved = BookmarkStore.resolve(path: tempDir.path)
        XCTAssertNotNil(resolved, "Should resolve a saved bookmark")
        // Bookmark resolution may return the canonical path (e.g. /private/var on macOS).
        // Compare using standardized paths.
        XCTAssertEqual(
            resolved?.standardizedFileURL.path,
            tempDir.standardizedFileURL.path
        )
    }

    func testResolveReturnsNilForUnknownPath() {
        let result = BookmarkStore.resolve(path: "/nonexistent/path/\(UUID().uuidString)")
        XCTAssertNil(result, "Resolving unknown path should return nil")
    }

    func testRemoveDeletesBookmark() {
        BookmarkStore.save(url: tempDir)
        XCTAssertNotNil(BookmarkStore.resolve(path: tempDir.path))

        BookmarkStore.remove(path: tempDir.path)
        XCTAssertNil(BookmarkStore.resolve(path: tempDir.path), "Bookmark should be gone after remove")
    }

    func testSaveOverwritesPreviousBookmark() {
        // Save twice — should not crash and still resolve correctly
        BookmarkStore.save(url: tempDir)
        BookmarkStore.save(url: tempDir)
        let resolved = BookmarkStore.resolve(path: tempDir.path)
        XCTAssertEqual(
            resolved?.standardizedFileURL.path,
            tempDir.standardizedFileURL.path
        )
    }
}
