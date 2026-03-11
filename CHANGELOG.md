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
