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

# Garante env de user dbus/runtime para systemctl --user funcionar fora de sessão gráfica
# (cron, sudo -i, ssh non-interactive, apt postinvoke hook, etc).
if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
  export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -S "$XDG_RUNTIME_DIR/bus" ]; then
  export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
fi
# Se ainda assim não há bus de usuário, avisa e segue só com system bus
if ! [ -S "${XDG_RUNTIME_DIR:-/dev/null}/bus" ]; then
  warn "user dbus indisponível (XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR) — systemctl --user será pulado"
  USER_BUS_OK=0
else
  USER_BUS_OK=1
fi

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

# Aurora 2.1: Ollama protection (slice + VRAM watchdog)
copia_se_diff "$AURORA_REPO/units/ollama.slice"                 /etc/systemd/system/ollama.slice                 root:root 0644
copia_se_diff "$AURORA_REPO/units/ollama-vram-watchdog.service" /etc/systemd/system/ollama-vram-watchdog.service root:root 0644
copia_se_diff "$AURORA_REPO/units/ollama-vram-watchdog.timer"   /etc/systemd/system/ollama-vram-watchdog.timer   root:root 0644
copia_se_diff "$AURORA_REPO/aurora-vram-check"                  /usr/local/sbin/aurora-vram-check                root:root 0755

# Drop-in pra ollama.service apontar pra ollama.slice (só se ollama.service existe)
if [ -f /etc/systemd/system/ollama.service ] || [ -f /lib/systemd/system/ollama.service ]; then
  sudo -n mkdir -p /etc/systemd/system/ollama.service.d
  copia_se_diff "$AURORA_REPO/units/ollama-slice.conf" /etc/systemd/system/ollama.service.d/aurora-slice.conf root:root 0644
fi

# Aurora 2.1 (Round C): Health monitor (SMART + thermal + disk)
copia_se_diff "$AURORA_REPO/units/aurora-health.service" /etc/systemd/system/aurora-health.service root:root 0644
copia_se_diff "$AURORA_REPO/units/aurora-health.timer"   /etc/systemd/system/aurora-health.timer   root:root 0644
copia_se_diff "$AURORA_REPO/aurora-health-check"         /usr/local/sbin/aurora-health-check        root:root 0755

# Instalar lm-sensors se faltar (silencioso, idempotente)
if ! command -v sensors >/dev/null 2>&1; then
  log "Instalando lm-sensors (necessário pra checagem térmica)..."
  sudo -n DEBIAN_FRONTEND=noninteractive apt-get install -y lm-sensors >/dev/null 2>&1 \
    && log "lm-sensors instalado" \
    || warn "Falha ao instalar lm-sensors — checagem térmica de CPU desabilitada"
fi

# Detectar sensores na primeira execução (idempotente: sensors-detect cria /etc/modules-load.d/sensors.conf)
if command -v sensors-detect >/dev/null 2>&1 && [ ! -f /etc/modules-load.d/sensors.conf ]; then
  log "Rodando sensors-detect --auto (uma única vez)..."
  sudo -n sensors-detect --auto >/dev/null 2>&1 || warn "sensors-detect retornou erro (não fatal)"
fi

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
if [ $USER_BUS_OK -eq 1 ]; then
  systemctl --user daemon-reload
fi

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

# Aurora 2.1: ollama-vram-watchdog.timer (só habilita se ollama.service existe)
if [ -f /etc/systemd/system/ollama.service ] || [ -f /lib/systemd/system/ollama.service ]; then
  if ! systemctl is-enabled --quiet ollama-vram-watchdog.timer 2>/dev/null; then
    sudo -n systemctl enable ollama-vram-watchdog.timer 2>&1 | grep -v "Created symlink" || true
    log "Enabled: ollama-vram-watchdog.timer"
  fi
  if ! systemctl is-active --quiet ollama-vram-watchdog.timer 2>/dev/null; then
    sudo -n systemctl start ollama-vram-watchdog.timer || warn "Falha ao iniciar ollama-vram-watchdog.timer"
    log "Started: ollama-vram-watchdog.timer"
  fi
fi

# Aurora 2.1 (Round C): aurora-health.timer
if ! systemctl is-enabled --quiet aurora-health.timer 2>/dev/null; then
  sudo -n systemctl enable aurora-health.timer 2>&1 | grep -v "Created symlink" || true
  log "Enabled: aurora-health.timer"
fi
if ! systemctl is-active --quiet aurora-health.timer 2>/dev/null; then
  sudo -n systemctl start aurora-health.timer || warn "Falha ao iniciar aurora-health.timer"
  log "Started: aurora-health.timer"
fi

# Aurora 2.1: NVIDIA suspend/resume/hibernate (preservam VRAM em transições de power)
if [ -f /lib/systemd/system/nvidia-suspend.service ]; then
  for s in nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service; do
    if ! systemctl is-enabled --quiet "$s" 2>/dev/null; then
      sudo -n systemctl enable "$s" 2>&1 | grep -v "Created symlink" || true
      log "Enabled: $s"
    fi
  done
fi

# User services
if [ $USER_BUS_OK -eq 1 ]; then
  if ! systemctl --user is-enabled --quiet aurora-user.service 2>/dev/null; then
    systemctl --user enable aurora-user.service 2>&1 | grep -v "Created symlink" || true
    log "Enabled (user): aurora-user.service"
  fi
  # Tentar start (so funciona dentro de sessão grafica)
  if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
    systemctl --user start aurora-user.service 2>/dev/null || log "aurora-user.service start falhou (talvez fora de sessão grafica)"
  fi
else
  log "Pulando enable/start de aurora-user.service (sem dbus de usuário)"
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
