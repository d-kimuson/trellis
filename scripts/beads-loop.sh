#!/usr/bin/env bash
set -euo pipefail

# beads-loop: bd ready のタスクを Claude Code で順次実装する
#
# Usage:
#   ./scripts/beads-loop.sh                    # unassigned タスクを最大10件処理
#   ./scripts/beads-loop.sh -n 5               # 最大5件
#   ./scripts/beads-loop.sh -p P1              # P1 以上のタスクのみ
#   ./scripts/beads-loop.sh -p P0 -n 3         # P0 のみ、最大3件
#   ./scripts/beads-loop.sh --dry-run          # タスク一覧を表示して終了
#   ./scripts/beads-loop.sh --usage-limit 90   # 5h utilization 90% で停止

usage() {
  cat <<'EOF'
Usage: beads-loop.sh [options]

Options:
  -n NUM            最大実行タスク数 (default: 10)
  -p P0|P1|P2|P3    指定した優先度のタスクのみ処理
  --dry-run         タスク一覧を表示して終了
  --usage-limit NUM 5h utilization の停止閾値 % (default: 80)
  -h, --help        このヘルプを表示
EOF
}

# --- Defaults ---
MAX_COUNT=10
PRIORITY=""
DRY_RUN=false
USAGE_LIMIT=80

# --- Parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n)           MAX_COUNT="$2"; shift 2 ;;
    -p)           PRIORITY="$2"; shift 2 ;;
    --dry-run)    DRY_RUN=true; shift ;;
    --usage-limit) USAGE_LIMIT="$2"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    *)            echo "Unknown option: $1"; usage; exit 1 ;;
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
  (( pct >= USAGE_LIMIT ))
}

# --- Build bd ready args ---
build_ready_args() {
  local args=(--unassigned --quiet)
  if [[ -n "$BD_PRIORITY" ]]; then
    args+=(--priority "$BD_PRIORITY")
  fi
  echo "${args[@]}"
}

# --- Main loop ---
count=0

log "beads-loop 開始 (max: ${MAX_COUNT}, priority: ${PRIORITY:-all}, usage-limit: ${USAGE_LIMIT}%)"

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

  # ready タスクの確認
  read -ra ready_args <<< "$(build_ready_args)"
  ready_output=$(bd ready "${ready_args[@]}" 2>/dev/null || true)
  if [[ -z "$ready_output" ]] || echo "$ready_output" | grep -q "0 issues"; then
    log "ready タスクなし。終了します。"
    break
  fi

  task_count=$(echo "$ready_output" | grep -c '^\s*[0-9]\+\.' || true)
  log "ready タスク: ${task_count} 件"

  if [[ "$DRY_RUN" == true ]]; then
    echo "$ready_output"
    break
  fi

  # セッション ID を生成
  session_id=$(uuidgen)
  log "セッション開始: ${session_id}"

  # Claude Code で /beads-dev を実行
  claude \
    --dangerously-skip-permissions \
    -p '/beads-dev' \
    --session-id "$session_id" \
    --verbose \
    || {
      log "WARNING: Claude Code が非ゼロで終了 (exit=$?)"
    }

  log "セッション完了: ${session_id}"

  # コミット漏れチェック
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
      exit 1
    fi
  fi

  count=$((count + 1))
  log "完了タスク数: ${count}/${MAX_COUNT}"
done

log "beads-loop 終了。合計 ${count} タスク処理。"
