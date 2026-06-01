#!/bin/bash
# Aurora 2.3 - editor de texto estilo "Notepad do Windows 11".
# Adota o gnome-text-editor (Editor de Texto do GNOME) como padrão de texto: ele
# restaura a sessão (reabre as abas e guarda rascunho de documento sem título até
# fecharem uma a uma) -- o que o gedit não faz. O gedit permanece instalado.
# Idempotente. Roda na sessão do usuário (chamado pelo aurora-bootstrap.sh).
set -u

DESKTOP="org.gnome.TextEditor.desktop"
log() { printf '[editor] %s\n' "$*"; }

# 1. gnome-text-editor instalado? (instala se faltar -- "adicionar, nunca remover")
if [ ! -f "/usr/share/applications/$DESKTOP" ]; then
  log "instalando gnome-text-editor..."
  sudo -n DEBIAN_FRONTEND=noninteractive apt-get install -y gnome-text-editor >/dev/null 2>&1 \
    && log "gnome-text-editor instalado" \
    || { log "WARN: falha ao instalar gnome-text-editor -- padrão não alterado"; exit 0; }
fi

# 2. tornar padrão de text/plain (o "notepad"; o gedit segue instalado e usável)
if [ "$(xdg-mime query default text/plain 2>/dev/null)" != "$DESKTOP" ]; then
  if xdg-mime default "$DESKTOP" text/plain 2>/dev/null; then
    log "gnome-text-editor definido como padrão de text/plain"
  fi
fi

# 3. comportamento Notepad: restaurar a sessão (reabre abas + rascunho sem título)
#    -- e ja e o default do gnome-text-editor, mas garante de forma idempotente.
if command -v gsettings >/dev/null 2>&1; then
  if [ "$(gsettings get org.gnome.TextEditor restore-session 2>/dev/null)" != "true" ]; then
    gsettings set org.gnome.TextEditor restore-session true 2>/dev/null && log "restore-session ligado"
  fi
fi

exit 0
