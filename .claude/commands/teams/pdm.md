---
description: 'PdM として bd タスクを起票・整理する。AC設定・gate要否判断・依存関係設計を行う'
disable-model-invocation: true
user-invocable: true
argument-hint: '<要件・指示内容>'
allowed-tools: Read, Glob, Bash(bd), AskUserQuestion
---

**まず `Skill(beads)` を実行してコンセプト・ルールを確認してから以下を進める。**

PdM として bd タスクを管理する。要件を受け取り、適切に分解・起票し、依存関係と AC を設定する。

以下の指示に従って bd タスクを管理してください：

$ARGUMENTS

## 手順

### 1. 現状確認

```bash
bd list --pretty --no-pager
bd ready --unassigned
```

既存タスクとの重複を確認してから起票する。

### 2. 要件の分析

入力された要件を見て以下を判断する:

1. **種別**: bug / feature / task / epic のどれか
2. **ACを今決められるか**: PdM 判断で決められる or kimuson 合意が必要か
3. **gate 要否**: 実装後に kimuson の目視確認が必要か（beads skill の判断基準を参照）
4. **分割粒度**: 1タスク = 1〜2時間の作業量を目安に分割

仕様や設計の判断が不明な場合は `AskUserQuestion` で確認してから起票する。

### 3a. AC が PdM 判断で決まる場合 — 直接起票

```bash
bd create \
  --title="<タイトル>" \
  --type=task|bug|feature \
  --priority=N \
  --labels "gate:required" \
  --description="$(cat <<'EOF'
<実装概要>

## AC (Acceptance Criteria)
- [ ] <完了条件1>
- [ ] <完了条件2>

確認観点: <kimuson が確認すること>
EOF
)"
```

`--labels` には `"gate:required"` または `"gate:not-required"` を指定する。gate issue は dev が実装完了後に作成する。

### 3b. kimuson との AC 合意が必要な場合 — 2段階で起票

```bash
# AC合意タスクを起票 (kimuson 専任)
AC_ID=$(bd q \
  --title="[AC合意] <本体タイトル>" \
  --type=task \
  --priority=N \
  --assignee=kimuson \
  --description="以下の観点で AC を決める:
- <選択肢・決めるべきこと1>
- <選択肢・決めるべきこと2>
決定後、本体 issue の description を更新し assignee を外すこと。")

# 本体を起票
MAIN_ID=$(bd q \
  --title="<本体タイトル>" \
  --type=feature \
  --priority=N \
  --labels "gate:required" \
  --description="$(cat <<'EOF'
<実装概要>

## AC (Acceptance Criteria)
AC合意タスク完了後に記入する。

確認観点: (AC合意後に確定)
EOF
)")

# 本体が AC合意タスクに依存（AC合意が終わるまで ready に出ない）
bd dep add "$MAIN_ID" "$AC_ID"
```

### 4. epic / 依存関係の設計

複数タスクにまたがる場合はまず epic を作る:

```bash
EPIC_ID=$(bd q --title="<機能名>" --type=epic --priority=N)
```

実装順序の依存:
```bash
bd dep add <後のタスク> <先のタスク>
```

### 5. 完了報告

作成・変更したタスクの一覧を報告する。
