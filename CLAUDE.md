## Project Overview

tmux alternative built on libghostty. macOS native app (SwiftUI + AppKit).

## Tech Stack

- GUI: SwiftUI + AppKit (NSViewRepresentable for libghostty surface)
- Terminal: libghostty (Ghostty v1.2.1, patched for direct macOS static lib)
- Build: Nix Flakes (Zig 0.14) + Make + system swiftc
- Test: XCTest via xcodebuild (SPM Package.swift defines targets)
- Lint: SwiftLint (via Nix devShell)
- Quality gate: check-changed (runs lint/build/test on changed files)
- Task tracking: bd (beads) — see AGENTS.md

## Running Commands

すべてのビルド/品質コマンドは `DEVELOPER_DIR=... nix develop -c` 経由で実行する。インタラクティブシェルには入れないため、必ずワンライナーで実行すること。

```bash
# 環境変数プレフィックス (全コマンド共通)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer nix develop -c <command>
```

初回セットアップ:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer nix develop -c make setup
```

個別コマンド:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer nix develop -c make build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer nix develop -c make test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer nix develop -c make lint
```

## Quality Gate (MUST follow)

.swift ファイルを変更したら、コミット前に必ず実行:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer nix develop -c npx -y check-changed@0.0.1-beta.4 run
```

lint, build, test を変更ファイルに対して実行する。全チェック通過が必須。失敗したら修正して再実行。

## Source Structure

```
Sources/
  GhosttyKit/             # C module map for libghostty headers
  OreoreTerminal/         # Library target (all app code)
    ContentView.swift
    SidebarView.swift
    GhosttyApp.swift      # libghostty C API wrapper
    Models/
      SessionStore.swift
    Terminal/
      PanelNode.swift     # Recursive split tree (ADT)
      TerminalSession.swift
      TerminalView.swift
      PanelView.swift
  OreoreTerminalApp/      # Executable target (entry point only)
    main.swift
Tests/
  OreoreTerminalTests/    # Test target
patches/                  # libghostty build patches
deps/ghostty/             # Cloned ghostty source (gitignored)
```

## Dual Build System

- **Makefile**: App build. Compiles all Swift files with swiftc directly.
- **Package.swift (SPM)**: Test/IDE support. Library + executable + test targets.
- Both must be kept in sync when adding/moving source files.

## Architecture Constraints

- Core logic (models, state) should be GUI-independent for future cross-platform
- Files using ghostty C types must `import GhosttyKit`
- Public types in OreoreTerminal library need `public` access for test/app target access

## Nix + Xcode Pitfalls

- **`swift test` は使用禁止**: Xcode 26 の testing plugin バグで壊れる。`make test` を使う
- **`xcodebuild` は Makefile 内で `env -i` 経由実行**: Nix の LD/LDFLAGS がリンカーを破壊するため
- **SwiftLint は nix develop 内でのみ利用可能**: PATH に入るのは devShell 内だけ

## Coding Conventions

- Prefer value types (struct/enum) over classes where possible
- Models: Pure data + functions, avoid mutable shared state
- SwiftUI views: Keep thin, delegate logic to models/stores
