#!/bin/bash
# Aurora - Gradia autosave watcher
# ----------------------------------------------------------------------------
# O Gradia, quando invocado via `--screenshot=INTERACTIVE` (atalho
# Shift+Super+S configurado em chrome-keybindings), salva o resultado DIRETO em
# ~/Imagens/Screenshot-NN.png — NÃO no cache last_image.png.
#
# (O cache last_image.png só é tocado em fluxos internos: abrir arquivo,
# editar e Overwrite on Close. Para o uso real do atalho de teclado, o cache
# fica intocado e o screenshot vai direto pra ~/Imagens.)
#
# Este daemon monitora ~/Imagens/ via inotify; toda vez que um arquivo
# `Screenshot-*.png` é criado/movido, move-o para
# ~/Imagens/printscreens-gradia/gradia-TIMESTAMP.png — preservando o conteúdo
# e tirando a poluição da raiz de ~/Imagens.

set -euo pipefail

WATCH_DIR="$HOME/Imagens"
DEST_DIR="$HOME/Imagens/printscreens-gradia"

mkdir -p "$DEST_DIR"

# Espera o diretório existir (sempre deve, mas defensive)
while [ ! -d "$WATCH_DIR" ]; do
    sleep 30
done

# inotifywait dispara em close_write (arquivo terminou de ser escrito) e
# moved_to (renomeação atomic do tipo `.tmp` -> `Screenshot-22.png`)
inotifywait -m -e close_write,moved_to --format '%f' "$WATCH_DIR" 2>/dev/null \
| while read -r filename; do
    # Só interessam Screenshot-NN.png do Gradia (XDG portal interativo)
    case "$filename" in
        Screenshot-*.png) ;;
        *) continue ;;
    esac

    src="$WATCH_DIR/$filename"
    [ -f "$src" ] || continue

    ts=$(date +%Y%m%d-%H%M%S)
    dst="$DEST_DIR/gradia-$ts.png"

    # Colisão de timestamp (improvável, possível em batch)
    n=1
    while [ -e "$dst" ]; do
        dst="$DEST_DIR/gradia-$ts-$n.png"
        n=$((n+1))
    done

    if mv -- "$src" "$dst" 2>/dev/null; then
        logger -t gradia-autosave "moveu $src -> $dst"
    else
        logger -t gradia-autosave "FALHOU mover $src"
    fi
done
