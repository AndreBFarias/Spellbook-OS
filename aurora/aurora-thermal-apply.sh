#!/bin/bash
# Aurora 2.9 - Thermal apply: ryzenadj (levers de potencia) + NBFC (fan agressiva
#   anti-calor) + ec_sys + higiene termica. Idempotente.
# Chamado por aurora-bootstrap.sh (DEFAULT, sem flag) e por aurora-self-heal no drift.
#
# Contexto (medido 2026-07-11): Nitro AN515-47 ventila mal; carga total -> 97C em 3s.
# platform_profile=performance e REJEITADO pelo EC; ryzenadj CO e rejeitado pelo SMU,
# mas tctl-temp/PPT funcionam. Secure Boot OFF -> ec_sys/NBFC carregam a quente.
# Dono não liga p/ ruido: fan SEMPRE agressiva. CPU inteligente fica no aurora-switcher.
set -u

AURORA_REPO="/home/andrefarias/.config/zsh/aurora"
NBFC_CFG_NAME="Acer Nitro AN515-47 Aurora"
NBFC_CFG_SRC="$AURORA_REPO/nbfc/${NBFC_CFG_NAME}.json"
NBFC_CFG_DST="/usr/share/nbfc/configs/${NBFC_CFG_NAME}.json"

log()  { printf '[thermal-apply] %s\n' "$*"; }
warn() { printf '[thermal-apply][WARN] %s\n' "$*" >&2; }
_have(){ command -v "$1" >/dev/null 2>&1; }

# --- 1. ryzenadj (build-if-missing). Lever de PPT/tctl-temp; CO rejeitado pelo SMU. ---
if ! _have ryzenadj; then
  log "ryzenadj ausente -> build from source"
  sudo -n DEBIAN_FRONTEND=noninteractive apt-get install -y cmake build-essential libpci-dev git >/dev/null 2>&1
  d=$(mktemp -d)
  if git clone --depth 1 https://github.com/FlyGoat/RyzenAdj "$d/r" >/dev/null 2>&1; then
    if ( cd "$d/r" && mkdir -p build && cd build \
         && cmake -DCMAKE_BUILD_TYPE=Release .. >/dev/null 2>&1 \
         && make -j"$(nproc)" >/dev/null 2>&1 \
         && sudo -n make install >/dev/null 2>&1 && sudo -n ldconfig ); then
      log "ryzenadj instalado (/usr/local/bin)"
    else warn "build ryzenadj falhou"; fi
  else warn "git clone ryzenadj falhou (sem rede?)"; fi
  rm -rf "$d"
fi

# --- 2. NBFC-Linux (build-if-missing). Controle direto de fan via EC. ---
if ! _have nbfc; then
  log "nbfc ausente -> build from source"
  sudo -n DEBIAN_FRONTEND=noninteractive apt-get install -y make gcc liblua5.4-dev libxml2-dev libcurl4-openssl-dev git >/dev/null 2>&1
  d=$(mktemp -d)
  if git clone --depth 1 https://github.com/nbfc-linux/nbfc-linux "$d/n" >/dev/null 2>&1; then
    if ( cd "$d/n" && make >/dev/null 2>&1 && sudo -n make install >/dev/null 2>&1 ); then
      log "nbfc instalado"
    else warn "build nbfc falhou"; fi
  else warn "git clone nbfc falhou (sem rede?)"; fi
  rm -rf "$d"
fi

# --- 3. ec_sys write_support (persistente + a quente; SB off nesta maquina) ---
printf 'ec_sys\n' | sudo -n tee /etc/modules-load.d/ec_sys.conf >/dev/null 2>&1
printf 'options ec_sys write_support=1\n' | sudo -n tee /etc/modprobe.d/ec_sys.conf >/dev/null 2>&1
if ! lsmod | grep -q '^ec_sys'; then
  sudo -n modprobe ec_sys write_support=1 2>/dev/null && log "ec_sys carregado (write_support=1)" || warn "modprobe ec_sys falhou"
fi

# --- 4. Config agressiva + seleção (idempotente) ---
if [ -f "$NBFC_CFG_SRC" ] && _have nbfc; then
  sudo -n mkdir -p /usr/share/nbfc/configs
  if ! sudo -n cmp -s "$NBFC_CFG_SRC" "$NBFC_CFG_DST" 2>/dev/null; then
    sudo -n install -m 0644 "$NBFC_CFG_SRC" "$NBFC_CFG_DST" && log "config NBFC agressiva instalada"
  fi
  if ! grep -qF "$NBFC_CFG_NAME" /etc/nbfc/nbfc.json 2>/dev/null; then
    sudo -n nbfc config --set "$NBFC_CFG_NAME" >/dev/null 2>&1 && log "config selecionada: $NBFC_CFG_NAME"
  fi
else
  warn "config agressiva ou nbfc ausente -> pulando seleção"
fi

# --- 5. nbfc_service (systemd enable+start; fallback nbfc start) ---
_nbfc_unit=""
for u in nbfc_service.service nbfc.service; do
  systemctl list-unit-files "$u" >/dev/null 2>&1 && { _nbfc_unit="$u"; break; }
done
if [ -n "$_nbfc_unit" ]; then
  systemctl is-enabled --quiet "$_nbfc_unit" 2>/dev/null || sudo -n systemctl enable "$_nbfc_unit" >/dev/null 2>&1
  if ! systemctl is-active --quiet "$_nbfc_unit" 2>/dev/null; then
    sudo -n nbfc stop >/dev/null 2>&1   # mata daemon manual (nbfc start) se houver -> evita 2 daemons
    sudo -n systemctl start "$_nbfc_unit" >/dev/null 2>&1 && log "$_nbfc_unit iniciado"
  fi
elif _have nbfc; then
  nbfc status >/dev/null 2>&1 || { sudo -n nbfc start >/dev/null 2>&1 && log "nbfc start (sem unit systemd)"; }
fi

# --- 5b. Auto-switcher (CPU inteligente): script + units + timer (idempotente) ---
if [ -f "$AURORA_REPO/aurora-switcher" ]; then
  if ! sudo -n cmp -s "$AURORA_REPO/aurora-switcher" /usr/local/sbin/aurora-switcher 2>/dev/null; then
    sudo -n install -m 0755 "$AURORA_REPO/aurora-switcher" /usr/local/sbin/aurora-switcher && log "aurora-switcher instalado"
  fi
  _changed=0
  for u in aurora-switcher.service aurora-switcher.timer; do
    if ! sudo -n cmp -s "$AURORA_REPO/units/$u" "/etc/systemd/system/$u" 2>/dev/null; then
      sudo -n install -m 0644 "$AURORA_REPO/units/$u" "/etc/systemd/system/$u" && { log "unit $u instalada"; _changed=1; }
    fi
  done
  [ "$_changed" -eq 1 ] && sudo -n systemctl daemon-reload
  systemctl is-enabled --quiet aurora-switcher.timer 2>/dev/null || sudo -n systemctl enable aurora-switcher.timer >/dev/null 2>&1
  systemctl is-active  --quiet aurora-switcher.timer 2>/dev/null || { sudo -n systemctl start aurora-switcher.timer >/dev/null 2>&1 && log "aurora-switcher.timer iniciado"; }
fi

# --- 6. Higiene: thermald e no-op em AMD -> mascara (blinda contra reativacao por apt) ---
if [ "$(systemctl is-enabled thermald 2>/dev/null)" != "masked" ]; then
  sudo -n systemctl disable --now thermald >/dev/null 2>&1
  sudo -n systemctl mask thermald >/dev/null 2>&1 && log "thermald mascarado (no-op em AMD)"
fi

log "thermal-apply concluido"
exit 0
