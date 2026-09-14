#!/usr/bin/env bash
# aurora-gradia-clipboard.sh — Super+Shift+S: tira um print NOVO da tela toda,
# joga no clipboard e abre no Gradia pra recortar/anotar. (v3.38)
#
# HISTÓRICO DO REDESENHO (2026-07-29): a versão v3.35 deste atalho NÃO capturava —
# só abria no Gradia a imagem que estivesse no clipboard. Na prática virou um
# ciclo vicioso: o exit-method='copy' do Gradia copiava a edição e FECHAVA o app
# no instante seguinte; o clipboard Wayland morre com o dono, o wl-clip-persist
# não terminava de clonar (journal: "failed to write clipboard data ... Broken
# pipe" em todos os mime types) e o clipboard ficava ora quebrado ("problema ao
# copiar" na tela), ora preso na cópia ANTIGA — que era o que este atalho abria.
# Cura em par: este script captura print novo (a entrada não depende mais do
# clipboard) e o aurora-gradia-config.sh fixa exit-method='none' (o Gradia para
# de copiar-e-morrer; a edição fica salva no arquivo via overwrite-screenshot).
#
# A captura é a MESMA do PrtSc (aurora-print-clipboard.sh): --interactive=false,
# que não monta overlay e sobrevive ao descompasso de opcodes do portal (v3.35).
# O recorte de região se faz DENTRO do Gradia, com a tela cheia carregada.
#
# Por que abrir por ARGUMENTO POSICIONAL (`gradia FILE`) e não por STDIN:
# o stdin NÃO faz hand-off pra instância já aberta e obrigava a
# `flatpak kill; sleep 0.5` + cold-start de ~2s a cada atalho (a lentidão de
# 2026-07-24). O argumento posicional é o contrato de CLI mais estável do Gradia
# (o 1.13.0 removeu a flag --screenshot-file=), carrega o PNG na hora e o
# GApplication faz hand-off SEM cold-start. Como existe arquivo de origem, o
# overwrite-screenshot=true grava a edição por cima ao fechar (auto-save).
#
# 'setsid … &' (não 'exec'): sob o Spawn do COSMIC o exec do flatpak não abre a
# janela. '</dev/null' é OBRIGATÓRIO: o main() do Gradia chama read_from_stdin()
# ANTES do app.run() e, se o stdin não for tty, bloqueia em read() até EOF — o
# cosmic-comp repassa aos filhos um pipe que nunca fecha, e a janela só apareceria
# quando esse pipe fechasse.
set -uo pipefail

DEST="$HOME/Imagens/printscreens-gradia"
STATE="${XDG_RUNTIME_DIR:-/tmp}/aurora-last-print"
mkdir -p "$DEST"

# --- 1. Captura um print novo (tela toda, não-interativo) ---
before=$(date +%s)
shot="$(cosmic-screenshot --interactive=false --save-dir "$DEST" --notify=false 2>/dev/null | tail -1)"

if [ -z "${shot:-}" ] || [ ! -f "${shot:-}" ]; then
    shot="$(find "$DEST" -maxdepth 1 -type f -iname '*.png' -newermt "@$before" \
              -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"
fi

if [ -n "${shot:-}" ] && [ -s "${shot:-}" ]; then
    # Print novo no clipboard também ("print e cola"), igual ao PrtSc. O wl-copy
    # se auto-daemoniza e serve o conteúdo de forma estável (dono não morre).
    wl-copy --type image/png < "$shot" 2>/dev/null
    printf '%s' "$shot" > "$STATE" 2>/dev/null
    target="$shot"
else
    # --- 2. Fallback: captura falhou — cai no comportamento antigo (clipboard) ---
    types="$(wl-paste --list-types 2>/dev/null)"
    if ! grep -q '^image/' <<<"$types"; then
        notify-send -a "Aurora" -i dialog-error -t 4000 "Print falhou" \
            "O cosmic-screenshot não devolveu imagem e o clipboard não tem outra." 2>/dev/null
        exit 1
    fi
    tmp="$(mktemp --tmpdir aurora-clip-XXXXXX.png)"
    if grep -qx 'image/png' <<<"$types"; then
        wl-paste --type image/png > "$tmp" 2>/dev/null
    else
        src_type="$(grep -m1 '^image/' <<<"$types")"
        wl-paste --type "$src_type" 2>/dev/null | convert - png:"$tmp" 2>/dev/null
    fi
    if [ ! -s "$tmp" ]; then
        rm -f "$tmp"
        notify-send -a "Aurora" -i dialog-error -t 4000 "Print falhou" \
            "Captura indisponível e clipboard ilegível." 2>/dev/null
        exit 1
    fi
    target="$DEST/Screenshot_$(date +%Y-%m-%d_%H-%M-%S).png"
    mv "$tmp" "$target" || exit 1
    notify-send -a "Aurora" -i dialog-warning -t 3000 "Captura falhou — usando o clipboard" \
        "Abrindo no Gradia a imagem da área de transferência." 2>/dev/null
fi

# --- 3. Abre no Gradia (hand-off sem cold-start) ---
setsid flatpak run be.alexandervanhee.gradia "$target" >/dev/null 2>&1 </dev/null &
exit 0
