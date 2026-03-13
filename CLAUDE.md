## Project Overview

Terminal app built on libghostty. macOS native app (SwiftUI + AppKit).

## Tech Stack

- GUI: SwiftUI + AppKit (NSViewRepresentable for libghostty surface)
- Terminal: libghostty (Ghostty v1.2.1, patched for direct macOS static lib)
- Build: Nix Flakes (Zig 0.14, mkShellNoCC) + Make + system swiftc
- Test: XCTest via xcodebuild (SPM Package.swift defines targets)
- Lint: SwiftLint (via Nix devShell)
- Quality gate: gatecheck (runs lint/build/test on changed files)
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

## Debug Logging

バグ調査時は `make debug` で起動すること。ファイルベースのログが有効になる。

```bash
make debug            # デバッグビルドで起動 (DEBUG_LOGGING フラグ有効)
make debug-log        # 別ターミナルで最新ログを tail -f
```

ログ出力先: `~/Library/Logs/Trellis/debug-YYYY-MM-DD-HH-mm-ss.log`

- 起動ごとに新しいファイルが作られる
- キーボードイベント (`[KEY]`)、OSC アクション (`[OSC]`)、ghostty アクション (`[ACTION]`)、起動 (`[STARTUP]`) が記録される
- `debugLog("[CATEGORY] message")` で任意のログを追加できる (非デバッグビルドはゼロオーバーヘッド)

## Quality Gate (MUST follow)

.swift ファイルを変更したら、コミット前に必ず実行:

```bash
npx -y gatecheck check
```

lint, build, test を変更ファイルに対して実行する。全チェック通過が必須。失敗したら修正して再実行。

## UI Terminology

| Term | Description | Code |
|------|-------------|------|
| ActivityBar | Sidebar の左にある狭いアイコン列。Sidebar トグル・通知ベル・設定等 | ContentView の左端 VStack (width: 32) |
| Sidebar | ワークスペース一覧が並ぶ左ペイン (macOS HIG 準拠) | SidebarView |
| Area | ワークスペース内のコンテンツ表示単位。LayoutNode で分割管理 | AreaLayoutView |
| Panel | Area 内の個別ビュー | TerminalPanel, BrowserPanel, FileTreePanel 等 |
| Workspace | 複数の Area をまとめた作業単位 | Workspace model |

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

詳細なコーディング規約は [docs/CODING_GUIDELINE.md](docs/CODING_GUIDELINE.md) を参照。
