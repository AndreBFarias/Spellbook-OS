#!/bin/bash
# Aurora 2.0 - Watchdog: detecta desvio e re-aplica
# Invocado pelo aurora-watchdog.timer (a cada 15min)
set -u

log() { printf '[aurora-watchdog] %s\n' "$*"; }

ALVO_GOVERNOR="performance"   # mantido em performance (escolha do usuário)
ALVO_S76="performance"
# Aurora 2.8 - respeita o modo COOL (sentinela /etc/aurora/allow-powersave). Sob ele,
# o esperado passa a ser powersave/balanced, entao o watchdog NÃO trata a escolha do
# usuário como desvio (nem a reverte a cada 15min). Ver DOSSIE-2026-07-09 / comando `cool`.
if [ -e /etc/aurora/allow-powersave ]; then
  ALVO_GOVERNOR="powersave"
  ALVO_S76="balanced"
fi
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
  if [ "$prof" != "$ALVO_S76" ]; then
    log "DESVIO: system76-power=$prof (esperado: $ALVO_S76)"
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

# Aurora 2.8 - platform_profile agressivo (fans). Re-assere apos resume/drift (o EC
# costuma resetar o perfil ao voltar do suspend). Requer acer_wmi predator_v4=1.
PP=/sys/firmware/acpi/platform_profile
if [ -e "$PP" ] && [ "$(cat "$PP" 2>/dev/null)" != "balanced-performance" ]; then
  log "DESVIO: platform_profile=$(cat "$PP" 2>/dev/null) (esperado: balanced-performance)"
  desviou=1
fi

# Aurora 2.8 - guarda de divergencia: o watchdog roda do repo, mas re-aplica a copia
# instalada em /usr/local/sbin (so atualizada por aurora-bootstrap.sh). Se divergirem,
# uma edicao de politica no repo não teria efeito -> torna o drift visivel no journal.
REPO_APPLY="/home/andrefarias/.config/zsh/aurora/aurora-root-apply"
if [ -f "$REPO_APPLY" ] && ! cmp -s "$REPO_APPLY" /usr/local/sbin/aurora-root-apply; then
  log "AVISO: /usr/local/sbin/aurora-root-apply difere do repo -- rode aurora/aurora-bootstrap.sh"
fi

if [ $desviou -eq 1 ]; then
  log "Re-aplicando aurora-root-apply..."
  if /usr/local/sbin/aurora-root-apply; then
    log "re-apply OK"
  else
    rc=$?
    log "ERRO: aurora-root-apply falhou (rc=$rc)"
    exit 1
  fi
else
  log "OK - sem desvio"
fi
exit 0
