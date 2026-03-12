import Foundation

/// Persists URL bookmarks to UserDefaults so file-tree roots survive app restarts.
///
/// Bookmarks are keyed by the URL's path string. On non-sandboxed builds the
/// `.minimalBookmark` option is used, which tracks the file identity and can
/// resolve path changes (e.g. volume remounts). When App Sandbox is enabled in
/// the future, add `.withSecurityScope` to both `bookmarkData` and
/// `URL(resolvingBookmarkData:options:)` calls and call
/// `startAccessingSecurityScopedResource()` after resolving.
public enum BookmarkStore {

    /// UserDefaults instance used for storage. Override in tests.
    public static var defaults: UserDefaults = .standard

    private static let storageKey = "trellis.fileTreeBookmarks"

    // MARK: - Public API

    /// Create and persist a bookmark for `url`.
    /// Silently ignores errors (e.g. permission denied); the caller can still
    /// use the raw path as a fallback.
    public static func save(url: URL) {
        guard let data = try? url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }

        var bookmarks = stored()
        bookmarks[url.path] = data
        defaults.set(bookmarks, forKey: storageKey)
    }

    /// Resolve a previously-saved bookmark for `path`.
    ///
    /// - Returns: The resolved `URL` (which may differ from `path` if e.g. a
    ///   volume was remounted), or `nil` if no bookmark exists or resolution fails.
    public static func resolve(path: String) -> URL? {
        let bookmarks = stored()
        guard let data = bookmarks[path] else { return nil }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        if isStale {
            save(url: url)
        }

        return url
    }

    /// Remove the stored bookmark for `path`.
    public static func remove(path: String) {
        var bookmarks = stored()
        bookmarks.removeValue(forKey: path)
        defaults.set(bookmarks, forKey: storageKey)
    }

    // MARK: - Private

    private static func stored() -> [String: Data] {
        defaults.dictionary(forKey: storageKey) as? [String: Data] ?? [:]
    }
}
