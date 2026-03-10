import SwiftUI

public struct ContentView: View {
    @ObservedObject var sessionStore: SessionStore

    public init(sessionStore: SessionStore) {
        self._sessionStore = ObservedObject(wrappedValue: sessionStore)
    }

    public var body: some View {
        NavigationSplitView {
            SidebarView(sessionStore: sessionStore)
                .frame(minWidth: 160, idealWidth: 200)
        } detail: {
            PanelView(
                node: sessionStore.rootPanel,
                ghosttyApp: sessionStore.ghosttyApp,
                sessionStore: sessionStore
            )
        }
        .frame(minWidth: 800, minHeight: 500)
    }
}
