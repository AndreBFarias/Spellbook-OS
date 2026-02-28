#!/bin/zsh

local FUNC_DIR="$ZDOTDIR/functions"

if [ ! -d "$FUNC_DIR" ]; then
    return 0
fi

[ -f "$FUNC_DIR/_helpers.zsh" ] && source "$FUNC_DIR/_helpers.zsh"

for f in "$FUNC_DIR"/*.zsh; do
    [[ "$(basename "$f")" == "_helpers.zsh" ]] && continue
    source "$f"
done
