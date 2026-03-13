import Foundation
import Observation

/// Manages content search across files in the tree.
/// Placeholder for future full-text search implementation.
@Observable
public final class ContentSearchProvider {
    public var searchQuery: String = ""
    public var isSearchActive: Bool = false

    public init() {}
}
