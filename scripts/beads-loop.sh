#!/usr/bin/env bash
set -euo pipefail

# beads-loop: bd ready のタスクを Claude Code で順次実装する
#
# Usage:
#   ./scripts/beads-loop.sh                        # unassigned タスクを最大10件処理
#   ./scripts/beads-loop.sh -n 5                   # 最大5件
#   ./scripts/beads-loop.sh -p P1                  # P1 以上のタスクのみ
#   ./scripts/beads-loop.sh -p P0 -n 3             # P0 のみ、最大3件
#   ./scripts/beads-loop.sh --dry-run              # タスク一覧を表示して終了
#   ./scripts/beads-loop.sh --usage-limit 90       # 5h utilization 90% で停止
#   ./scripts/beads-loop.sh --architect-every 5    # 5タスクごとにアーキテクトレビュー
#   ./scripts/beads-loop.sh --max-gates 8          # open gate 8件以上で gate:not-required 優先

usage() {
  cat <<'EOF'
Usage: beads-loop.sh [options]

Options:
  -n NUM                最大実行タスク数 (default: 10)
  -p P0|P1|P2|P3        指定した優先度のタスクのみ処理
  --dry-run             タスク一覧を表示して終了
  --usage-limit NUM     5h utilization の停止閾値 % (default: 80)
  --architect-every N   N タスクごとにアーキテクトレビューを実行 (0 = 無効, default: 0)
  --max-gates N         open gate がこの件数以上なら gate:not-required を優先 (default: 10)
  -h, --help            このヘルプを表示
EOF
}

# --- Defaults ---
MAX_COUNT=10
PRIORITY=""
DRY_RUN=false
USAGE_LIMIT=80
ARCHITECT_EVERY=0
MAX_GATES=10

# --- Parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n)               MAX_COUNT="$2"; shift 2 ;;
    -p)               PRIORITY="$2"; shift 2 ;;
    --dry-run)        DRY_RUN=true; shift ;;
    --usage-limit)    USAGE_LIMIT="$2"; shift 2 ;;
    --architect-every) ARCHITECT_EVERY="$2"; shift 2 ;;
    --max-gates)      MAX_GATES="$2"; shift 2 ;;
    -h|--help)        usage; exit 0 ;;
    *)                echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# Normalize priority: P0 → 0, P1 → 1, etc.
BD_PRIORITY=""
if [[ -n "$PRIORITY" ]]; then
  BD_PRIORITY="${PRIORITY#P}"
  if ! [[ "$BD_PRIORITY" =~ ^[0-3]$ ]]; then
    echo "Invalid priority: $PRIORITY (expected P0-P3)"
    exit 1
  fi
fi

log() {
  echo "[$(date '+%H:%M:%S')] $*"
}

check_uncommitted() {
  local changes
  changes=$(git status --porcelain -- ':!.beads/' 2>/dev/null || true)
  [[ -n "$changes" ]]
}

# --- Usage API (self-contained) ---
get_oauth_token() {
  if [[ "$OSTYPE" == darwin* ]]; then
    security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null \
      | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null
  else
    jq -r '.claudeAiOauth.accessToken // empty' "$HOME/.claude/.credentials.json" 2>/dev/null
  fi
}

fetch_five_hour_utilization() {
  local token
  token=$(get_oauth_token)
  if [[ -z "$token" ]] || [[ "$token" == "null" ]]; then
    echo ""
    return
  fi
  local response
  response=$(curl -sf --max-time 5 \
    -H "Authorization: Bearer $token" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "Content-Type: application/json" \
    "https://api.anthropic.com/api/oauth/usage" 2>/dev/null) || { echo ""; return; }
  echo "$response" | jq -r '.five_hour.utilization // empty' 2>/dev/null | cut -d. -f1
}

check_rate_limit() {
  local pct
  pct=$(fetch_five_hour_utilization)
  if [[ -z "$pct" ]]; then
    return 1  # 取得失敗 → 制限なしとみなす
  fi
  log "5h utilization: ${pct}% (limit: ${USAGE_LIMIT}%)"
  if (( pct >= USAGE_LIMIT )); then
    return 0
  fi
  return 1
}

# --- Gate count check ---
get_open_gate_count() {
  bd list --type=gate --status=open --json 2>/dev/null | jq 'length' 2>/dev/null || echo "0"
}

# --- Build bd ready args ---
build_ready_args() {
  local args=(--unassigned --json)
  if [[ -n "$BD_PRIORITY" ]]; then
    args+=(--priority "$BD_PRIORITY")
  fi
  echo "${args[@]}"
}

# --- Architect review ---
run_architect_review() {
  log "=== アーキテクトレビュー開始 ==="

  claude \
    --dangerously-skip-permissions \
    --model opus \
    --effort high \
    -p 'teams:architect' \
    --verbose \
    || {
      log "WARNING: アーキテクトレビューが非ゼロで終了 (exit=$?)"
    }

  log "アーキテクトレビュー完了。PdM セッションで issue 化します。"

  claude \
    --dangerously-skip-permissions \
    -p 'teams:pdm アーキテクトレビューの結果を docs/tmp/architect-review/ の最新ファイルから読み込んで issue を起票してください' \
    --verbose \
    || {
      log "WARNING: PdM セッションが非ゼロで終了 (exit=$?)"
    }

  log "=== アーキテクトレビュー + issue 起票 完了 ==="
}

# --- Main loop ---
count=0
tasks_since_architect=0

log "beads-loop 開始 (max: ${MAX_COUNT}, priority: ${PRIORITY:-all}, usage-limit: ${USAGE_LIMIT}%, architect-every: ${ARCHITECT_EVERY}, max-gates: ${MAX_GATES})"

while true; do
  if (( count >= MAX_COUNT )); then
    log "${MAX_COUNT} タスク完了。終了します。"
    break
  fi

  # レート制限チェック
  if check_rate_limit; then
    log "5h utilization が ${USAGE_LIMIT}% を超えています。停止します。"
    break
  fi

  # アーキテクトレビュースケジュール
  if (( ARCHITECT_EVERY > 0 && tasks_since_architect >= ARCHITECT_EVERY )); then
    run_architect_review
    tasks_since_architect=0
  fi

  # ready タスクの確認 (JSON でパース)
  read -ra ready_args <<< "$(build_ready_args)"
  ready_json=$(bd ready "${ready_args[@]}" 2>/dev/null || echo "[]")
  task_count=$(echo "$ready_json" | jq 'length')
  if (( task_count == 0 )); then
    log "ready タスクなし。終了します。"
    break
  fi
  log "ready タスク: ${task_count} 件"

  if [[ "$DRY_RUN" == true ]]; then
    echo "$ready_json" | jq -r '.[] | "[\(.priority)] [\(.issue_type)] \(.id): \(.title)"'
    break
  fi

  # --- タスク選択 ---
  # Gate count に応じて選択対象を絞る
  gate_count=$(get_open_gate_count)
  if (( gate_count >= MAX_GATES )); then
    log "open gate: ${gate_count} 件 (>= ${MAX_GATES})。gate:not-required タスクを優先します。"
    # gate:not-required ラベル付きの ready タスクから1件目を取得
    task_id=$(bd ready --unassigned --label gate:not-required --json 2>/dev/null \
      | jq -r '.[0].id // empty' 2>/dev/null)
    if [[ -z "$task_id" ]]; then
      log "gate:not-required の ready タスクなし。gate が消化されるまで停止します。"
      break
    fi
  else
    # 通常: ready の1件目（priority 順）
    task_id=$(echo "$ready_json" | jq -r '.[0].id // empty')
  fi

  if [[ -z "$task_id" ]]; then
    log "タスク ID を取得できませんでした。終了します。"
    break
  fi
  log "タスク選択: ${task_id}"

  # --- セッション ID を生成 ---
  session_id=$(uuidgen)
  log "セッション開始: ${session_id}"

  # --- ブランチ作成 ---
  branch_name="dev/${task_id}"
  git checkout -b "$branch_name" || {
    log "ERROR: ブランチ ${branch_name} の作成に失敗。終了します。"
    break
  }
  log "ブランチ作成: ${branch_name}"

  # --- set-state でメタデータ記録 ---
  bd set-state "$task_id" branch="$branch_name" --reason "beads-loop で自動作成" 2>/dev/null || true
  bd set-state "$task_id" session="$session_id" --reason "beads-loop セッション開始" 2>/dev/null || true

  # --- Claude Code で teams:dev-auto を実行 ---
  system_prompt="session-id: ${session_id}
task-id: ${task_id}"

  claude \
    --dangerously-skip-permissions \
    -p 'teams:dev-auto' \
    --session-id "$session_id" \
    --append-system-prompt "$system_prompt" \
    --verbose \
    || {
      log "WARNING: Claude Code が非ゼロで終了 (exit=$?)"
    }

  log "セッション完了: ${session_id}"

  # --- コミット漏れチェック ---
  if check_uncommitted; then
    log "WARNING: コミットされていない変更を検出。クリーンアップを依頼します。"
    claude \
      --dangerously-skip-permissions \
      -p 'コミットされていない変更があります。git status を確認し、実装に関連する変更はコミットしてください。不要な変更は git restore してください。.beads/ は無視して構いません。' \
      --resume "$session_id" \
      || {
        log "WARNING: クリーンアップが非ゼロで終了 (exit=$?)"
      }

    if check_uncommitted; then
      log "ERROR: クリーンアップ後もコミットされていない変更が残っています。手動確認してください。"
      git status -- ':!.beads/'
      git checkout main
      exit 1
    fi
  fi

  # --- main に戻る ---
  git checkout main
  log "main に復帰"

  count=$((count + 1))
  tasks_since_architect=$((tasks_since_architect + 1))
  log "完了タスク数: ${count}/${MAX_COUNT}"
done

log "beads-loop 終了。合計 ${count} タスク処理。"
