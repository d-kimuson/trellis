import SwiftUI

public struct SettingsView: View {
    @Bindable var settings: AppSettings
    let onApply: () -> Void
    /// Called when the user dismisses settings. When nil, falls back to SwiftUI `dismiss`.
    var onClose: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    // Snapshot taken on appear for Discard support
    @State private var snapshotFontSize: Double = 13
    @State private var snapshotFontFamily: String = ""
    @State private var snapshotPanelFontSize: Double = 13
    @State private var snapshotIPCEnabled: Bool = false
    @State private var snapshotKeyBindings: KeyBindingMap = .defaults
    @State private var editingAction: BindableAction?
    @State private var capturedCombo: KeyCombo?

    public init(settings: AppSettings, onApply: @escaping () -> Void, onClose: (() -> Void)? = nil) {
        self.settings = settings
        self.onApply = onApply
        self.onClose = onClose
    }

    private func closeSettings() {
        if let onClose { onClose() } else { dismiss() }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button {
                    closeSettings()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ghosttySection
                    panelsSection
                    keyBindingsSection
                    cliSection
                }
                .padding(20)
            }

            Divider()

            // Footer buttons
            HStack {
                Button("Revert") {
                    settings.fontSize = snapshotFontSize
                    settings.fontFamily = snapshotFontFamily
                    settings.panelFontSize = snapshotPanelFontSize
                    settings.ipcServerEnabled = snapshotIPCEnabled
                    settings.keyBindings = snapshotKeyBindings
                    onApply()
                }
                .foregroundColor(.secondary)

                Spacer()

                Button("Done") {
                    closeSettings()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            snapshotFontSize = settings.fontSize
            snapshotFontFamily = settings.fontFamily
            snapshotPanelFontSize = settings.panelFontSize
            snapshotIPCEnabled = settings.ipcServerEnabled
            snapshotKeyBindings = settings.keyBindings
        }
        .onChange(of: settings.fontSize) { _, _ in onApply() }
        .onChange(of: settings.fontFamily) { _, _ in onApply() }
    }

    // MARK: - Ghostty Section

    private var ghosttySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Ghostty", icon: "terminal")

            // Info banner
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.top, 1)
                Text("These settings are written to **~/.config/ghostty/config** and applied in real-time.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.06))
            )

            SettingsRow(label: "Font Size") {
                HStack(spacing: 8) {
                    Stepper(
                        value: $settings.fontSize,
                        in: 6...72,
                        step: 1
                    ) {
                        EmptyView()
                    }
                    .labelsHidden()

                    Text("\(Int(settings.fontSize.rounded())) pt")
                        .font(.system(size: 13, design: .monospaced))
                        .frame(width: 44, alignment: .leading)
                }
            }

            SettingsRow(label: "Font Family") {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("e.g. Menlo, JetBrains Mono", text: $settings.fontFamily)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                    Text("Leave blank to use ghostty's default.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - CLI Section

    private var cliSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "CLI Control", icon: "terminal.fill")

            SettingsRow(label: "Enable") {
                Toggle("Allow external CLI control (trellis)", isOn: $settings.ipcServerEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            if settings.ipcServerEnabled {
                SettingsRow(label: "Socket") {
                    Text(IPCServer.socketPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }

                SettingsRow(label: "Usage") {
                    Text("trellis list-panels\ntrellis send-keys s:<id> $'cmd\\n'")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Key Bindings Section

    private var keyBindingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Key Bindings", icon: "keyboard")

            VStack(spacing: 1) {
                ForEach(BindableAction.allCases, id: \.rawValue) { action in
                    let combo = settings.keyBindings.combo(for: action)
                    HStack {
                        Text(action.displayTitle)
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if editingAction == action {
                            KeyCaptureField(combo: $capturedCombo) {
                                if let newCombo = capturedCombo {
                                    let binding = KeyBinding(combo: newCombo, action: action)
                                    settings.keyBindings = settings.keyBindings.merging([binding])
                                }
                                editingAction = nil
                                capturedCombo = nil
                            }
                            .frame(width: 160)
                        } else {
                            Button {
                                editingAction = action
                                capturedCombo = combo
                            } label: {
                                Text(combo?.displayString ?? "—")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(combo != nil ? .primary : .secondary)
                                    .frame(width: 160, alignment: .center)
                                    .padding(.vertical, 3)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.secondary.opacity(0.08))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
            }

            Button("Reset to Defaults") {
                settings.keyBindings = .defaults
            }
            .font(.system(size: 12))
            .foregroundColor(.secondary)
        }
    }

    // MARK: - Panels Section

    private var panelsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Panels", icon: "sidebar.left")

            SettingsRow(label: "Font Size") {
                HStack(spacing: 8) {
                    Stepper(
                        value: $settings.panelFontSize,
                        in: 8...32,
                        step: 1
                    ) {
                        EmptyView()
                    }
                    .labelsHidden()

                    Text("\(Int(settings.panelFontSize.rounded())) pt")
                        .font(.system(size: 13, design: .monospaced))
                        .frame(width: 44, alignment: .leading)
                }
            }
        }
    }
}

// MARK: - Supporting Views

private struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.primary)
    }
}

private struct SettingsRow<Content: View>: View {
    let label: String
    let content: () -> Content

    init(label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .trailing)

            content()
        }
    }
}
