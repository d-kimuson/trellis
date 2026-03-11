## Project Overview

Terminal app built on libghostty. macOS native app (SwiftUI + AppKit).

## Tech Stack

- GUI: SwiftUI + AppKit (NSViewRepresentable for libghostty surface)
- Terminal: libghostty (Ghostty v1.2.1, patched for direct macOS static lib)
- Build: Nix Flakes (Zig 0.14, mkShellNoCC) + Make + system swiftc
- Test: XCTest via xcodebuild (SPM Package.swift defines targets)
- Lint: SwiftLint (via Nix devShell)
- Quality gate: check-changed (runs lint/build/test on changed files)
- Task tracking: bd (beads) — see AGENTS.md

## Running Commands

direnv が `.envrc` を自動ロードするので、プレフィックスなしで実行できる。

初回セットアップ:
```bash
make setup
```

個別コマンド:
```bash
make build
make test
make lint
```

## Quality Gate (MUST follow)

.swift ファイルを変更したら、コミット前に必ず実行:

```bash
npx -y check-changed@0.0.1-beta.4 run
```

lint, build, test を変更ファイルに対して実行する。全チェック通過が必須。失敗したら修正して再実行。

## Source Structure

```
Sources/
  GhosttyKit/          # C module map for libghostty headers
  Trellis/             # Library target (all app code)
    ContentView.swift
    SidebarView.swift
    GhosttyApp.swift   # libghostty C API wrapper
    Models/            # Data types + WorkspaceStore
    Terminal/          # TerminalView, PanelView, split layout
    Panels/            # BrowserPanelView, FileTreePanelView
    Notifications/     # NotificationStore, NotificationManager
  TrellisApp/          # Executable target (entry point only)
    main.swift
Tests/
  TrellisTests/        # Test target
patches/               # libghostty build patches
deps/ghostty/          # Cloned ghostty source (gitignored)
```

## Dual Build System

- **Makefile**: App build. Compiles all Swift files with swiftc directly.
- **Package.swift (SPM)**: Test/IDE support. Library + executable + test targets.
- Both must be kept in sync when adding/moving source files.

## Architecture Constraints

- Core logic (models, state) should be GUI-independent for future cross-platform
- Files using ghostty C types must `import GhosttyKit`
- Public types in Trellis library need `public` access for test/app target access

## Build Pitfalls

- **`swift test` は使用禁止**: Xcode 26 の testing plugin バグで壊れる。`make test` を使う
- **SwiftLint は nix develop 内でのみ利用可能**: PATH に入るのは devShell 内だけ

## Coding Conventions

- Prefer value types (struct/enum) over classes where possible
- Models: Pure data + functions, avoid mutable shared state
- SwiftUI views: Keep thin, delegate logic to models/stores
