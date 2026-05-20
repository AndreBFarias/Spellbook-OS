#!/bin/bash
# aurora-reapply-all.sh — Reaplica TODAS as features Aurora idempotentemente
#
# Invocado por: APT DPkg::Post-Invoke (via 99-aurora-postinvoke), sysupgrade,
# aurora-self-heal, ou manualmente após reinstalar pacote crítico.
#
# Estratégia:
#   1. aurora-bootstrap.sh --post-update --quiet  (cobre TUDO: sysctl, units, kernelstub se necessário,
#      apt hook, NetworkManager wifi-powersave, journald, earlyoom, dconf)
#   2. Sub-aplicadores user-space (sem sudo): chrome divert, extensions, user-services, userscripts
#   3. Logs em ~/.local/state/aurora-reapply.log
#
# Idempotente: pode rodar múltiplas vezes sem efeitos colaterais.
# Usa exit code 0 mesmo com warns (não bloqueia callers como apt).

set -u

AURORA="$HOME/.config/zsh/aurora"
LOG="${XDG_STATE_HOME:-$HOME/.local/state}/aurora-reapply.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG" >&2; }

log "=== aurora-reapply-all START ==="

# 1. Bootstrap consolidado (root-aware, decide internamente o que precisa sudo).
#    --post-update é o modo idempotente padrão.
if [ -x "$AURORA/aurora-bootstrap.sh" ]; then
    log ">> aurora-bootstrap.sh --post-update"
    bash "$AURORA/aurora-bootstrap.sh" --post-update --quiet 2>&1 | sed 's/^/   /' | tee -a "$LOG" >&2 || \
        log "WARN: bootstrap retornou erro (continuando)"
fi

# 2. Sub-aplicadores user-space, todos idempotentes.
#    Ordem importa: divert antes de extensions (extensions usa o symlink resultante).
SUB_APPLIERS=(
    aurora-chrome-divert-apply.sh
    aurora-chrome-extensions-apply.sh
    aurora-user-apply.sh
    aurora-user-services-apply.sh
    aurora-userscripts-apply.sh
)

for sub in "${SUB_APPLIERS[@]}"; do
    if [ -x "$AURORA/$sub" ]; then
        log ">> $sub"
        "$AURORA/$sub" 2>&1 | sed 's/^/   /' | tee -a "$LOG" >&2 || \
            log "WARN: $sub retornou erro (continuando)"
    fi
done

# 3. Reload de daemons (idempotente; ignora se não há mudança real).
if command -v dconf >/dev/null 2>&1; then
    sudo -n dconf update 2>/dev/null && log ">> dconf update OK"
fi
sudo -n systemctl daemon-reload 2>/dev/null && log ">> systemctl daemon-reload OK"
systemctl --user daemon-reload 2>/dev/null && log ">> systemctl --user daemon-reload OK"

log "=== aurora-reapply-all END ==="
exit 0
