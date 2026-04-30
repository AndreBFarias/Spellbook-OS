#!/bin/bash
# Aurora 2.0 - User tunings (NVIDIA performance mode em sessão grafica)
# Invocado por aurora-user.service (--user)
set -u

log() { printf '[aurora-user] %s\n' "$*"; }
warn() { printf '[aurora-user][WARN] %s\n' "$*" >&2; }

# Aguardar DISPLAY ate 30s (X11/Mutter pode não estar pronto no inicio)
for i in $(seq 1 30); do
  if [ -n "${DISPLAY:-}" ] && xset q >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if [ -z "${DISPLAY:-}" ]; then
  warn "DISPLAY não setado apos 30s, abortando NVIDIA tuning"
  exit 0
fi

if ! command -v nvidia-settings >/dev/null 2>&1; then
  warn "nvidia-settings não encontrado"
  exit 0
fi

# GpuPowerMizerMode: 0=Adaptive, 1=Performance, 2=Auto
saida=$(nvidia-settings -a '[gpu:0]/GpuPowerMizerMode=1' 2>&1) && \
  log "GpuPowerMizerMode=1 (Performance) aplicado" || \
  warn "nvidia-settings falhou: $saida"

# Persistence mode (mantem driver carregado, evita re-init custoso)
if command -v nvidia-smi >/dev/null 2>&1; then
  if nvidia-smi -pm 1 >/dev/null 2>&1; then
    log "nvidia-smi persistence mode ativado"
  else
    log "nvidia-smi -pm 1 falhou (precisa root) - skip"
  fi
fi

log "aurora-user-apply concluido"

# Post-boot validation: gera AURORA-OK.md ou AURORA-ERRO.md no Desktop quando relevante
if [ -x "$HOME/.config/zsh/aurora/aurora-postboot-validate.sh" ]; then
  "$HOME/.config/zsh/aurora/aurora-postboot-validate.sh" || warn "postboot-validate falhou (não bloqueia)"
fi

exit 0
