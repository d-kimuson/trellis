## Task Tracking (bd)

This project uses **bd** (beads) for issue tracking. Issues are stored locally in `.beads/`.

### Workflow

```bash
bd ready                              # Find available work (no blockers)
bd show <id>                          # View issue details + dependencies
bd update <id> --status=in_progress   # Claim work
bd close <id>                         # Mark complete
bd close <id1> <id2> ...              # Close multiple at once
```

### Creating Issues

```bash
bd create --title="..." --type=task|bug|feature|epic --priority=2
bd create --title="..." --type=task --priority=1 --description="..."
bd dep add <issue> <depends-on>       # issue depends on depends-on
```

Priority: 0 (critical) to 4 (backlog). Use numbers, not words.

### Sync

```bash
bd sync --from-main    # Pull beads updates from main branch
bd sync --status       # Check sync status
```

## Quality Gate (MUST follow)

.swift ファイルを変更したら、コミット前に必ず実行:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer nix develop -c npx -y check-changed@0.0.1-beta.4 run
```

全チェック通過が必須。失敗したら修正して再実行。

個別コマンド(すべて `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer nix develop -c` 経由で実行):

```bash
make lint    # SwiftLint
make build   # App build
make test    # XCTest via xcodebuild
```

## Session Completion

1. Create bd issues for remaining/discovered work
2. Quality gate を実行し全チェック通過を確認(コード変更がある場合)
3. Close completed bd issues
4. Commit: `bd sync --from-main && git add <files> && git commit`
5. Provide context for next session

Note: This repo has no remote. Do not attempt `git push`.

## Key Constraints

- Read `CLAUDE.md` for architecture details, build setup, and known pitfalls
- Core models must remain GUI-independent (future Linux/GTK support)
- libghostty patches are in `patches/` — do not modify `deps/ghostty/` directly
- When adding source files, update both Makefile and Package.swift
- Files using ghostty C types must `import GhosttyKit`
