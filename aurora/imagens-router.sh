#!/bin/bash
# Aurora - imagens-router: roteia arquivos do ~/Downloads por origem
# ----------------------------------------------------------------------------
# Chrome extensions baixam direto pra ~/Downloads (não respeitam paths
# customizados por extension). Este daemon monitora ~/Downloads via inotify e
# move arquivos para pastas dedicadas em ~/Imagens/ baseado em padrões:
#
#   1. ~/Downloads/FireShot/*.{png,pdf,jpg} -> ~/Imagens/Fireshot/
#      (FireShot tem subpasta própria; movemos o conteúdo)
#
#   2. ~/Downloads/*.pdf com metadata Producer contendo "PrintFriendly"
#      -> ~/Imagens/PrintFriendly/
#      (PrintFriendly não usa subpasta nem prefixo de nome; precisamos sniff
#      do PDF metadata via pdfinfo do poppler-utils)
#
# Outros downloads ficam intocados.

set -euo pipefail

DOWNLOADS="$HOME/Downloads"
FIRESHOT_SRC="$DOWNLOADS/FireShot"
FIRESHOT_DST="$HOME/Imagens/Fireshot"
PRINTFRIENDLY_DST="$HOME/Imagens/PrintFriendly"

mkdir -p "$FIRESHOT_DST" "$PRINTFRIENDLY_DST" "$DOWNLOADS"

log() { logger -t imagens-router "$*"; }

# Move um arquivo com colisão handling
move_with_ts() {
    local src="$1"
    local dst_dir="$2"
    [ -f "$src" ] || return 1
    local base
    base=$(basename -- "$src")
    local dst="$dst_dir/$base"
    local n=1
    while [ -e "$dst" ]; do
        # Insere timestamp antes da extensão
        local stem="${base%.*}"
        local ext="${base##*.}"
        local ts=$(date +%Y%m%d-%H%M%S)
        if [ "$stem" = "$base" ]; then
            dst="$dst_dir/${base}-${ts}-$n"
        else
            dst="$dst_dir/${stem}-${ts}-${n}.${ext}"
        fi
        n=$((n+1))
    done
    if mv -- "$src" "$dst" 2>/dev/null; then
        log "moveu $src -> $dst"
    else
        log "FALHOU mover $src"
    fi
}

# Verifica se PDF é do PrintFriendly via metadata Producer
is_printfriendly_pdf() {
    local f="$1"
    [ -f "$f" ] || return 1
    case "$f" in *.pdf|*.PDF) ;; *) return 1 ;; esac
    command -v pdfinfo >/dev/null 2>&1 || return 1
    local producer
    producer=$(pdfinfo "$f" 2>/dev/null | grep -i "^Producer:" | head -1)
    echo "$producer" | grep -qi "printfriendly\|print friendly" && return 0
    # Fallback: nome contem printfriendly
    case "$f" in *[pP]rint[fF]riendly*|*print\ friendly*) return 0 ;; esac
    return 1
}

# Tarefa: processa um arquivo recém-aparecido
process_file() {
    local path="$1"
    [ -f "$path" ] || return

    # Se path está em ~/Downloads/FireShot/, move pra Fireshot
    case "$path" in
        "$FIRESHOT_SRC"/*)
            move_with_ts "$path" "$FIRESHOT_DST"
            return
            ;;
    esac

    # Se é PDF do PrintFriendly em ~/Downloads/ raiz
    case "$path" in
        "$DOWNLOADS"/*.pdf|"$DOWNLOADS"/*.PDF)
            if is_printfriendly_pdf "$path"; then
                move_with_ts "$path" "$PRINTFRIENDLY_DST"
                return
            fi
            ;;
    esac
}

# Monitora 2 paths em paralelo: ~/Downloads e ~/Downloads/FireShot
# (subpasta criada lazy pelo FireShot; criamos se não existir)
mkdir -p "$FIRESHOT_SRC"

# Loop principal: inotifywait com formato que inclui path + filename
inotifywait -m -e close_write,moved_to --format '%w%f' "$DOWNLOADS" "$FIRESHOT_SRC" 2>/dev/null \
| while read -r full_path; do
    # Pequeno delay para garantir que escrita finalizou (Chrome usa .crdownload)
    sleep 1
    [ -f "$full_path" ] || continue
    # Ignora arquivos .crdownload temporários do Chrome
    case "$full_path" in *.crdownload) continue ;; esac
    process_file "$full_path"
done
