#!/usr/bin/env bash
# auditoria-repos.sh — Scanner retroativo de violacoes de anonimato
# Varre todos os repos em DEV_DIR buscando vazamentos em mensagens e arquivos
# Uso: bash auditoria-repos.sh [diretorio_base]

set -euo pipefail

BASE_DIR="${1:-${DEV_DIR:-$HOME/Desenvolvimento}}"
LOG_DIR="$HOME/.local/share/spellbook"
LOG_FILE="$LOG_DIR/auditoria.log"
HOOKS_SOURCE="$HOME/.config/git/hooks"

mkdir -p "$LOG_DIR" 2>/dev/null

# --- Regexes ---
AI_MENTION_RE='[Cc]laude|[Aa]nthropic|[Oo]pen[Aa][Ii]|[Cc]hat[Gg][Pp][Tt]|[Cc]opilot|[Gg]emini|[Gg][Pp][Tt]-[34]|[Dd]eep[Ss]eek|[Cc]ursor|[Aa]ider|[Ww]indsurf|[Cc]odeium|[Tt]abnine|noreply@anthropic'
EMOJI_RE='[\x{1F600}-\x{1F64F}\x{1F300}-\x{1F5FF}\x{1F680}-\x{1F6FF}\x{2600}-\x{26FF}\x{2700}-\x{27BF}\x{1F900}-\x{1F9FF}\x{1FA00}-\x{1FA6F}\x{1FA70}-\x{1FAFF}]'

# --- Cores ---
C_RED='\033[38;2;255;85;85m'
C_GREEN='\033[38;2;80;250;123m'
C_YELLOW='\033[38;2;241;250;140m'
C_PURPLE='\033[38;2;189;147;249m'
C_CYAN='\033[38;2;139;233;253m'
C_COMMENT='\033[38;2;98;114;164m'
C_BOLD='\033[1m'
C_DIM='\033[2m'
C_RESET='\033[0m'

TOTAL_VIOLATIONS=0
TOTAL_REPOS=0
TOTAL_CLEAN=0
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

_log() {
    echo "[$TIMESTAMP] $1" >> "$LOG_FILE"
}

_log "=== Inicio da auditoria em $BASE_DIR ==="

echo ""
echo -e "  ${C_PURPLE}${C_BOLD}AUDITORIA DE ANONIMATO${C_RESET}"
echo -e "  ${C_COMMENT}$(printf '%.0s─' {1..48})${C_RESET}"
echo -e "  ${C_COMMENT}Base: $BASE_DIR${C_RESET}"
echo -e "  ${C_COMMENT}Log:  $LOG_FILE${C_RESET}"
echo ""

# Encontrar todos os repos
REPOS=$(find "$BASE_DIR" -maxdepth 4 -name ".git" -type d -prune 2>/dev/null | sed 's/\/\.git//' | sort)

if [[ -z "$REPOS" ]]; then
    echo -e "  ${C_YELLOW}Nenhum repositorio encontrado.${C_RESET}"
    exit 0
fi

while read -r REPO_PATH; do
    [[ -z "$REPO_PATH" ]] && continue
    REPO_NAME=$(basename "$REPO_PATH")
    TOTAL_REPOS=$((TOTAL_REPOS + 1))
    REPO_VIOLATIONS=0
    REPO_DETAILS=""

    # [1/3] Escanear mensagens de commit (git log --all)
    MSG_HITS=0
    while read -r SHA; do
        [[ -z "$SHA" ]] && continue
        FULL_MSG=$(git -C "$REPO_PATH" log --format="%B" -1 "$SHA" 2>/dev/null)
        SHORT=$(echo "$SHA" | cut -c1-8)
        SUBJECT=$(git -C "$REPO_PATH" log --format="%s" -1 "$SHA" 2>/dev/null)
        FOUND=""

        if echo "$FULL_MSG" | grep -qiE "$COAUTHOR_RE" 2>/dev/null; then
            FOUND="${FOUND}co-author "
        fi
        if echo "$FULL_MSG" | grep -qiE "$AI_MENTION_RE" 2>/dev/null; then
            FOUND="${FOUND}ia "
        fi
        if echo "$FULL_MSG" | grep -qP "$EMOJI_RE" 2>/dev/null; then
            FOUND="${FOUND}emoji "
        fi

        if [[ -n "$FOUND" ]]; then
            MSG_HITS=$((MSG_HITS + 1))
            REPO_DETAILS="${REPO_DETAILS}      ${C_RED}msg${C_RESET} ${SHORT} [${FOUND% }] \"${SUBJECT}\"\n"
            _log "[$REPO_NAME] msg $SHORT [$FOUND] \"$SUBJECT\""
        fi
    done < <(git -C "$REPO_PATH" log --all --format="%H" 2>/dev/null)
    REPO_VIOLATIONS=$((REPO_VIOLATIONS + MSG_HITS))

    # [2/3] Escanear conteudo de arquivos no HEAD (git grep)
    FILE_HITS=0
    while read -r LINE; do
        [[ -z "$LINE" ]] && continue
        FILE_HITS=$((FILE_HITS + 1))
        REPO_DETAILS="${REPO_DETAILS}      ${C_YELLOW}file${C_RESET} ${LINE}\n"
        _log "[$REPO_NAME] file $LINE"
    done < <(git -C "$REPO_PATH" grep -iE "$COAUTHOR_RE" HEAD 2>/dev/null || true)

    while read -r LINE; do
        [[ -z "$LINE" ]] && continue
        # Filtrar falso-positivos: variaveis de config, database cursors, etc.
        if echo "$LINE" | grep -qiE '(api_key|api-key|provider|model|client|_MODEL|_API|endpoint|baseurl|base_url|\.cursor\(\)|cursor\s*=\s*conn|cursor\s*=\s*db|cursor\s*=\s*self|getcursor|set_cursor|cursor_factory|CursorKind)' 2>/dev/null; then
            continue
        fi
        FILE_HITS=$((FILE_HITS + 1))
        REPO_DETAILS="${REPO_DETAILS}      ${C_YELLOW}file${C_RESET} ${LINE}\n"
        _log "[$REPO_NAME] file $LINE"
    done < <(git -C "$REPO_PATH" grep -iE "$AI_MENTION_RE" HEAD 2>/dev/null || true)
    REPO_VIOLATIONS=$((REPO_VIOLATIONS + FILE_HITS))

    # [3/3] Verificar integridade dos hooks
    # Se core.hooksPath está configurado globalmente, os hooks centrais são usados
    GLOBAL_HOOKS_PATH=$(git config --global core.hooksPath 2>/dev/null || true)
    HOOKS_OK=true
    HOOKS_DETAIL=""

    if [[ -n "$GLOBAL_HOOKS_PATH" ]]; then
        # core.hooksPath ativo: verificar hooks centrais
        for HOOK in pre-commit commit-msg pre-push _lib.sh; do
            if [[ ! -f "$GLOBAL_HOOKS_PATH/$HOOK" ]]; then
                HOOKS_OK=false
                HOOKS_DETAIL="${HOOKS_DETAIL}${HOOK}(ausente-central) "
            elif [[ ! -x "$GLOBAL_HOOKS_PATH/$HOOK" ]]; then
                HOOKS_OK=false
                HOOKS_DETAIL="${HOOKS_DETAIL}${HOOK}(não-exec-central) "
            fi
        done
    else
        # Sem core.hooksPath: verificar hooks per-repo
        for HOOK in pre-commit commit-msg pre-push; do
            HOOK_PATH="$REPO_PATH/.git/hooks/$HOOK"
            if [[ ! -f "$HOOK_PATH" ]]; then
                HOOKS_OK=false
                HOOKS_DETAIL="${HOOKS_DETAIL}${HOOK}(ausente) "
            elif [[ ! -x "$HOOK_PATH" ]]; then
                HOOKS_OK=false
                HOOKS_DETAIL="${HOOKS_DETAIL}${HOOK}(não-exec) "
            fi
        done

        if [[ ! -f "$REPO_PATH/.git/hooks/_lib.sh" ]]; then
            HOOKS_OK=false
            HOOKS_DETAIL="${HOOKS_DETAIL}_lib.sh(ausente) "
        fi
    fi

    if [[ "$HOOKS_OK" == false ]]; then
        REPO_VIOLATIONS=$((REPO_VIOLATIONS + 1))
        REPO_DETAILS="${REPO_DETAILS}      ${C_CYAN}hooks${C_RESET} ${HOOKS_DETAIL% }\n"
        _log "[$REPO_NAME] hooks: $HOOKS_DETAIL"
    fi

    # Exibir resultado do repo
    if [[ $REPO_VIOLATIONS -gt 0 ]]; then
        TOTAL_VIOLATIONS=$((TOTAL_VIOLATIONS + REPO_VIOLATIONS))
        echo -e "  ${C_RED}[${REPO_VIOLATIONS}]${C_RESET} ${C_BOLD}${REPO_NAME}${C_RESET}"
        echo -e "$REPO_DETAILS"
    else
        TOTAL_CLEAN=$((TOTAL_CLEAN + 1))
        echo -e "  ${C_GREEN}[OK]${C_RESET} ${REPO_NAME}"
    fi

done <<< "$REPOS"

# Resumo
echo ""
echo -e "  ${C_COMMENT}$(printf '%.0s─' {1..48})${C_RESET}"
echo -e "  ${C_BOLD}Resumo${C_RESET}"
echo -e "    Repos escaneados: ${TOTAL_REPOS}"
echo -e "    Repos limpos:     ${C_GREEN}${TOTAL_CLEAN}${C_RESET}"
echo -e "    Violacoes:        ${C_RED}${TOTAL_VIOLATIONS}${C_RESET}"
echo -e "    Log:              ${C_DIM}${LOG_FILE}${C_RESET}"
echo ""

_log "=== Fim: $TOTAL_REPOS repos, $TOTAL_CLEAN limpos, $TOTAL_VIOLATIONS violacoes ==="

exit 0

# "Confie, mas verifique." — Proverbio russo (atribuido a Reagan)
