import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// SwiftUI wrapper for AppKit-based drop target that intercepts tab drag events.
/// Uses NSView overlay so WKWebView (browser panels) doesn't consume the drag events.
/// Transparent to regular mouse events — only activates during tab drag operations.
struct TabDropInterceptView: NSViewRepresentable {
    let area: Area
    let store: WorkspaceStore
    let onEdgeChanged: (DropEdge?) -> Void

    func makeNSView(context: Context) -> TabDropInterceptNSView {
        let view = TabDropInterceptNSView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: TabDropInterceptNSView, context: Context) {
        context.coordinator.area = area
        context.coordinator.store = store
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(area: area, store: store, onEdgeChanged: onEdgeChanged)
    }

    final class Coordinator {
        var area: Area
        var store: WorkspaceStore
        let onEdgeChanged: (DropEdge?) -> Void

        init(area: Area, store: WorkspaceStore, onEdgeChanged: @escaping (DropEdge?) -> Void) {
            self.area = area
            self.store = store
            self.onEdgeChanged = onEdgeChanged
        }
    }
}

/// AppKit NSView that intercepts tab drag-and-drop events.
/// Uses the drag pasteboard to distinguish tab drags from regular mouse events:
/// - During tab drags: returns self from hitTest (catches drag events above WKWebView)
/// - Otherwise: returns nil from hitTest (transparent to clicks, scrolls, etc.)
final class TabDropInterceptNSView: NSView {
    var coordinator: TabDropInterceptView.Coordinator?
    private static let tabDragPBType = NSPasteboard.PasteboardType(UTType.tabDragData.identifier)

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([Self.tabDragPBType])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Only intercept hits when our custom tab drag type is on the drag pasteboard.
    // This makes the view transparent to regular mouse events (clicks pass through
    // to WKWebView) but opaque to tab drag operations.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let dragPB = NSPasteboard(name: .drag)
        if dragPB.availableType(from: [Self.tabDragPBType]) != nil {
            return super.hitTest(point)
        }
        return nil
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        updateEdge(sender)
        return .move
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        updateEdge(sender)
        return .move
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        coordinator?.onEdgeChanged(nil)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let coordinator = coordinator else { return false }
        let edge = computeEdge(sender)
        coordinator.onEdgeChanged(nil)

        guard let data = sender.draggingPasteboard.data(forType: Self.tabDragPBType),
              let dragData = try? JSONDecoder().decode(TabDragData.self, from: data) else {
            return false
        }

        let area = coordinator.area
        if dragData.sourceAreaId == area.id && area.tabs.count <= 1 { return false }

        let direction: SplitDirection =
            (edge == .top || edge == .bottom) ? .horizontal : .vertical
        let insertBefore = (edge == .leading || edge == .top)

        coordinator.store.moveTabToNewArea(
            tabId: dragData.tabId,
            from: dragData.sourceAreaId,
            adjacentTo: area.id,
            direction: direction,
            insertBefore: insertBefore
        )
        return true
    }

    private func updateEdge(_ sender: NSDraggingInfo) {
        coordinator?.onEdgeChanged(computeEdge(sender))
    }

    private func computeEdge(_ sender: NSDraggingInfo) -> DropEdge {
        let location = convert(sender.draggingLocation, from: nil)
        // AppKit Y is bottom-up; convert to SwiftUI top-down coordinates
        let swiftUIPoint = CGPoint(x: location.x, y: bounds.height - location.y)
        return AreaPanelView.determineEdge(location: swiftUIPoint, size: bounds.size)
    }
}

// MARK: - SwiftUI Split Drop Delegate

/// SwiftUI DropDelegate for edge-based area splitting (used by terminal and other non-browser panels).
/// Uses dropUpdated for real-time cursor position tracking.
struct SplitDropDelegate: DropDelegate {
    let area: Area
    let store: WorkspaceStore
    let viewSize: CGSize
    let onEdgeChanged: (DropEdge?) -> Void

    func dropEntered(info: DropInfo) {
        updateEdge(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateEdge(info: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        onEdgeChanged(nil)
    }

    func performDrop(info: DropInfo) -> Bool {
        let edge = AreaPanelView.determineEdge(location: info.location, size: viewSize)
        onEdgeChanged(nil)

        let providers = info.itemProviders(for: [.tabDragData])
        guard let provider = providers.first else { return false }

        provider.loadObject(ofClass: TabDragTransfer.self) { object, _ in
            guard let transfer = object as? TabDragTransfer else { return }
            let dragData = transfer.data
            DispatchQueue.main.async {
                if dragData.sourceAreaId == area.id && area.tabs.count <= 1 { return }
                let direction: SplitDirection =
                    (edge == .top || edge == .bottom) ? .horizontal : .vertical
                let insertBefore = (edge == .leading || edge == .top)
                store.moveTabToNewArea(
                    tabId: dragData.tabId,
                    from: dragData.sourceAreaId,
                    adjacentTo: area.id,
                    direction: direction,
                    insertBefore: insertBefore
                )
            }
        }
        return true
    }

    private func updateEdge(info: DropInfo) {
        let edge = AreaPanelView.determineEdge(location: info.location, size: viewSize)
        onEdgeChanged(edge)
    }
}

/// NSItemProviderReading wrapper for TabDragData to work with SwiftUI .onDrop(of:delegate:).
final class TabDragTransfer: NSObject, NSItemProviderReading {
    let data: TabDragData

    required init(data: TabDragData) {
        self.data = data
        super.init()
    }

    static var readableTypeIdentifiersForItemProvider: [String] {
        [UTType.tabDragData.identifier]
    }

    static func object(
        withItemProviderData data: Data,
        typeIdentifier: String
    ) throws -> Self {
        let decoded = try JSONDecoder().decode(TabDragData.self, from: data)
        return Self(data: decoded)
    }
}
