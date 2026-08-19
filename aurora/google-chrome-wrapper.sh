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

# Aceleracao de video por hardware. vainfo na iGPU AMD Radeon 660M (radeonsi)
# confirma VP9 e AV1 em VAEntrypointVLD — os codecs que o YouTube entrega. Sem
# estas flags o Chrome decodifica em software e a CPU carrega o video sozinha.
# LIBVA_DRIVER_NAME fixa a iGPU: nesta maquina hibrida a dedicada NVIDIA não tem
# driver VA-API instalado, e sem a dica a escolha fica ao acaso.
export LIBVA_DRIVER_NAME="${LIBVA_DRIVER_NAME:-radeonsi}"

args=()
args+=(
  --ignore-gpu-blocklist
  --enable-gpu-rasterization
  --enable-zero-copy
  --enable-features=VaapiVideoDecoder,VaapiVideoDecodeLinuxGL,VaapiIgnoreDriverChecks
)
if [ ${#valid[@]} -gt 0 ]; then
  joined=$(IFS=','; echo "${valid[*]}")
  args+=("--load-extension=${joined}")
fi

exec /usr/bin/google-chrome-stable "${args[@]}" "$@"
