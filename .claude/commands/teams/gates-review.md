---
description: '未確認 gate を操作フローごとにまとめて確認サマリーを出力し、kimuson の結果を受けて処理する'
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash(bd), Bash(git), Read, Glob, Grep, AskUserQuestion
---

未確認 gate を一覧し、**機能エリア・操作フローごとにまとめた**動作確認サマリーを出力する。
kimuson が確認結果を返したら gate の承認・却下処理を行う。

## 手順

### 1. 未確認 gate の取得

```bash
bd list --type=gate --status=open --no-pager
bd show <gate-id>   # 各 gate の詳細確認
```

各 gate の description から以下を抽出する:
- 確認観点（何を確認するか）
- 確認に必要な操作手順
- 種別: Feature / Bug Fix / Regression のどれか
- 紐づく task ID

### 2. 操作フロー別にグルーピング

同じ操作手順で確認できる gate をまとめる。
たとえば「通知を送る操作」が必要な gate が複数あれば、操作手順を1つにまとめて確認項目を列挙する。

グルーピングの基準:
- 同じ画面・機能エリアを操作するもの
- 共通の前提操作（ビルド・起動・特定の状態セットアップ）が必要なもの

### 3. 確認サマリーの出力

以下フォーマットで出力する。**issue ごとではなく操作フローごとに提示する。**

---

## 動作確認

**ビルド:**
```
make build && make run
```

---

### <機能エリア名>（例: 通知機能）

**手順:**
1. <具体的な操作>
2. <具体的な操作>
3. ...

**確認してほしいこと:**
- [ ] <確認項目> (Feature) — `<gate-id>`
- [ ] <確認項目> (Bug Fix) — `<gate-id>`, `<gate-id>`
- [ ] <確認項目> (Regression)

---

### <別の機能エリア名>

**手順:**
...

**確認してほしいこと:**
- [ ] ...

---

(機能エリアごとに繰り返し)

---

**確認後、結果を教えてください（例: 通知 Dock 跳ね NG — 跳ねなかった）**

---

### 4. kimuson の確認結果を受けて処理する

#### OK の場合 → gate を close し、ブランチを main にマージ、タスクを close

```bash
# gate を close
bd close <gate-id> --reason="kimuson 動作確認 OK"

# タスクのブランチを main にマージ
# ブランチ名は bd state <task-id> branch で取得
branch=$(bd state <task-id> branch)
git checkout main
git merge "$branch" --no-ff -m "merge: <タスクタイトル> ($branch)"
git branch -d "$branch"

# タスクを close
bd close <task-id> --reason="gate 通過、動作確認完了、main にマージ済み"
```

#### NG の場合 → comment に問題を記録し、タスクを open に戻す

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

### 5. 処理後の確認

```bash
bd list --type=gate --status=open --no-pager
```

残りの gate と処理結果をまとめて報告する。
