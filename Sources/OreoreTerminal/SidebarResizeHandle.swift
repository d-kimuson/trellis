import SwiftUI

struct SidebarResizeHandle: View {
    @Binding var sidebarWidth: CGFloat
    @State private var isDragging = false
    @State private var dragStartWidth: CGFloat = 0

    private static let minWidth: CGFloat = 120
    private static let maxWidth: CGFloat = 400
    private static let hitAreaWidth: CGFloat = 8

    var body: some View {
        Rectangle()
            .fill(isDragging ? Color.accentColor.opacity(0.6) : Color(nsColor: .separatorColor))
            .frame(width: isDragging ? 2 : 1)
            .frame(maxHeight: .infinity)
            .padding(.horizontal, (Self.hitAreaWidth - 1) / 2)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            dragStartWidth = sidebarWidth
                        }
                        let newWidth = dragStartWidth + value.translation.width
                        sidebarWidth = min(max(newWidth, Self.minWidth), Self.maxWidth)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
    }
}
