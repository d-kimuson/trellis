# Trellis

A terminal app for macOS with a side-panel UI, workspaces, and native notifications — built for engineers juggling parallel sessions.

## Overview

Trellis is a macOS terminal reimagined around how engineers actually work today: multiple sessions running side by side, each demanding attention at different times.

Instead of buried tabs or split panes you lose track of, Trellis gives you a side-panel layout with workspace-based organization. Switch between contexts with tabs, keep long-running processes visible, and let OSC 777/9 notifications surface what matters — as desktop alerts, badge counts, or focus shifts — so nothing slips through.

Built for workflows where you're running multiple Claude Code instances, watching build pipelines, and tailing logs all at once.

## Features

- **Workspaces** — Isolated contexts with independent layouts. Switch between projects without losing state.
- **Split panes** — Horizontal and vertical splits with draggable dividers. Recursive nesting supported.
- **Tab system** — Each area holds multiple tabs. Drag tabs between areas or drop them on edges to create new splits.
- **Native notifications** — OSC 9/777 desktop notifications with per-tab badge counts and click-to-focus.
- **Built-in browser** — Side-by-side documentation browsing without leaving the terminal.
- **File tree** — Directory browser with preview pane and .gitignore-aware filtering.
- **CLI control** — Control panels from any terminal via the `trellis` command (tmux-style).

## Tech

- **Terminal engine**: [libghostty](https://github.com/ghostty-org/ghostty) (GPU-accelerated via Metal)
- **GUI**: SwiftUI + AppKit
- **Build**: Nix Flakes + Make

## Install

Download the latest `.dmg` from [Releases](https://github.com/d-kimuson/trellis/releases), open it, and drag Trellis to Applications.

**Note**: Trellis is not signed with an Apple Developer certificate. macOS will block the app on first launch with "Trellis is damaged and can't be opened." This is a Gatekeeper restriction, not an actual problem with the app.

To run it, remove the quarantine attribute after copying to Applications:

```bash
xattr -d com.apple.quarantine /Applications/Trellis.app
```

## CLI Control

Trellis ships with a built-in CLI for controlling panels from any terminal — useful for AI agent workflows where one agent needs to spawn or communicate with another.

**Setup**: Enable in **Settings → CLI Control → Allow external CLI control**.

The `trellis` binary (the app itself) doubles as the CLI client when invoked with a subcommand.

```bash
# List all terminal panels
trellis list-panels

# Send keys to the active panel (or create a new one if no --panel given)
trellis send-keys 'codex .' Enter          # new panel, prints its id to stdout
trellis send-keys --panel s:<id> 'hi' Enter  # existing panel
```

**Agent-to-agent example** — Claude Code spawns Codex in a new panel, Codex reports back when done:

```bash
# Claude Code side: start Codex in a new panel, capture the panel id
CODEX_PANEL=$(trellis send-keys 'codex .' Enter)

# Codex side: when finished, notify Claude Code's panel
trellis send-keys --panel s:<cc-panel-id> 'LGTM!' Enter
```

**Reference**:

| Command | Description |
|---------|-------------|
| `trellis list-panels` | JSON list of all terminal panels with id, title, pwd, workspace |
| `trellis send-keys [--panel\|-p <id>] <keys> [Enter]` | Send text to a panel. Omit `--panel` to create a new panel. `Enter` appends a newline. |

**Notes**:
- Panel ids are in `s:<UUID>` format; use `list-panels` to discover them.
- `--panel` / `-p` are equivalent.
- `Enter` is a special token that appends `\n`; other keys like `Tab` or Ctrl sequences (`\x03` = Ctrl+C) can be embedded directly in the string.
- When `--panel` is omitted, the new panel id is printed to stdout, making it pipeable.

## Development

See [docs/dev.md](docs/dev.md) for setup instructions.

```bash
# Prerequisites: Xcode, Nix, direnv
direnv allow
make setup   # Build libghostty (first time only)
make run     # Build and launch Trellis.app
```

## License

TBD
