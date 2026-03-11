# Trellis shell integration for zsh
# Restores scrollback content when a pinned workspace is reopened after restart.
#
# Setup: add the following line to your ~/.zshrc
#   source ~/.config/trellis/shell-integration/trellis-zsh-integration.zsh
#
# (Trellis copies this file to ~/.config/trellis/shell-integration/ on startup.)

_trellis_restore_scrollback_once() {
    local path="${TRELLIS_RESTORE_SCROLLBACK_FILE:-}"
    [[ -n "$path" ]] || return 0
    unset TRELLIS_RESTORE_SCROLLBACK_FILE

    if [[ -r "$path" ]]; then
        # Temporarily resize the terminal to the original capture width so that
        # hard-wrapped content (e.g. ls columns) replays without misalignment.
        # CSI 8 ; rows ; cols t — XTWINOPS window resize; rows=0 means "keep current".
        local orig_cols="${TRELLIS_TERMINAL_COLS:-}"
        unset TRELLIS_TERMINAL_COLS
        if [[ -n "$orig_cols" && "$orig_cols" -gt 0 ]]; then
            printf '\e[8;0;%st' "$orig_cols"
        fi

        /bin/cat -- "$path" 2>/dev/null || true
        /bin/rm -f -- "$path" >/dev/null 2>&1 || true
    fi
}
_trellis_restore_scrollback_once
