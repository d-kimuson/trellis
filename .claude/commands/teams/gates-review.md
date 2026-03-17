---
description: '確認待ち gate を一覧提示し、kimuson が選んだものをブランチ checkout して1件ずつ動作確認する'
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash(bd), Bash(git), Bash(make), Read, Glob, Grep, AskUserQuestion
---

確認待ち gate を一覧提示し、kimuson が選んだものをブランチ checkout して1件ずつ動作確認する。

## 手順

### 1. 確認対象 gate の絞り込み

```bash
bd list --type=gate --status=open --no-pager
```

各 gate について `bd show <gate-id>` で依存タスクを確認し、**依存タスクがすべて closed のもののみ**を対象とする。

```bash
bd show <gate-id>   # "Depends on" のタスクを確認
bd show <task-id>   # status が closed かチェック
```

依存タスクが open のものは「修正作業中」としてスキップする（提示しない）。

### 2. 一覧を提示して確認対象を選んでもらう

対象 gate を以下フォーマットで提示し、確認してほしいものを選んでもらう:

---

## 確認待ち gate

| # | Gate ID | タスク | 変更内容（1行） | 種別 |
|---|---------|--------|----------------|------|
| 1 | `trellis-xxx` | trellis-yyy | <何をしたか> | Bug Fix / Feature |
| 2 | `trellis-xxx` | trellis-yyy | <何をしたか> | Bug Fix / Feature |

確認する番号を教えてください（例: 全部 / 1,3 / 2のみ）

---

### 3. 選ばれた gate を1件ずつ確認する

選ばれた gate を **1件ずつ順番に**処理する。次の gate に進むのは前の gate の結果を受けてから。

各 gate の処理:

#### 3-1. ブランチ checkout とビルド

```bash
# タスクのブランチを取得
branch=$(bd state <task-id> branch)

git checkout "$branch"
make build
make run
```

#### 3-2. 確認内容を提示

gate の description から確認観点を抽出して提示する:

---

### <gate タイトル> — `<gate-id>`（N/M）

**ブランチ:** `<branch-name>`
**変更内容:** <何をしたか1〜2行>

**手順:**
1. <具体的な操作>
2. ...

**確認してほしいこと:**
- [ ] <確認項目>
- [ ] <確認項目>

結果を教えてください（OK / NG — 問題の詳細）

---

#### 3-3. 結果を受けて処理する

**OK の場合 → gate を close し、ブランチを main にマージ、タスクを close**

```bash
# gate を close
bd close <gate-id> --reason="kimuson 動作確認 OK"

# ブランチを main にマージ
git checkout main
git merge --squash "$branch" && git commit -m "merge: <タスクタイトル> ($branch)"
git branch -d "$branch"

# タスクを close
bd close <task-id> --reason="gate 通過、動作確認完了、main にマージ済み"
```

**NG の場合 → comment に問題を記録し、タスクを open に戻す**

```bash
# gate に問題の詳細を記録
bd comments add <gate-id> "$(cat <<'EOF'
## 動作確認 NG

### 問題
<報告された問題の内容>

### 再現手順
<どういう操作で起きるか>

### 期待する挙動
<どうあるべきか>
EOF
)"

# タスクを open に戻す
bd update <task-id> --status=open
```

gate は open のまま維持する（タスクが再実装・再クローズされるまでブロック継続）。

次の gate に進む前に main に戻す:

```bash
git checkout main
```

### 4. 処理後の確認

```bash
bd list --type=gate --status=open --no-pager
```

残りの gate と処理結果をまとめて報告する。
