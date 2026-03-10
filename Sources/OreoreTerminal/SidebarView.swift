import SwiftUI

struct SidebarView: View {
    @ObservedObject var sessionStore: SessionStore

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $sessionStore.selectedSessionId) {
                Section("Sessions") {
                    ForEach(sessionStore.sessions) { session in
                        HStack {
                            Image(systemName: "terminal")
                                .foregroundColor(.secondary)
                            Text(session.title)
                                .lineLimit(1)
                        }
                        .tag(session.id)
                        .contextMenu {
                            Button("Split Horizontal") {
                                sessionStore.split(session, direction: .horizontal)
                            }
                            Button("Split Vertical") {
                                sessionStore.split(session, direction: .vertical)
                            }
                            Divider()
                            Button("Close") {
                                sessionStore.closeSession(session)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            // Bottom toolbar
            HStack {
                Button(action: {
                    let newSession = sessionStore.createSession()
                    // Add new session as a split to the right of the current layout
                    sessionStore.rootPanel = .split(
                        id: UUID(),
                        direction: .vertical,
                        first: sessionStore.rootPanel,
                        second: .terminal(newSession),
                        ratio: 0.5
                    )
                }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("New Terminal")

                Spacer()
            }
            .padding(8)
        }
    }
}
