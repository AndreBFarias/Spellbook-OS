#!/bin/bash
# _lib.sh — Biblioteca compartilhada para hooks git
# Regexes centralizados + funcoes de logging
# Fonte: source "$HOME/.config/git/hooks/_lib.sh" 2>/dev/null || true

# --- Diretorio de logs ---
HOOK_LOG_DIR="$HOME/.local/share/spellbook"
HOOK_LOG_FILE="$HOOK_LOG_DIR/hooks.log"

# --- Regexes centralizados ---

# Emojis (para grep -P / perl)
EMOJI_RE='[\x{1F600}-\x{1F64F}\x{1F300}-\x{1F5FF}\x{1F680}-\x{1F6FF}\x{2600}-\x{26FF}\x{2700}-\x{27BF}\x{1F900}-\x{1F9FF}\x{1FA00}-\x{1FA6F}\x{1FA70}-\x{1FAFF}]'

# Co-autoria e atribuicao (case-insensitive via grep -iE)
COAUTHOR_RE='[Cc]o-[Aa]uthored-[Bb]y|[Pp]aired-[Ww]ith|[Aa]ssisted-[Bb]y'

# Mencoes a ferramentas de IA (case-insensitive via grep -iE)
AI_MENTION_RE='[Cc]laude|[Aa]nthropic|[Oo]pen[Aa][Ii]|[Cc]hat[Gg][Pp][Tt]|[Cc]opilot|[Gg]emini|[Gg][Pp][Tt]-[34]|[Dd]eep[Ss]eek|[Cc]ursor|[Aa]ider|[Ww]indsurf|[Cc]odeium|[Tt]abnine|noreply@anthropic'

# Secrets (para grep -P)
SECRET_RE='(sk-[a-zA-Z0-9]{20,}|sk-ant-[a-zA-Z0-9]{20,}|AIza[0-9A-Za-z_-]{35}|ghp_[a-zA-Z0-9]{36}|gho_[a-zA-Z0-9]{36}|github_pat_[a-zA-Z0-9]{22}_[a-zA-Z0-9]{59}|AKIA[0-9A-Z]{16})'

# --- Funcoes utilitarias ---

_hook_log() {
    local hook_name="$1"
    local message="$2"
    local repo_name
    repo_name=$(_hook_repo_name)

    mkdir -p "$HOOK_LOG_DIR" 2>/dev/null
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$hook_name] [$repo_name] $message" >> "$HOOK_LOG_FILE" 2>/dev/null
}

_hook_repo_name() {
    local root
    root=$(git rev-parse --show-toplevel 2>/dev/null)
    if [[ -n "$root" ]]; then
        basename "$root"
    else
        echo "unknown"
    fi
}

_hook_detect_context() {
    local repo_path="$1"

    if [[ "$repo_path" == *"/MEC/"* || "$repo_path" == *"/MEC" ]]; then
        EXPECTED_NAME="andrefariasmec"
        EXPECTED_EMAIL="andrefarias@mec.gov.br"
        EXPECTED_SSH_ALIAS="github.com-mec"
        CONTEXT="MEC"
    elif [[ "$repo_path" == *"/VitoriaMariaDB/"* || "$repo_path" == *"/VitoriaMariaDB" ]]; then
        EXPECTED_NAME="vitoriamariadb"
        EXPECTED_EMAIL="vitoriamaria.sds@gmail.com"
        EXPECTED_SSH_ALIAS="github.com-vit"
        CONTEXT="VitoriaMariaDB"
    else
        EXPECTED_NAME="AndreBFarias"
        EXPECTED_EMAIL="andre.dsbf@gmail.com"
        EXPECTED_SSH_ALIAS="github.com-personal"
        CONTEXT="Pessoal"
    fi
}

_hook_validate_identity() {
    local current_name current_email
    current_name=$(git config --get user.name)
    current_email=$(git config --get user.email)

    if [[ "$current_name" != "$EXPECTED_NAME" || "$current_email" != "$EXPECTED_EMAIL" ]]; then
        echo "  [BLOQUEIO] Identidade incorreta para contexto $CONTEXT"
        echo "    Esperado: $EXPECTED_NAME <$EXPECTED_EMAIL>"
        echo "    Atual:    $current_name <$current_email>"
        echo "    Corrija com: santuario <projeto>"
        return 1
    fi
    return 0
}

# "A desconfianca e mae da seguranca." — Aristofanes
