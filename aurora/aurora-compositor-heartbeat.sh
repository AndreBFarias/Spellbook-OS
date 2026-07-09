#!/bin/bash
# Aurora 2.8 - aurora-compositor-heartbeat: detecta hang SILENCIOSO do compositor
# ---------------------------------------------------------------------------
# Pega o freeze que o amdgpu-dmcub-watchdog NÃO pega: tela estatica, cursor do
# mouse ainda mexe, ZERO erro no kernel (o "estado morto residual"). Foi esse o
# caso do freeze de 2026-07-09 (ver DOSSIE-2026-07-09-termico-e-freeze.md).
#
# Mecanismo: ping D-Bus no main loop do gnome-shell a cada CHECK_S. O ping
# org.freedesktop.DBus.Peer.Ping e servido pelo próprio main loop -> loop travado
# não responde e o ping estoura o timeout. FAILS_TRIGGER falhas consecutivas =
# hang confirmado -> dispara o aurora-gpu-revive-trigger (o MESMO do Ctrl+Alt+0).
#
# Seguranca:
#   - so X11 (no Wayland gnome-shell --replace não se aplica; no-op gracioso).
#   - cooldown + teto/hora (recidiva pausa o auto-recover e alerta no Desktop).
#   - cooldown (120s) >> REPEAT_S do revive (15s) -> NUNCA escala pro restart
#     destrutivo de sessão por acidente; sempre a recuperação leve (gpu_recover
#     + gnome-shell --replace, que no X11 PRESERVA as janelas/apps).
#   - kill-switch: ~/.config/aurora-no-hb ou /etc/aurora/no-compositor-hb.
#   - singleton: no-op se outra instancia ja roda.
#
# Roda na sessão grafica do usuário (autostart, como o xbindkeys). Tag: aurora-compositor-hb.
set -u

CHECK_S=10          # intervalo entre pings
PING_TIMEOUT=5      # timeout de cada ping (loop travado não responde a tempo)
FAILS_TRIGGER=3     # N falhas consecutivas (~30s) = hang confirmado
COOLDOWN_S=120      # não recupera de novo dentro disso
MAX_PER_HOUR=4      # acima disso, para de auto-recuperar e alerta

LOG_TAG="aurora-compositor-hb"
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/aurora-compositor-hb"
HIST="$STATE_DIR/recover_history"
TRIGGER="$HOME/.config/zsh/aurora/aurora-gpu-revive-trigger"
ALERT="$HOME/Desktop/AURORA-GPU-AVISO.md"

log() { logger -t "$LOG_TAG" "$*" 2>/dev/null; }

# --- kill-switch -----------------------------------------------------------
[ -e "$HOME/.config/aurora-no-hb" ] || [ -e /etc/aurora/no-compositor-hb ] && { log "kill-switch ativo -> heartbeat desativado"; exit 0; }

# --- so X11 ----------------------------------------------------------------
if [ "${XDG_SESSION_TYPE:-x11}" != "x11" ]; then
  log "sessão ${XDG_SESSION_TYPE:-?} (não-X11) -> heartbeat desativado"
  exit 0
fi

# --- singleton (evita instancias duplicadas de logins repetidos) -----------
me="$(basename "$0")"
others=$(pgrep -fc "$me" 2>/dev/null || echo 1)
[ "${others:-1}" -gt 1 ] && { log "outra instancia ja roda -> saindo"; exit 0; }

command -v gdbus >/dev/null 2>&1 || { log "gdbus ausente -> heartbeat não pode rodar"; exit 0; }
mkdir -p "$STATE_DIR" 2>/dev/null
touch "$HIST" 2>/dev/null

ping_shell() {
  timeout "$PING_TIMEOUT" gdbus call --session \
    --dest org.gnome.Shell --object-path /org/gnome/Shell \
    --method org.freedesktop.DBus.Peer.Ping >/dev/null 2>&1
}

log "heartbeat iniciado (check=${CHECK_S}s timeout=${PING_TIMEOUT}s gatilho=${FAILS_TRIGGER} falhas)"
fails=0
last_recover=0

while true; do
  if ping_shell; then
    fails=0
  else
    fails=$((fails + 1))
    log "ping do gnome-shell falhou ($fails/$FAILS_TRIGGER)"
    if [ "$fails" -ge "$FAILS_TRIGGER" ]; then
      now=$(date +%s)
      if [ $(( now - last_recover )) -lt "$COOLDOWN_S" ]; then
        log "hang detectado, mas em cooldown ($(( now - last_recover ))s < ${COOLDOWN_S}s)"
      else
        # teto por hora
        hour_ago=$(( now - 3600 ))
        recent=$(awk -v t="$hour_ago" '$1+0 >= t' "$HIST" 2>/dev/null | wc -l)
        if [ "$recent" -ge "$MAX_PER_HOUR" ]; then
          log "ALERTA: ${recent} recoveries/1h -- recidiva (hardware/driver). Auto-recover PAUSADO 5min."
          cat > "$ALERT" 2>/dev/null <<EOF
# Aurora - display travando com frequencia

O compositor (gnome-shell) travou e foi auto-recuperado ${recent}x na última hora.
Recorrencia assim aponta hardware/driver -- auto-recover pausado para não mascarar.

Ações:
- Atualizar firmware/kernel: sudo apt install --reinstall linux-firmware && reboot.
- Considere desligar PSR (suspeito de freeze silencioso de display AMD):
  sudo kernelstub --add-options "amdgpu.dcdebugmask=0x10"  (requer reboot).
- Logs deste heartbeat: journalctl -t $LOG_TAG -n 100

Remova este arquivo apos resolver.
EOF
          fails=0
          sleep 300
          continue
        fi
        log "hang do compositor CONFIRMADO (${fails} pings sem resposta) -> recuperando (equivale ao Ctrl+Alt+0)"
        if [ -x "$TRIGGER" ]; then
          "$TRIGGER" >/dev/null 2>&1 || log "trigger de recuperação falhou"
        else
          log "trigger $TRIGGER não encontrado/executavel"
        fi
        echo "$now" >> "$HIST"
        # poda histórico > 1h
        awk -v t="$hour_ago" '$1+0 >= t' "$HIST" > "${HIST}.tmp" 2>/dev/null && mv "${HIST}.tmp" "$HIST"
        last_recover="$now"
        fails=0
        sleep 15   # da tempo do compositor voltar antes de re-avaliar
      fi
    fi
  fi
  sleep "$CHECK_S"
done
