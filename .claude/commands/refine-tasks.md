---
description: 'bd タスクの追加・優先度調整・依存設定など、タスク管理全般を行う'
disable-model-invocation: true
user-invocable: true
argument-hint: '<指示内容>'
allowed-tools: Read, Glob, Bash(bd), AskUserQuestion
---

以下の指示に従って bd タスクを管理してください：

$ARGUMENTS

## 手順

### 1. 現状確認

```bash
bd ready   # 未着手タスク一覧
bd list --pretty --no-pager   # 全タスク一覧
```

### 2. レビュードキュメントの読み込み（該当する場合）

指示にレビュー結果からのタスク起票が含まれる場合、以下のパスを候補として Glob で探す：

| レビュー種別 | 候補パス |
|------------|---------|
| アーキテクトレビュー | `docs/tmp/architect-review/*.md` |
| セキュリティレビュー | `docs/tmp/security-review.md`, `docs/tmp/security-review-*.md` |
| QA レビュー | `docs/tmp/qa/*.md` |

ファイルが見つからない・複数候補があって判断できない場合は `AskUserQuestion` でパスを確認してから読む。

### 3. タスクの起票・更新

**内容が自明な場合**（指示が明確・ドキュメントに詳細あり）はそのまま実行する。

**仕様や設計に判断が必要な場合**（機能の範囲・実装方針・分割粒度など）は、自分の解釈をまとめて `AskUserQuestion` で確認してから実行する。
例：「〇〇を1タスクにまとめようと思いますがよいですか？」「△△は feature ではなく task で切ります」

**タスク作成：**

```bash
bd create --title="..." --type=task|bug|feature|epic --priority=N --description="..."
```

| タイプ | 用途 |
|--------|------|
| bug | バグ修正 |
| feature | 機能追加 |
| task | その他作業 |
| epic | 複数タスクをまとめる親 |

priority: 0=緊急, 1=高, 2=中, 3=低

レビュードキュメントの重大度からの変換目安：

| 重大度 | タイプ | priority |
|--------|--------|---------|
| Critical | bug | 0 |
| High | bug/task | 1 |
| Medium | task | 2 |
| Low | task | 3 |

**優先度変更：**

```bash
bd update <id> --priority=N
```

**依存関係：**

```bash
bd dep add <id> <depends-on-id>
```

### 4. 担当とワークフローの設計

タスクごとに「誰がどう進めるか」を判断し、適切に設定する。

**担当の設定:**

| 担当 | 設定方法 | beads-loop での扱い |
|------|---------|-------------------|
| AI のみ | assignee なし（デフォルト） | `bd ready --unassigned` で自動取得 |
| kaito のみ | `--assignee kaito` | スキップされる |
| kaito + AI（相談→実装） | `--assignee kaito` + description に方針 | kaito が方針決定後、assignee を外して AI に渡す |

**判断基準:**
- **AI のみ**: 仕様が明確なバグ修正、リファクタ、テスト追加
- **kaito のみ**: 外部サービスの設定、ライセンス判断、リリース作業
- **kaito + AI**: 仕様の設計判断が必要な機能追加、UI/UXの方向性決め

```bash
bd update <id> --assignee kaito          # kaito 担当
bd update <id> --assignee ""             # AI に渡す（assignee 解除）
```

**動作確認の事前設計 (Acceptance Criteria):**

タスク起票時に、完了後の動作確認方法を description に含める：

- `[AC: auto]` — テストで担保可能。AI が自動クローズ
- `[AC: gate]` — ユーザーの目視確認が必要。AI が human gate を作成

例：
```
--description="... [AC: gate] 確認観点: サイドバーのアイコンサイズが視認しやすいか"
```

### 5. 完了報告

作成・変更したタスクの一覧を報告する。

## 注意事項

- 既存タスクと重複しないか確認してから作成する
- 1タスク = 1〜2時間の作業量を目安に分割する
- 複数タスクにまたがる機能はエピックを先に作る
