#!/bin/bash
# aurora-ROLLBACK.sh — Reverte parcialmente as mudanças do aurora-bootstrap.
#
# Reverte (com --dry-run mostra o que faria sem executar):
#   - /etc/sysctl.d/99-aurora.conf                 -> remove + sysctl --system
#   - /etc/default/earlyoom                        -> restaura .dpkg-dist se houver
#   - /etc/systemd/journald.conf.d/*aurora*        -> remove + reload systemd-journald
#   - /etc/NetworkManager/conf.d/99-aurora-*.conf  -> remove + reload NM
#   - /etc/NetworkManager/conf.d/default-wifi-powersave-on.conf.bak-aurora-ultra -> restaura
#   - /etc/systemd/logind.conf.d/99-no-suspend.conf -> remove + restart systemd-logind
#   - /etc/apt/apt.conf.d/99-aurora-postinvoke     -> remove (sem auto-reapply)
#   - units systemd Aurora                         -> disable + remove
#   - User services Aurora                         -> stop + disable + remove (systemctl --user)
#
# NÃO reverte (risco alto, exige decisão manual):
#   - dpkg-divert do google-chrome-stable  (rode: sudo dpkg-divert --remove --rename /usr/bin/google-chrome-stable)
#   - kernel cmdline params (rode: sudo kernelstub --delete-options "pcie_aspm=off nvme.noacpi=1 ...")
#   - dconf db custom (rode: sudo dconf reset -f / && sudo dconf update)
#
# Uso:
#   bash aurora-ROLLBACK.sh           # interativo, pede confirmação
#   bash aurora-ROLLBACK.sh --yes     # não-interativo
#   bash aurora-ROLLBACK.sh --dry-run # só imprime, não executa

set -u

DRY_RUN=0
YES=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --yes|-y)  YES=1 ;;
        --help|-h) sed -n '2,30p' "$0"; exit 0 ;;
    esac
done

run() {
    if [ $DRY_RUN -eq 1 ]; then
        printf '[dry-run] %s\n' "$*"
    else
        printf '[exec] %s\n' "$*"
        "$@"
    fi
}

confirm() {
    if [ $YES -eq 1 ] || [ $DRY_RUN -eq 1 ]; then return 0; fi
    read -r -p "Continuar com rollback? [y/N] " ans
    case "$ans" in [yY]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

echo "=== Aurora Rollback (parcial) ==="
echo "Modo: $([ $DRY_RUN -eq 1 ] && echo 'DRY-RUN' || echo 'EXECUTAR')"
echo ""
confirm || { echo "Abortado."; exit 0; }

# 1. Configs em /etc/ (root)
for f in \
    /etc/sysctl.d/99-aurora.conf \
    /etc/apt/apt.conf.d/99-aurora-postinvoke \
    /etc/systemd/logind.conf.d/99-no-suspend.conf \
    /etc/NetworkManager/conf.d/99-aurora-ultra-wifi.conf \
    /etc/systemd/journald.conf.d/00-aurora-persistent.conf ; do
    if [ -f "$f" ]; then run sudo rm -f "$f"; fi
done

# 2. Restaurar default-wifi-powersave-on.conf do .bak (se houver)
if [ -f /etc/NetworkManager/conf.d/default-wifi-powersave-on.conf.bak-aurora-ultra ]; then
    run sudo mv /etc/NetworkManager/conf.d/default-wifi-powersave-on.conf.bak-aurora-ultra \
                /etc/NetworkManager/conf.d/default-wifi-powersave-on.conf
fi

# 3. earlyoom default — restaurar do .dpkg-dist se houver
if [ -f /etc/default/earlyoom.dpkg-dist ]; then
    run sudo mv /etc/default/earlyoom.dpkg-dist /etc/default/earlyoom
fi

# 4. Units systemd Aurora (root)
for unit in \
    aurora-root.service \
    aurora-watchdog.service aurora-watchdog.timer \
    aurora-health.service aurora-health.timer \
    mem-snapshot.service mem-snapshot.timer \
    oom-postmortem.service \
    product-oom-watchdog.service \
    ollama-vram-watchdog.service ollama-vram-watchdog.timer ; do
    if systemctl is-enabled --quiet "$unit" 2>/dev/null; then
        run sudo systemctl disable --now "$unit"
    fi
    if [ -f "/etc/systemd/system/$unit" ]; then
        run sudo rm -f "/etc/systemd/system/$unit"
    fi
done

# 5. User services Aurora
for unit in aurora-user.service gradia-autosave.service imagens-router.service; do
    if systemctl --user is-enabled --quiet "$unit" 2>/dev/null; then
        run systemctl --user disable --now "$unit"
    fi
    if [ -f "$HOME/.config/systemd/user/$unit" ]; then
        run rm -f "$HOME/.config/systemd/user/$unit"
    fi
done

# 6. Reload
run sudo systemctl daemon-reload
run systemctl --user daemon-reload
run sudo systemctl restart systemd-journald 2>/dev/null || true
run sudo systemctl reload NetworkManager 2>/dev/null || true
run sudo sysctl --system 2>/dev/null

echo ""
echo "=== Rollback completo ==="
echo "Lembre-se de também reverter manualmente:"
echo "  - dpkg-divert Chrome: sudo dpkg-divert --remove --rename /usr/bin/google-chrome-stable"
echo "  - kernel cmdline: sudo kernelstub --delete-options 'pcie_aspm=off ...'"
echo "  - dconf db custom: sudo dconf reset -f / && sudo dconf update"
exit 0
