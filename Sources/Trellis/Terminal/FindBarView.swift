import SwiftUI

/// Find bar overlay shown at the top of a terminal view when Cmd+F is pressed.
/// Provides keyword search with previous/next navigation and match count display.
struct FindBarView: View {
    @Bindable var session: TerminalSession
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        if session.isFindVisible {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                TextField("Find", text: $session.findQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .frame(minWidth: 150)
                    .focused($isTextFieldFocused)
                    .onKeyPress(.return) {
                        session.onFindNavigate?(true)
                        return .handled
                    }
                    .onKeyPress(.tab) {
                        session.onFindNavigate?(true)
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        session.isFindVisible = false
                        return .handled
                    }

                matchCountLabel

                Divider().frame(height: 14)

                Button(action: { session.onFindNavigate?(false) }) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .disabled(session.findMatchCount == 0)
                .help("Previous match (Shift+Return)")

                Button(action: { session.onFindNavigate?(true) }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .disabled(session.findMatchCount == 0)
                .help("Next match (Return)")

                Divider().frame(height: 14)

                Button(action: { session.isFindVisible = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help("Close (Escape)")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial)
            .overlay(alignment: .bottom) {
                Divider()
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isTextFieldFocused = true
                }
            }
        }
    }

    @ViewBuilder
    private var matchCountLabel: some View {
        if session.findQuery.isEmpty {
            EmptyView()
        } else if session.findMatchCount == 0 {
            Text("No matches")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        } else {
            Text("\(session.findCurrentMatchIndex) of \(session.findMatchCount)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}
