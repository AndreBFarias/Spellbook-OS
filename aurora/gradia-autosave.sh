#!/bin/bash
# Aurora - Gradia autosave watcher
# ----------------------------------
# Monitora o cache do Gradia (~/.var/app/be.alexandervanhee.gradia/cache/gradia/)
# e copia toda nova versão de `last_image.png` para ~/Imagens/printscreens-gradia/
# com timestamp único. Resolve a falta de auto-save nativo do Gradia (que só
# expõe `custom-export-command` via botão manual ou save dialog).
#
# Disparado por inotify CLOSE_WRITE/MOVED_TO no diretório de cache.
# Gradia regrava last_image.png a cada take screenshot / open / export.

set -euo pipefail

CACHE_DIR="$HOME/.var/app/be.alexandervanhee.gradia/cache/gradia"
DEST_DIR="$HOME/Imagens/printscreens-gradia"
SOURCE_FILE="last_image.png"

mkdir -p "$DEST_DIR"

# Espera o cache existir (Gradia pode não ter rodado ainda)
while [ ! -d "$CACHE_DIR" ]; do
    sleep 30
done

last_hash=""

# Captura snapshot inicial para evitar duplicar a primeira detecção
if [ -f "$CACHE_DIR/$SOURCE_FILE" ]; then
    last_hash=$(sha256sum "$CACHE_DIR/$SOURCE_FILE" | awk '{print $1}')
fi

inotifywait -m -e close_write,moved_to --format '%f' "$CACHE_DIR" 2>/dev/null \
| while read -r filename; do
    [ "$filename" = "$SOURCE_FILE" ] || continue

    src="$CACHE_DIR/$SOURCE_FILE"
    [ -f "$src" ] || continue

    # Hash check para evitar copiar arquivo idêntico (Gradia pode rewritar mesmo conteúdo)
    new_hash=$(sha256sum "$src" | awk '{print $1}')
    [ "$new_hash" = "$last_hash" ] && continue
    last_hash="$new_hash"

    ts=$(date +%Y%m%d-%H%M%S)
    dst="$DEST_DIR/gradia-$ts.png"

    # Lida com colisão de timestamp (improvável, mas possível em scripts batch)
    n=1
    while [ -e "$dst" ]; do
        dst="$DEST_DIR/gradia-$ts-$n.png"
        n=$((n+1))
    done

    cp -- "$src" "$dst"
    logger -t gradia-autosave "salvou $dst"
done
