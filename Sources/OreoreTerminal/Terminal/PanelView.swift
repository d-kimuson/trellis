import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

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

/// The edge zone where a tab is being dragged over for area splitting.
enum DropEdge: Equatable {
    case top, bottom, leading, trailing
}

/// Renders a single area: tab bar + active tab's panel content.
/// Supports drag & drop for tab movement and area splitting.
struct AreaPanelView: View {
    let area: Area
    let ghosttyApp: GhosttyAppWrapper
    @ObservedObject var store: WorkspaceStore

    @State private var dropInsertIndex: Int?
    @State private var dropEdge: DropEdge?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Tab bar (always visible)
                tabBar

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

            // Edge drop zone overlay
            edgeDropOverlay
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(area.tabs.enumerated()), id: \.element.id) { index, tab in
                        tabButton(tab: tab, index: index)
                    }
                }
            }
            .dropDestination(for: TabDragData.self) { items, _ in
                guard let dragData = items.first else { return false }
                let insertAt = dropInsertIndex ?? area.tabs.count
                store.moveTab(
                    tabId: dragData.tabId,
                    from: dragData.sourceAreaId,
                    to: area.id,
                    at: insertAt
                )
                dropInsertIndex = nil
                return true
            } isTargeted: { isTargeted in
                if !isTargeted {
                    dropInsertIndex = nil
                }
            }

            // Add tab button
            Button(
                action: { store.addTab(to: area.id) },
                label: {
                    Image(systemName: "plus")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                }
            )
            .buttonStyle(.borderless)
            .help("New Tab")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Tab Button

    private func tabButton(tab: Tab, index: Int) -> some View {
        let isActive = index == area.activeTabIndex
        let dragData = TabDragData(tabId: tab.id, sourceAreaId: area.id)

        return Button(
            action: { store.selectTab(in: area.id, at: index) },
            label: {
                HStack(spacing: 4) {
                    // Drop insert indicator (left side)
                    if dropInsertIndex == index {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 2, height: 16)
                    }

                    if let session = tab.content.terminalSession {
                        Text(session.title)
                            .font(.caption)
                            .lineLimit(1)
                    }

                    Button(
                        action: { store.closeTab(in: area.id, at: index) },
                        label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                    )
                    .buttonStyle(.borderless)
                    .help("Close Tab")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    isActive
                        ? Color.accentColor.opacity(0.2)
                        : Color.clear
                )
                .cornerRadius(4)
            }
        )
        .buttonStyle(.borderless)
        .draggable(dragData)
        .onDrop(of: [.tabDragData], isTargeted: .none) { _ in
            // This handles the per-tab drop target for insert position
            false
        }
        .onContinuousHover { phase in
            switch phase {
            case .active:
                dropInsertIndex = index
            case .ended:
                break
            }
        }
    }

    // MARK: - Edge Drop Zones

    private var edgeDropOverlay: some View {
        GeometryReader { geo in
            let edgeSize: CGFloat = 40

            ZStack {
                // Top edge
                edgeDropZone(edge: .top)
                    .frame(width: geo.size.width, height: edgeSize)
                    .position(x: geo.size.width / 2, y: edgeSize / 2)

                // Bottom edge
                edgeDropZone(edge: .bottom)
                    .frame(width: geo.size.width, height: edgeSize)
                    .position(x: geo.size.width / 2, y: geo.size.height - edgeSize / 2)

                // Leading edge
                edgeDropZone(edge: .leading)
                    .frame(width: edgeSize, height: geo.size.height)
                    .position(x: edgeSize / 2, y: geo.size.height / 2)

                // Trailing edge
                edgeDropZone(edge: .trailing)
                    .frame(width: edgeSize, height: geo.size.height)
                    .position(x: geo.size.width - edgeSize / 2, y: geo.size.height / 2)
            }
        }
        .allowsHitTesting(true)
    }

    private func edgeDropZone(edge: DropEdge) -> some View {
        let direction: SplitDirection = (edge == .top || edge == .bottom)
            ? .horizontal
            : .vertical

        return Color.clear
            .contentShape(Rectangle())
            .dropDestination(for: TabDragData.self) { items, _ in
                guard let dragData = items.first else { return false }
                // Don't split if dragging within same area and it's the only tab
                if dragData.sourceAreaId == area.id && area.tabs.count <= 1 {
                    return false
                }
                store.moveTabToNewArea(
                    tabId: dragData.tabId,
                    from: dragData.sourceAreaId,
                    adjacentTo: area.id,
                    direction: direction
                )
                dropEdge = nil
                return true
            } isTargeted: { isTargeted in
                dropEdge = isTargeted ? edge : (dropEdge == edge ? nil : dropEdge)
            }
            .overlay(
                dropEdge == edge
                    ? Color.accentColor.opacity(0.3)
                    : Color.clear
            )
            .animation(.easeInOut(duration: 0.15), value: dropEdge)
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
