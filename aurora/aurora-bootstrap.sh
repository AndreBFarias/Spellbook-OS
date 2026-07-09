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
  "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
  "transparent_hugepage=madvise"
  "mitigations=off"
  # Aurora 2.3 ULTRA - always-plugged desktop replacement
  "pcie_aspm=off"
  "nvme_core.default_ps_max_latency_us=0"
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

# 2. Copiar arquivos para locais oficiais (idempotente via cmp + validação pós-cópia)
copia_se_diff() {
  local src=$1 dst=$2 owner=${3:-root:root} mode=${4:-0644}
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    return 0
  fi
  if ! sudo -n install -o "${owner%:*}" -g "${owner#*:}" -m "$mode" "$src" "$dst" 2>/dev/null; then
    warn "Falha em install $dst — sudo -n sem cache. Rode 'sudo -v' primeiro."
    return 1
  fi
  # Validação pós-cópia: arquivo de destino bate com fonte
  if ! cmp -s "$src" "$dst"; then
    warn "Cópia inconsistente: $dst (cmp falhou após install)"
    return 1
  fi
  log "Instalado: $dst"
}

# Script root (executavel)
copia_se_diff "$AURORA_REPO/aurora-root-apply" /usr/local/sbin/aurora-root-apply root:root 0755

# sysctl
copia_se_diff "$AURORA_REPO/99-aurora.conf" /etc/sysctl.d/99-aurora.conf root:root 0644

# Aurora 2.8: destrava acer_wmi predator_v4 (expoe platform_profile p/ curva de fan
# agressiva + RPM das fans via hwmon no Nitro). Vale no próximo boot (modprobe.d).
copia_se_diff "$AURORA_REPO/acer_wmi-predator.conf" /etc/modprobe.d/acer_wmi-predator.conf root:root 0644

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

# Aurora 2.3: amdgpu DMCUB display watchdog (recupera display AMD travado sem reboot;
# descoberto 2026-06-01 -- freeze por DMCUB hang no Nitro-5 hibrido). Script vive no
# repo (~/.config/zsh/aurora/amdgpu-dmcub-watchdog), so as units vao pro systemd.
copia_se_diff "$AURORA_REPO/units/amdgpu-dmcub-watchdog.service" /etc/systemd/system/amdgpu-dmcub-watchdog.service root:root 0644
copia_se_diff "$AURORA_REPO/units/amdgpu-dmcub-watchdog.timer"   /etc/systemd/system/amdgpu-dmcub-watchdog.timer   root:root 0644

# Aurora 2.3: botão de pânico de GPU (Ctrl+Alt+0). Script root em /usr/local/sbin
# (não-gravável pelo user -> sudoers NOPASSWD seguro). O atalho em si (xbindkeys)
# é configurado em user-space na seção 6e (aurora-gpu-shortcut-apply.sh).
copia_se_diff "$AURORA_REPO/aurora-gpu-revive" /usr/local/sbin/aurora-gpu-revive root:root 0755
# sudoers: validar com visudo ANTES de ativar (um sudoers inválido quebra o sudo)
if ! sudo -n cmp -s "$AURORA_REPO/sudoers-aurora-gpu-revive" /etc/sudoers.d/aurora-gpu-revive 2>/dev/null; then
  if sudo -n visudo -cf "$AURORA_REPO/sudoers-aurora-gpu-revive" >/dev/null 2>&1; then
    sudo -n install -o root -g root -m 0440 "$AURORA_REPO/sudoers-aurora-gpu-revive" /etc/sudoers.d/aurora-gpu-revive \
      && log "Instalado: /etc/sudoers.d/aurora-gpu-revive"
  else
    warn "sudoers-aurora-gpu-revive inválido (visudo -cf falhou) -- NÃO instalado"
  fi
fi

# Drop-in pra ollama.service apontar pra ollama.slice (só se ollama.service existe)
if [ -f /etc/systemd/system/ollama.service ] || [ -f /lib/systemd/system/ollama.service ]; then
  sudo -n mkdir -p /etc/systemd/system/ollama.service.d
  copia_se_diff "$AURORA_REPO/units/ollama-slice.conf"     /etc/systemd/system/ollama.service.d/aurora-slice.conf root:root 0644
  # Aurora 2.2: keep_alive 30m + max_loaded 3 (substitui memory.conf antigo com 30s/1)
  copia_se_diff "$AURORA_REPO/units/ollama-keepalive.conf" /etc/systemd/system/ollama.service.d/memory.conf      root:root 0644
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

# Aurora 2.2: Forensics de OOM (journald persistente + mem-snapshot 30s)
# Journal persistente: drop-in + diretório /var/log/journal/<machine-id>/
journald_changed=0
if ! sudo -n cmp -s "$AURORA_REPO/journald-persistent.conf" /etc/systemd/journald.conf.d/00-persistent.conf 2>/dev/null; then
  sudo -n mkdir -p /etc/systemd/journald.conf.d
  sudo -n install -m 0644 -o root -g root "$AURORA_REPO/journald-persistent.conf" /etc/systemd/journald.conf.d/00-persistent.conf
  journald_changed=1
  log "Instalado: /etc/systemd/journald.conf.d/00-persistent.conf"
fi
MACHINE_ID=$(cat /etc/machine-id 2>/dev/null || true)
if [ -n "$MACHINE_ID" ] && [ ! -d "/var/log/journal/$MACHINE_ID" ]; then
  sudo -n install -d -m 2755 -o root -g systemd-journal "/var/log/journal/$MACHINE_ID"
  journald_changed=1
  log "Criado: /var/log/journal/$MACHINE_ID"
fi
if [ "$journald_changed" -eq 1 ]; then
  sudo -n systemctl restart systemd-journald
  log "Restarted: systemd-journald"
fi

# mem-snapshot (snapshot CSV de memória + PSI a cada 30s)
copia_se_diff "$AURORA_REPO/units/mem-snapshot.service" /etc/systemd/system/mem-snapshot.service root:root 0644
copia_se_diff "$AURORA_REPO/units/mem-snapshot.timer"   /etc/systemd/system/mem-snapshot.timer   root:root 0644
copia_se_diff "$AURORA_REPO/mem-snapshot"               /usr/local/sbin/mem-snapshot              root:root 0755
copia_se_diff "$AURORA_REPO/mem-snapshot.logrotate"     /etc/logrotate.d/mem-snapshot             root:root 0644

# oom-postmortem (verifica boot anterior, gera relatório no Desktop se houve OOM)
copia_se_diff "$AURORA_REPO/units/oom-postmortem.service" /etc/systemd/system/oom-postmortem.service root:root 0644
copia_se_diff "$AURORA_REPO/oom-postmortem"               /usr/local/sbin/oom-postmortem              root:root 0755

# Aurora 2.2 - OOM por produto (cgroup.kill watchdog generalizado)
# Fecha PRODUTO INTEIRO atomicamente quando pressão sistêmica é crítica
# (em vez de matar processo individual). Funciona pra qualquer slice
# (browser, electron, claude, ollama, luna, steam, heavy-other).
copia_se_diff "$AURORA_REPO/units/product-oom-watchdog.service" /etc/systemd/system/product-oom-watchdog.service root:root 0644
copia_se_diff "$AURORA_REPO/product-oom-watchdog"               /usr/local/sbin/product-oom-watchdog              root:root 0755
copia_se_diff "$AURORA_REPO/luna-launch"                        /usr/local/bin/luna-launch                        root:root 0755

# Aurora 2.6 - anti-suspend DESATIVADO (laptop-friendly): não instalamos mais o
# logind drop-in nem o dconf no-suspend, para o laptop poder suspender/dormir.
# A remoção dos arquivos já instalados foi feita uma vez no apply do Sprint A.

# Aurora 2.3 ULTRA - Wi-Fi powersave off (NetworkManager)
copia_se_diff "$AURORA_REPO/99-aurora-ultra-wifi.conf" /etc/NetworkManager/conf.d/99-aurora-ultra-wifi.conf root:root 0644

# Bug fix: 'default-wifi-powersave-on.conf' vem APOS '99-*' em ordem alfabetica
# (9 < d em ASCII) e sobrescreve wifi.powersave=2 com wifi.powersave=3.
# Se Pop!_OS reinstalar via apt, remover aqui idempotente.
_pop_wifi_on="/etc/NetworkManager/conf.d/default-wifi-powersave-on.conf"
_pop_wifi_bak="${_pop_wifi_on}.bak-aurora-ultra"
if [ -f "$_pop_wifi_on" ] && [ ! -f "$_pop_wifi_bak" ]; then
  sudo -n mv "$_pop_wifi_on" "$_pop_wifi_bak"
  sudo -n systemctl reload NetworkManager 2>/dev/null || true
  log "Removido (sobrescrevia powersave): default-wifi-powersave-on.conf"
elif [ -f "$_pop_wifi_on" ] && [ -f "$_pop_wifi_bak" ]; then
  # Re-aplicação: bak já existe; apenas remover o arquivo reinstalado pelo apt
  sudo -n rm -f "$_pop_wifi_on"
  sudo -n systemctl reload NetworkManager 2>/dev/null || true
  log "Removido (re-aplicação): default-wifi-powersave-on.conf (bak preservado)"
fi
unset _pop_wifi_on _pop_wifi_bak

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

# Aurora 2.1 (Round D): slices pra browser e Electron apps
copia_user "$AURORA_REPO/units/browser.slice"  "$USER_SYSTEMD_DIR/browser.slice"
copia_user "$AURORA_REPO/units/electron.slice" "$USER_SYSTEMD_DIR/electron.slice"

# Aurora 2.2 - slices Luna / Steam / heavy-other (todas com OOMPolicy=kill)
copia_user "$AURORA_REPO/units/luna.slice"         "$USER_SYSTEMD_DIR/luna.slice"
copia_user "$AURORA_REPO/units/steam.slice"        "$USER_SYSTEMD_DIR/steam.slice"
copia_user "$AURORA_REPO/units/heavy-other.slice"  "$USER_SYSTEMD_DIR/heavy-other.slice"

# Helper: cria override XDG do .desktop envelopando Exec= em systemd-run
# Idempotente: se override já tem marker Aurora, pula.
aplica_slice_override() {
  local app="$1" slice="$2"
  local src="/usr/share/applications/${app}.desktop"
  local dst="$HOME/.local/share/applications/${app}.desktop"
  [ -f "$src" ] || return 0
  if [ -f "$dst" ] && grep -q "Aurora 2.1 override" "$dst" 2>/dev/null; then
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  # Reescreve cada linha Exec= envolvendo o binário (primeira palavra) em systemd-run --user --scope
  sed -E "s|^Exec=([^ \t]+)|Exec=systemd-run --user --slice=${slice} --scope --quiet -- \1|g" "$src" > "$dst"
  printf '\n# Aurora 2.1 override (slice=%s)\n' "$slice" >> "$dst"
  chmod 0644 "$dst"
  log "Override aplicado: $dst (slice=$slice)"
}

# Aplica overrides condicionalmente pros apps presentes em /usr/share/applications
aplica_slice_override "google-chrome"  "browser.slice"
aplica_slice_override "firefox"        "browser.slice"
aplica_slice_override "firefox-esr"    "browser.slice"
aplica_slice_override "brave-browser"  "browser.slice"
aplica_slice_override "chromium"       "browser.slice"
aplica_slice_override "slack"          "electron.slice"
aplica_slice_override "discord"        "electron.slice"
aplica_slice_override "code"           "electron.slice"
aplica_slice_override "cursor"         "electron.slice"
aplica_slice_override "zoom"           "electron.slice"

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

# Aurora 2.3: amdgpu-dmcub-watchdog.timer (só habilita se houver GPU amdgpu)
if [ -d /sys/module/amdgpu ] || ls /sys/kernel/debug/dri/*/amdgpu_gpu_recover >/dev/null 2>&1; then
  if ! systemctl is-enabled --quiet amdgpu-dmcub-watchdog.timer 2>/dev/null; then
    sudo -n systemctl enable amdgpu-dmcub-watchdog.timer 2>&1 | grep -v "Created symlink" || true
    log "Enabled: amdgpu-dmcub-watchdog.timer"
  fi
  if ! systemctl is-active --quiet amdgpu-dmcub-watchdog.timer 2>/dev/null; then
    sudo -n systemctl start amdgpu-dmcub-watchdog.timer || warn "Falha ao iniciar amdgpu-dmcub-watchdog.timer"
    log "Started: amdgpu-dmcub-watchdog.timer"
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

# Aurora 2.2: mem-snapshot.timer (forensics de OOM)
if ! systemctl is-enabled --quiet mem-snapshot.timer 2>/dev/null; then
  sudo -n systemctl enable mem-snapshot.timer 2>&1 | grep -v "Created symlink" || true
  log "Enabled: mem-snapshot.timer"
fi
if ! systemctl is-active --quiet mem-snapshot.timer 2>/dev/null; then
  sudo -n systemctl start mem-snapshot.timer || warn "Falha ao iniciar mem-snapshot.timer"
  log "Started: mem-snapshot.timer"
fi

# Aurora 2.2: oom-postmortem.service (oneshot por boot)
# Enabled mas NÃO start aqui — só dispara automaticamente no próximo boot via WantedBy=multi-user.target
if ! systemctl is-enabled --quiet oom-postmortem.service 2>/dev/null; then
  sudo -n systemctl enable oom-postmortem.service 2>&1 | grep -v "Created symlink" || true
  log "Enabled: oom-postmortem.service (roda no próximo boot)"
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

# 6. Userscripts (deploy idempotente: ~/.config/zsh/aurora/userscripts/ -> ~/userscripts/)
if [ -x "$AURORA_REPO/aurora-userscripts-apply.sh" ]; then
  "$AURORA_REPO/aurora-userscripts-apply.sh" | sed 's/^/[bootstrap] /' || warn "userscripts-apply retornou erro (não bloqueia)"
fi

# 6b. Chrome extensions unpacked (injeta --load-extension no .desktop do Chrome)
if [ -x "$AURORA_REPO/aurora-chrome-extensions-apply.sh" ]; then
  "$AURORA_REPO/aurora-chrome-extensions-apply.sh" | sed 's/^/[bootstrap] /' || warn "chrome-extensions-apply retornou erro (não bloqueia)"
fi

# 6c. Chrome dpkg-divert + policy de IA (requer sudo; idempotente)
if [ -x "$AURORA_REPO/aurora-chrome-divert-apply.sh" ]; then
  "$AURORA_REPO/aurora-chrome-divert-apply.sh" | sed 's/^/[bootstrap] /' || warn "chrome-divert-apply retornou erro (não bloqueia)"
fi

# 6d. User services (gradia-autosave, imagens-router) — instala em
# ~/.config/systemd/user/ a partir dos templates em aurora/units/
if [ -x "$AURORA_REPO/aurora-user-services-apply.sh" ]; then
  "$AURORA_REPO/aurora-user-services-apply.sh" | sed 's/^/[bootstrap] /' || warn "user-services-apply retornou erro (não bloqueia)"
fi

# 6e. Atalho Ctrl+Alt+0 -> aurora-gpu-revive (xbindkeys, dispara com a tela travada)
if [ -x "$AURORA_REPO/aurora-gpu-shortcut-apply.sh" ]; then
  "$AURORA_REPO/aurora-gpu-shortcut-apply.sh" | sed 's/^/[bootstrap] /' || warn "gpu-shortcut-apply retornou erro (não bloqueia)"
fi

# 6f. Editor de texto estilo Notepad (gnome-text-editor padrão + restore-session)
if [ -x "$AURORA_REPO/aurora-editor-apply.sh" ]; then
  "$AURORA_REPO/aurora-editor-apply.sh" | sed 's/^/[bootstrap] /' || warn "editor-apply retornou erro (não bloqueia)"
fi

# 7. Sunset do ritual antigo (so se ainda ativo)
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
