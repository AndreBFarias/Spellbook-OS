#!/bin/zsh
# termico.zsh — leitura e controle térmico (Aurora 2.8)
# Comandos:
#   temp    -> readout de todos os sensores + modo/governor atual
#   cool    -> modo dinâmico (governor powersave + EPP balance_performance): esfria idle/carga-leve, turbo intacto
#   perf    -> volta ao modo performance (postura Aurora histórica)
#   travou  -> fallback do Ctrl+Alt+0: recupera o display AMD travado sem reboot
# Ver DOSSIE-2026-07-09-termico-e-freeze.md e AURORA-2.6-THERMAL.md.

AURORA_SENTINEL="/etc/aurora/allow-powersave"
AURORA_APPLY="/usr/local/sbin/aurora-root-apply"

# --- helper: lê um arquivo de hwmon pelo nome do chip -----------------------
__hw_read() {  # __hw_read <nome-do-chip> <arquivo>   ex: __hw_read k10temp temp1_input
  local h
  for h in /sys/class/hwmon/hwmon*; do
    [ "$(cat "$h/name" 2>/dev/null)" = "$1" ] || continue
    [ -r "$h/$2" ] && { cat "$h/$2" 2>/dev/null; return 0; }
  done
  return 1
}
__mC2C() { [ -n "$1" ] && awk -v m="$1" 'BEGIN{printf "%.1f", m/1000}'; }  # milli-Celsius -> C
__col_temp() {  # colore por faixa: <75 verde, 75-90 amarelo, >90 vermelho
  local t="${1%%.*}"
  if   [ "${t:-0}" -ge 90 ]; then printf '%s' "$D_RED"
  elif [ "${t:-0}" -ge 75 ]; then printf '%s' "$D_YELLOW"
  else printf '%s' "$D_GREEN"; fi
}

temp() {
  __header "Estado térmico — $(hostname)" "$D_CYAN"

  # modo/governor
  local gov epp modo
  gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo '?')
  epp=$(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null || echo '?')
  if [ -e "$AURORA_SENTINEL" ]; then modo="${D_GREEN}COOL${D_RESET} (dinâmico)"; else modo="${D_ORANGE}PERF${D_RESET} (performance)"; fi
  __item "modo" "$(echo -e "$modo")"
  __item "governor" "$gov / EPP $epp"

  # CPU (k10temp Tctl) + acpitz (chassi)
  local tctl acpi cpuc
  tctl=$(__mC2C "$(__hw_read k10temp temp1_input)")
  acpi=$(__mC2C "$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)")
  cpuc="$(__col_temp "$tctl")"
  [ -n "$tctl" ] && __item "CPU (Tctl)" "$(echo -e "${cpuc}${tctl} C${D_RESET}")"
  [ -n "$acpi" ] && __item "chassi" "${acpi} C"

  # iGPU AMD
  local amt amp
  amt=$(__mC2C "$(__hw_read amdgpu temp1_input)")
  amp=$(__hw_read amdgpu power1_average)
  [ -n "$amt" ] && __item "iGPU AMD" "${amt} C$([ -n "$amp" ] && awk -v p="$amp" 'BEGIN{printf " / %.1f W", p/1000000}')"

  # dGPU NVIDIA
  if command -v nvidia-smi >/dev/null 2>&1; then
    local nv; nv=$(nvidia-smi --query-gpu=temperature.gpu,power.draw --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')
    [ -n "$nv" ] && __item "dGPU RTX" "$(echo "$nv" | awk -F, '{printf "%s C / %s W", $1, $2}')"
  fi

  # NVMe (mostra o mais quente dos dois)
  local nmax=0 h t
  for h in /sys/class/hwmon/hwmon*; do
    [ "$(cat "$h/name" 2>/dev/null)" = "nvme" ] || continue
    t=$(cat "$h/temp1_input" 2>/dev/null); [ -n "$t" ] && [ "$t" -gt "$nmax" ] && nmax="$t"
  done
  [ "$nmax" -gt 0 ] && __item "NVMe (max)" "$(__mC2C "$nmax") C"

  # Fans: RPM real via acer-wmi (predator_v4). Fallback: inferência se ausente.
  local fan1 fan2 pp
  fan1=$(cat /sys/devices/platform/acer-wmi/hwmon/hwmon*/fan1_input 2>/dev/null | head -1)
  fan2=$(cat /sys/devices/platform/acer-wmi/hwmon/hwmon*/fan2_input 2>/dev/null | head -1)
  pp=$(cat /sys/firmware/acpi/platform_profile 2>/dev/null)
  echo ""
  if [ -n "$fan1" ]; then
    __item "fans CPU/GPU" "${fan1} / ${fan2} RPM"
    __item "perfil fan" "${pp:-?} (agressivo = balanced-performance)"
  elif [ -n "$tctl" ] && [ "${tctl%%.*}" -lt 90 ]; then
    __ok "fans OK (inferido): CPU ${tctl} C sob controle. RPM só com acer_wmi predator_v4=1."
  else
    __warn "CPU alta (${tctl} C) e sem readout de RPM — verifique refrigeração/dust."
  fi
  echo -e "  ${D_COMMENT}alternar:  cool  (frio) | perf (turbo pinado) | travou (display travado)${D_RESET}"
  echo ""
}

# --- toggle modo COOL (powersave + balance_performance) ---------------------
cool() {
  __header "Aplicando modo COOL (dinâmico, frio)" "$D_GREEN"
  sudo mkdir -p /etc/aurora && sudo touch "$AURORA_SENTINEL" || { __err "falha criando sentinela"; return 1; }
  if sudo "$AURORA_APPLY"; then
    __ok "modo COOL ativo — governor powersave + EPP balance_performance (turbo sob carga intacto)."
    __ok "o watchdog agora respeita esta escolha (não reverte)."
  else
    __err "aurora-root-apply falhou"; return 1
  fi
  temp
}

perf() {
  __header "Voltando ao modo PERFORMANCE" "$D_ORANGE"
  sudo rm -f "$AURORA_SENTINEL" || { __err "falha removendo sentinela"; return 1; }
  if sudo "$AURORA_APPLY"; then
    __ok "modo PERFORMANCE ativo — governor performance pinado (postura Aurora histórica)."
  else
    __err "aurora-root-apply falhou"; return 1
  fi
  temp
}

# --- fallback do botão de pânico Ctrl+Alt+0 (display AMD travado) ------------
travou() {
  local trig="$HOME/.config/zsh/aurora/aurora-gpu-revive-trigger"
  __warn "recuperando display AMD (equivale ao Ctrl+Alt+0)..."
  if [ -x "$trig" ]; then "$trig"; else sudo -n /usr/local/sbin/aurora-gpu-revive; fi
}
