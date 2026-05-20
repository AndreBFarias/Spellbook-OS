#!/bin/zsh
# Carregador de functions/*.zsh — robusto contra arquivos com syntax error.

FUNC_DIR="${ZDOTDIR:-$HOME/.config/zsh}/functions"
[[ -d "$FUNC_DIR" ]] || return 0

[[ -f "$FUNC_DIR/_helpers.zsh" ]] && source "$FUNC_DIR/_helpers.zsh"

for f in "$FUNC_DIR"/*.zsh; do
    [[ "$(basename "$f")" == "_helpers.zsh" ]] && continue
    source "$f" 2>/dev/null || print -u2 "[functions.zsh] WARN: falha em $f"
done
unset f FUNC_DIR
