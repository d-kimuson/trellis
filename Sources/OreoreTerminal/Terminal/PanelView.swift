import SwiftUI

/// Recursively renders the panel tree as split views with draggable dividers.
struct PanelView: View {
    let node: PanelNode
    let ghosttyApp: GhosttyAppWrapper
    @ObservedObject var sessionStore: SessionStore

    var body: some View {
        switch node {
        case .terminal(let session):
            TerminalPanelWrapper(
                session: session,
                ghosttyApp: ghosttyApp,
                onSplitH: { sessionStore.split(session, direction: .horizontal) },
                onSplitV: { sessionStore.split(session, direction: .vertical) },
                onClose: { sessionStore.closeSession(session) }
            )

        case .split(let splitId, let direction, let first, let second, let ratio):
            SplitContainer(
                direction: direction,
                ratio: ratio,
                onRatioChange: { newRatio in
                    sessionStore.rootPanel = sessionStore.rootPanel.updatingRatio(
                        splitId: splitId,
                        ratio: newRatio
                    )
                },
                first: {
                    PanelView(node: first, ghosttyApp: ghosttyApp, sessionStore: sessionStore)
                },
                second: {
                    PanelView(node: second, ghosttyApp: ghosttyApp, sessionStore: sessionStore)
                }
            )
        }
    }
}

/// Wraps a terminal view with a thin toolbar for split/close actions.
struct TerminalPanelWrapper: View {
    let session: TerminalSession
    let ghosttyApp: GhosttyAppWrapper
    let onSplitH: () -> Void
    let onSplitV: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Mini toolbar
            HStack(spacing: 4) {
                Text(session.title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()

                Button(action: onSplitH) {
                    Image(systemName: "rectangle.split.1x2")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Split Horizontal")

                Button(action: onSplitV) {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Split Vertical")

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Close")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))

            // Terminal surface
            TerminalView(ghosttyApp: ghosttyApp, session: session)
        }
        .border(Color(nsColor: .separatorColor), width: 0.5)
    }
}

/// A resizable split container with a draggable divider.
struct SplitContainer<First: View, Second: View>: View {
    let direction: SplitDirection
    let ratio: Double
    let onRatioChange: (Double) -> Void
    @ViewBuilder let first: () -> First
    @ViewBuilder let second: () -> Second

    @State private var isDragging = false

    private let dividerThickness: CGFloat = 4
    private let minRatio: Double = 0.15
    private let maxRatio: Double = 0.85

    var body: some View {
        GeometryReader { geo in
            let totalSize = direction == .horizontal ? geo.size.height : geo.size.width
            let firstSize = totalSize * ratio
            let secondSize = totalSize * (1 - ratio) - dividerThickness

            if direction == .horizontal {
                VStack(spacing: 0) {
                    first()
                        .frame(height: firstSize)

                    divider(totalSize: totalSize, isHorizontal: true)

                    second()
                        .frame(height: secondSize)
                }
            } else {
                HStack(spacing: 0) {
                    first()
                        .frame(width: firstSize)

                    divider(totalSize: totalSize, isHorizontal: false)

                    second()
                        .frame(width: secondSize)
                }
            }
        }
    }

    private func divider(totalSize: CGFloat, isHorizontal: Bool) -> some View {
        Rectangle()
            .fill(isDragging ? Color.accentColor : Color(nsColor: .separatorColor))
            .frame(
                width: isHorizontal ? nil : dividerThickness,
                height: isHorizontal ? dividerThickness : nil
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        isDragging = true
                        let offset = isHorizontal ? value.location.y : value.location.x
                        let currentFirstSize = totalSize * ratio
                        let newFirstSize = currentFirstSize + offset - (dividerThickness / 2)
                        let newRatio = Double(newFirstSize / totalSize)
                        onRatioChange(min(maxRatio, max(minRatio, newRatio)))
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor(image: isHorizontal
                        ? NSCursor.resizeUpDown.image
                        : NSCursor.resizeLeftRight.image,
                        hotSpot: NSPoint(x: 8, y: 8)
                    ).push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}
