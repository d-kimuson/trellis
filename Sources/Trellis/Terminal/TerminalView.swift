import AppKit
import GhosttyKit
import SwiftUI

/// NSView subclass that hosts a libghostty terminal surface.
/// Handles input forwarding, resize, and Metal rendering.
/// Implements NSTextInputClient for proper keyboard handling (IME, Shift+key, Ctrl+key, arrows).
class GhosttyNSView: NSView, NSTextInputClient {
    private let ghosttyApp: GhosttyAppWrapper
    let session: TerminalSession
    var surface: ghostty_surface_t?

    // NSTextInputClient state
    private var imMarkedText: NSMutableAttributedString = NSMutableAttributedString()
    private var imSelectedRange: NSRange = NSRange(location: 0, length: 0)

    /// Pending debounced resize task. Cancelled and rescheduled on each layout change
    /// so ghostty_surface_set_size is only called after the size settles.
    private var pendingResizeTask: DispatchWorkItem?

    /// Non-nil while inside keyDown — collects text from insertText calls.
    /// Matches Ghostty's keyTextAccumulator pattern for proper IME handling.
    private var keyTextAccumulator: [String]?

    // MARK: - Find Support (stored properties — methods in GhosttyNSView+Find.swift)

    /// CALayer drawn on top of the terminal surface to show search match highlights.
    let highlightLayer = CALayer()

    /// All match positions in the current search result.
    var findMatches: [FindMatch] = []

    /// Full text from last search read (kept for reference; bytes unused after refactor).
    var findTextBytes: [UInt8] = []

    /// Full text string from last search read.
    var findTextContent: String = ""

    /// Cell-grid offset (y * cols + x) where the visible viewport started at last read.
    var findViewportOffset: Int = 0

    /// Terminal column width at last search read.
    var findTerminalCols: Int = 0

    /// Pending work item for debounced find query changes.
    var findQueryDebounceWork: DispatchWorkItem?

    /// Pending work item for debounced highlight refresh after scroll/key events.
    var highlightRefreshWork: DispatchWorkItem?

    /// Expected viewport row of the current match after the most recent scroll-to-match.
    /// Used by drawHighlights() to identify which viewport match is the "current" one (orange).
    var findCurrentMatchExpectedViewportRow: Int = -1

    init(ghosttyApp: GhosttyAppWrapper, session: TerminalSession) {
        self.ghosttyApp = ghosttyApp
        self.session = session
        super.init(frame: .zero)

        wantsLayer = true
        layer?.isOpaque = true

        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        debugLog("[FOCUS] viewDidMoveToWindow: surface=\(surface.map { "\($0)" } ?? "nil") window=\(window != nil ? "yes" : "nil")")

        if surface == nil, window != nil {
            createSurface()
            // Defer makeFirstResponder so the view hierarchy is fully established
            // before requesting focus. Calling it synchronously during SwiftUI layout
            // can fail silently, leaving the old surface focused in ghostty.
            // This triggers resignFirstResponder on the old terminal
            // (→ ghostty_surface_set_focus false) and becomeFirstResponder here
            // (→ ghostty_surface_set_focus true).
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                debugLog("[FOCUS] makeFirstResponder: self=\(ObjectIdentifier(self)) currentFR=\(window.firstResponder != nil ? "\(type(of: window.firstResponder!))" : "nil")")
                let result = window.makeFirstResponder(self)
                debugLog("[FOCUS] makeFirstResponder result=\(result)")
            }
        }
    }

    override func layout() {
        super.layout()
        highlightLayer.frame = bounds
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
        surface = ghosttyApp.createSurface(
            for: self,
            workingDirectory: session.initialWorkingDirectory,
            envVars: session.initialEnvVars
        )
        session.surface = surface
        ghosttyApp.focusedSurface = surface
        if let surface {
            ghosttyApp.registerSession(surface: surface, session: session)
            // Explicitly mark unfocused until becomeFirstResponder fires.
            // ghostty defaults new surfaces to focused=true, which causes
            // cursor blinking on surfaces that haven't received focus yet.
            ghostty_surface_set_focus(surface, false)
            debugLog("[FOCUS] createSurface: set focus=false surface=\(surface)")
        }

        if let surface, let window {
            let scale = window.backingScaleFactor
            ghostty_surface_set_content_scale(surface, scale, scale)
            layer?.contentsScale = scale

            if let screen = window.screen {
                ghostty_surface_set_display_id(surface, screen.displayID)
            }
        }

        setupHighlightLayer()
        setupFindSubscriptions()
        updateSurfaceSize()
    }

    private func setupHighlightLayer() {
        highlightLayer.backgroundColor = nil
        highlightLayer.isOpaque = false
        highlightLayer.frame = bounds
        highlightLayer.zPosition = 100
        layer?.addSublayer(highlightLayer)
    }

    private func updateSurfaceSize() {
        guard surface != nil else { return }

        // Debounce rapid-fire layout changes (e.g., split-pane drag at 60 fps).
        // ghostty adjusts the viewport scroll on every ghostty_surface_set_size call,
        // so sending it on every frame causes the terminal to scroll to unexpected
        // positions. We cancel and reschedule so the call only fires once the size
        // has been stable for ~32 ms (≈ 2 frames).
        pendingResizeTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self, let surface = self.surface else { return }
            let scaledSize = self.convertToBacking(self.bounds.size)
            // Skip zero or sub-pixel sizes that can appear during SwiftUI layout passes.
            // Passing zero dimensions to ghostty can reset its scroll state.
            guard scaledSize.width >= 1, scaledSize.height >= 1 else { return }
            ghostty_surface_set_size(surface, UInt32(scaledSize.width), UInt32(scaledSize.height))
        }
        pendingResizeTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.032, execute: task)
    }

    // MARK: - Keyboard Input (via NSTextInputClient)

    /// Intercept Cmd+key combos before the menu system consumes them.
    /// macOS does NOT call keyDown for Cmd+key — only performKeyEquivalent.
    /// Let app menu shortcuts pass through; forward the rest to ghostty.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Only handle key equivalents when this view is the actual first responder.
        // performKeyEquivalent is traversed through the view hierarchy, so without
        // this guard unfocused terminal panes would also receive Cmd+K etc.
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        guard let surface else { return super.performKeyEquivalent(with: event) }

        if event.modifierFlags.contains(.command) {
            let char = event.charactersIgnoringModifiers?.lowercased() ?? ""
            let withShift = event.modifierFlags.contains(.shift)

            // Command palette (Cmd+Shift+P)
            if withShift && char == "p" {
                ghosttyApp.store?.dispatch(.toggleCommandPalette)
                return true
            }

            // Font size shortcuts — handle directly so they always reach GhosttyAppWrapper.
            // keyCode 24 = the +/= key (US: Shift+= → "+", JIS: base key is already "+").
            // Check both "+" and "=" to handle US and JIS keyboard layouts.
            if withShift && (char == "+" || char == "=") {
                ghosttyApp.increaseFontSize()
                return true
            }
            if char == "-" || char == "_" {
                ghosttyApp.decreaseFontSize()
                return true
            }
            if !withShift && char == "0" {
                ghosttyApp.resetFontSize()
                return true
            }

            // Toggle find bar (Cmd+F)
            if char == "f" && !withShift {
                if session.isFindVisible {
                    // Cmd+F while bar is open: close it and return focus to terminal
                    session.isFindVisible = false
                } else {
                    session.isFindVisible = true
                }
                return true
            }

            // Let these pass to the app menu bar
            let menuKeys: Set<String> = ["q", "w", "d", "b", "=", ","]
            if menuKeys.contains(char) {
                return super.performKeyEquivalent(with: event)
            }

            // Handle Cmd+V paste directly via ghostty_surface_text
            // (ghostty's keybinding system doesn't trigger read_clipboard_cb)
            // Use focusedSurface so paste goes to the last-clicked terminal regardless
            // of which NSView happens to be the current first responder.
            if char == "v" {
                let pasteTarget = ghosttyApp.focusedSurface ?? surface
                let pasteboard = NSPasteboard.general
                if let content = pasteboard.string(forType: .string), !content.isEmpty {
                    content.withCString { cstr in
                        ghostty_surface_text(pasteTarget, cstr, UInt(content.utf8.count))
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

        // For Ctrl/Cmd combos, skip the input context and send directly to ghostty.
        let hasModifier = event.modifierFlags.contains(.control)
            || event.modifierFlags.contains(.command)
        if hasModifier {
            sendKeyToGhostty(event: event, text: nil, composing: false)
            return
        }

        // Track whether we had marked text before this event.
        // Needed to detect when composition was just cleared (e.g. backspace to cancel).
        let markedTextBefore = imMarkedText.length > 0

        // Begin accumulating text from insertText calls during this keyDown.
        keyTextAccumulator = []
        defer { keyTextAccumulator = nil }

        // This triggers insertText / setMarkedText / doCommand callbacks.
        interpretKeyEvents([event])

        // Sync preedit state after the input system has processed the event.
        syncPreedit(clearIfNeeded: markedTextBefore)

        if let accumulated = keyTextAccumulator, !accumulated.isEmpty {
            // Composition complete — send each accumulated text as a non-composing key.
            for text in accumulated {
                sendKeyToGhostty(event: event, text: text, composing: false)
            }
        } else {
            // No text produced — send key with composing flag.
            // composing is true if we have preedit OR if we just cleared preedit
            // (e.g. backspace to cancel composition should not delete prior characters).
            let composing = imMarkedText.length > 0 || markedTextBefore
            sendKeyToGhostty(event: event, text: event.characters, composing: composing)
        }
        // Key events can trigger ghostty scroll (Page Up/Down, vi-mode, etc.).
        scheduleHighlightRefresh()
    }

    /// Send a key event to ghostty with optional text and composing state.
    private func sendKeyToGhostty(event: NSEvent, text: String?, composing: Bool) {
        guard let surface else { return }
        debugLog("[KEY] keyCode=\(event.keyCode) mods=\(Self.modsDebugString(event.modifierFlags)) text=\(text.map { "\"\($0)\"" } ?? "nil") composing=\(composing) repeat=\(event.isARepeat)")

        var key = ghostty_input_key_s()
        key.action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        key.mods = Self.convertModifiers(event.modifierFlags)
        key.keycode = UInt32(event.keyCode)
        key.composing = composing

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

        // Only encode text if it's a printable, non-function-key character.
        // macOS uses private-use area U+F700-U+F8FF for arrow/function keys.
        // Passing these as text confuses ghostty when kitty keyboard protocol is active
        // (e.g. Claude Code), producing garbled characters instead of escape sequences.
        let isFunctionChar = text.flatMap { $0.unicodeScalars.first }
            .map { $0.value >= 0xF700 && $0.value <= 0xF8FF } ?? false
        if let text, !text.isEmpty,
           let first = text.utf8.first, first >= 0x20, !isFunctionChar
        {
            text.withCString { cstr in
                key.text = cstr
                _ = ghostty_surface_key(surface, key)
            }
        } else {
            _ = ghostty_surface_key(surface, key)
        }
    }

    /// Sync preedit state with ghostty. Matches Ghostty's syncPreedit pattern.
    private func syncPreedit(clearIfNeeded: Bool = true) {
        guard let surface else { return }
        if imMarkedText.length > 0 {
            let str = imMarkedText.string
            str.withCString { ptr in
                let len = str.utf8CString.count
                // Subtract 1 for the null terminator
                ghostty_surface_preedit(surface, ptr, UInt(max(len - 1, 0)))
            }
        } else if clearIfNeeded {
            ghostty_surface_preedit(surface, nil, 0)
        }
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

        // Composition ended — clear preedit
        unmarkText()

        // If inside keyDown, accumulate text for later processing.
        if keyTextAccumulator != nil {
            keyTextAccumulator!.append(text)
            return
        }

        // Outside keyDown (e.g. external input) — send directly
        if let surface {
            text.withCString { cstr in
                ghostty_surface_text(surface, cstr, UInt(text.utf8.count))
            }
        }
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

        // If not inside keyDown, sync preedit immediately (e.g. keyboard layout change).
        // Inside keyDown, preedit is synced after interpretKeyEvents returns.
        if keyTextAccumulator == nil {
            syncPreedit()
        }
    }

    func unmarkText() {
        guard imMarkedText.length > 0 else { return }
        imMarkedText.mutableString.setString("")
        syncPreedit()
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
            y: frame.size.height - y,
            width: max(w, 1),
            height: max(h, 1)
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
        debugLog("[FOCUS] becomeFirstResponder: result=\(result) surface=\(surface.map { "\($0)" } ?? "nil")")
        if result, let surface {
            ghosttyApp.focusedSurface = surface
            // Defocus all other surfaces first — resignFirstResponder is not reliably
            // called when AppKit reassigns first responder during view hierarchy changes
            // (e.g. split). This ensures only one surface has ghostty focus at a time.
            ghosttyApp.defocusAllSurfaces(except: surface)
            ghostty_surface_set_focus(surface, true)
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        debugLog("[FOCUS] resignFirstResponder: result=\(result) surface=\(surface.map { "\($0)" } ?? "nil")")
        if result, let surface {
            ghostty_surface_set_focus(surface, false)
        }
        return result
    }

    override func mouseDown(with event: NSEvent) {
        // Update focusedSurface immediately on click so that Cmd+V routes to the correct
        // terminal even if the responder chain is temporarily inconsistent (e.g. SwiftUI
        // re-render between click and key event).
        if let surface {
            ghosttyApp.focusedSurface = surface
        }
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

    override func rightMouseDown(with event: NSEvent) {
        // Bring focus to the clicked terminal pane before showing the menu.
        if let surface {
            ghosttyApp.focusedSurface = surface
        }
        window?.makeFirstResponder(self)
        super.rightMouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()

        let copyItem = NSMenuItem(title: "Copy", action: #selector(copyToClipboard), keyEquivalent: "")
        copyItem.target = self
        copyItem.isEnabled = surface != nil
        menu.addItem(copyItem)

        let clipboardText = NSPasteboard.general.string(forType: .string) ?? ""
        let pasteItem = NSMenuItem(title: "Paste", action: #selector(pasteFromClipboard), keyEquivalent: "")
        pasteItem.target = self
        pasteItem.isEnabled = surface != nil && !clipboardText.isEmpty
        menu.addItem(pasteItem)

        menu.addItem(.separator())

        if let url = session.hoveredURL {
            let openItem = NSMenuItem(title: "Open URL", action: #selector(openHoveredURL(_:)), keyEquivalent: "")
            openItem.target = self
            openItem.representedObject = url
            menu.addItem(openItem)
        }

        let searchItem = NSMenuItem(title: "Search Web", action: #selector(searchInWeb), keyEquivalent: "")
        searchItem.target = self
        searchItem.isEnabled = !clipboardText.isEmpty
        menu.addItem(searchItem)

        return menu
    }

    @objc private func copyToClipboard() {
        guard let surface else { return }
        let action = "copy_to_clipboard"
        action.withCString { cstr in
            ghostty_surface_binding_action(surface, cstr, UInt(action.utf8.count))
        }
    }

    @objc private func pasteFromClipboard() {
        guard let surface else { return }
        guard let content = NSPasteboard.general.string(forType: .string), !content.isEmpty else { return }
        content.withCString { cstr in
            ghostty_surface_text(surface, cstr, UInt(content.utf8.count))
        }
    }

    @objc private func openHoveredURL(_ sender: NSMenuItem) {
        guard let urlString = sender.representedObject as? String,
              let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func searchInWeb() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.google.com/search?q=\(encoded)") else { return }
        NSWorkspace.shared.open(url)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        // ghostty_input_scroll_mods_t is an int, need to pack precision flag
        let scrollMods: ghostty_input_scroll_mods_t = event.hasPreciseScrollingDeltas ? 1 : 0
        ghostty_surface_mouse_scroll(surface, event.scrollingDeltaX, event.scrollingDeltaY, scrollMods)
        // Redraw highlights immediately (ghostty processes mouse scroll synchronously).
        // Also schedule a debounced redraw as fallback for precision-scroll accumulation.
        redrawHighlights()
        scheduleHighlightRefresh()
    }

    // MARK: - File Drop

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
        ]) else { return [] }
        return .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let surface else { return false }
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty else { return false }

        let filePaths = urls.map(\.path)
        let text = formatDroppedPaths(filePaths: filePaths, base: session.pwd)
        guard !text.isEmpty else { return false }

        text.withCString { cstr in
            ghostty_surface_text(surface, cstr, UInt(text.utf8.count))
        }
        return true
    }

    // MARK: - Helpers

    private func convertMousePosition(_ event: NSEvent) -> NSPoint {
        let local = convert(event.locationInWindow, from: nil)
        return NSPoint(x: local.x, y: bounds.height - local.y)
    }

    private static func modsDebugString(_ flags: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if flags.contains(.shift)   { parts.append("shift") }
        if flags.contains(.control) { parts.append("ctrl") }
        if flags.contains(.option)  { parts.append("opt") }
        if flags.contains(.command) { parts.append("cmd") }
        return parts.isEmpty ? "none" : parts.joined(separator: "+")
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
            ghosttyApp.unregisterSession(surface: surface)
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
