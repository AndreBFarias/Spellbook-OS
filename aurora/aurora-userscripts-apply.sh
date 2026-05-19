#!/bin/bash
# Aurora 2.x - Deploy idempotente de userscripts e Chrome extensions versionados.
#
# [2026-05-19] DESATIVADO: o destino ~/userscripts/ foi removido a pedido do
# dono. A fonte de verdade ~/.config/zsh/aurora/userscripts/ agora é também o
# path de carregamento direto. Chrome extensions unpacked devem ser
# re-importadas apontando para o próprio source. Este script vira no-op para
# manter compatibilidade com chamadas no aliases.zsh / aurora-bootstrap.sh /
# aurora-postboot-validate.sh / aurora-user-apply.sh sem quebrá-las.
exit 0

set -u

SRC_DIR="$HOME/.config/zsh/aurora/userscripts"
DST_DIR="$HOME/userscripts"

log()  { printf '[userscripts] %s\n' "$*"; }
warn() { printf '[userscripts][WARN] %s\n' "$*" >&2; }

[ -d "$SRC_DIR" ] || { warn "fonte ausente: $SRC_DIR"; exit 0; }
mkdir -p "$DST_DIR"

# hash agregado de uma arvore: concatena sha256 dos arquivos em ordem
tree_hash() {
  local root="$1"
  [ -d "$root" ] || { echo ""; return; }
  ( cd "$root" && find . -type f ! -name '.*' -print0 | LC_ALL=C sort -z | xargs -0 sha256sum 2>/dev/null | sha256sum | awk '{print $1}' )
}

total=0
changed=0

# 1. Arquivos .user.js soltos
for src in "$SRC_DIR"/*.user.js; do
  [ -f "$src" ] || continue
  total=$((total+1))
  name=$(basename "$src")
  dst="$DST_DIR/$name"
  src_sum=$(sha256sum "$src" | awk '{print $1}')
  dst_sum=""
  [ -f "$dst" ] && dst_sum=$(sha256sum "$dst" | awk '{print $1}')
  if [ "$src_sum" != "$dst_sum" ]; then
    cp -f "$src" "$dst"
    log "deploy file: $name (sha256=${src_sum:0:12}...)"
    changed=$((changed+1))
  fi
done

# 2. Diretorios de extension (terminam em -ext/)
for srcd in "$SRC_DIR"/*-ext; do
  [ -d "$srcd" ] || continue
  total=$((total+1))
  name=$(basename "$srcd")
  dstd="$DST_DIR/$name"
  mkdir -p "$dstd"

  src_th=$(tree_hash "$srcd")
  dst_th=$(tree_hash "$dstd")

  if [ "$src_th" != "$dst_th" ]; then
    if command -v rsync >/dev/null 2>&1; then
      rsync -a --delete "$srcd/" "$dstd/"
    else
      # fallback portavel sem rsync
      rm -rf "$dstd"
      cp -r "$srcd" "$dstd"
    fi
    log "deploy dir:  $name/ (tree=${src_th:0:12}...)"
    changed=$((changed+1))
  fi
done

if [ $total -eq 0 ]; then
  log "nenhum artefato em $SRC_DIR"
elif [ $changed -eq 0 ]; then
  log "sincronizado ($total artefato(s))"
fi

exit 0
