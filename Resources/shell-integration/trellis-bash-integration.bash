# Trellis shell integration for bash
# Restores scrollback content when a pinned workspace is reopened after restart.
#
# Setup: add the following line to your ~/.bashrc or ~/.bash_profile
#   source ~/.config/trellis/shell-integration/trellis-bash-integration.bash
#
# (Trellis copies this file to ~/.config/trellis/shell-integration/ on startup.)

# Running command tracking: write/clear a temp file so the app knows
# which command is executing at snapshot time.
_trellis_preexec() {
    local sid="${TRELLIS_SESSION_ID:-}"
    [ -n "$sid" ] || return 0
    printf '%s' "${BASH_COMMAND:-}" > "/tmp/trellis-running-${sid}.txt" 2>/dev/null
}
_trellis_precmd() {
    local sid="${TRELLIS_SESSION_ID:-}"
    [ -n "$sid" ] || return 0
    /bin/rm -f "/tmp/trellis-running-${sid}.txt" 2>/dev/null
}
trap '_trellis_preexec' DEBUG
PROMPT_COMMAND="_trellis_precmd${PROMPT_COMMAND:+;$PROMPT_COMMAND}"

_trellis_restore_scrollback_once() {
    local path="${TRELLIS_RESTORE_SCROLLBACK_FILE:-}"
    [ -n "$path" ] || return 0
    unset TRELLIS_RESTORE_SCROLLBACK_FILE
    if [ -r "$path" ]; then
        /bin/cat -- "$path" 2>/dev/null || true
        /bin/rm -f -- "$path" >/dev/null 2>&1 || true
    fi
}
_trellis_restore_scrollback_once
