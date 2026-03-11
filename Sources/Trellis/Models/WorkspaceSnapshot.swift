import Foundation

struct TabSnapshot: Codable {
    let tabId: UUID
    let type: String  // "terminal" | "browser" | "fileTree"
    let cwd: String?
    let scrollback: String?
    let browserURL: String?
    let fileTreePath: String?
}

struct AreaSnapshot: Codable {
    let areaId: UUID
    let tabs: [TabSnapshot]
    let activeTabIndex: Int
}

struct WorkspaceSnapshot: Codable {
    let schemaVersion: Int
    let id: UUID
    let name: String
    let isPinned: Bool
    let areas: [AreaSnapshot]
    let savedAt: Date
}
