import AppKit
import GhosttyKit
import SwiftUI

/// NSView subclass that hosts a libghostty terminal surface.
/// Handles input forwarding, resize, and Metal rendering.
/// Implements NSTextInputClient for proper keyboard handling (IME, Shift+key, Ctrl+key, arrows).
class GhosttyNSView: NSView, NSTextInputClient {
    private let ghosttyApp: GhosttyAppWrapper
    private let session: TerminalSession
    private var surface: ghostty_surface_t?

    // NSTextInputClient state
    private var pendingKeyEvent: NSEvent?
    private var pendingInsertText: String?
    private var imMarkedText: NSMutableAttributedString = NSMutableAttributedString()
    private var imSelectedRange: NSRange = NSRange(location: 0, length: 0)

    init(ghosttyApp: GhosttyAppWrapper, session: TerminalSession) {
        self.ghosttyApp = ghosttyApp
        self.session = session
        super.init(frame: .zero)

        wantsLayer = true
        layer?.isOpaque = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if surface == nil, window != nil {
            createSurface()
        }
    }

    override func layout() {
        super.layout()
        updateSurfaceSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let surface, let window {
            let scale = window.backingScaleFactor
            ghostty_surface_set_content_scale(surface, scale, scale)
            layer?.contentsScale = scale
        }
        updateSurfaceSize()
    }

    // MARK: - Surface Management

    private func createSurface() {
        let userdata = Unmanaged.passUnretained(session).toOpaque()
        surface = ghosttyApp.createSurface(for: self, userdata: userdata)
        session.surface = surface
        ghosttyApp.focusedSurface = surface

        if let surface, let window {
            let scale = window.backingScaleFactor
            ghostty_surface_set_content_scale(surface, scale, scale)
            layer?.contentsScale = scale

            if let screen = window.screen {
                ghostty_surface_set_display_id(surface, screen.displayID)
            }
        }
        updateSurfaceSize()
    }

    private func updateSurfaceSize() {
        guard let surface else { return }
        let scaledSize = convertToBacking(bounds.size)
        ghostty_surface_set_size(
            surface,
            UInt32(scaledSize.width),
            UInt32(scaledSize.height)
        )
    }

    // MARK: - Keyboard Input (via NSTextInputClient)

    /// Intercept Cmd+key combos before the menu system consumes them.
    /// macOS does NOT call keyDown for Cmd+key — only performKeyEquivalent.
    /// Let app menu shortcuts (Cmd+Q/W/B/D) pass through; forward the rest to ghostty.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let surface else { return super.performKeyEquivalent(with: event) }

        if event.modifierFlags.contains(.command) {
            let char = event.charactersIgnoringModifiers?.lowercased() ?? ""
            // Let these pass to the app menu bar
            let menuKeys: Set<String> = ["q", "w", "d", "b"]
            if menuKeys.contains(char) {
                return super.performKeyEquivalent(with: event)
            }

            // Handle Cmd+V paste directly via ghostty_surface_text
            // (ghostty's keybinding system doesn't trigger read_clipboard_cb)
            if char == "v" {
                let pasteboard = NSPasteboard.general
                if let content = pasteboard.string(forType: .string), !content.isEmpty {
                    content.withCString { cstr in
                        ghostty_surface_text(surface, cstr, UInt(content.utf8.count))
                    }
                }
                return true
            }

            // Forward Cmd+C, Cmd+A, etc. to ghostty
            keyDown(with: event)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        guard surface != nil else {
            super.keyDown(with: event)
            return
        }

        pendingKeyEvent = event
        pendingInsertText = nil

        // For Ctrl/Cmd combos, skip the input context and send directly to ghostty.
        // The input context is for text composition (Shift+key, IME) — not modifier combos.
        let hasModifier = event.modifierFlags.contains(.control)
            || event.modifierFlags.contains(.command)
        if !hasModifier {
            inputContext?.handleEvent(event)
        }

        // During IME composition, preedit is already sent via ghostty_surface_preedit
        // in setMarkedText. Don't also send a key event which would interfere.
        if hasMarkedText() {
            pendingKeyEvent = nil
            pendingInsertText = nil
            return
        }

        sendPendingKeyToGhostty()
    }

    /// Called after interpretKeyEvents / inputContext?.handleEvent to send the
    /// collected key event + text to ghostty.
    private func sendPendingKeyToGhostty() {
        guard let event = pendingKeyEvent, let surface else { return }
        pendingKeyEvent = nil

        var key = ghostty_input_key_s()
        key.action = GHOSTTY_ACTION_PRESS
        key.mods = Self.convertModifiers(event.modifierFlags)
        key.keycode = UInt32(event.keyCode)
        key.composing = hasMarkedText()

        // consumed_mods: modifiers that produced the text (exclude control/command)
        let consumedFlags = event.modifierFlags.subtracting([.control, .command])
        key.consumed_mods = Self.convertModifiers(consumedFlags)

        // unshifted_codepoint: the character without any modifiers applied
        if event.type == .keyDown || event.type == .keyUp {
            if let chars = event.characters(byApplyingModifiers: []),
               let scalar = chars.unicodeScalars.first
            {
                key.unshifted_codepoint = scalar.value
            }
        }

        if let text = pendingInsertText, !text.isEmpty {
            text.withCString { cstr in
                key.text = cstr
                _ = ghostty_surface_key(surface, key)
            }
        } else {
            _ = ghostty_surface_key(surface, key)
        }
        pendingInsertText = nil
    }

    override func keyUp(with event: NSEvent) {
        guard let surface else {
            super.keyUp(with: event)
            return
        }

        var key = ghostty_input_key_s()
        key.action = GHOSTTY_ACTION_RELEASE
        key.mods = Self.convertModifiers(event.modifierFlags)
        key.keycode = UInt32(event.keyCode)
        key.composing = false
        _ = ghostty_surface_key(surface, key)
    }

    override func flagsChanged(with event: NSEvent) {
        guard let surface else { return }

        var key = ghostty_input_key_s()
        key.mods = Self.convertModifiers(event.modifierFlags)
        key.keycode = UInt32(event.keyCode)
        key.action = GHOSTTY_ACTION_PRESS
        key.composing = false
        _ = ghostty_surface_key(surface, key)
    }

    // MARK: - NSTextInputClient

    /// Called by the input system when text is ready to be inserted (regular typing, Shift+key, etc.).
    func insertText(_ string: Any, replacementRange: NSRange) {
        let text: String
        if let attrStr = string as? NSAttributedString {
            text = attrStr.string
        } else if let str = string as? String {
            text = str
        } else {
            return
        }

        // Clear marked text and preedit display (IME composition ended)
        imMarkedText = NSMutableAttributedString()
        if let surface {
            ghostty_surface_preedit(surface, nil, 0)
        }

        pendingInsertText = text
    }

    /// Called by the input system for non-text key events (Ctrl+C, arrows, Enter, etc.).
    override func doCommand(by selector: Selector) {
        // pendingInsertText stays nil — ghostty handles these via keycode + modifiers
    }

    /// Called by the input system for IME composition (e.g. Japanese input).
    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if let attrStr = string as? NSAttributedString {
            imMarkedText = NSMutableAttributedString(attributedString: attrStr)
        } else if let str = string as? String {
            imMarkedText = NSMutableAttributedString(string: str)
        }
        imSelectedRange = selectedRange

        // Send preedit text to ghostty via the dedicated preedit API
        // so that composing text is rendered inline in the terminal.
        if let surface {
            let text = imMarkedText.string
            if text.isEmpty {
                ghostty_surface_preedit(surface, nil, 0)
            } else {
                text.withCString { cstr in
                    ghostty_surface_preedit(surface, cstr, UInt(selectedRange.location))
                }
            }
        }
    }

    func unmarkText() {
        imMarkedText = NSMutableAttributedString()
        // Clear preedit display
        if let surface {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }

    func selectedRange() -> NSRange {
        imSelectedRange
    }

    func markedRange() -> NSRange {
        if imMarkedText.length == 0 {
            return NSRange(location: NSNotFound, length: 0)
        }
        return NSRange(location: 0, length: imMarkedText.length)
    }

    func hasMarkedText() -> Bool {
        imMarkedText.length > 0
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        nil
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        // Query ghostty for the cursor position to place the IME candidate window
        guard let surface, let window else { return .zero }
        var x: Double = 0
        var y: Double = 0
        var w: Double = 0
        var h: Double = 0
        ghostty_surface_ime_point(surface, &x, &y, &w, &h)

        // ghostty returns coordinates in the view's coordinate system (origin top-left)
        // Convert to NSView coordinates (origin bottom-left)
        let cursorRect = NSRect(
            x: x,
            y: bounds.height - y - h,
            width: w,
            height: h
        )
        let windowRect = convert(cursorRect, to: nil)
        return window.convertToScreen(windowRect)
    }

    func characterIndex(for point: NSPoint) -> Int {
        0
    }

    // MARK: - Mouse Input

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result, let surface {
            ghosttyApp.focusedSurface = surface
        }
        return result
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        session.onFocused?()
        guard let surface else { return }
        let pos = convertMousePosition(event)
        let mods = Self.convertModifiers(event.modifierFlags)
        ghostty_surface_mouse_pos(surface, pos.x, pos.y, mods)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, mods)
    }

    override func mouseUp(with event: NSEvent) {
        guard let surface else { return }
        let pos = convertMousePosition(event)
        let mods = Self.convertModifiers(event.modifierFlags)
        ghostty_surface_mouse_pos(surface, pos.x, pos.y, mods)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, mods)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let surface else { return }
        let pos = convertMousePosition(event)
        ghostty_surface_mouse_pos(surface, pos.x, pos.y, Self.convertModifiers(event.modifierFlags))
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        // ghostty_input_scroll_mods_t is an int, need to pack precision flag
        let scrollMods: ghostty_input_scroll_mods_t = event.hasPreciseScrollingDeltas ? 1 : 0
        ghostty_surface_mouse_scroll(surface, event.scrollingDeltaX, event.scrollingDeltaY, scrollMods)
    }

    // MARK: - Helpers

    private func convertMousePosition(_ event: NSEvent) -> NSPoint {
        let local = convert(event.locationInWindow, from: nil)
        return NSPoint(x: local.x, y: bounds.height - local.y)
    }

    private static func convertModifiers(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var raw: UInt32 = 0
        if flags.contains(.shift)   { raw |= UInt32(GHOSTTY_MODS_SHIFT.rawValue) }
        if flags.contains(.control) { raw |= UInt32(GHOSTTY_MODS_CTRL.rawValue) }
        if flags.contains(.option)  { raw |= UInt32(GHOSTTY_MODS_ALT.rawValue) }
        if flags.contains(.command) { raw |= UInt32(GHOSTTY_MODS_SUPER.rawValue) }
        return ghostty_input_mods_e(rawValue: raw)
    }

    func destroySurface() {
        if let surface {
            ghostty_surface_free(surface)
        }
        surface = nil
        session.surface = nil
    }

    deinit {
        destroySurface()
    }
}

// MARK: - NSScreen extension for display ID

extension NSScreen {
    var displayID: UInt32 {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return deviceDescription[key] as? UInt32 ?? 0
    }
}

/// SwiftUI wrapper for the ghostty terminal NSView.
/// Reuses the NSView stored on TerminalSession so that layout changes
/// (split, tab switch) don't destroy the terminal surface.
struct TerminalView: NSViewRepresentable {
    let ghosttyApp: GhosttyAppWrapper
    let session: TerminalSession

    func makeNSView(context: Context) -> GhosttyNSView {
        if let existing = session.nsView {
            return existing
        }
        let view = GhosttyNSView(ghosttyApp: ghosttyApp, session: session)
        session.nsView = view
        return view
    }

    func updateNSView(_ nsView: GhosttyNSView, context: Context) {}

    static func dismantleNSView(_ nsView: GhosttyNSView, coordinator: ()) {
        // Don't destroy the surface — the session owns the view's lifecycle.
        // Surface cleanup happens in TerminalSession.close() or deinit.
    }
}
