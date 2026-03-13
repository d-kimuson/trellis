import AppKit

/// Manages shared NSEvent local monitors for browser panels.
/// Ensures at most one monitor per event type exists app-wide,
/// preventing monitor leaks when dismantleNSView is not called.
public final class BrowserEventMonitor {
    public static let shared = BrowserEventMonitor()

    private var mouseHandlers: [ObjectIdentifier: (NSEvent) -> NSEvent?] = [:]
    private var keyboardHandlers: [ObjectIdentifier: (NSEvent) -> NSEvent?] = [:]
    private var mouseMonitor: Any?
    private var keyboardMonitor: Any?

    public init() {}

    // MARK: - Mouse

    public func addMouseHandler(for owner: AnyObject, handler: @escaping (NSEvent) -> NSEvent?) {
        mouseHandlers[ObjectIdentifier(owner)] = handler
        installMouseMonitorIfNeeded()
    }

    public func removeMouseHandler(for owner: AnyObject) {
        mouseHandlers.removeValue(forKey: ObjectIdentifier(owner))
        uninstallMouseMonitorIfEmpty()
    }

    // MARK: - Keyboard

    public func addKeyboardHandler(for owner: AnyObject, handler: @escaping (NSEvent) -> NSEvent?) {
        keyboardHandlers[ObjectIdentifier(owner)] = handler
        installKeyboardMonitorIfNeeded()
    }

    public func removeKeyboardHandler(for owner: AnyObject) {
        keyboardHandlers.removeValue(forKey: ObjectIdentifier(owner))
        uninstallKeyboardMonitorIfEmpty()
    }

    // MARK: - Convenience

    public func removeAll(for owner: AnyObject) {
        removeMouseHandler(for: owner)
        removeKeyboardHandler(for: owner)
    }

    // MARK: - Inspection (for testing)

    public var mouseHandlerCount: Int { mouseHandlers.count }
    public var keyboardHandlerCount: Int { keyboardHandlers.count }
    public var hasMouseMonitor: Bool { mouseMonitor != nil }
    public var hasKeyboardMonitor: Bool { keyboardMonitor != nil }

    // MARK: - Private

    private func installMouseMonitorIfNeeded() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.dispatchMouse(event) ?? event
        }
    }

    private func uninstallMouseMonitorIfEmpty() {
        guard mouseHandlers.isEmpty, let monitor = mouseMonitor else { return }
        NSEvent.removeMonitor(monitor)
        mouseMonitor = nil
    }

    private func installKeyboardMonitorIfNeeded() {
        guard keyboardMonitor == nil else { return }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.dispatchKeyboard(event) ?? event
        }
    }

    private func uninstallKeyboardMonitorIfEmpty() {
        guard keyboardHandlers.isEmpty, let monitor = keyboardMonitor else { return }
        NSEvent.removeMonitor(monitor)
        keyboardMonitor = nil
    }

    private func dispatchMouse(_ event: NSEvent) -> NSEvent? {
        for handler in mouseHandlers.values {
            if handler(event) == nil { return nil }
        }
        return event
    }

    private func dispatchKeyboard(_ event: NSEvent) -> NSEvent? {
        for handler in keyboardHandlers.values {
            if handler(event) == nil { return nil }
        }
        return event
    }
}
