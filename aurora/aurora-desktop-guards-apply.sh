#!/bin/bash
# Aurora - desktop-guards: mantém o menu de lançamento saudável (idempotente).
#
# [2026-09-15] A parte genérica saiu daqui para o aurora-menu-doctor.py, que
# resolve o Exec de verdade (wrappers, `flatpak run`, distrobox, `sh -c`) e
# limpa também o mimeapps.list. O que continua aqui é só o que é específico
# demais para o doctor: um Exec que precisa ser reescrito em vez de removido, e
# um serviço a mascarar.
#
# Quarentena: ~/.local/share/aurora-menu-quarentena/. Ela NÃO fica mais dentro
# de applications/ — o XDG varre subdiretórios e o órfão continuava registrado
# como handler de mimetype com o nome do subdiretório na frente
# (`.aurora-orphan-bak-org.gimp.GIMP.desktop` estava no mimeinfo.cache).
# O doctor migra o diretório antigo sozinho.
#
# Roda em user-space, sem sudo. Sempre exit 0 (não bloqueia o self-heal).
set -u

APPS="$HOME/.local/share/applications"
DOCTOR="$HOME/.config/zsh/aurora/aurora-menu-doctor.py"
log(){ printf '[aurora-desktop-guards] %s\n' "$1"; }

[ -d "$APPS" ] || exit 0

# 1. PhotoGIMP: Exec=--command=gimp-3.0 (inexistente no GIMP 3.2+, bwrap falha).
# Aqui o lançador está CERTO e o comando é que envelheceu — reescrever é a
# correção; mandar para a quarentena perderia a customização do PhotoGIMP.
# Roda antes do doctor: com o Exec consertado, o doctor já o vê saudável.
gimp_desktop="$APPS/org.gimp.GIMP.desktop"
if [ -f "$gimp_desktop" ] && grep -q -- '--command=gimp-3\.0' "$gimp_desktop" 2>/dev/null; then
  sed -i 's/--command=gimp-3\.0/--command=gimp/' "$gimp_desktop" \
    && log "Exec gimp-3.0→gimp em org.gimp.GIMP.desktop"
fi

# 2. O resto do menu — órfãos, permissões, associações mortas, cache.
if [ -x "$DOCTOR" ]; then
  "$DOCTOR" --fix
else
  log "AVISO: aurora-menu-doctor.py ausente — menu não verificado"
fi

# 3. tracker-extract-3 mascarado (mata o loop de crash SIGSYS seccomp×libcuda).
if [ "$(systemctl --user is-enabled tracker-extract-3.service 2>/dev/null)" != "masked" ]; then
  systemctl --user mask tracker-extract-3.service >/dev/null 2>&1 \
    && log "tracker-extract-3 mascarado"
fi

exit 0
