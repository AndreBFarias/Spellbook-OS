#!/usr/bin/env bash
# claude-paste-image.sh — paste universal disparado por um atalho global.
# Se o clipboard contém imagem, salva PNG em /tmp/claude-paste-<ts>.png e digita o
# path (com espaço antes/depois) no foco atual via wtype — que é como se entrega
# uma imagem ao agente Code no terminal, já que ele recebe TEXTO, não bitmap.
# Se contém texto, digita o texto direto.
#
# ---------------------------------------------------------------------------
# ATALHO: use Super+V NESTA MÁQUINA, não Ctrl+Shift+V.
#
# No Andromeda-OS o binding é Ctrl+Shift+V, e lá isso faz sentido porque a dona
# quis um "colar universal" que substitui o colar do sistema. AQUI a decisão foi
# outra, de propósito (problema D1 desta máquina — o dono está no cosmic-term e
# já briga com Ctrl+C/Ctrl+V):
#
#   1. Atalho global é registrado no COMPOSITOR e CONSOME a tecla antes do app.
#      Tomar Ctrl+Shift+V tira do cosmic-term o colar nativo dele.
#   2. O colar nativo do terminal usa BRACKETED PASTE: o shell recebe o texto
#      como dado, e um texto com quebras de linha NÃO é executado. O `wtype`
#      abaixo digita tecla a tecla, SEM bracketed paste — colar texto de várias
#      linhas no terminal EXECUTARIA cada linha. Substituir o colar do terminal
#      por este script troca uma conveniência por um risco real.
#   3. Super+V não colide com nada no `custom` (que tem só Ctrl+Alt+T e
#      Ctrl+Shift+S) e deixa Ctrl+V e Ctrl+Shift+V exatamente como estão.
#
# Entrada a acrescentar em
# ~/.config/cosmic/com.system76.CosmicSettings.Shortcuts/v1/custom:
#
#     (
#         modifiers: [ Super ],
#         key: "v",
#         description: Some("Paste universal — texto ou imagem->path (Aurora)"),
#     ): Spawn("/usr/local/bin/claude-paste-image.sh"),
#
# Os defaults do compositor não vivem em arquivo (são compilados no cosmic-comp),
# então a ausência de colisão com Super+V só se confirma testando na sessão.
# ---------------------------------------------------------------------------
#
# DEPENDÊNCIAS AUSENTES EM 11/09/2026 (medido): wl-clipboard e wtype não estavam
# instalados. Ambos existem em noble/universe (wl-clipboard 2.2.1-1build1,
# wtype 0.4-3). Sem eles o script sai com exit 1 e só escreve no log:
#   sudo apt install -y wl-clipboard wtype
#
# Fonte canônica em ~/.config/zsh/scripts/, instalado em
# /usr/local/bin/claude-paste-image.sh pelo aurora-bootstrap.sh (copia_se_diff).

set -uo pipefail

LOG=/tmp/claude-paste-image.log
{
  echo "--- $(date -Iseconds) ---"
} >> "$LOG" 2>&1

# Garantir env Wayland mínimo (compositor faz Spawn sem WAYLAND_DISPLAY em alguns casos)
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

if ! command -v wl-paste >/dev/null 2>&1; then
  echo "wl-paste ausente (pacote wl-clipboard)" >> "$LOG"
  notify-send "agente Paste" "wl-clipboard não instalado — sudo apt install -y wl-clipboard wtype" 2>/dev/null || true
  exit 1
fi
if ! command -v wtype >/dev/null 2>&1; then
  echo "wtype ausente" >> "$LOG"
  notify-send "agente Paste" "wtype não instalado — sudo apt install -y wl-clipboard wtype" 2>/dev/null || true
  exit 1
fi

TYPES="$(wl-paste --list-types 2>/dev/null || true)"
echo "tipos: $TYPES" >> "$LOG"

if [ -z "$TYPES" ]; then
  echo "clipboard vazio" >> "$LOG"
  exit 0
fi

if echo "$TYPES" | grep -qiE '^image/'; then
  TS="$(date +%Y%m%d-%H%M%S-%N)"
  PNG="/tmp/claude-paste-${TS}.png"
  if echo "$TYPES" | grep -qi '^image/png'; then
    wl-paste --type image/png > "$PNG"
  else
    # qualquer image/* — pega o primeiro tipo image/ disponível
    IMG_TYPE="$(echo "$TYPES" | grep -iE '^image/' | head -1)"
    wl-paste --type "$IMG_TYPE" > "$PNG"
  fi
  if [ -s "$PNG" ]; then
    echo "imagem salva: $PNG ($(stat -c '%s' "$PNG") bytes)" >> "$LOG"
    sleep 0.05
    wtype -- " ${PNG} "
  else
    echo "ERRO: PNG vazio em $PNG" >> "$LOG"
    rm -f "$PNG"
    exit 1
  fi
elif echo "$TYPES" | grep -qiE '^(text/|UTF8_STRING|STRING)'; then
  TXT="$(wl-paste --no-newline 2>/dev/null || wl-paste 2>/dev/null || true)"
  if [ -n "$TXT" ]; then
    echo "texto: ${#TXT} chars" >> "$LOG"
    sleep 0.05
    wtype -- "$TXT"
  fi
else
  echo "tipo não suportado: $TYPES" >> "$LOG"
  notify-send "agente Paste" "Clipboard tem tipo não suportado: $TYPES" 2>/dev/null || true
fi
