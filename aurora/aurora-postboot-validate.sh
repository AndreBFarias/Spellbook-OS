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
PARAMS_OBRIGATORIOS=(amd_pstate=active processor.max_cstate=1 mitigations=off transparent_hugepage=madvise nvidia.NVreg_PreserveVideoMemoryAllocations=1)
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
