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
