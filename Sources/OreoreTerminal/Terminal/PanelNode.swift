import Foundation

public enum SplitDirection {
    case horizontal
    case vertical
}

/// A recursive tree structure representing the terminal panel layout.
/// Each node is either a single terminal or a split containing two children.
public indirect enum PanelNode: Identifiable {
    case terminal(TerminalSession)
    case split(id: UUID, direction: SplitDirection, first: PanelNode, second: PanelNode, ratio: Double)

    public var id: UUID {
        switch self {
        case .terminal(let session):
            return session.id
        case .split(let id, _, _, _, _):
            return id
        }
    }

    /// Returns a new tree with the given session's panel split
    public func splitting(sessionId: UUID, direction: SplitDirection, newSession: TerminalSession) -> PanelNode {
        switch self {
        case .terminal(let session) where session.id == sessionId:
            return .split(
                id: UUID(),
                direction: direction,
                first: .terminal(session),
                second: .terminal(newSession),
                ratio: 0.5
            )
        case .terminal:
            return self
        case .split(let id, let dir, let first, let second, let ratio):
            return .split(
                id: id,
                direction: dir,
                first: first.splitting(sessionId: sessionId, direction: direction, newSession: newSession),
                second: second.splitting(sessionId: sessionId, direction: direction, newSession: newSession),
                ratio: ratio
            )
        }
    }

    /// Returns a new tree with the given session removed.
    /// When a split loses one child, the remaining child is promoted.
    public func removing(sessionId: UUID) -> PanelNode {
        switch self {
        case .terminal(let session) where session.id == sessionId:
            // This shouldn't happen at root level; handled by parent split
            return self
        case .terminal:
            return self
        case .split(let id, let dir, let first, let second, let ratio):
            // Check if either child is the terminal to remove
            if case .terminal(let s) = first, s.id == sessionId {
                return second
            }
            if case .terminal(let s) = second, s.id == sessionId {
                return first
            }
            // Recurse
            return .split(
                id: id,
                direction: dir,
                first: first.removing(sessionId: sessionId),
                second: second.removing(sessionId: sessionId),
                ratio: ratio
            )
        }
    }

    /// Update the split ratio for a specific split node
    public func updatingRatio(splitId: UUID, ratio: Double) -> PanelNode {
        switch self {
        case .terminal:
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
}
