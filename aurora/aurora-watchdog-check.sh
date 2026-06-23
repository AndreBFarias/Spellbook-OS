#!/bin/bash
# Aurora 2.0 - Watchdog: detecta desvio e re-aplica
# Invocado pelo aurora-watchdog.timer (a cada 15min)
set -u

log() { printf '[aurora-watchdog] %s\n' "$*"; }

ALVO_GOVERNOR="powersave"   # Aurora 2.6: governor dinâmico (laptop-friendly)
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

# Aurora 2.6 - suspend e downclock em idle agora são PERMITIDOS (laptop-friendly):
# removidos os checks de anti-suspend (targets mascarados + logind) e de CPU pinned.

# boost = 1
if [ -f /sys/devices/system/cpu/cpufreq/boost ]; then
  b=$(cat /sys/devices/system/cpu/cpufreq/boost)
  if [ "$b" != "1" ]; then
    log "DESVIO: boost=$b (esperado: 1)"
    desviou=1
  fi
fi

# NVIDIA persistence-mode = Enabled
if command -v nvidia-smi >/dev/null 2>&1; then
  pm=$(nvidia-smi --query-gpu=persistence_mode --format=csv,noheader 2>/dev/null | head -1 | tr '[:upper:]' '[:lower:]')
  if [ -n "$pm" ] && [ "$pm" != "enabled" ]; then
    log "DESVIO: NVIDIA persistence-mode=$pm (esperado: Enabled)"
    desviou=1
  fi
fi

# Wi-Fi powersave off (Aurora 2.3 ULTRA) — checa drop-in NM
if [ ! -f /etc/NetworkManager/conf.d/99-aurora-ultra-wifi.conf ]; then
  log "DESVIO: drop-in NM 99-aurora-ultra-wifi.conf ausente"
  desviou=1
elif ! grep -q '^wifi.powersave *= *2' /etc/NetworkManager/conf.d/99-aurora-ultra-wifi.conf 2>/dev/null; then
  log "DESVIO: 99-aurora-ultra-wifi.conf sem wifi.powersave=2"
  desviou=1
fi

# default-wifi-powersave-on.conf sobrescreve por ordem alfabetica — não pode voltar
if [ -f /etc/NetworkManager/conf.d/default-wifi-powersave-on.conf ]; then
  log "DESVIO: default-wifi-powersave-on.conf reapareceu (sobrescreve nosso powersave=2)"
  desviou=1
fi

if [ $desviou -eq 1 ]; then
  log "Re-aplicando aurora-root-apply..."
  /usr/local/sbin/aurora-root-apply
else
  log "OK - sem desvio"
fi
exit 0
