import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// Recursively renders the layout tree as split views with draggable dividers.
struct AreaLayoutView: View {
    let node: LayoutNode
    let ghosttyApp: GhosttyAppWrapper
    var store: WorkspaceStore
    @ObservedObject var notificationStore: NotificationStore

    var body: some View {
        switch node {
        case .leaf(let area):
            AreaPanelView(
                area: area,
                ghosttyApp: ghosttyApp,
                store: store,
                notificationStore: notificationStore,
                isActiveArea: store.activeWorkspace?.activeAreaId == area.id
            )

        case .split(let splitId, let direction, let first, let second, let ratio):
            SplitContainer(
                direction: direction,
                ratio: ratio,
                onRatioChange: { newRatio in
                    store.updateRatio(splitId: splitId, ratio: newRatio)
                },
                first: {
                    AreaLayoutView(node: first, ghosttyApp: ghosttyApp, store: store, notificationStore: notificationStore)
                },
                second: {
                    AreaLayoutView(node: second, ghosttyApp: ghosttyApp, store: store, notificationStore: notificationStore)
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
    var store: WorkspaceStore
    @ObservedObject var notificationStore: NotificationStore
    var isActiveArea: Bool = false

    @State private var dropInsertIndex: Int?
    @State private var dropEdge: DropEdge?

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar (always visible)
            tabBar

            // All tab contents stacked — keeps surfaces alive across tab switches
            if !area.tabs.isEmpty {
                GeometryReader { geo in
                    ZStack {
                        ForEach(Array(area.tabs.enumerated()), id: \.element.id) { index, tab in
                            let isActive = index == area.activeTabIndex
                            switch tab.content {
                            case .terminal:
                                panelContent(for: tab.content)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .opacity(isActive ? 1 : 0)
                                    .allowsHitTesting(isActive)
                            case .browser, .fileTree:
                                if isActive {
                                    panelContent(for: tab.content)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }
                        }
                    }
                    .overlay { splitPreview(size: geo.size) }
                    .onDrop(
                        of: [.tabDragData],
                        delegate: SplitDropDelegate(
                            area: area,
                            store: store,
                            viewSize: geo.size,
                            onEdgeChanged: { dropEdge = $0 }
                        )
                    )
                }
            } else {
                VStack(spacing: 12) {
                    Text("Empty")
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        Button("Terminal") { store.addTerminalTab(to: area.id) }
                        Button("Browser") { store.addBrowserTab(to: area.id) }
                        Button("File Tree") { store.addFileTreeTab(to: area.id) }
                    }
                    .font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.accentColor, lineWidth: isActiveArea ? 2 : 0)
                .allowsHitTesting(false)
        )
    }

    // MARK: - Drop Edge Detection

    /// Determine which edge the cursor is closest to.
    static func determineEdge(location: CGPoint, size: CGSize) -> DropEdge {
        let relX = size.width > 0 ? location.x / size.width : 0.5
        let relY = size.height > 0 ? location.y / size.height : 0.5

        let distances: [(DropEdge, CGFloat)] = [
            (.leading, relX),
            (.trailing, 1 - relX),
            (.top, relY),
            (.bottom, 1 - relY)
        ]
        return distances.min(by: { $0.1 < $1.1 })!.0
    }

    /// Half-area preview overlay showing where the split will occur.
    @ViewBuilder
    private func splitPreview(size: CGSize) -> some View {
        if let edge = dropEdge {
            let isVertical = (edge == .leading || edge == .trailing)
            let alignment = Self.edgeAlignment(edge)

            Color.accentColor.opacity(0.2)
                .frame(
                    width: isVertical ? size.width / 2 : nil,
                    height: isVertical ? nil : size.height / 2
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.1), value: dropEdge)
        }
    }

    private static func edgeAlignment(_ edge: DropEdge) -> Alignment {
        switch edge {
        case .leading: return .leading
        case .trailing: return .trailing
        case .top: return .top
        case .bottom: return .bottom
        }
    }

    // MARK: - Panel Content

    @ViewBuilder
    private func panelContent(for content: PanelContent) -> some View {
        switch content {
        case .terminal(let session):
            TerminalPanelWrapper(
                session: session,
                ghosttyApp: ghosttyApp,
                areaId: area.id,
                store: store
            )
        case .browser(let state):
            BrowserPanelView(state: state, onFocused: { store.activateArea(area.id) })
                .overlay {
                    TabDropInterceptView(
                        area: area,
                        store: store,
                        onEdgeChanged: { dropEdge = $0 }
                    )
                }
        case .fileTree(let state):
            let onFileTreeFocused = {
                store.activateArea(area.id)
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
            let session = area.tabs.compactMap { $0.content.terminalSession }.first
            if let session {
                FileTreePanelWithCwd(state: state, session: session, onFocused: onFileTreeFocused)
            } else {
                FileTreePanelView(state: state, settings: AppSettings.shared, onFocused: onFileTreeFocused)
            }
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

            // Tab bar action icons
            HStack(spacing: 2) {
                tabBarIcon("terminal", help: "New Terminal") {
                    store.addTerminalTab(to: area.id)
                }
                tabBarIcon("globe", help: "New Browser") {
                    store.addBrowserTab(to: area.id)
                }
                tabBarIcon("folder", help: "New File Tree") {
                    store.addFileTreeTab(to: area.id)
                }

                Divider().frame(height: 14).padding(.horizontal, 2)

                tabBarIcon("rectangle.split.2x1", help: "Split Vertical") {
                    store.splitArea(areaId: area.id, direction: .vertical)
                }
                tabBarIcon("rectangle.split.1x2", help: "Split Horizontal") {
                    store.splitArea(areaId: area.id, direction: .horizontal)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Tab Bar Icon

    private func tabBarIcon(
        _ systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 10))
            .foregroundColor(.secondary)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .help(help)
    }

    // MARK: - Tab Button

    private func tabButton(tab: Tab, index: Int) -> some View {
        let isActive = index == area.activeTabIndex
        let dragData = TabDragData(tabId: tab.id, sourceAreaId: area.id)
        // Use plain view + onTapGesture instead of Button to allow .draggable() to work.
        // Button consumes the drag gesture, preventing tab dragging.
        // Exception: the close button uses Button so it has reliable hit testing
        // regardless of which area is focused.
        return HStack(spacing: 0) {
            if dropInsertIndex == index {
                Rectangle().fill(Color.accentColor).frame(width: 2, height: 16)
            }
            // Close button: use Button for reliable click handling.
            // .onTapGesture on a tiny icon inside a .draggable() parent can fail to fire
            // on the first click in an unfocused area.
            Button(action: { store.closeTab(in: area.id, at: index) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            // Tab label area: draggable and selectable.
            HStack(spacing: 4) {
                Image(systemName: tab.content.iconName)
                    .font(.system(size: 10)).foregroundColor(.secondary)
                TabTitleLabel(content: tab.content)
                if case .terminal(let session) = tab.content {
                    TabNotificationBadge(session: session, notificationStore: notificationStore)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                store.selectTab(in: area.id, at: index)
                if case .terminal(let session) = tab.content, let nsView = session.nsView {
                    // Restore keyboard focus to the terminal surface when switching tabs.
                    NSApp.keyWindow?.makeFirstResponder(nsView)
                } else {
                    // Non-terminal tab: resign terminal first responder so cursor stops blinking.
                    NSApp.keyWindow?.makeFirstResponder(nil)
                }
            }
            .draggable(dragData)
            .onDrop(of: [.tabDragData], isTargeted: .none) { _ in
                false
            }
        }
        .padding(.leading, 4)
        .background(isActive ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(4)
    }
}

/// Wraps a terminal view for embedding in an area panel.
struct TerminalPanelWrapper: View {
    let session: TerminalSession
    let ghosttyApp: GhosttyAppWrapper
    let areaId: UUID
    var store: WorkspaceStore

    var body: some View {
        TerminalView(ghosttyApp: ghosttyApp, session: session)
            .id(session.id)
            .border(Color(nsColor: .separatorColor), width: 0.5)
            .overlay(alignment: .top) {
                FindBarView(session: session)
            }
            .overlay(alignment: .bottomLeading) {
                if let url = session.pendingURL {
                    URLSuggestBanner(url: url, onDismiss: {
                        session.pendingURL = nil
                    }, onOpenInBrowser: { parsedURL in
                        store.addBrowserTab(to: areaId, url: parsedURL)
                        session.pendingURL = nil
                    })
                    .padding(8)
                }
            }
            // Use onChange(initial: true) instead of onAppear so that closures are
            // re-registered whenever areaId changes (e.g. after a split operation),
            // preventing stale captures from routing focus to the wrong area.
            .onChange(of: areaId, initial: true) { _, newAreaId in
                session.onFocused = { [weak store] in
                    store?.activateArea(newAreaId)
                }
                session.onProcessExited = { [weak store] in
                    store?.closeTerminalSession(session)
                }
            }
    }
}

/// VSCode-style URL suggestion banner shown at the bottom of the terminal.
private struct URLSuggestBanner: View {
    let url: String
    let onDismiss: () -> Void
    let onOpenInBrowser: (URL) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Text(url)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundColor(.primary)

            if let parsedURL = URL(string: url) {
                Button("Open") {
                    onOpenInBrowser(parsedURL)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .help("Open in internal browser")
            }

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
            }
            .buttonStyle(.borderless)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .shadow(radius: 2, y: 1)
        .transition(.move(edge: .bottom).combined(with: .opacity))
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
    @State private var localRatio: Double?

    private let dividerThickness: CGFloat = 4
    private let minRatio: Double = 0.15
    private let maxRatio: Double = 0.85

    var body: some View {
        GeometryReader { geo in
            let activeRatio = localRatio ?? ratio
            let totalSize = direction == .horizontal ? geo.size.height : geo.size.width
            let firstSize = max(0, totalSize * activeRatio)
            let secondSize = max(0, totalSize * (1 - activeRatio) - dividerThickness)

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
                        let currentFirstSize = totalSize * (localRatio ?? ratio)
                        let newFirstSize = currentFirstSize + offset - (dividerThickness / 2)
                        let newRatio = Double(newFirstSize / totalSize)
                        localRatio = min(maxRatio, max(minRatio, newRatio))
                    }
                    .onEnded { _ in
                        if let localRatio {
                            onRatioChange(localRatio)
                        }
                        localRatio = nil
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
            .onDisappear {
                NSCursor.pop()
            }
    }
}

// MARK: - Tab Title Label

/// Reactively displays tab title. For terminal tabs, observes the session
/// to update when pwd changes (TerminalSession is @Observable).
struct TabTitleLabel: View {
    let content: PanelContent

    var body: some View {
        switch content {
        case .terminal(let session):
            TerminalTabTitle(session: session)
        default:
            Text(content.tabTitle).font(.caption).lineLimit(1)
        }
    }
}

/// Observes a terminal session to reactively update the tab title when pwd changes.
private struct TerminalTabTitle: View {
    var session: TerminalSession

    var body: some View {
        Text(tabTitle).font(.caption).lineLimit(1)
    }

    private var tabTitle: String {
        session.tabTitle
    }
}

/// Shows an unread notification badge on a terminal tab.
/// Wraps FileTreePanelView and observes the co-located terminal session so that
/// the workspace cwd stays current even after the terminal navigates to a new directory.
private struct FileTreePanelWithCwd: View {
    @ObservedObject var state: FileTreeState
    var session: TerminalSession
    var onFocused: (() -> Void)?

    var body: some View {
        FileTreePanelView(state: state, workspaceCwd: session.pwd, settings: AppSettings.shared, onFocused: onFocused)
    }
}

/// Observes both the session and the notification store for reactive updates.
private struct TabNotificationBadge: View {
    var session: TerminalSession
    @ObservedObject var notificationStore: NotificationStore

    var body: some View {
        let count = notificationStore.unreadCount(forSession: session.id)
        if count > 0 {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)
        }
    }
}
