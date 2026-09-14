#!/bin/bash
# Aurora - editor de texto padrão do sistema.
# [2026-08-18] O dono optou pelo gedit: ele recebe o tema Dracula, e o
# gnome-text-editor duplicava a entrada "Text Editor" no menu. O pacote
# gnome-text-editor foi removido com apt purge -- este script NÃO o reinstala e
# NÃO devolve text/plain para ele.
# Idempotente. Roda na sessão do usuário (chamado pelo aurora-bootstrap.sh).
set -u

DESKTOP="org.gnome.gedit.desktop"
log() { printf '[Editor] %s\n' "$*"; }

if [ ! -f "/usr/share/applications/$DESKTOP" ]; then
  log "Gedit não instalado -- padrão de text/plain não alterado"
  exit 0
fi

if [ "$(xdg-mime query default text/plain 2>/dev/null)" != "$DESKTOP" ]; then
  xdg-mime default "$DESKTOP" text/plain 2>/dev/null \
    && log "Gedit definido como padrão de text/plain" \
    || log "Falha ao definir o gedit como padrão de text/plain"
fi

exit 0
