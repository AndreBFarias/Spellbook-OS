#!/bin/bash
# Aurora 2.0 - Watchdog: detecta desvio e re-aplica
# Invocado pelo aurora-watchdog.timer (a cada 15min)
set -u

log() { printf '[aurora-watchdog] %s\n' "$*"; }

ALVO_GOVERNOR="performance"
desviou=0

# Verifica governor
gov_atual=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "?")
if [ "$gov_atual" != "$ALVO_GOVERNOR" ]; then
  log "DESVIO: governor=$gov_atual (esperado: $ALVO_GOVERNOR)"
  desviou=1
fi

# Verifica system76-power profile
if command -v system76-power >/dev/null 2>&1; then
  prof=$(system76-power profile 2>/dev/null | awk -F': ' '/Power Profile/ {print tolower($2)}')
  if [ "$prof" != "performance" ]; then
    log "DESVIO: system76-power=$prof (esperado: performance)"
    desviou=1
  fi
fi

# Verifica earlyoom
if ! systemctl is-active --quiet earlyoom.service; then
  log "DESVIO: earlyoom inativo"
  desviou=1
fi

if [ $desviou -eq 1 ]; then
  log "Re-aplicando aurora-root-apply..."
  /usr/local/sbin/aurora-root-apply
else
  log "OK - sem desvio"
fi
exit 0
