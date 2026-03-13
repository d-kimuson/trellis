---
description: 'バージョンをリリースする（CHANGELOG更新 → GitHub Release作成）'
disable-model-invocation: true
user-invocable: true
argument-hint: '[version]'
allowed-tools: Read, Glob, Grep, Bash(git), Bash(gh), Bash(date), Bash(plutil), Bash(./scripts/generate-licenses.sh), Write, Edit
---

Trellis のリリース作業を行います。引数にバージョン番号を指定してください（例: `/release 0.2.0`）。省略した場合は `Resources/Info.plist` から読み取ります。

バージョン: `$ARGUMENTS`

## CHANGELOG フォーマット（必ず守ること）

```markdown
## [x.y.z] — YYYY-MM-DD

### Added
- ユーザーから見える新機能の説明（実装詳細でなく動作）

### Changed
- 既存動作への変更点

### Fixed
- 修正したバグ（再現条件や症状を簡潔に）

### Removed
- 削除した機能・動作

### Security
- セキュリティ修正（CVE等があれば記載）
```

- セクションはエントリがあるものだけ記載（空セクション不要）
- 各エントリは体言止め or 動詞原形で統一（「〜を追加」「Add 〜」等）
- 技術的な実装詳細より、ユーザーへの影響を優先して記述

## 手順

### 1. バージョン確定

`$ARGUMENTS` が空の場合:
```bash
plutil -extract CFBundleShortVersionString raw Resources/Info.plist
```
で読み取る。以降 `VERSION` はこの値を指す。

### 2. 変更内容の収集

直前のタグから現在までのコミットを取得:
```bash
git log $(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)..HEAD --oneline
```

取得したコミットを上記フォーマットのセクションに分類する。分類の判断基準:
- `feat:` / `add` / 新機能 → Added
- `fix:` / バグ修正 → Fixed
- `refactor:` / `chore:` / 動作変更 → Changed
- 削除・廃止 → Removed
- セキュリティ関連 → Security

### 3. サードパーティライセンス更新

```bash
./scripts/generate-licenses.sh
```

生成された `THIRD_PARTY_LICENSES` に差分があればコミット対象に含める（ステップ 5 でまとめてコミット）。

### 4. CHANGELOG.md 更新

`CHANGELOG.md` の `## [Unreleased]` の直下に新しいエントリを挿入する:

```markdown
## [Unreleased]

## [VERSION] — YYYY-MM-DD

### Added
- ...
```

挿入後、必ずユーザーに内容を確認してもらう。ユーザーの承認なしに次のステップへ進まないこと。

### 5. リリースコミット

```bash
git add CHANGELOG.md THIRD_PARTY_LICENSES
git commit -m "chore: release v${VERSION}"
```

### 6. リリーススクリプト実行

```bash
./scripts/release.sh ${VERSION}
```

このスクリプトが以下を行う:
- `make clean && make app`
- zip / dmg の生成
- git タグの作成・プッシュ
- GitHub Release の作成（汎用テンプレートのノート付き）

### 7. GitHub Release ノートを更新

スクリプト実行後、CHANGELOG のエントリをベースに Release Note を更新する:

```bash
gh release edit "v${VERSION}" --notes "$(cat <<'NOTES'
## What's New

### Added
- ...

## Install

1. Open `Trellis-VERSION-macos-arm64.dmg`
2. Drag Trellis to Applications

> **Note**: Trellis is not notarized. macOS may block it on first launch.
> Remove the quarantine attribute after installation:
> ```bash
> xattr -d com.apple.quarantine /Applications/Trellis.app
> ```

## Requirements
- macOS 14.0+
- Apple Silicon (arm64)
NOTES
)"
```

"What's New" セクションには CHANGELOG から該当バージョンのエントリをそのまま転記する（セクション構成・文言を変えない）。

### 8. 完了報告

リリースURLを表示して完了を伝える:
```
https://github.com/d-kimuson/trellis/releases/tag/vVERSION
```
