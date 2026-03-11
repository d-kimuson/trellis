# Trellis shell integration for bash
# Restores scrollback content when a pinned workspace is reopened after restart.
#
# Setup: add the following line to your ~/.bashrc or ~/.bash_profile
#   source ~/.config/trellis/shell-integration/trellis-bash-integration.bash
#
# (Trellis copies this file to ~/.config/trellis/shell-integration/ on startup.)

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
