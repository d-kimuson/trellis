import AppKit
import SwiftUI

/// A field that captures a key combination when focused.
/// Displays the current combo or "Press keys..." while recording.
struct KeyCaptureField: NSViewRepresentable {
    @Binding var combo: KeyCombo?
    let onCommit: () -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.combo = combo
        view.onUpdate = { newCombo in
            combo = newCombo
        }
        view.onCommit = onCommit
        // Become first responder after layout
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.combo = combo
    }
}

final class KeyCaptureNSView: NSView {
    var combo: KeyCombo?
    var onUpdate: ((KeyCombo) -> Void)?
    var onCommit: (() -> Void)?

    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupLabel()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLabel()
    }

    private func setupLabel() {
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updateLabel()
    }

    private func updateLabel() {
        label.stringValue = combo?.displayString ?? "Press keys..."
        label.textColor = combo != nil ? .labelColor : .secondaryLabelColor
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            label.stringValue = "Press keys..."
            label.textColor = .systemBlue
        }
        return result
    }

    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.intersection([.command, .shift, .control, .option]) != [] else {
            // Escape cancels
            if event.keyCode == 53 {
                onCommit?()
                return
            }
            return
        }

        let char = event.charactersIgnoringModifiers?.lowercased() ?? ""
        guard !char.isEmpty else { return }

        var modifiers = KeyModifier()
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.shift)   { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.option)  { modifiers.insert(.option) }

        let newCombo = KeyCombo(modifiers: modifiers, key: char)
        combo = newCombo
        onUpdate?(newCombo)
        updateLabel()

        // Auto-commit after capturing
        DispatchQueue.main.async { [weak self] in
            self?.onCommit?()
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Intercept all key equivalents while recording
        if window?.firstResponder === self {
            keyDown(with: event)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
