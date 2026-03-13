import Foundation

/// Direction of a split between two layout regions.
public enum SplitDirection {
    case horizontal
    case vertical
}

/// A recursive tree structure representing the layout of areas.
/// Each node is either a single area (leaf) or a split containing two children.
public indirect enum LayoutNode: Identifiable {
    case leaf(Area)
    case split(id: UUID, direction: SplitDirection, first: LayoutNode, second: LayoutNode, ratio: Double)

    public var id: UUID {
        switch self {
        case .leaf(let area):
            return area.id
        case .split(let id, _, _, _, _):
            return id
        }
    }

    // MARK: - Query

    /// Collects all areas in the tree (depth-first).
    public var allAreas: [Area] {
        switch self {
        case .leaf(let area):
            return [area]
        case .split(_, _, let first, let second, _):
            return first.allAreas + second.allAreas
        }
    }

    /// Finds an area by its ID.
    public func findArea(id areaId: UUID) -> Area? {
        switch self {
        case .leaf(let area):
            return area.id == areaId ? area : nil
        case .split(_, _, let first, let second, _):
            return first.findArea(id: areaId) ?? second.findArea(id: areaId)
        }
    }

    // MARK: - Transformations

    /// Returns a new tree with the given area split into two areas.
    /// When `insertBefore` is true, newArea is placed first (left/top).
    public func splittingArea(
        areaId: UUID,
        direction: SplitDirection,
        newArea: Area,
        insertBefore: Bool = false
    ) -> LayoutNode {
        switch self {
        case .leaf(let area) where area.id == areaId:
            let existing = LayoutNode.leaf(area)
            let new = LayoutNode.leaf(newArea)
            return .split(
                id: UUID(),
                direction: direction,
                first: insertBefore ? new : existing,
                second: insertBefore ? existing : new,
                ratio: 0.5
            )
        case .leaf:
            return self
        case .split(let id, let dir, let first, let second, let ratio):
            if first.findArea(id: areaId) != nil {
                return .split(
                    id: id, direction: dir,
                    first: first.splittingArea(areaId: areaId, direction: direction, newArea: newArea, insertBefore: insertBefore),
                    second: second,
                    ratio: ratio
                )
            } else {
                return .split(
                    id: id, direction: dir,
                    first: first,
                    second: second.splittingArea(areaId: areaId, direction: direction, newArea: newArea, insertBefore: insertBefore),
                    ratio: ratio
                )
            }
        }
    }

    /// Returns a new tree with the given area removed.
    /// When a split loses one child, the remaining child is promoted.
    public func removingArea(areaId: UUID) -> LayoutNode {
        switch self {
        case .leaf(let area) where area.id == areaId:
            // Removal at root level - caller should handle this case
            return self
        case .leaf:
            return self
        case .split(let id, let dir, let first, let second, let ratio):
            if case .leaf(let area) = first, area.id == areaId {
                return second
            }
            if case .leaf(let area) = second, area.id == areaId {
                return first
            }
            if first.findArea(id: areaId) != nil {
                return .split(id: id, direction: dir, first: first.removingArea(areaId: areaId), second: second, ratio: ratio)
            } else {
                return .split(id: id, direction: dir, first: first, second: second.removingArea(areaId: areaId), ratio: ratio)
            }
        }
    }

    /// Update the split ratio for a specific split node.
    public func updatingRatio(splitId: UUID, ratio: Double) -> LayoutNode {
        switch self {
        case .leaf:
            return self
        case .split(let id, let dir, let first, let second, let currentRatio):
            let newRatio = id == splitId ? ratio : currentRatio
            return .split(
                id: id,
                direction: dir,
                first: first.updatingRatio(splitId: splitId, ratio: ratio),
                second: second.updatingRatio(splitId: splitId, ratio: ratio),
                ratio: newRatio
            )
        }
    }

    /// Returns a new tree with the specified area replaced.
    public func updatingArea(areaId: UUID, transform: (Area) -> Area) -> LayoutNode {
        switch self {
        case .leaf(let area) where area.id == areaId:
            return .leaf(transform(area))
        case .leaf:
            return self
        case .split(let id, let dir, let first, let second, let ratio):
            if first.findArea(id: areaId) != nil {
                return .split(id: id, direction: dir, first: first.updatingArea(areaId: areaId, transform: transform), second: second, ratio: ratio)
            } else {
                return .split(id: id, direction: dir, first: first, second: second.updatingArea(areaId: areaId, transform: transform), ratio: ratio)
            }
        }
    }
}
