---
description: 'bd ready からタスクを1つ選んでバックグラウンドで実装する'
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash(bd), Read, Glob, Grep
---

bdから実装可能なタスクを1つ選び、バックグラウンドエージェントとして実装を完了させてください。

## 手順

### 1. タスク選択

```bash
bd ready
```

出力されたタスク一覧から、以下の基準で1つ選ぶ：
- ブロッカーがない
- スコープが明確（1セッションで完了できる）
- 優先度が最も高い

```bash
bd show <id>
```

詳細を確認し、実装方針を決める。

### 2. タスクを in_progress に更新

```bash
bd update <id> --status=in_progress
```

### 3. 実装

CLAUDE.md・AGENTS.md の規約に従って実装する：
- コアロジックはGUI非依存に保つ
- ソースファイルを追加した場合は `Makefile` と `Package.swift` 両方を更新する
- `GhosttyKit` の型を使う場合は `import GhosttyKit`

### 4. クオリティゲート

```bash
npx -y check-changed@0.0.1-beta.4 run
```

全チェック（lint / build / test）が通過すること。失敗した場合は修正して再実行。

### 5. コミット＆クローズ

```bash
bd sync --from-main
git add <変更ファイル>
git commit -m "<タスクタイトルを簡潔に>"
bd close <id>
```

### 6. 完了報告

実装内容・変更ファイル・クオリティゲート結果をまとめて報告してください。

## 制約

- 1タスクのみ実装する（複数タスクに手を出さない）
- スコープ外の修正・リファクタは行わない（別タスクを作成して記録するに留める）
- `git push` は行わない（このリポジトリはリモートなし）
