import SwiftUI

/// Recursively renders the layout tree as split views with draggable dividers.
struct AreaLayoutView: View {
    let node: LayoutNode
    let ghosttyApp: GhosttyAppWrapper
    @ObservedObject var store: WorkspaceStore

    var body: some View {
        switch node {
        case .leaf(let area):
            AreaPanelView(
                area: area,
                ghosttyApp: ghosttyApp,
                store: store
            )

        case .split(let splitId, let direction, let first, let second, let ratio):
            SplitContainer(
                direction: direction,
                ratio: ratio,
                onRatioChange: { newRatio in
                    store.updateRatio(splitId: splitId, ratio: newRatio)
                },
                first: {
                    AreaLayoutView(node: first, ghosttyApp: ghosttyApp, store: store)
                },
                second: {
                    AreaLayoutView(node: second, ghosttyApp: ghosttyApp, store: store)
                }
            )
        }
    }
}

/// Renders a single area: tab bar (stub) + active tab's panel content.
struct AreaPanelView: View {
    let area: Area
    let ghosttyApp: GhosttyAppWrapper
    @ObservedObject var store: WorkspaceStore

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar (minimal stub)
            if area.tabs.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Array(area.tabs.enumerated()), id: \.element.id) { index, tab in
                            tabButton(tab: tab, index: index)
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color(nsColor: .controlBackgroundColor))
            }

            // Active tab content
            if let activeTab = area.activeTab,
               let session = activeTab.content.terminalSession {
                TerminalPanelWrapper(
                    session: session,
                    ghosttyApp: ghosttyApp,
                    areaId: area.id,
                    store: store
                )
            } else {
                Text("Empty area")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func tabButton(tab: Tab, index: Int) -> some View {
        Button(
            action: { store.selectTab(in: area.id, at: index) },
            label: {
                HStack(spacing: 4) {
                    if let session = tab.content.terminalSession {
                        Text(session.title)
                            .font(.caption)
                            .lineLimit(1)
                    }

                    if area.tabs.count > 1 {
                        Button(
                            action: { store.closeTab(in: area.id, at: index) },
                            label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8))
                            }
                        )
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    index == area.activeTabIndex
                        ? Color.accentColor.opacity(0.2)
                        : Color.clear
                )
                .cornerRadius(4)
            }
        )
        .buttonStyle(.borderless)
    }
}

/// Wraps a terminal view with a thin toolbar for split/close actions.
struct TerminalPanelWrapper: View {
    let session: TerminalSession
    let ghosttyApp: GhosttyAppWrapper
    let areaId: UUID
    @ObservedObject var store: WorkspaceStore

    var body: some View {
        VStack(spacing: 0) {
            // Mini toolbar
            HStack(spacing: 4) {
                Text(session.title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()

                Button(
                    action: { store.splitArea(areaId: areaId, direction: .horizontal) },
                    label: { Image(systemName: "rectangle.split.1x2").font(.caption) }
                )
                .buttonStyle(.borderless)
                .help("Split Horizontal")

                Button(
                    action: { store.splitArea(areaId: areaId, direction: .vertical) },
                    label: { Image(systemName: "rectangle.split.2x1").font(.caption) }
                )
                .buttonStyle(.borderless)
                .help("Split Vertical")

                Button(
                    action: { store.closeArea(areaId: areaId) },
                    label: { Image(systemName: "xmark").font(.caption) }
                )
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
