import SwiftUI

/// VS Code-style command palette overlay.
/// Displayed at the top-center of the window when activated via Cmd+Shift+P.
struct CommandPaletteView: View {
    let store: WorkspaceStore
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var selectedIndex = 0

    private var filteredCommands: [AppCommand] {
        AppCommand.allCommands.filter { $0.matches(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
                TextField("Type a command...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .onSubmit { executeSelected() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // Command list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredCommands.enumerated()), id: \.element.id) { index, command in
                            CommandRow(command: command, isSelected: index == selectedIndex)
                                .id(command.id)
                                .contentShape(Rectangle())
                                .onTapGesture { execute(command) }
                        }
                    }
                }
                .frame(maxHeight: 300)
                .onChange(of: selectedIndex) { _, newValue in
                    if let cmd = filteredCommands[safe: newValue] {
                        proxy.scrollTo(cmd.id, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 500)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
        .onKeyPress(.upArrow) {
            moveSelection(-1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(1)
            return .handled
        }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }

    private func moveSelection(_ delta: Int) {
        let count = filteredCommands.count
        guard count > 0 else { return }
        selectedIndex = max(0, min(count - 1, selectedIndex + delta))
    }

    private func executeSelected() {
        guard let command = filteredCommands[safe: selectedIndex] else { return }
        execute(command)
    }

    private func execute(_ command: AppCommand) {
        isPresented = false
        executeCommand(command, store: store)
    }
}

// MARK: - Command Row

private struct CommandRow: View {
    let command: AppCommand
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: command.icon)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .frame(width: 20)
            Text(command.title)
                .font(.system(size: 13))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(4)
        .padding(.horizontal, 4)
    }
}

// MARK: - Command Execution

@MainActor
private func executeCommand(_ command: AppCommand, store: WorkspaceStore) {
    switch command.id {
    // Workspace
    case "workspace.new":
        store.addWorkspace()
    case "workspace.close":
        store.removeWorkspace(at: store.activeWorkspaceIndex)

    // Tab
    case "tab.newTerminal":
        guard let areaId = store.activeWorkspace?.activeAreaId else { return }
        store.addTerminalTab(to: areaId)
    case "tab.newBrowser":
        guard let areaId = store.activeWorkspace?.activeAreaId else { return }
        store.addBrowserTab(to: areaId)
    case "tab.newFileTree":
        guard let areaId = store.activeWorkspace?.activeAreaId else { return }
        store.addFileTreeTab(to: areaId)
    case "tab.close":
        guard let workspace = store.activeWorkspace,
              let areaId = workspace.activeAreaId,
              let area = workspace.layout.findArea(id: areaId) else { return }
        store.closeTab(in: areaId, at: area.activeTabIndex)

    // Area
    case "area.splitHorizontal":
        store.splitActiveArea(direction: .horizontal)
    case "area.splitVertical":
        store.splitActiveArea(direction: .vertical)
    case "area.close":
        store.closeActiveArea()

    // UI
    case "ui.toggleSidebar":
        NotificationCenter.default.post(name: .toggleSidebar, object: nil)
    case "ui.openSettings":
        NotificationCenter.default.post(name: .openSettings, object: nil)

    // Font
    case "font.increase":
        store.ghosttyApp.increaseFontSize()
    case "font.decrease":
        store.ghosttyApp.decreaseFontSize()
    case "font.reset":
        store.ghosttyApp.resetFontSize()

    default:
        break
    }
}

// MARK: - Safe Collection Access

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
