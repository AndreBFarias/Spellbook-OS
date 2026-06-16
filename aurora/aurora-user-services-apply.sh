#!/bin/bash
# Aurora - instala/atualiza user services do Aurora (systemd --user)
# ----------------------------------------------------------------------------
# Para cada arquivo *.service em aurora/units/ listado abaixo, faz:
#   1. cp pra ~/.config/systemd/user/ se ausente ou diff
#   2. daemon-reload se algum mudou
#   3. enable --now (idempotente)
#
# Idempotente: pula serviço já ativo + arquivo sincronizado.

set -u

SRC_DIR="$HOME/.config/zsh/aurora/units"
DST_DIR="$HOME/.config/systemd/user"

# Lista dos services user-level mantidos pelo Aurora
USER_SERVICES=(
  "gradia-autosave.service"
  "imagens-router.service"
)

# Timers (systemd --user): copia o .timer + o .service par; habilita SO o .timer.
USER_TIMERS=(
  "spellbook-autosync.timer"
)

log()  { printf '[user-services] %s\n' "$*"; }
warn() { printf '[user-services][WARN] %s\n' "$*" >&2; }

copy_unit() {
  local unit="$1"
  local src="$SRC_DIR/$unit" dst="$DST_DIR/$unit"
  if [ ! -f "$src" ]; then warn "fonte ausente: $src"; return; fi
  if [ ! -f "$dst" ] || ! cmp -s "$src" "$dst"; then
    cp -- "$src" "$dst"; log "atualizado: $unit"; needs_reload=1
  fi
}

mkdir -p "$DST_DIR"
needs_reload=0

for unit in "${USER_SERVICES[@]}"; do
  copy_unit "$unit"
done
for timer in "${USER_TIMERS[@]}"; do
  copy_unit "$timer"
  copy_unit "${timer%.timer}.service"
done

if [ "$needs_reload" = "1" ]; then
  systemctl --user daemon-reload
fi

# Enable + start cada um (idempotente)
for unit in "${USER_SERVICES[@]}"; do
  if ! systemctl --user is-enabled --quiet "$unit" 2>/dev/null; then
    systemctl --user enable "$unit" >/dev/null 2>&1 && log "enabled: $unit"
  fi
  if ! systemctl --user is-active --quiet "$unit" 2>/dev/null; then
    systemctl --user start "$unit" 2>/dev/null && log "started: $unit"
  fi
done

# Timers: habilita+start so o .timer (ele aciona o .service oneshot no schedule)
for timer in "${USER_TIMERS[@]}"; do
  if ! systemctl --user is-enabled --quiet "$timer" 2>/dev/null; then
    systemctl --user enable "$timer" >/dev/null 2>&1 && log "enabled: $timer"
  fi
  if ! systemctl --user is-active --quiet "$timer" 2>/dev/null; then
    systemctl --user start "$timer" 2>/dev/null && log "started: $timer"
  fi
done
