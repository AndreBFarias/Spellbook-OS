#!/bin/bash
# Aurora - editor de texto padrão do sistema.
#
# [2026-08-18] A versão anterior tinha "org.gnome.gedit.desktop" escrito no corpo,
# por decisão da época (gedit recebia o tema Dracula).
# [2026-09-15] O gedit foi removido na leva-04 e este script virou uma instrução
# para um programa que não existe: ele saía 0 dizendo "não instalado", calado,
# enquanto o self-heal continuava chamando-o de hora em hora. Pior: se o gedit
# voltasse por uma dependência qualquer, este script tomaria text/plain do
# COSMIC Edit de volta, contra a regra do dono ("na duplicidade o COSMIC vence").
#
# Agora quem escolhe é o aurora-menu-doctor.py, com a mesma política que ele usa
# para repor qualquer default órfão. Nenhum nome de editor mora aqui — trocar o
# editor padrão é instalar o editor, não editar este arquivo.
#
# Idempotente. Roda na sessão do usuário (chamado pelo aurora-bootstrap.sh).
set -u

DOCTOR="$HOME/.config/zsh/aurora/aurora-menu-doctor.py"
log() { printf '[Editor] %s\n' "$*"; }

[ -x "$DOCTOR" ] || { log "aurora-menu-doctor.py ausente — padrão não alterado"; exit 0; }

desejado="$("$DOCTOR" --melhor-para text/plain 2>/dev/null)" || desejado=""
if [ -z "$desejado" ]; then
  log "nenhum editor instalado declara text/plain — padrão não alterado"
  exit 0
fi

atual="$(xdg-mime query default text/plain 2>/dev/null)"
if [ "$atual" = "$desejado" ]; then
  exit 0
fi

if xdg-mime default "$desejado" text/plain 2>/dev/null; then
  log "text/plain: $atual → $desejado"
else
  log "falha ao definir $desejado como padrão de text/plain"
fi

exit 0
