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

## Tech

- **Terminal engine**: [libghostty](https://github.com/ghostty-org/ghostty) (GPU-accelerated via Metal)
- **GUI**: SwiftUI + AppKit
- **Build**: Nix Flakes + Make

## Getting Started

See [docs/dev.md](docs/dev.md) for development setup.

```bash
# Prerequisites: Xcode, Nix, direnv
direnv allow
make setup   # Build libghostty (first time only)
make run     # Build and launch Trellis.app
```

## License

TBD
