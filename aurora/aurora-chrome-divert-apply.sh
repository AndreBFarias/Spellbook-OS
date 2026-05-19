#!/bin/bash
# Aurora - dpkg-divert do google-chrome-stable + wrapper persistente
# ----------------------------------------------------------------------------
# Objetivo: garantir que QUALQUER invocação de /usr/bin/google-chrome-stable
# (incluindo .desktop entries do sistema, xdg-open, scripts internos) injete
# --load-extension automaticamente. Sobrevive a apt upgrade.
#
# Idempotente: detecta se divert já existe.
# Requer sudo (NOPASSWD recomendado em aurora-user-apply.sh, mas aqui apenas
# alerta se não puder elevar).

set -u

DIVERT_TARGET="/usr/bin/google-chrome-stable"
DIVERT_RENAMED="${DIVERT_TARGET}.distrib"
WRAPPER_TPL="$HOME/.config/zsh/aurora/google-chrome-wrapper.sh"
POLICY_DIR="/etc/opt/chrome/policies/managed"
POLICY_FILE="${POLICY_DIR}/aurora-no-ai-no-antigravity.json"

log()  { printf '[chrome-divert] %s\n' "$*"; }
warn() { printf '[chrome-divert][WARN] %s\n' "$*" >&2; }

# Confirma que conseguimos sudo
if ! sudo -n true 2>/dev/null; then
  warn "sudo NOPASSWD não configurado; pulando aplicação automática"
  warn "rode manualmente: sudo bash $0"
  exit 0
fi

# 1. dpkg-divert: renomeia binário original se ainda não foi
if ! dpkg-divert --listpackage "$DIVERT_TARGET" 2>/dev/null | grep -q "^diverts"; then
  if [ -e "$DIVERT_RENAMED" ]; then
    log "ok: divert .distrib já existe"
  else
    sudo dpkg-divert --add --rename "$DIVERT_TARGET" >/dev/null 2>&1 \
      && log "diverted $DIVERT_TARGET -> $DIVERT_RENAMED" \
      || warn "falha dpkg-divert"
  fi
fi

# 2. Instala wrapper que aponta para o renamed binary
if [ -f "$WRAPPER_TPL" ]; then
  # Gera wrapper com path absoluto do binário renomeado
  sed "s|exec /usr/bin/google-chrome-stable |exec $DIVERT_RENAMED |" "$WRAPPER_TPL" \
    | sudo tee "$DIVERT_TARGET" >/dev/null
  sudo chmod 0755 "$DIVERT_TARGET"
  sudo chown root:root "$DIVERT_TARGET"
  log "wrapper instalado em $DIVERT_TARGET"
fi

# 3. Policy file: desabilita IA + bloqueia Antigravity
sudo mkdir -p "$POLICY_DIR"
sudo tee "$POLICY_FILE" >/dev/null << 'POLEOF'
{
  "GenAiDefaultSettings": 2,
  "HelpMeWriteSettings": 2,
  "TabOrganizerSettings": 2,
  "TabCompareSettings": 2,
  "HistorySearchSettings": 2,
  "CreateThemesSettings": 2,
  "ComposeSettings": 2,
  "AutofillPredictionSettings": 2,
  "DevToolsGenAiSettings": 2,
  "PasswordManagerPasskeysSettings": 2,
  "OptimizationGuideOnDeviceModelExecutionEnabled": false,
  "GenAILocalFoundationalModelSettings": 1,
  "BuiltInAIAPIsEnabled": false,
  "ExtensionInstallBlocklist": [
    "eeijfnjmjelapkebgockoeaadonbchdd"
  ],
  "ExtensionInstallAllowlist": []
}
POLEOF
sudo chmod 0644 "$POLICY_FILE"
log "policy instalada em $POLICY_FILE"
