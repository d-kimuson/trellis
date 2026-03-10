import AppKit
import GhosttyKit
import SwiftUI

/// NSView subclass that hosts a libghostty terminal surface.
/// Handles input forwarding, resize, and Metal rendering.
class GhosttyNSView: NSView {
    private let ghosttyApp: GhosttyAppWrapper
    private let session: TerminalSession
    private var surface: ghostty_surface_t?

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
        surface = ghosttyApp.createSurface(for: self)
        session.surface = surface

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

    // MARK: - Keyboard Input

    override func keyDown(with event: NSEvent) {
        guard let surface else {
            super.keyDown(with: event)
            return
        }

        var key = ghostty_input_key_s()
        key.action = GHOSTTY_ACTION_PRESS
        key.mods = Self.convertModifiers(event.modifierFlags)
        key.keycode = UInt32(event.keyCode)
        key.composing = false

        if let chars = event.characters {
            chars.withCString { cstr in
                key.text = cstr
                _ = ghostty_surface_key(surface, key)
            }
        } else {
            _ = ghostty_surface_key(surface, key)
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

    // MARK: - Mouse Input

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
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
        if let surface {
            ghostty_surface_free(surface)
        }
        surface = nil
        session.surface = nil
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
struct TerminalView: NSViewRepresentable {
    let ghosttyApp: GhosttyAppWrapper
    let session: TerminalSession

    func makeNSView(context: Context) -> GhosttyNSView {
        GhosttyNSView(ghosttyApp: ghosttyApp, session: session)
    }

    func updateNSView(_ nsView: GhosttyNSView, context: Context) {}

    static func dismantleNSView(_ nsView: GhosttyNSView, coordinator: ()) {
        nsView.destroySurface()
    }
}
