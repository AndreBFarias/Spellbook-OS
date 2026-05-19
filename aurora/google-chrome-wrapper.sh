#!/bin/bash
# Aurora - wrapper Chrome que sempre injeta --load-extension
# ----------------------------------------------------------------------------
# Razão: o .desktop entry tem --load-extension, mas se Chrome é lançado por
# (a) terminal direto (`google-chrome ...`), (b) restauração de sessão guardada,
# (c) outro app que chama via xdg-open, ele pode pular o .desktop.
# Wrapper garante a flag em qualquer invocação que resolva o nome via PATH.
#
# Lista é mantida em sync com aurora-chrome-extensions-apply.sh.
set -u

EXTENSION_PATHS=(
  "$HOME/.config/zsh/aurora/userscripts/control-c-ilimitado-ext"
)

valid=()
for p in "${EXTENSION_PATHS[@]}"; do
  [ -d "$p" ] && [ -f "$p/manifest.json" ] && valid+=("$p")
done

args=()
if [ ${#valid[@]} -gt 0 ]; then
  joined=$(IFS=','; echo "${valid[*]}")
  args+=("--load-extension=${joined}")
fi

exec /usr/bin/google-chrome-stable "${args[@]}" "$@"
