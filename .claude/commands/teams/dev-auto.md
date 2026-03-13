---
description: 'bd ready からタスクを1つ選んで自律実装する。ユーザー確認なしで意思決定し、継続メモを残す'
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash(bd), Bash(git), Bash(make), Bash(npx), Read, Glob, Grep, Edit, Write
---

bdから実装可能なタスクを1つ選び、ユーザー確認なしで自律的に実装を完了させる。

**重要:** このモードではユーザーへの質問・確認ができない。判断が必要な場面では自分で決断し、その理由を記録に残す。

システムプロンプトに以下のメタデータが含まれる場合がある。継続メモに必ず記録すること:
- `session-id:` — このセッションの ID
- `task-id:` — 実装対象のタスク ID（指定されている場合はタスク選択をスキップ）

**再開セッション:** `--resume` で呼ばれた場合は gates-review で NG になった修正の再開。
`bd comments <task-id>` で NG の詳細を確認し、問題を修正してから再度クオリティゲート→コミットの流れに入る。

## 手順

### 1. タスク選択

システムプロンプトに `task-id:` が指定されている場合はそのタスクを使う。指定がない場合は自分で選択する:

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

### 2. タスクを in_progress に更新

```bash
bd update <id> --status=in_progress
```

### 3. 実装

**自律判断の原則:**
- 仕様の解釈に選択肢がある場合は AC に最も忠実な解釈を選ぶ
- 実装方針に迷った場合は保守的・シンプルな方を選ぶ
- スコープ外の問題を発見した場合は後述の手順で issue 化し、今のタスクに集中する

実装上の注意:
- コアロジックはGUI非依存に保つ
- ソースファイルを追加した場合は `Makefile` と `Package.swift` 両方を更新する
- `GhosttyKit` の型を使う場合は `import GhosttyKit`

ユニットテストで動作を保証できる箇所は TDD で実装する（テスト先行 → 最小実装 → リファクタ）。GUIや ghostty C API に依存する部分はテスト対象外。

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
1. `make build && make run`
2. [変更内容に応じた確認操作]

## 影響しうる箇所
[変更により挙動が変わりうる機能・画面]

## 関連ファイル
[変更したファイル一覧]
EOF
)")

# gate が完了するまでタスクをブロック
bd dep add <task-id> "$GATE_ID"
```

### 7. 継続メモを残す

実装の判断・状況・次のセッションへの引き継ぎ事項を comment に記録する:

```bash
bd comments add <id> "$(cat <<'EOF'
## 自律実装メモ

### セッション
session-id: <システムプロンプトから転記>

### コミット
<コミットハッシュ> — <コミットメッセージ>

### 実装判断のログ
- <判断が必要だった点>: <選んだ方向と理由>

### 注意が必要な箇所
- <潜在的な問題・副作用があれば記載>

### 次のセッションへ
- gate が NG になった場合: <再実装で注意すべきこと>
- 関連する未解決問題: <あれば>
EOF
)"
```

### 8. スコープ外タスクの記録

実装中に発見したスコープ外の問題・改善点は issue 化して kimuson に渡す:

```bash
bd create \
  --title="[要確認] <発見した問題>" \
  --type=task \
  --priority=3 \
  --assignee=kimuson \
  --description="<発見した状況と内容>。dev-auto 実装中に発見。kimuson が確認・整理すること。"
```

### 9. 完了報告

実装内容・コミットハッシュ・クオリティゲート結果・gate ID（作成した場合）を報告する。

## 制約

- 1タスクのみ実装する（複数タスクに手を出さない）
- スコープ外の修正は行わない（issue 化に留める）
- `git push` は行わない
- ユーザーへの質問・確認は行わない（自律的に決断する）
