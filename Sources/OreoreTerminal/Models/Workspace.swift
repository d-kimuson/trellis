import Foundation

/// A workspace containing a layout tree of areas.
public struct Workspace: Identifiable {
    public let id: UUID
    public var name: String
    public var layout: LayoutNode
    public var activeAreaId: UUID?

    public init(id: UUID = UUID(), name: String, layout: LayoutNode, activeAreaId: UUID? = nil) {
        self.id = id
        self.name = name
        self.layout = layout
        self.activeAreaId = activeAreaId
    }

    /// The currently active area, if any.
    public var activeArea: Area? {
        guard let activeAreaId else { return nil }
        return layout.findArea(id: activeAreaId)
    }

    /// All areas in this workspace.
    public var allAreas: [Area] {
        layout.allAreas
    }
}
