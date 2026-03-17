# Changelog

All notable changes to Trellis are documented here.

## Format

Each release entry uses the following sections (omit sections with no entries):

- **Added** — New features
- **Changed** — Changes to existing behavior
- **Fixed** — Bug fixes
- **Removed** — Removed features or behavior
- **Security** — Security fixes

---

## [Unreleased]

## [0.0.5] — 2026-03-17

### Added
- コマンドパレット (Cmd+Shift+P)
- キーバインドのカスタマイズ UI
- 設定のファイル化 (UserDefaults → ~/.config/trellis/config.toml)
- ファイルプレビュー検索に件数表示・次/前ナビゲーション
- ファイルプレビューにテキスト検索 (Cmd+F)
- FileTreeView に git diff フィルター機能
- DiffView に行コメント付きレビュー機能
- FileTreeView からターミナルへのドラッグ&ドロップで相対パス入力
- FileTreeView に右クリックコンテキストメニュー
- macOS ネイティブウィンドウタブ対応
- ブロードキャスト入力機能
- Spotlight 統合
- Touch Bar 対応
- Accessibility (VoiceOver) — NSAccessibility プロトコル実装
- セッション復元時に中断コマンドを通知
- 通知にワークスペース名を付帯
- 通知時に Dock アイコンバウンス
- Find 検索窓での Cmd+V ペースト対応

### Changed
- AppSettings / FileTreeState / NotificationStore / TerminalSession を @Observable に移行
- FileTreeState の責務分割リファクタリング
- TerminalSession からプラットフォーム依存を分離
- ActivityBar・サイドバーのアイコンサイズを拡大

### Fixed
- Cmd+V ペーストを ghostty の bracketed paste フローに統合
- タブ/エリア切替時にターミナルの firstResponder が復帰しない問題
- フォーカス管理: パネル外クリック時のデフォーカスと FileTreeView のフォーカス対応
- Git diff/status がサブディレクトリで動作しない問題
- FileTreeView ディレクトリ探索の深さ制限追加 (クラッシュ防止)
- DiffView レビューコメント UI が表示されない問題
- Git Diff View のコードブロックと行番号の高さ不一致
- Settings を専用 NSPanel 化、キーバインド変更後に NSMenu を再ビルド
- セッション復元の interrupted 通知が表示されない問題
- GhosttyAppWrapper.current の static weak をスレッドセーフに修正
- FileTreeState FSEventStream callback のレース条件修正
- TerminalSession スレッド安全性: deinit/close 整理と MainActor.assumeIsolated 適用
- NSCursor push/pop のバランス崩れ防止
- IPCServer の write を non-blocking に変更
- CVDisplayLink の毎フレーム tick を削除し wakeup_cb のみで駆動
- escapeJS で `</script>` タグをエスケープして diff プレビュー破損を修正
- コメントフォーム幅をビューポート内に制限

## [0.0.4] — 2026-03-13

### Added
- Text search in terminal scrollback with Cmd+F (highlight + navigation)
- Sidebar redesign — Pinned / Workspaces two-section layout
- GitHub-style git diff viewer in file tree (diff2html)
- Syntax highlighting in file preview
- Show dotfiles in file tree (`.claude`, `.env`, etc.)
- Secure bookmark to persist file tree root path across restarts
- Full-screen support (Enter Full Screen menu)
- Right-click context menu (Copy / Paste / Open URL / Search Web)
- File tree directory picker defaults to workspace cwd

### Changed
- Replace Timer with CVDisplayLink for refresh rate–aware updates

### Fixed
- Session restore: pwd and git branch not shown after restore
- File tree: nested expansion disappears after reload
- File node UUID collisions (XOR → SHA-256 based ID)
- PanelView: stale `areaId` capture causing focus issues
- IPCServer: changed `unowned` reference to `weak` to prevent crash on exit
- GhosttyAppWrapper: shutdown ordering to prevent use-after-free
- Restrict scrollback file permissions to 0600 and clean up stale files

## [0.0.3] — 2026-03-11

### Added
- Browser DevTools accessible via F12 and toolbar button
- Workspace pinning with session snapshot and replay
- trellis CLI for external panel control
- Panel font size setting and improved settings UX

### Changed
- Improved scrollback replay stability and sidebar UX
- Watch file tree recursively with FSEventStream; restore expanded dirs on reload
- Refactor notification tracking to use sessionId instead of workspaceIndex+areaId

### Fixed
- Scrollback replay: ZDOTDIR injection for zsh (no user config required)
- Terminal resize instability: debounce size updates and guard zero sizes
- Desktop notifications not appearing via OSC 9
- Tab close button not working on first click in unfocused areas
- ghostty focus state not syncing when terminals are added or split

## [0.1.0] — 2026-03-11

### Added
- Initial release
