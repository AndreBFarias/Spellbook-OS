#!/bin/bash
# Aurora 2.0 - Validador pos-boot
#
# Comportamento:
#   - Roda os 3 grupos de checks (kernel cmdline, services root, service user)
#   - Mantem estado em ~/.config/zsh/aurora/.last-status (primeira-execucao | ok | erro)
#   - Maquina de estados:
#       primeira-execucao + OK    -> cria AURORA-OK.md (uma unica vez, anuncia)
#       ok-anterior + OK          -> remove qualquer AURORA-* do Desktop (silencio)
#       erro-anterior + OK        -> cria AURORA-OK.md (consertou!), remove ERRO
#       qualquer-anterior + ERRO  -> cria AURORA-ERRO.md com contexto pro Claude
#
# Arquivos no Desktop sao notificacoes leves: aparecem so quando ha algo a comunicar.

set -u

# Garante env de user dbus/runtime para systemctl --user funcionar fora de sessão gráfica
if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
  export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -S "$XDG_RUNTIME_DIR/bus" ]; then
  export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
fi
if [ -S "${XDG_RUNTIME_DIR:-/dev/null}/bus" ]; then
  USER_BUS_OK=1
else
  USER_BUS_OK=0
fi

DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
STATUS_FILE="$HOME/.config/zsh/aurora/.last-status"
OK_FILE="$DESKTOP_DIR/AURORA-OK.md"
ERR_FILE="$DESKTOP_DIR/AURORA-ERRO.md"

mkdir -p "$DESKTOP_DIR"

last="primeira-execucao"
[ -f "$STATUS_FILE" ] && last=$(cat "$STATUS_FILE" 2>/dev/null || echo "primeira-execucao")

falhas=()
contexto_blocks=""

add_contexto() {
  contexto_blocks="${contexto_blocks}$1
"
}

# --- Check 1: kernel cmdline (kernelstub args ativos apos reboot) ---
cmdline=$(cat /proc/cmdline 2>/dev/null || echo "")
PARAMS_OBRIGATORIOS=(amd_pstate=active processor.max_cstate=1 mitigations=off transparent_hugepage=madvise nvidia.NVreg_PreserveVideoMemoryAllocations=1 pcie_aspm=off nvme_core.default_ps_max_latency_us=0)
faltando_kernel=()
for p in "${PARAMS_OBRIGATORIOS[@]}"; do
  echo "$cmdline" | grep -qF -- "$p" || faltando_kernel+=("$p")
done

if [ ${#faltando_kernel[@]} -gt 0 ]; then
  falhas+=("kernel cmdline faltando: ${faltando_kernel[*]}")
  add_contexto "### Kernel cmdline (esperado todos os 5 params)
\`\`\`
$cmdline
\`\`\`
**Faltando:** ${faltando_kernel[*]}

**Provaveis causas (em ordem):**
1. Reboot pendente apos bootstrap — kernelstub configurou mas precisa reiniciar
2. apt upgrade reverteu — \`apt-postinvoke hook\` deveria ter reaplicado
3. Bootstrap não rodou — checar \`~/.config/zsh/aurora/\`

**Correcao sugerida (escolha uma):**
\`\`\`bash
# Caso 1: so reboot
sudo reboot

# Caso 2 ou 3: re-rodar bootstrap, depois reboot
bash ~/.config/zsh/aurora/aurora-bootstrap.sh --post-update
sudo reboot

# Caso o kernelstub esteja realmente sem os params:
sudo kernelstub --print-config
sudo kernelstub --add-options \"${faltando_kernel[*]}\"
sudo reboot
\`\`\`
"
fi

# --- Check 2: services root ativos ---
SERVICES_ROOT=(aurora-root.service aurora-watchdog.timer earlyoom.service)
for s in "${SERVICES_ROOT[@]}"; do
  if ! systemctl is-active --quiet "$s" 2>/dev/null; then
    falhas+=("service inativo: $s")
    status_dump=$(systemctl status "$s" --no-pager 2>&1 | head -15)
    add_contexto "### $s
\`\`\`
$status_dump
\`\`\`
**Correcao sugerida:**
\`\`\`bash
sudo systemctl start $s
journalctl -u $s --no-pager -n 30
\`\`\`
"
  fi
done

# --- Check 3: aurora-user.service (só se houver dbus de usuário) ---
if [ $USER_BUS_OK -eq 1 ]; then
  if ! systemctl --user is-active --quiet aurora-user.service 2>/dev/null; then
    falhas+=("aurora-user.service inativo")
    status_dump=$(systemctl --user status aurora-user.service --no-pager 2>&1 | head -15)
    add_contexto "### aurora-user.service (NVIDIA tuning)
\`\`\`
$status_dump
\`\`\`
"
  fi
fi

# --- Check 4: ollama-vram-watchdog.timer (Aurora 2.1) ---
# Só verifica se ollama.service existe — sem ollama, watchdog não aplica
if [ -f /etc/systemd/system/ollama.service ] || [ -f /lib/systemd/system/ollama.service ]; then
  if ! systemctl is-active --quiet ollama-vram-watchdog.timer 2>/dev/null; then
    falhas+=("ollama-vram-watchdog.timer inativo")
    status_dump=$(systemctl status ollama-vram-watchdog.timer --no-pager 2>&1 | head -10)
    add_contexto "### ollama-vram-watchdog.timer (proteção VRAM)
\`\`\`
$status_dump
\`\`\`
"
  fi
fi

# --- Check 5: NVIDIA suspend/resume/hibernate enabled (Aurora 2.1) ---
# Só checa se o driver existe; warning, não bloqueia
if [ -f /lib/systemd/system/nvidia-suspend.service ]; then
  for s in nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service; do
    if ! systemctl is-enabled --quiet "$s" 2>/dev/null; then
      falhas+=("$s não habilitado (preserva VRAM em suspend/resume)")
    fi
  done
fi

# --- Check 6: aurora-health.timer (Aurora 2.1 - Round C) ---
if [ -f /etc/systemd/system/aurora-health.timer ]; then
  if ! systemctl is-active --quiet aurora-health.timer 2>/dev/null; then
    falhas+=("aurora-health.timer inativo (monitor SMART/thermal/disk)")
    status_dump=$(systemctl status aurora-health.timer --no-pager 2>&1 | head -10)
    add_contexto "### aurora-health.timer (monitor de saúde)
\`\`\`
$status_dump
\`\`\`
"
  fi
fi

# --- Check 7: mem-snapshot.timer (Aurora 2.2 - forensics de OOM) ---
if [ -f /etc/systemd/system/mem-snapshot.timer ]; then
  if ! systemctl is-active --quiet mem-snapshot.timer 2>/dev/null; then
    falhas+=("mem-snapshot.timer inativo (forensics de OOM)")
    status_dump=$(systemctl status mem-snapshot.timer --no-pager 2>&1 | head -10)
    add_contexto "### mem-snapshot.timer (snapshot CSV de memória + PSI a cada 30s)
\`\`\`
$status_dump
\`\`\`
"
  fi
fi

# --- Check 8: journald persistente (Aurora 2.2) ---
if [ -f /etc/systemd/journald.conf.d/00-persistent.conf ]; then
  machine_id=$(cat /etc/machine-id 2>/dev/null)
  if [ -n "$machine_id" ] && [ ! -d "/var/log/journal/$machine_id" ]; then
    falhas+=("journald persistente sem diretório /var/log/journal/$machine_id")
    add_contexto "### journald persistente
Diretório \`/var/log/journal/$machine_id\` ausente — journal cairá em /run (volátil).
Rode: \`sudo install -d -m 2755 -o root -g systemd-journal /var/log/journal/$machine_id && sudo systemctl restart systemd-journald\`
"
  fi
fi

# --- Check 9: oom-postmortem.service habilitado (Aurora 2.2) ---
if [ -f /etc/systemd/system/oom-postmortem.service ]; then
  if ! systemctl is-enabled --quiet oom-postmortem.service 2>/dev/null; then
    falhas+=("oom-postmortem.service não habilitado (não dispara após crash)")
    add_contexto "### oom-postmortem.service
Rode: \`sudo systemctl enable oom-postmortem.service\`
"
  fi
fi

# --- Check 10: Aurora 2.3 ULTRA — anti-suspend (logind drop-in + targets mascarados) ---
if [ ! -f /etc/systemd/logind.conf.d/99-no-suspend.conf ]; then
  falhas+=("logind drop-in 99-no-suspend.conf ausente (USB não carrega em suspend)")
  add_contexto "### Anti-suspend (Aurora 2.3 ULTRA)
\`/etc/systemd/logind.conf.d/99-no-suspend.conf\` ausente.
Rode: \`bash ~/.config/zsh/aurora/aurora-bootstrap.sh --post-update\`
"
fi

SLEEP_TARGETS_CHECK=(sleep.target suspend.target hibernate.target hybrid-sleep.target)
sleep_nao_mascarados=()
for t in "${SLEEP_TARGETS_CHECK[@]}"; do
  if [ "$(systemctl is-enabled "$t" 2>/dev/null)" != "masked" ]; then
    sleep_nao_mascarados+=("$t")
  fi
done
if [ ${#sleep_nao_mascarados[@]} -gt 0 ]; then
  falhas+=("sleep targets não mascarados: ${sleep_nao_mascarados[*]}")
  add_contexto "### Sleep targets não mascarados
Rode: \`sudo systemctl mask ${sleep_nao_mascarados[*]}\`
"
fi

# --- Check 11: Aurora 2.3 ULTRA — CPU pinned + boost + NVIDIA pm ---
if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq ]; then
  cmax=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq)
  cmin=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq)
  if [ "$cmin" != "$cmax" ]; then
    falhas+=("CPU não pinned: scaling_min($cmin) != scaling_max($cmax)")
  fi
fi

if [ -f /sys/devices/system/cpu/cpufreq/boost ]; then
  bst=$(cat /sys/devices/system/cpu/cpufreq/boost)
  if [ "$bst" != "1" ]; then
    falhas+=("cpufreq/boost=$bst (esperado 1)")
  fi
fi

if command -v nvidia-smi >/dev/null 2>&1; then
  nv_pm=$(nvidia-smi --query-gpu=persistence_mode --format=csv,noheader 2>/dev/null | head -1 | tr '[:upper:]' '[:lower:]')
  if [ -n "$nv_pm" ] && [ "$nv_pm" != "enabled" ]; then
    falhas+=("NVIDIA persistence-mode=$nv_pm (esperado Enabled)")
  fi
fi

# --- Check 12: Userscripts e extensions deployados (Aurora userscripts) ---
USERSCRIPTS_SRC="$HOME/.config/zsh/aurora/userscripts"
USERSCRIPTS_DST="$HOME/userscripts"
if [ -d "$USERSCRIPTS_SRC" ]; then
  faltando_us=()
  divergente_us=()
  # hash agregado da arvore de um diretório
  _tree_hash() {
    ( cd "$1" 2>/dev/null && find . -type f ! -name '.*' -print0 | LC_ALL=C sort -z | xargs -0 sha256sum 2>/dev/null | sha256sum | awk '{print $1}' )
  }

  # arquivos .user.js
  for src in "$USERSCRIPTS_SRC"/*.user.js; do
    [ -f "$src" ] || continue
    name=$(basename "$src")
    dst="$USERSCRIPTS_DST/$name"
    if [ ! -f "$dst" ]; then faltando_us+=("$name"); continue; fi
    s_sum=$(sha256sum "$src" | awk '{print $1}')
    d_sum=$(sha256sum "$dst" | awk '{print $1}')
    [ "$s_sum" != "$d_sum" ] && divergente_us+=("$name")
  done

  # diretórios de extension (*-ext/)
  for srcd in "$USERSCRIPTS_SRC"/*-ext; do
    [ -d "$srcd" ] || continue
    name=$(basename "$srcd")
    dstd="$USERSCRIPTS_DST/$name"
    if [ ! -d "$dstd" ]; then faltando_us+=("$name/"); continue; fi
    s_th=$(_tree_hash "$srcd")
    d_th=$(_tree_hash "$dstd")
    [ "$s_th" != "$d_th" ] && divergente_us+=("$name/")
  done

  if [ ${#faltando_us[@]} -gt 0 ] || [ ${#divergente_us[@]} -gt 0 ]; then
    msg=""
    [ ${#faltando_us[@]} -gt 0 ] && msg="faltando: ${faltando_us[*]}"
    [ ${#divergente_us[@]} -gt 0 ] && msg="$msg divergente: ${divergente_us[*]}"
    falhas+=("userscripts $msg")
    add_contexto "### Userscripts/extensions (Aurora deploy)
Fonte: \`$USERSCRIPTS_SRC\`
Destino: \`$USERSCRIPTS_DST\`
${msg}

**Correcao:**
\`\`\`bash
bash ~/.config/zsh/aurora/aurora-userscripts-apply.sh
\`\`\`
"
  fi
fi

# --- Diagnostico final ---
if [ ${#falhas[@]} -eq 0 ]; then
  status_atual="ok"
else
  status_atual="erro"
fi

ts=$(date -Iseconds)

gerar_ok() {
  local titulo=$1
  cat > "$OK_FILE" <<EOF
# Aurora 2.0 — $titulo

**Data:** $ts
**Host:** $(hostname)
**Kernel:** $(uname -r)

Todos os checks pos-boot passaram. Pode apagar este arquivo a qualquer momento.

## Estado verificado

\`\`\`
$(cat /proc/cmdline | tr ' ' '\n' | grep -E "mitigations|max_cstate|amd_pstate|transparent_hugepage|NVreg_Preserve")
\`\`\`

\`\`\`
$(systemctl is-active aurora-root.service aurora-watchdog.timer earlyoom.service | paste -d' ' - <(echo aurora-root.service; echo aurora-watchdog.timer; echo earlyoom.service))
aurora-user.service: $([ $USER_BUS_OK -eq 1 ] && systemctl --user is-active aurora-user.service || echo "skipped (no user dbus)")
\`\`\`

Este arquivo so aparece quando: (a) e a primeira vez que tudo passa, ou (b) o sistema voltou ao normal apos um erro. Em boots seguintes com tudo OK, nada e gerado.
EOF
}

gerar_erro() {
  cat > "$ERR_FILE" <<EOF
# Aurora 2.0 — ERRO detectado pos-boot

**Data:** $ts
**Host:** $(hostname)
**Kernel:** $(uname -r)

## Como usar este arquivo

Abra um terminal, va para um diretório confortavel e rode:

\`\`\`bash
cca
\`\`\`

Cole o conteudo deste arquivo (todo) e peca para o Claude consertar. Ele tem contexto suficiente.

## Falhas detectadas (${#falhas[@]})

$(printf -- '- %s\n' "${falhas[@]}")

## Diagnostico detalhado

$contexto_blocks

## Onde investigar

- Logs do bootstrap: \`journalctl -u aurora-root.service -n 50\`
- Logs do watchdog: \`journalctl -u aurora-watchdog.service -n 50\`
- Repo aurora versionado: \`~/.config/zsh/aurora/\`
- Recovery doc: \`~/.config/zsh/aurora/RECOVERY.md\`
- Re-rodar bootstrap: \`bash ~/.config/zsh/aurora/aurora-bootstrap.sh --post-update\`
EOF
}

case "$last:$status_atual" in
  primeira-execucao:ok)
    gerar_ok "Tudo OK na primeira validação apos instalação"
    rm -f "$ERR_FILE"
    ;;
  ok:ok)
    rm -f "$OK_FILE" "$ERR_FILE"
    ;;
  erro:ok)
    gerar_ok "Sistema voltou ao normal (erro anterior corrigido)"
    rm -f "$ERR_FILE"
    ;;
  *:erro)
    gerar_erro
    rm -f "$OK_FILE"
    ;;
esac

echo "$status_atual" > "$STATUS_FILE"

# Sempre 0 - validador não deve quebrar o servico
exit 0
