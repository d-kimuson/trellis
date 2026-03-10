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

## Build & Quality Commands

```bash
# Enter dev shell (required for build/lint)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer nix develop

# Inside dev shell:
make setup   # Initial: clone ghostty + build libghostty.a
make build   # Build the app (Makefile swiftc)
make run     # Build + run
make test    # Run tests (xcodebuild test)
make lint    # SwiftLint
make check   # All checks via check-changed
```

Note: `make test` uses `xcodebuild test` (not `swift test`) due to Xcode 26 testing plugin bug.

## Quality Gate (MUST follow)

After modifying .swift files, run check-changed to verify changes:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer nix develop -c npx -y check-changed@0.0.1-beta.4 run
```

This runs lint, build, and test against changed files. All checks must pass before committing. If a check fails, fix the issue and re-run until all pass.

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

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` must be set (Nix overrides it)
- swiftc: `/usr/bin/xcrun -sdk macosx swiftc` (Nix's Swift SDK is incompatible)
- Metal compiler requires Xcode (proprietary, not in nixpkgs)
- Core logic (models, state) should be GUI-independent for future cross-platform
- Files using ghostty C types must `import GhosttyKit`
- Public types in OreoreTerminal library need `public` access for test/app target access

## Nix + Xcode Pitfalls

Nix devShell と Xcode ツールチェインの衝突がいくつかあり、回避策が組み込まれている:

- **`swift test` は使用禁止**: Xcode 26 の testing plugin バグで壊れる。`make test` (= `xcodebuild test`) を使う
- **`xcodebuild` は `env -i` 経由で実行**: Nix の LD/LDFLAGS がリンカーを破壊するため、Makefile 内で `env -i` でクリーン環境にしている
- **SwiftLint は nix develop 内でのみ利用可能**: PATH に入るのは devShell 内だけ
- **check-changed は `nix develop -c` で実行**: 上記すべてを考慮し、コマンド全体を nix develop 内で実行する

## Coding Conventions

- Prefer value types (struct/enum) over classes where possible
- Models: Pure data + functions, avoid mutable shared state
- SwiftUI views: Keep thin, delegate logic to models/stores
