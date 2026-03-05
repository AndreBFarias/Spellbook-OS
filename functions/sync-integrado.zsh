#!/bin/zsh
# Sistema Integrado de Sincronizacao do Controle de Bordo
# Combina sync de repos, processamento de inbox, automacao e health checks

VAULT_DIR="${BORDO_DIR:-$HOME/Controle de Bordo}"
DEV_DIR="${DEV_DIR:-$HOME/Desenvolvimento}"
SISTEMA_DIR="$VAULT_DIR/.sistema"
SCRIPTS_DIR="$SISTEMA_DIR/scripts"

# Configuracoes de sync
VAULT_GIT_DIR="$VAULT_DIR/.git"
SYNC_LOCK_FILE="/tmp/controle_de_bordo_sync.lock"
SYNC_LOG_FILE="$VAULT_DIR/.sistema/logs/sync.log"

# Criar diretorio de logs
mkdir -p "$VAULT_DIR/.sistema/logs"

__log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$SYNC_LOG_FILE"
}

# Verificar se sync esta em andamento
__check_sync_lock() {
    if [[ -f "$SYNC_LOCK_FILE" ]]; then
        local pid=$(cat "$SYNC_LOCK_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            __warn "Sync ja em andamento (PID: $pid)"
            return 1
        else
            rm -f "$SYNC_LOCK_FILE"
        fi
    fi
    return 0
}

__acquire_sync_lock() {
    echo $$ > "$SYNC_LOCK_FILE"
}

__release_sync_lock() {
    rm -f "$SYNC_LOCK_FILE"
}

# Health check rapido
__vault_health_check() {
    __header "HEALTH CHECK" "$D_CYAN"

    # Verificar tamanho
    local vault_size=$(du -sb "$VAULT_DIR" 2>/dev/null | cut -f1)
    local vault_size_mb=$((vault_size / 1024 / 1024))
    local limit_mb=1024

    if (( vault_size_mb > limit_mb )); then
        __err "Vault excede 1GB ($vault_size_mb MB)"
        __log "ERROR" "Vault size exceeded: ${vault_size_mb}MB"
        return 1
    fi

    echo -e "  ${D_GREEN}Tamanho OK:${D_RESET} ${vault_size_mb}MB / ${limit_mb}MB"

    # Verificar estrutura
    local missing_dirs=()
    for dir in 01_Pessoal 02_Trabalho 03_Projetos 04_Conceitos 05_Diario 99_Arquivo; do
        if [[ ! -d "$VAULT_DIR/$dir" ]]; then
            missing_dirs+=("$dir")
        fi
    done

    if (( ${#missing_dirs[@]} > 0 )); then
        __warn "Diretorios ausentes: ${missing_dirs[@]}"
        __log "WARN" "Missing directories: ${missing_dirs[@]}"
    else
        echo -e "  ${D_GREEN}Estrutura OK${D_RESET}"
    fi

    # Verificar git
    if [[ -d "$VAULT_GIT_DIR" ]]; then
        local git_status=$(cd "$VAULT_DIR" && git status --porcelain 2>/dev/null | wc -l)
        if (( git_status > 0 )); then
            echo -e "  ${D_YELLOW}Git:${D_RESET} $git_status arquivos modificados"
        else
            echo -e "  ${D_GREEN}Git:${D_RESET} sincronizado"
        fi
    fi

    __log "INFO" "Health check passed"
    return 0
}

# Processar inbox
__process_inbox() {
    __header "PROCESSANDO INBOX" "$D_CYAN"

    if [[ ! -d "$VAULT_DIR/00_Inbox" ]]; then
        mkdir -p "$VAULT_DIR/00_Inbox"
        echo -e "  ${D_COMMENT}Inbox criado${D_RESET}"
    fi

    local inbox_count=$(find "$VAULT_DIR/00_Inbox" -name "*.md" -type f 2>/dev/null | wc -l)

    if (( inbox_count == 0 )); then
        echo -e "  ${D_COMMENT}Inbox vazio${D_RESET}"
        return 0
    fi

    echo -e "  ${D_FG}Encontrados $inbox_count arquivos${D_RESET}"
    __log "INFO" "Processing inbox: $inbox_count files"

    # Executar processador de inbox
    if [[ -f "$SCRIPTS_DIR/inbox_processor.py" ]]; then
        python3 "$SCRIPTS_DIR/inbox_processor.py" --auto-merge 2>&1 | while read line; do
            echo "  ${D_COMMENT}|${D_RESET} $line"
        done
        __log "INFO" "Inbox processing completed"
    else
        __err "Processador de inbox nao encontrado"
        __log "ERROR" "Inbox processor not found"
        return 1
    fi
}

# Executar automacoes
__run_automations() {
    __header "EXECUTANDO AUTOMACOES" "$D_CYAN"

    # 1. Auto-tags e relacoes
    echo -e "  ${D_COMMENT}[1/3] Auto-tags e relacoes...${D_RESET}"
    if [[ -f "$SCRIPTS_DIR/automatizar_vault.py" ]]; then
        python3 "$SCRIPTS_DIR/automatizar_vault.py" --auto > /dev/null 2>&1
        echo -e "  ${D_GREEN}OK${D_RESET}"
        __log "INFO" "Auto-tags completed"
    fi

    # 2. Verificar consistencia (apenas log)
    echo -e "  ${D_COMMENT}[2/3] Verificando consistencia...${D_RESET}"
    if [[ -f "$SCRIPTS_DIR/verificar_consistencia.py" ]]; then
        local broken_links=$(python3 "$SCRIPTS_DIR/verificar_consistencia.py" 2>&1 | grep -c "links quebrados")
        if (( broken_links > 0 )); then
            echo -e "  ${D_YELLOW}Atenção: $broken_links problemas encontrados${D_RESET}"
            __log "WARN" "Consistency check: $broken_links issues"
        else
            echo -e "  ${D_GREEN}OK${D_RESET}"
            __log "INFO" "Consistency check passed"
        fi
    fi

    # 3. Padronizacao leve (apenas notas sem frontmatter)
    echo -e "  ${D_COMMENT}[3/3] Padronizacao...${D_RESET}"
    if [[ -f "$SCRIPTS_DIR/padronizar_documentos.py" ]]; then
        python3 "$SCRIPTS_DIR/padronizar_documentos.py" --filter="00_Inbox" --auto > /dev/null 2>&1
        echo -e "  ${D_GREEN}OK${D_RESET}"
        __log "INFO" "Standardization completed"
    fi
}

# Sync com repositorios de desenvolvimento
__sync_dev_repos() {
    __header "SINCRONIZANDO REPOSITORIOS" "$D_CYAN"

    # Usar a funcao existente mas integrada
    sincronizar_controle_de_bordo --auto --stats 2>&1 | tail -20
    __log "INFO" "Dev repos sync completed"
}

# Sync com git
__sync_git() {
    if [[ ! -d "$VAULT_GIT_DIR" ]]; then
        return 0
    fi

    __header "SINCRONIZANDO GIT" "$D_CYAN"

    cd "$VAULT_DIR"

    # Verificar se ha mudancas
    if [[ -z $(git status --porcelain 2>/dev/null) ]]; then
        echo -e "  ${D_COMMENT}Nenhuma mudanca para commit${D_RESET}"
        return 0
    fi

    # Add
    git add -A > /dev/null 2>&1

    # Commit com timestamp
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    git commit -m "Sync: $timestamp" > /dev/null 2>&1

    # Push se houver remote
    if git remote > /dev/null 2>&1; then
        if git push > /dev/null 2>&1; then
            echo -e "  ${D_GREEN}Push realizado${D_RESET}"
            __log "INFO" "Git push completed"
        else
            echo -e "  ${D_YELLOW}Push falhou (pode haver conflitos)${D_RESET}"
            __log "WARN" "Git push failed"
        fi
    else
        echo -e "  ${D_COMMENT}Commit local realizado (sem remote)${D_RESET}"
    fi
}

# Verificar e limpar emojis
__check_emojis() {
    local emoji_guardian="$VAULT_DIR/.sistema/scripts/emoji_guardian.py"

    if [[ ! -f "$emoji_guardian" ]]; then
        __log "WARN" "Emoji guardian not found"
        return 0
    fi

    __header "VERIFICANDO EMOJIS" "$D_CYAN"

    # Verificar emojis
    local check_output=$(python3 "$emoji_guardian" check "$VAULT_DIR" 2>&1)
    local emoji_count
    emoji_count=$(echo "$check_output" | grep -c "ARQUIVO") || emoji_count=0

    if (( emoji_count > 0 )); then
        echo -e "  ${D_YELLOW}Encontrados $emoji_count arquivo(s) com emojis${D_RESET}"
        __log "WARN" "Found $emoji_count files with emojis"

        # Limpar automaticamente
        echo -e "  ${D_COMMENT}Limpando emojis...${D_RESET}"
        local clean_output=$(python3 "$emoji_guardian" clean "$VAULT_DIR" --apply 2>&1)
        local cleaned
        cleaned=$(echo "$clean_output" | grep -c "LIMPO\|Arquivos processados") || cleaned=0

        if (( cleaned > 0 )); then
            echo -e "  ${D_GREEN}Emojis removidos com sucesso${D_RESET}"
            __log "INFO" "Emojis cleaned successfully"
        else
            echo -e "  ${D_COMMENT}Nenhum emoji para limpar${D_RESET}"
        fi
    else
        echo -e "  ${D_GREEN}Nenhum emoji encontrado${D_RESET}"
        __log "INFO" "No emojis found"
    fi
}

# Atualizar dashboards
__update_dashboards() {
    __header "ATUALIZANDO DASHBOARDS" "$D_CYAN"

    # Os dashboards usam dataview, entao apenas tocamos no arquivo
    # para atualizar a data de modificacao
    local dashboards=(
        "Home.md"
        "01_Pessoal/Dashboard_Pessoal.md"
        "02_Trabalho/Dashboard_Trabalho.md"
        "03_Projetos/Dashboard_Projetos.md"
        "04_Conceitos/Dashboard_Conceitos.md"
        "05_Diario/Dashboard_Diario.md"
    )

    for dash in "${dashboards[@]}"; do
        local dash_path="$VAULT_DIR/$dash"
        if [[ -f "$dash_path" ]]; then
            # Atualizar data de modificacao no frontmatter
            sed -i "s/modified: .*/modified: $(date +%Y-%m-%d)/" "$dash_path" 2>/dev/null
            touch "$dash_path"
        fi
    done

    echo -e "  ${D_GREEN}Dashboards atualizados${D_RESET}"
    __log "INFO" "Dashboards updated"
}

# Funcao principal de sincronizacao integrada
sincronizar_controle_de_bordo_full() {
    local skip_health=0
    local skip_inbox=0
    local skip_git=0
    local skip_dev=0
    local verbose=0

    for arg in "$@"; do
        case "$arg" in
            --skip-health) skip_health=1 ;;
            --skip-inbox) skip_inbox=1 ;;
            --skip-git) skip_git=1 ;;
            --skip-dev) skip_dev=1 ;;
            --verbose) verbose=1 ;;
            --help)
                echo "Uso: sincronizar_controle_de_bordo_full [opcoes]"
                echo ""
                echo "Opcoes:"
                echo "  --skip-health    Pula health check"
                echo "  --skip-inbox     Pula processamento de inbox"
                echo "  --skip-git       Pula sincronizacao git"
                echo "  --skip-dev       Pula sync de repos de desenvolvimento"
                echo "  --verbose        Modo verboso"
                echo "  --help           Mostra esta ajuda"
                return 0
                ;;
        esac
    done

    # Verificar lock
    if ! __check_sync_lock; then
        return 1
    fi

    __acquire_sync_lock
    trap __release_sync_lock EXIT

    __log "INFO" "Starting full sync"

    __header "SINCRONIZACAO INTEGRADA DO CONTROLE DE BORDO" "$D_CYAN"
    echo ""
    echo -e "  ${D_COMMENT}Vault:${D_RESET} $VAULT_DIR"
    echo -e "  ${D_COMMENT}Inicio:${D_RESET} $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    local start_time=$(date +%s)

    # 1. Health Check
    if (( ! skip_health )); then
        __vault_health_check || { __log "ERROR" "Health check failed"; return 1; }
        echo ""
    fi

    # 2. Processar Inbox
    if (( ! skip_inbox )); then
        __process_inbox
        echo ""
    fi

    # 3. Automacoes
    __run_automations
    echo ""

    # 4. Sync com repos de desenvolvimento
    if (( ! skip_dev )); then
        __sync_dev_repos
        echo ""
    fi

    # 5. Sync Git
    if (( ! skip_git )); then
        __sync_git
        echo ""
    fi

    # 6. Verificar e limpar emojis
    __check_emojis
    echo ""

    # 7. Atualizar dashboards
    __update_dashboards
    echo ""

    # Relatorio final
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    __header "SINCRONIZACAO CONCLUIDA" "$D_GREEN"
    echo ""
    echo -e "  ${D_COMMENT}Duracao:${D_RESET} ${duration}s"
    echo -e "  ${D_COMMENT}Log:${D_RESET} $SYNC_LOG_FILE"
    echo ""

    # Estatisticas
    local total_notes=$(find "$VAULT_DIR" -name "*.md" -not -path "*/\.*" -not -path "*/99_Arquivo/*" | wc -l)
    local vault_size=$(du -sh "$VAULT_DIR" | cut -f1)
    local sync_size=$(du -sh --exclude=99_Arquivo --exclude=_reorganizacao_backup "$VAULT_DIR" | cut -f1)

    echo -e "  ${D_FG}Notas:${D_RESET} $total_notes"
    echo -e "  ${D_FG}Tamanho total:${D_RESET} $vault_size"
    echo -e "  ${D_FG}Tamanho sync:${D_RESET} $sync_size"
    echo ""

    __ok "Vault sincronizado com sucesso!"
    __log "INFO" "Full sync completed in ${duration}s"

    # Notificacao desktop
    if command -v notify-send > /dev/null 2>&1; then
        notify-send "Controle de Bordo" "Sincronizacao concluida em ${duration}s" -i dialog-information
    fi
}

# Alias para facilitar
alias sync_full='sincronizar_controle_de_bordo_full'
alias sync_quick='sincronizar_controle_de_bordo_full --skip-dev --skip-git'
alias sync_dev='sincronizar_controle_de_bordo_full --skip-inbox'
