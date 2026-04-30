#!/bin/bash
# Aurora 2.0 - Bootstrap idempotente
#
# Modos:
#   --first-install  : instala tudo do zero (kernelstub args + units + apt hook)
#   --post-update    : re-aplica apos apt upgrade (sem mexer em kernelstub se ja ok)
#   --quiet          : sem output exceto erros
#   (sem flags)      : equivale a --post-update
#
# Idempotente: pode rodar quantas vezes quiser sem efeitos colaterais.

set -u

AURORA_REPO="/home/andrefarias/.config/zsh/aurora"
QUIET=0
MODE="post-update"

for arg in "$@"; do
  case "$arg" in
    --first-install) MODE="first-install" ;;
    --post-update)   MODE="post-update" ;;
    --quiet)         QUIET=1 ;;
  esac
done

log() { [ $QUIET -eq 0 ] && printf '[bootstrap] %s\n' "$*"; }
warn() { printf '[bootstrap][WARN] %s\n' "$*" >&2; }
err() { printf '[bootstrap][ERR] %s\n' "$*" >&2; exit 1; }

# Sanity check
[ -d "$AURORA_REPO" ] || err "Repo não encontrado: $AURORA_REPO"

log "Modo: $MODE"

# 1. Kernelstub args (so em first-install OU se faltando algum param-chave)
KERNELSTUB_PARAMS=(
  "amd_pstate=active"
  "processor.max_cstate=1"
  "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
  "transparent_hugepage=madvise"
  "mitigations=off"
)

if command -v kernelstub >/dev/null 2>&1; then
  cmdline_atual=$(sudo -n kernelstub --print-config 2>/dev/null | awk -F': ' '/Kernel Boot Options/ {sub(/^\.+/,"",$2); print $2}' || true)
  if [ -z "$cmdline_atual" ]; then
    cmdline_atual=$(cat /proc/cmdline)
    log "Usando /proc/cmdline (kernelstub --print-config requer sudo)"
  fi
  faltando=()
  for p in "${KERNELSTUB_PARAMS[@]}"; do
    if ! echo "$cmdline_atual" | grep -qF "$p"; then
      faltando+=("$p")
    fi
  done
  if [ ${#faltando[@]} -gt 0 ]; then
    log "Adicionando ao kernelstub: ${faltando[*]}"
    sudo -n kernelstub --add-options "${faltando[*]}" 2>&1 | grep -v "^kernelstub" || true
  else
    log "Kernelstub: todos os params ja presentes"
  fi
else
  warn "kernelstub não instalado - pulando args persistidos"
fi

# 2. Copiar arquivos para locais oficiais (idempotente via cmp)
copia_se_diff() {
  local src=$1 dst=$2 owner=${3:-root:root} mode=${4:-0644}
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    return 0
  fi
  sudo -n install -o "${owner%:*}" -g "${owner#*:}" -m "$mode" "$src" "$dst"
  log "Instalado: $dst"
}

# Script root (executavel)
copia_se_diff "$AURORA_REPO/aurora-root-apply" /usr/local/sbin/aurora-root-apply root:root 0755

# sysctl
copia_se_diff "$AURORA_REPO/99-aurora.conf" /etc/sysctl.d/99-aurora.conf root:root 0644

# earlyoom default
copia_se_diff "$AURORA_REPO/earlyoom.default" /etc/default/earlyoom root:root 0644

# Units root
copia_se_diff "$AURORA_REPO/units/aurora-root.service"     /etc/systemd/system/aurora-root.service     root:root 0644
copia_se_diff "$AURORA_REPO/units/aurora-watchdog.service" /etc/systemd/system/aurora-watchdog.service root:root 0644
copia_se_diff "$AURORA_REPO/units/aurora-watchdog.timer"   /etc/systemd/system/aurora-watchdog.timer   root:root 0644

# apt hook
copia_se_diff "$AURORA_REPO/units/99-aurora-postinvoke" /etc/apt/apt.conf.d/99-aurora-postinvoke root:root 0644

# 3. User-level units (sem sudo)
USER_SYSTEMD_DIR="$HOME/.config/systemd/user"
mkdir -p "$USER_SYSTEMD_DIR"

copia_user() {
  local src=$1 dst=$2
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then return 0; fi
  install -m 0644 "$src" "$dst"
  log "Instalado (user): $dst"
}

copia_user "$AURORA_REPO/units/aurora-user.service" "$USER_SYSTEMD_DIR/aurora-user.service"
copia_user "$AURORA_REPO/units/claude.slice"        "$USER_SYSTEMD_DIR/claude.slice"

# 4. Reload systemd e enable
sudo -n systemctl daemon-reload
systemctl --user daemon-reload

# 5. Enable services (idempotente)
for s in earlyoom.service aurora-root.service aurora-watchdog.timer; do
  if ! systemctl is-enabled --quiet "$s" 2>/dev/null; then
    sudo -n systemctl enable "$s" 2>&1 | grep -v "Created symlink" || true
    log "Enabled: $s"
  fi
done

# Start (no caso de first-install OU se inativo)
for s in aurora-root.service aurora-watchdog.timer earlyoom.service; do
  if ! systemctl is-active --quiet "$s" 2>/dev/null; then
    sudo -n systemctl start "$s" || warn "Falha ao iniciar $s"
    log "Started: $s"
  fi
done

# User services
if ! systemctl --user is-enabled --quiet aurora-user.service 2>/dev/null; then
  systemctl --user enable aurora-user.service 2>&1 | grep -v "Created symlink" || true
  log "Enabled (user): aurora-user.service"
fi
# Tentar start (so funciona dentro de sessão grafica)
if [ -n "${DISPLAY:-}${XDG_RUNTIME_DIR:-}" ]; then
  systemctl --user start aurora-user.service 2>/dev/null || log "aurora-user.service start falhou (talvez fora de sessão grafica)"
fi

# 6. Sunset do ritual antigo (so se ainda ativo)
if [ -f /etc/systemd/system/ritual-aurora-root.service ]; then
  sudo -n systemctl disable ritual-aurora-root.service 2>/dev/null || true
  log "Disabled (legacy): ritual-aurora-root.service"
fi
if [ -f "$HOME/.config/autostart/ritual_aurora.desktop" ]; then
  mv "$HOME/.config/autostart/ritual_aurora.desktop" "$HOME/.config/autostart/ritual_aurora.desktop.disabled" 2>/dev/null && \
    log "Desativado autostart legacy: ritual_aurora.desktop -> .disabled"
fi

log "Bootstrap concluido (modo=$MODE)"
exit 0
