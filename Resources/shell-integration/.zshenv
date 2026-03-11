# vim:ft=zsh
#
# Trellis ZDOTDIR bootstrap for zsh.
#
# When Trellis restores a pinned workspace, it sets ZDOTDIR to this directory
# so zsh loads this file first. We immediately restore the user's real ZDOTDIR
# (saved in TRELLIS_ZSH_ZDOTDIR), source their original .zshenv, and then
# load the Trellis integration script.

if [[ -n "${TRELLIS_ZSH_ZDOTDIR+X}" ]]; then
    builtin export ZDOTDIR="$TRELLIS_ZSH_ZDOTDIR"
    builtin unset TRELLIS_ZSH_ZDOTDIR
else
    builtin unset ZDOTDIR
fi

{
    builtin typeset _trellis_file="${ZDOTDIR-$HOME}/.zshenv"
    [[ ! -r "$_trellis_file" ]] || builtin source -- "$_trellis_file"
} always {
    if [[ -o interactive && -n "${TRELLIS_SHELL_INTEGRATION_DIR:-}" ]]; then
        builtin typeset _trellis_integ="$TRELLIS_SHELL_INTEGRATION_DIR/trellis-zsh-integration.zsh"
        [[ -r "$_trellis_integ" ]] && builtin source -- "$_trellis_integ"
    fi
    builtin unset _trellis_file _trellis_integ
}
