import Foundation

indirect enum LayoutNodeSnapshot: Codable {
    case leaf(areaId: UUID)
    case split(id: UUID, direction: String, ratio: Double, first: LayoutNodeSnapshot, second: LayoutNodeSnapshot)

    private enum CodingKeys: String, CodingKey {
        case type, areaId, id, direction, ratio, first, second
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "leaf":
            self = .leaf(areaId: try container.decode(UUID.self, forKey: .areaId))
        default:
            self = .split(
                id: try container.decode(UUID.self, forKey: .id),
                direction: try container.decode(String.self, forKey: .direction),
                ratio: try container.decode(Double.self, forKey: .ratio),
                first: try container.decode(LayoutNodeSnapshot.self, forKey: .first),
                second: try container.decode(LayoutNodeSnapshot.self, forKey: .second)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .leaf(let areaId):
            try container.encode("leaf", forKey: .type)
            try container.encode(areaId, forKey: .areaId)
        case .split(let id, let direction, let ratio, let first, let second):
            try container.encode("split", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(direction, forKey: .direction)
            try container.encode(ratio, forKey: .ratio)
            try container.encode(first, forKey: .first)
            try container.encode(second, forKey: .second)
        }
    }
}

struct TabSnapshot: Codable {
    let tabId: UUID
    let type: String  // "terminal" | "browser" | "fileTree"
    let cwd: String?
    let scrollback: String?
    let terminalCols: Int?  // terminal width at capture time; used to resize before replay
    let browserURL: String?
    let fileTreePath: String?
    let gitBranch: String?
    let runningCommand: String?  // command that was executing at snapshot time
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
    let layoutSnapshot: LayoutNodeSnapshot?
    let savedAt: Date
}
