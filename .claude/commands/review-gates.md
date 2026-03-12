---
description: '未承認の gate を一覧し、動作確認サマリーを表示する'
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash(bd), Bash(git), Read, Glob, Grep
---

ユーザーの動作確認待ちになっている gate を一覧し、まとめて確認できるサマリーを表示してください。

## 手順

### 1. 未承認 gate の取得

```bash
bd gate list
```

### 2. 各 gate の詳細を取得

```bash
bd gate show <gate-id>
```

gate の description から以下を抽出する:
- 対応内容
- 確認手順
- 影響しうる箇所
- 関連ファイル

### 3. 関連コミットの特定

各 gate に紐づくタスクIDを確認し、そのタスクに対応するコミットを特定する:

```bash
bd show <task-id>
git log --oneline -20
```

### 4. 変更の影響分析

関連ファイルの変更差分を確認し、影響範囲を分析する:

```bash
git diff <commit>^..<commit> --stat
git diff <commit>^..<commit>
```

### 5. サマリーの出力

以下のフォーマットで出力する。ユーザーがこれを見て効率よく動作確認できることを目指す。

---

## 動作確認待ち一覧

**ビルド:**
```
make build && make run
```

### 1. [gate タイトル] (`<gate-id>`)

**タスク:** `<task-id>` — [タスクタイトル]
**コミット:** `<hash>` — [コミットメッセージ]

**何が変わったか:**
[対応内容を1〜2行で]

**確認してほしいこと:**
1. [具体的な確認操作]
2. [具体的な確認操作]

**影響しうる箇所:**
[変更により挙動が変わりうる機能・画面]

---

(gate ごとに繰り返し)

---

**承認コマンド:**
```
bd gate approve <gate-id-1>   # [タイトル1]
bd gate approve <gate-id-2>   # [タイトル2]
```

**問題があった場合:**
修正が必要な gate があれば教えてください。修正内容を新タスクとして起票します。

---

### 6. ユーザーの応答に対応

**承認の場合:**
ユーザーが approve を実行、または「OK」「問題なし」等と応答したら:

```bash
bd gate approve <gate-id>
bd close <task-id>
```

**修正依頼の場合:**
修正内容を新タスクとして起票する。gate の「関連ファイル」「実装の要点」を新タスクの description に引き継ぎ、新セッションでもコンテキストを復元できるようにする:

```bash
bd create --title="[修正内容]" --type=bug --priority=1 --description="..."
bd gate approve <gate-id>
bd close <task-id>
```
