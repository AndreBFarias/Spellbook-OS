#!/bin/bash
# Aurora 2.3 - configura o atalho global Ctrl+Alt+0 -> aurora-gpu-revive-trigger
# via xbindkeys (XGrabKey direto no X: dispara mesmo com o compositor travado,
# desde que o Xorg esteja vivo -- exatamente o caso "so o cursor do mouse mexe").
# Idempotente. Roda na sessão do usuário (chamado pelo aurora-bootstrap.sh).
set -u

AURORA_REPO="/home/andrefarias/.config/zsh/aurora"
TRIGGER="$AURORA_REPO/aurora-gpu-revive-trigger"
RC="$HOME/.xbindkeysrc"
MARK="# Aurora 2.3 - botao de panico GPU (Ctrl+Alt+0)"

log() { printf '[gpu-shortcut] %s\n' "$*"; }

# 1. xbindkeys instalado?
if ! command -v xbindkeys >/dev/null 2>&1; then
  log "instalando xbindkeys..."
  sudo -n DEBIAN_FRONTEND=noninteractive apt-get install -y xbindkeys >/dev/null 2>&1 \
    && log "xbindkeys instalado" \
    || { log "WARN: falha ao instalar xbindkeys (sem sudo -n?) -- atalho não configurado"; exit 0; }
fi

chmod +x "$TRIGGER" 2>/dev/null

# 2. ~/.xbindkeysrc com a entrada do atalho (append idempotente, marcado)
if [ ! -f "$RC" ] || ! grep -qF "$MARK" "$RC" 2>/dev/null; then
  {
    [ -f "$RC" ] && echo ""
    echo "$MARK"
    echo "\"$TRIGGER\""
    echo "  control+alt + 0"
  } >> "$RC"
  log "entrada Ctrl+Alt+0 adicionada em $RC"
fi

# 3. autostart na sessão (para o xbindkeys subir a cada login)
AUTOSTART="$HOME/.config/autostart/xbindkeys.desktop"
if [ ! -f "$AUTOSTART" ]; then
  mkdir -p "$(dirname "$AUTOSTART")"
  cat > "$AUTOSTART" <<EOF
[Desktop Entry]
Type=Application
Name=xbindkeys (Aurora GPU shortcut)
Exec=xbindkeys
X-GNOME-Autostart-enabled=true
NoDisplay=true
Comment=Atalho Ctrl+Alt+0 para recuperar o display AMD travado
EOF
  log "autostart criado: $AUTOSTART"
fi

# 4. (re)carregar o xbindkeys agora (best-effort, só dentro de sessão gráfica)
if [ -n "${DISPLAY:-}" ]; then
  pkill -x xbindkeys 2>/dev/null
  sleep 0.3
  if xbindkeys 2>/dev/null; then
    log "xbindkeys (re)carregado (Ctrl+Alt+0 ativo)"
  else
    log "WARN: não consegui iniciar o xbindkeys agora"
  fi
fi

exit 0
