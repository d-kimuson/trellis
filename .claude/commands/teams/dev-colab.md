---
description: 'bd ready からタスクを1つ選んでユーザーと協働実装する'
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash(bd), Bash(git), Bash(make), Bash(npx), Read, Glob, Grep, Edit, Write, AskUserQuestion
---

bdから実装可能なタスクを1つ選び、kimuson と協働して実装を完了させる。
判断が必要な場面では `AskUserQuestion` で確認しながら進める。

## 手順

### 1. タスク選択

```bash
bd ready --unassigned
```

**選択ルール:**
1. P0 > P1 > P2 — 上位優先度が残っていれば下位は選ばない
2. 同一優先度内では全体最適で選ぶ（後続タスクを解放するもの、重大なバグ修正を優先）

```bash
bd show <id>
```

詳細を確認し、AC とラベル（`gate:required` / `gate:not-required`）を把握する。
実装前に方針をまとめて kimuson に共有し、問題があれば修正してから着手する。

### 2. タスクを in_progress に更新

```bash
bd update <id> --status=in_progress
```

### 3. 実装

実装上の注意:
- コアロジックはGUI非依存に保つ
- ソースファイルを追加した場合は `Makefile` と `Package.swift` 両方を更新する
- `GhosttyKit` の型を使う場合は `import GhosttyKit`

ユニットテストで動作を保証できる箇所は TDD で実装する（テスト先行 → 最小実装 → リファクタ）。GUIや ghostty C API に依存する部分はテスト対象外。

仕様・方針に判断が必要な場面では `AskUserQuestion` で確認してから進める。

### 4. クオリティゲート

```bash
npx -y check-changed@0.0.1-beta.4 run
```

全チェック（lint / build / test）が通過すること。失敗した場合は修正して再実行。

### 5. コミット

```bash
bd sync --from-main
git add <変更ファイル>
git commit -m "<タスクタイトルを簡潔に>"
```

### 6. gate の作成またはタスクのクローズ

ラベルを確認する（`bd show <id>` の labels フィールド）:

**`gate:not-required` ラベルの場合 → 自動クローズ:**

```bash
bd close <id> --reason="実装完了。テストで動作担保。gate 不要。"
```

**`gate:required` ラベルの場合 → gate を作成してタスクをブロック:**

```bash
GATE_ID=$(bd q \
  --title="<タスクタイトル>: 動作確認" \
  --type=gate \
  --priority=1 \
  --description="$(cat <<'EOF'
## 対応内容
[何をしたか1〜2行で]

## 確認手順
1. \`make build && make run\`
2. [変更内容に応じた確認操作を具体的に記載]

## 影響しうる箇所
[変更により挙動が変わりうる機能・画面]

## 関連ファイル
[変更したファイル一覧]

## 実装の要点
[アプローチの概要。代替案があれば簡潔に]
EOF
)")

# gate が完了するまでタスクをブロック
bd dep add <task-id> "$GATE_ID"
```

**確認手順は変更内容を踏まえて設計すること。**

### 7. スコープ外タスクの記録

実装中に発見したスコープ外の問題・改善点は issue 化して kimuson に渡す:

```bash
bd create \
  --title="[要確認] <発見した問題>" \
  --type=task \
  --priority=3 \
  --assignee=kimuson \
  --description="<発見した状況と内容>。dev-colab 実装中に発見。kimuson が確認・整理すること。"
```

### 8. 完了報告

実装内容・変更ファイル・クオリティゲート結果・gate ID（作成した場合）をまとめて報告する。

## 制約

- 1タスクのみ実装する（複数タスクに手を出さない）
- スコープ外の修正は行わない（issue 化に留める）
- `git push` は行わない
