import SwiftUI

public struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let onApply: () -> Void

    @Environment(\.dismiss) private var dismiss

    public init(settings: AppSettings, onApply: @escaping () -> Void) {
        self._settings = ObservedObject(wrappedValue: settings)
        self.onApply = onApply
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button {
                    dismiss()
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
                }
                .padding(20)
            }

            Divider()

            // Footer buttons
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Button("Apply") {
                    onApply()
                    dismiss()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Ghostty Section

    private var ghosttySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Ghostty", icon: "terminal")

            // Warning banner
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
                    .padding(.top, 1)
                Text("These settings are written to **~/.config/ghostty/config**. Changes take effect after clicking Apply.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.orange.opacity(0.08))
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
