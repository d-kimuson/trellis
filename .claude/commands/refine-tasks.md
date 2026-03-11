---
description: 'architect-review・qa レポートを読んで bd タスクを作成する'
disable-model-invocation: true
user-invocable: true
allowed-tools: Read, Glob, Bash(bd), Bash(ls), Bash(date)
---

`docs/tmp/architect-review.md` と `docs/tmp/qa/` 配下のレポートを読み込み、発見された問題・バグをbdタスクに変換してください。

## 手順

### 1. ドキュメント収集
- `docs/tmp/architect-review.md` を読む（存在する場合）
- `docs/tmp/qa/` 配下の全`.md`ファイルを読む
- 読んだファイルを一覧として記録しておく

### 2. タスク抽出ルール

各問題を1つのbdタスクに変換する。以下のルールで分類：

| レポート重大度 | bdタイプ | bd優先度 |
|-------------|---------|---------|
| Critical | bug | 0 |
| High | task | 1 |
| Medium | task | 2 |
| Low | task | 3 |
| QAバグ発見 | bug | 1 |
| 不足機能 | feature | 2 |

### 3. タスク作成

各タスクに対して：

```bash
bd create --title="..." --type=task|bug|feature --priority=N --description="..."
```

descriptionには以下を含める：
- 問題の概要
- 影響・リスク
- 改善の方向性（わかる場合）
- ソース（`architect-review.md` or `qa/20260311-01.md`）

### 4. 依存関係の設定

明らかな依存関係がある場合（例：リファクタ前提の機能追加）：

```bash
bd dep add <issue-id> <depends-on-id>
```

### 5. 完了報告

作成したタスクの一覧を表示してください（`bd show` で確認）。

## 注意事項

- 同じ問題を重複してタスク化しない（既存タスクを `bd ready` で確認してから作成）
- 巨大な問題は分割して複数タスクにする（1タスク = 1〜2時間の作業量を目安）
- エピックが必要な場合は `--type=epic` で親タスクを先に作る
