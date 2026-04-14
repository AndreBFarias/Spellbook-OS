#!/bin/bash

GUARD_CONFIG="$HOME/.config/zsh/cca/.cca_guard_config"
QUOTA_MANAGER="$HOME/.config/zsh/cca/cca_quota_manager.sh"

init_guard() {
    cat > "$GUARD_CONFIG" <<EOF
# Claude Guard Configuration

# Limites
MAX_FILE_SIZE_KB=100
MAX_CONTEXT_FILES=5
MAX_LINE_COUNT=2000

# Thresholds de aviso
WARN_FILE_SIZE_KB=50
WARN_CONTEXT_FILES=3
WARN_LINE_COUNT=1000

# Bloqueios automáticos
BLOCK_LARGE_READS=true
BLOCK_MASSIVE_CONTEXT=true
SUGGEST_ALTERNATIVES=true
EOF
    echo "[GUARD] Configuração criada em $GUARD_CONFIG"
}

load_config() {
    if [ ! -f "$GUARD_CONFIG" ]; then
        init_guard
    fi
    source "$GUARD_CONFIG"
}

check_file_size() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo "Arquivo não encontrado: $file"
        return 1
    fi

    local size_kb=$(du -k "$file" | cut -f1)
    local line_count=$(wc -l < "$file")

    if [ "$BLOCK_LARGE_READS" = "true" ] && [ $size_kb -gt $MAX_FILE_SIZE_KB ]; then
        echo "[BLOQUEADO] Arquivo muito grande!"
        echo "   Arquivo: $file"
        echo "   Tamanho: ${size_kb}KB (limite: ${MAX_FILE_SIZE_KB}KB)"
        echo "   Linhas: $line_count (limite: $MAX_LINE_COUNT)"
        echo ""
        echo "ALTERNATIVAS:"
        echo "1. Leia seções específicas: head -n 100 $file"
        echo "2. Busque padrões: grep 'palavra' $file"
        echo "3. Resuma com: cat $file | head -50 && echo '...' && tail -50"
        echo "4. Force (não recomendado): CLAUDE_FORCE=1 claude ..."
        return 1
    elif [ $size_kb -gt $WARN_FILE_SIZE_KB ]; then
        echo "[AVISO] Arquivo grande detectado"
        echo "   Arquivo: $file (${size_kb}KB)"
        echo "   Isso consumirá ~$((size_kb * 4)) tokens estimados"
        echo "   Continuar? (y/n)"
        read -r response
        if [ "$response" != "y" ]; then
            return 1
        fi
    fi

    return 0
}

check_context_size() {
    local file_count=$1

    if [ "$BLOCK_MASSIVE_CONTEXT" = "true" ] && [ $file_count -gt $MAX_CONTEXT_FILES ]; then
        echo "[BLOQUEADO] Contexto muito grande!"
        echo "   Arquivos no contexto: $file_count (limite: $MAX_CONTEXT_FILES)"
        echo ""
        echo "ALTERNATIVAS:"
        echo "1. Reduza o escopo: pergunte sobre arquivos específicos"
        echo "2. Use --skip-context se possível"
        echo "3. Divida em perguntas menores"
        return 1
    elif [ $file_count -gt $WARN_CONTEXT_FILES ]; then
        echo "[AVISO] Contexto grande ($file_count arquivos)"
        echo "   Continuar? (y/n)"
        read -r response
        if [ "$response" != "y" ]; then
            return 1
        fi
    fi

    return 0
}

warm_sudo() {
    # Autentica sudo para que o Claude Code possa rodar scripts que precisam
    # de permissões elevadas (install.sh, apt, etc.) sem travar no prompt.
    # A senha fica no cache do sudo (~15 min por padrão).
    if ! sudo -n true 2>/dev/null; then
        echo "[GUARD] Autenticando sudo para a sessão..."
        sudo -v 2>/dev/null || echo "[GUARD] AVISO: sudo não autenticado — scripts com apt podem travar"
    fi
}

before_claude_request() {
    load_config

    if [ -z "$CLAUDE_FORCE" ]; then
        bash "$QUOTA_MANAGER" pre-check || return 1
    fi

    warm_sudo

    return 0
}

after_claude_request() {
    local estimated_tokens=${1:-1000}
    bash "$QUOTA_MANAGER" add "$estimated_tokens"
}

analyze_command() {
    local cmd="$1"
    local total_tokens=0

    if [[ "$cmd" =~ "read" ]] || [[ "$cmd" =~ "cat" ]]; then
        local files=$(echo "$cmd" | grep -oE "[a-zA-Z0-9_/.-]+\.(py|js|ts|md|json|txt)" || echo "")
        for file in $files; do
            if [ -f "$file" ]; then
                local size_kb=$(du -k "$file" | cut -f1)
                total_tokens=$((total_tokens + size_kb * 4))
                check_file_size "$file" || return 1
            fi
        done
    fi

    echo "[GUARD] Custo estimado: ~$total_tokens tokens"
    return 0
}

case "$1" in
    init)
        init_guard
        ;;
    check-file)
        if [ -z "$2" ]; then
            echo "Uso: $0 check-file <arquivo>"
            exit 1
        fi
        load_config
        check_file_size "$2"
        ;;
    check-context)
        if [ -z "$2" ]; then
            echo "Uso: $0 check-context <num_arquivos>"
            exit 1
        fi
        load_config
        check_context_size "$2"
        ;;
    before)
        before_claude_request
        ;;
    after)
        after_claude_request "$2"
        ;;
    analyze)
        if [ -z "$2" ]; then
            echo "Uso: $0 analyze '<comando>'"
            exit 1
        fi
        load_config
        analyze_command "$2"
        ;;
    *)
        echo "Uso: $0 {init|check-file|check-context|before|after|analyze}"
        exit 1
        ;;
esac
