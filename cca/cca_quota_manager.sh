#!/bin/bash

QUOTA_FILE="$HOME/.config/zsh/cca/.cca_quota"
WEEKLY_LIMIT=999999999999
WARNING_THRESHOLD=900000000000
CRITICAL_THRESHOLD=950000000000

init_quota() {
    if [ ! -f "$QUOTA_FILE" ]; then
        echo "week_start=$(date +%Y-%m-%d)" > "$QUOTA_FILE"
        echo "tokens_used=0" >> "$QUOTA_FILE"
        echo "requests_count=0" >> "$QUOTA_FILE"
    fi
}

get_week_start() {
    grep "^week_start=" "$QUOTA_FILE" | cut -d'=' -f2
}

get_tokens_used() {
    grep "^tokens_used=" "$QUOTA_FILE" | cut -d'=' -f2
}

get_requests_count() {
    grep "^requests_count=" "$QUOTA_FILE" | cut -d'=' -f2
}

reset_if_new_week() {
    init_quota
    local week_start=$(get_week_start)
    local current_date=$(date +%Y-%m-%d)
    local days_diff=$(( ($(date -d "$current_date" +%s) - $(date -d "$week_start" +%s)) / 86400 ))

    if [ $days_diff -ge 7 ]; then
        echo "week_start=$current_date" > "$QUOTA_FILE"
        echo "tokens_used=0" >> "$QUOTA_FILE"
        echo "requests_count=0" >> "$QUOTA_FILE"
        echo "[QUOTA] Nova semana iniciada. Limite resetado."
    fi
}

add_tokens() {
    local tokens=$1
    local current=$(get_tokens_used)
    local new_total=$((current + tokens))
    local requests=$(($(get_requests_count) + 1))

    sed -i "s/^tokens_used=.*/tokens_used=$new_total/" "$QUOTA_FILE"
    sed -i "s/^requests_count=.*/requests_count=$requests/" "$QUOTA_FILE"
}

check_quota() {
    reset_if_new_week
    local tokens_used=$(get_tokens_used)
    local requests=$(get_requests_count)
    local remaining=$((WEEKLY_LIMIT - tokens_used))
    local percent=$((tokens_used * 100 / WEEKLY_LIMIT))

    echo "=== CLAUDE QUOTA STATUS ==="
    echo "Tokens usados: $tokens_used / $WEEKLY_LIMIT ($percent%)"
    echo "Tokens restantes: $remaining"
    echo "Requests esta semana: $requests"
    echo "Week start: $(get_week_start)"
    echo ""

    if [ $tokens_used -ge $CRITICAL_THRESHOLD ]; then
        echo "[CRÍTICO] $percent% do limite usado!"
        echo "    Evite comandos grandes. Use --skip-context quando possível."
        return 2
    elif [ $tokens_used -ge $WARNING_THRESHOLD ]; then
        echo "[AVISO] $percent% do limite usado!"
        echo "    Cuidado com contextos grandes."
        return 1
    else
        echo "[OK] Uso normal. Ainda tem $remaining tokens."
        return 0
    fi
}

estimate_tokens() {
    local text="$1"
    local char_count=${#text}
    local estimated=$((char_count / 4))
    echo $estimated
}

pre_request_check() {
    reset_if_new_week
    local tokens_used=$(get_tokens_used)

    if [ $tokens_used -ge $WEEKLY_LIMIT ]; then
        echo "[ERRO] LIMITE SEMANAL ATINGIDO!"
        echo "   Espere até $(date -d "$(get_week_start) + 7 days" +%Y-%m-%d) para nova semana."
        return 1
    elif [ $tokens_used -ge $CRITICAL_THRESHOLD ]; then
        echo "[AVISO] ZONA CRÍTICA: $((WEEKLY_LIMIT - tokens_used)) tokens restantes"
        echo "   Deseja continuar? (y/n)"
        read -r response
        if [ "$response" != "y" ]; then
            return 1
        fi
    fi
    return 0
}

case "$1" in
    init)
        init_quota
        echo "Quota manager inicializado em $QUOTA_FILE"
        ;;
    check)
        check_quota
        ;;
    add)
        if [ -z "$2" ]; then
            echo "Uso: $0 add <tokens>"
            exit 1
        fi
        add_tokens "$2"
        echo "Adicionado $2 tokens. Total: $(get_tokens_used)"
        ;;
    estimate)
        if [ -z "$2" ]; then
            echo "Uso: $0 estimate <texto>"
            exit 1
        fi
        tokens=$(estimate_tokens "$2")
        echo "Estimado: ~$tokens tokens"
        ;;
    pre-check)
        pre_request_check
        ;;
    reset)
        rm -f "$QUOTA_FILE"
        init_quota
        echo "Quota resetada."
        ;;
    *)
        echo "Uso: $0 {init|check|add|estimate|pre-check|reset}"
        exit 1
        ;;
esac
