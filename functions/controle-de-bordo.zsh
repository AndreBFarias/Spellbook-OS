#!/bin/zsh
# Funcoes integradas do Controle de Bordo v2.0
# Sistema completo de automacao, sync e QOL

# Configuracoes
VAULT_DIR="${BORDO_DIR:-$HOME/Controle de Bordo}"
SISTEMA_DIR="$VAULT_DIR/.sistema"
SCRIPTS_DIR="$SISTEMA_DIR/scripts"
HOOKS_DIR="$SISTEMA_DIR/hooks"
LOGS_DIR="$SISTEMA_DIR/logs"

# Garantir diretorios existam
mkdir -p "$LOGS_DIR"

# ============================================
# HELPERS
# ============================================

__cdb_log() {
    local level="$1"
    local msg="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $msg" >> "$LOGS_DIR/cdb.log"
}

__cdb_header() {
    local text="$1"
    local color="${2:-$D_CYAN}"
    echo ""
    echo -e "${color}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${D_RESET}"
    echo -e "${color}  $text${D_RESET}"
    echo -e "${color}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${D_RESET}"
}

# ============================================
# NAVEGACAO
# ============================================

# Ir para o vault
cdb() {
    cd "$VAULT_DIR"
    __ok "Diretorio: $VAULT_DIR"
}

# Abrir no Obsidian
vopen() {
    if command -v obsidian &> /dev/null; then
        obsidian "obsidian://open?vault=Controle%20de%20Bordo" &
    else
        __err "Obsidian nao encontrado"
        return 1
    fi
}

# ============================================
# CRIACAO DE NOTAS
# ============================================

__nova_nota_template() {
    local tipo="$1"
    local nome="$2"
    local template_file="$SISTEMA_DIR/templates/$tipo.md"

    if [[ ! -f "$template_file" ]]; then
        __err "Template nao encontrado: $tipo"
        return 1
    fi

    # Determinar diretorio
    local target_dir
    case "$tipo" in
        daily) target_dir="$VAULT_DIR/05_Diario/2026" ;;
        projeto) target_dir="$VAULT_DIR/03_Projetos" ;;
        trabalho) target_dir="$VAULT_DIR/02_Trabalho" ;;
        conceito) target_dir="$VAULT_DIR/04_Conceitos" ;;
        pessoal) target_dir="$VAULT_DIR/01_Pessoal" ;;
        *) target_dir="$VAULT_DIR/00_Inbox" ;;
    esac

    mkdir -p "$target_dir"

    # Gerar nome do arquivo
    local date_prefix
    if [[ "$tipo" == "daily" ]]; then
        date_prefix="$(date +%Y-%m-%d)"
    else
        date_prefix="$(date +%Y-%m-%d)_"
    fi

    # Normalizar nome
    local normalized=$(echo "$nome" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-' | cut -c1-50)
    local filename="${date_prefix}${normalized}.md"
    local filepath="$target_dir/$filename"

    # Criar conteudo
    local content=$(<"$template_file")
    content="${content//\{\{date:YYYY-MM-DD\}\}/$(date +%Y-%m-%d)}"
    content="${content//\{\{date:dddd\}\}/$(date +%A)}"
    content="${content//\{\{title\}\}/$nome}"

    echo "$content" > "$filepath"
    __ok "Criado: $filepath"
    __cdb_log "INFO" "Created note: $filepath"

    # Abrir se possivel
    if [[ -n "$EDITOR" ]]; then
        $EDITOR "$filepath"
    fi
}

# Atalhos para criar notas
vdaily() { __nova_nota_template daily "$(date +%Y-%m-%d)"; }
novo_projeto() { __nova_nota_template projeto "$@"; }
novo_trabalho() { __nova_nota_template trabalho "$@"; }
novo_conceito() { __nova_nota_template conceito "$@"; }
novo_pessoal() { __nova_nota_template pessoal "$@"; }

# Alias
alias vproj='novo_projeto'
alias vwork='novo_trabalho'
alias vconc='novo_conceito'
alias vpess='novo_pessoal'

# ============================================
# INBOX
# ============================================

vinbox() {
    if [[ ! -f "$SCRIPTS_DIR/inbox_processor.py" ]]; then
        __err "Processador de inbox nao encontrado"
        return 1
    fi

    __cdb_header "PROCESSANDO INBOX" "$D_CYAN"
    python3 "$SCRIPTS_DIR/inbox_processor.py" "$@"
}

# ============================================
# AUTOMACAO
# ============================================

vauto() {
    if [[ ! -f "$SCRIPTS_DIR/automatizar_vault.py" ]]; then
        __err "Script de automacao nao encontrado"
        return 1
    fi

    __cdb_header "AUTO-TAGS E RELACOES" "$D_CYAN"
    python3 "$SCRIPTS_DIR/automatizar_vault.py" "$@"
}

vpad() {
    if [[ ! -f "$SCRIPTS_DIR/padronizar_documentos.py" ]]; then
        __err "Script de padronizacao nao encontrado"
        return 1
    fi

    __cdb_header "PADRONIZANDO DOCUMENTOS" "$D_CYAN"
    python3 "$SCRIPTS_DIR/padronizar_documentos.py" "$@"
}

vcheck() {
    if [[ ! -f "$SCRIPTS_DIR/verificar_consistencia.py" ]]; then
        __err "Script de consistencia nao encontrado"
        return 1
    fi

    __cdb_header "VERIFICANDO CONSISTENCIA" "$D_CYAN"
    python3 "$SCRIPTS_DIR/verificar_consistencia.py" "$@"
}

vhealth() {
    if [[ ! -f "$SCRIPTS_DIR/health_check.py" ]]; then
        __err "Script de health check nao encontrado"
        return 1
    fi

    python3 "$SCRIPTS_DIR/health_check.py" "$@"
}

# ============================================
# SINCRONIZACAO INTEGRADA
# ============================================

SYNC_LOCK_FILE="/tmp/cdb_sync.lock"

__cdb_check_lock() {
    if [[ -f "$SYNC_LOCK_FILE" ]]; then
        local pid=$(cat "$SYNC_LOCK_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            __warn "Sync em andamento (PID: $pid)"
            return 1
        fi
        rm -f "$SYNC_LOCK_FILE"
    fi
    return 0
}

__cdb_acquire_lock() {
    echo $$ > "$SYNC_LOCK_FILE"
}

__cdb_release_lock() {
    rm -f "$SYNC_LOCK_FILE"
}

vsync() {
    local skip_health=0 skip_inbox=0 skip_git=0 skip_dev=0 verbose=0

    for arg in "$@"; do
        case "$arg" in
            --skip-health) skip_health=1 ;;
            --skip-inbox) skip_inbox=1 ;;
            --skip-git) skip_git=1 ;;
            --skip-dev) skip_dev=1 ;;
            --verbose) verbose=1 ;;
        esac
    done

    # Verificar lock
    if ! __cdb_check_lock; then
        return 1
    fi

    __cdb_acquire_lock
    trap __cdb_release_lock EXIT

    __cdb_header "SINCRONIZACAO INTEGRADA" "$D_CYAN"
    echo -e "  ${D_COMMENT}Inicio:${D_RESET} $(date '+%H:%M:%S')"
    echo ""

    local start_time=$(date +%s)
    __cdb_log "INFO" "Starting sync"

    # 1. Health Check
    if (( ! skip_health )); then
        echo -e "${D_COMMENT}[1/6] Health Check...${D_RESET}"
        local vault_size=$(du -sb "$VAULT_DIR" 2>/dev/null | cut -f1)
        local vault_mb=$((vault_size / 1024 / 1024))

        if (( vault_mb > 1024 )); then
            __err "Vault excede 1GB ($vault_mb MB)"
            __cdb_log "ERROR" "Vault size exceeded"
            return 1
        fi
        echo -e "  ${D_GREEN}OK${D_RESET} ($vault_mb MB)"
    fi

    # 2. Processar Inbox
    if (( ! skip_inbox )); then
        echo -e "${D_COMMENT}[2/6] Processando Inbox...${D_RESET}"
        if [[ -d "$VAULT_DIR/00_Inbox" ]]; then
            local inbox_count=$(find "$VAULT_DIR/00_Inbox" -name "*.md" -type f 2>/dev/null | wc -l)
            if (( inbox_count > 0 )); then
                python3 "$SCRIPTS_DIR/inbox_processor.py" --auto-merge > /dev/null 2>&1
                echo -e "  ${D_GREEN}OK${D_RESET} ($inbox_count arquivos)"
                __cdb_log "INFO" "Processed $inbox_count inbox files"
            else
                echo -e "  ${D_COMMENT}Vazio${D_RESET}"
            fi
        fi
    fi

    # 3. Automacoes
    echo -e "${D_COMMENT}[3/6] Auto-tags e relacoes...${D_RESET}"
    python3 "$SCRIPTS_DIR/automatizar_vault.py" --auto > /dev/null 2>&1
    echo -e "  ${D_GREEN}OK${D_RESET}"

    # 4. Sync Dev Repos
    if (( ! skip_dev )); then
        echo -e "${D_COMMENT}[4/6] Sync repos de desenvolvimento...${D_RESET}"
        sincronizar_controle_de_bordo --auto > /dev/null 2>&1
        echo -e "  ${D_GREEN}OK${D_RESET}"
    fi

    # 5. Sync Git
    if (( ! skip_git )) && [[ -d "$VAULT_DIR/.git" ]]; then
        echo -e "${D_COMMENT}[5/6] Sync Git...${D_RESET}"
        cd "$VAULT_DIR"
        if [[ -n $(git status --porcelain 2>/dev/null) ]]; then
            git add -A > /dev/null 2>&1
            git commit -m "Sync: $(date '+%Y-%m-%d %H:%M:%S')" > /dev/null 2>&1
            git push > /dev/null 2>&1 || true
            echo -e "  ${D_GREEN}OK${D_RESET}"
        else
            echo -e "  ${D_COMMENT}Sem mudancas${D_RESET}"
        fi
    fi

    # 6. Update Dashboards
    echo -e "${D_COMMENT}[6/6] Atualizando dashboards...${D_RESET}"
    for dash in Home.md 01_Pessoal/Dashboard_Pessoal.md 02_Trabalho/Dashboard_Trabalho.md \
                03_Projetos/Dashboard_Projetos.md 04_Conceitos/Dashboard_Conceitos.md \
                05_Diario/Dashboard_Diario.md; do
        local dash_path="$VAULT_DIR/$dash"
        if [[ -f "$dash_path" ]]; then
            sed -i "s/modified: .*/modified: $(date +%Y-%m-%d)/" "$dash_path" 2>/dev/null
            touch "$dash_path"
        fi
    done
    echo -e "  ${D_GREEN}OK${D_RESET}"

    # Relatorio
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    echo ""
    __cdb_header "SINCRONIZACAO CONCLUIDA" "$D_GREEN"
    echo -e "  ${D_COMMENT}Duracao:${D_RESET} ${duration}s"

    local total_notes=$(find "$VAULT_DIR" -name "*.md" -not -path "*/\.*" -not -path "*/99_Arquivo/*" 2>/dev/null | wc -l)
    local sync_size=$(du -sh --exclude=99_Arquivo --exclude=_reorganizacao_backup "$VAULT_DIR" 2>/dev/null | cut -f1)

    echo -e "  ${D_FG}Notas:${D_RESET} $total_notes"
    echo -e "  ${D_FG}Tamanho sync:${D_RESET} $sync_size"
    echo ""

    __cdb_log "INFO" "Sync completed in ${duration}s"
    __ok "Vault sincronizado!"
}

# Alias de sync
alias vquick='vsync --skip-dev --skip-git'
alias sync_full='vsync'
alias sync_quick='vquick'

# ============================================
# ESTATISTICAS E BUSCA
# ============================================

vstats() {
    __cdb_header "ESTATISTICAS DO VAULT" "$D_CYAN"

    local total_notes=$(find "$VAULT_DIR" -name "*.md" -not -path "*/\.*" -not -path "*/99_Arquivo/*" 2>/dev/null | wc -l)
    local vault_size=$(du -sh "$VAULT_DIR" 2>/dev/null | cut -f1)
    local sync_size=$(du -sh --exclude=99_Arquivo --exclude=_reorganizacao_backup "$VAULT_DIR" 2>/dev/null | cut -f1)

    echo ""
    echo -e "  ${D_COMMENT}Notas:${D_RESET} ${D_FG}$total_notes${D_RESET}"
    echo -e "  ${D_COMMENT}Total:${D_RESET} ${D_FG}$vault_size${D_RESET}"
    echo -e "  ${D_COMMENT}Sync:${D_RESET} ${D_FG}$sync_size${D_RESET}"
    echo ""

    echo -e "${D_PURPLE}Por Hub:${D_RESET}"
    for hub in 01_Pessoal 02_Trabalho 03_Projetos 04_Conceitos 05_Diario; do
        local count=$(find "$VAULT_DIR/$hub" -name "*.md" 2>/dev/null | wc -l)
        printf "  ${D_COMMENT}|${D_RESET} ${D_FG}%-15s${D_RESET} %4d notas\n" "$hub:" $count
    done
    echo ""

    echo -e "${D_PURPLE}Recentes (7 dias):${D_RESET}"
    find "$VAULT_DIR" -name "*.md" -mtime -7 -not -path "*/\.*" -not -path "*/99_Arquivo/*" 2>/dev/null | head -5 | while read f; do
        echo -e "  ${D_COMMENT}|${D_RESET} $(basename "$f")"
    done
    echo ""
}

vault_buscar() {
    local query="$1"
    [[ -z "$query" ]] && { __err "Uso: vault_buscar <termo>"; return 1; }

    __cdb_header "BUSCANDO: $query" "$D_CYAN"

    echo -e "${D_PURPLE}Em titulos:${D_RESET}"
    find "$VAULT_DIR" -name "*.md" -not -path "*/\.*" -not -path "*/99_Arquivo/*" 2>/dev/null | while read f; do
        basename "$f" .md | grep -i "$query" && echo -e "  ${D_COMMENT}->${D_RESET} $f"
    done | head -10

    echo ""
    echo -e "${D_PURPLE}Em conteudo:${D_RESET}"
    grep -r -l -i "$query" "$VAULT_DIR" --include="*.md" 2>/dev/null | grep -v "/\." | grep -v "/99_Arquivo/" | head -10 | while read f; do
        echo -e "  ${D_COMMENT}|${D_RESET} $(basename "$f")"
    done
    echo ""
}

# ============================================
# MANUTENCAO
# ============================================

vmaint() {
    __cdb_header "MANUTENCAO COMPLETA" "$D_CYAN"
    echo ""

    # 1. Health
    echo -e "${D_COMMENT}[1/5] Health check...${D_RESET}"
    vhealth --no-save
    echo ""

    # 2. Inbox
    echo -e "${D_COMMENT}[2/5] Processando inbox...${D_RESET}"
    vinbox
    echo ""

    # 3. Automacoes
    echo -e "${D_COMMENT}[3/5] Auto-tags...${D_RESET}"
    vauto --auto
    echo ""

    # 4. Padronizacao
    echo -e "${D_COMMENT}[4/5] Padronizacao...${D_RESET}"
    read -q "REPLY?Executar padronizacao? (s/N) "
    echo ""
    if [[ "$REPLY" == "s" ]]; then
        vpad
    fi
    echo ""

    # 5. Sync
    echo -e "${D_COMMENT}[5/5] Sync completo...${D_RESET}"
    vsync
}

# ============================================
# EXPORTACAO
# ============================================

vexport() {
    local device="${1:-mobile}"

    if [[ -f "$SCRIPTS_DIR/export_to_other_devices.py" ]]; then
        python3 "$SCRIPTS_DIR/export_to_other_devices.py" "$device"
    else
        __err "Script de exportacao nao encontrado"
        return 1
    fi
}

vmobile() {
    if [[ -f "$SCRIPTS_DIR/mobile_sync.sh" ]]; then
        bash "$SCRIPTS_DIR/mobile_sync.sh"
    else
        __err "Script mobile nao encontrado"
        return 1
    fi
}

# ============================================
# HELP
# ============================================

vhelp() {
    cat << 'EOF'

CONTROLE DE BORDO - AJUDA
=========================

NAVEGACAO
  cdb                    Ir para o diretorio do vault
  vopen                  Abrir no Obsidian

CRIAR NOTAS
  vdaily                 Nova daily note
  vproj "Nome"          Novo projeto
  vwork "Nome"          Nova tarefa de trabalho
  vconc "Nome"          Novo conceito
  vpess "Nome"          Nova nota pessoal

INBOX
  vinbox                 Processar inbox
  vinbox --dry-run       Simular
  vinbox --auto-merge    Auto-agregar

AUTOMACAO
  vauto                  Auto-tags e relacoes
  vpad                   Padronizar documentos
  vcheck                 Verificar consistencia
  vhealth                Health check

SYNC
  vsync                  Sync completo
  vquick                 Sync rapido (sem git/dev)
  vmaint                 Manutencao completa

INFO
  vstats                 Estatisticas
  vault_buscar "termo"   Buscar no vault

EXPORTACAO
  vexport <device>       Exportar para dispositivo
  vmobile                Preparar pacote mobile

Para mais detalhes: cat "$HOME/Controle de Bordo/SISTEMA_INTEGRACAO.md"

EOF
}

# ============================================
# COMPLETION
# ============================================

if [[ -n "$ZSH_VERSION" ]]; then
    _vfiles() { _files -W "$VAULT_DIR" -g "*.md"; }
    compdef _vfiles vinbox vpad vcheck
fi

__cdb_log "INFO" "Controle de Bordo functions loaded"

# ============================================
# PROTECAO CONTRA EMOJIS
# ============================================

# Verificar emojis no vault
vcheck_emoji() {
    __cdb_header "VERIFICANDO EMOJIS" "$D_CYAN"
    python3 "$VAULT_DIR/.sistema/scripts/emoji_guardian.py"
}

# Limpar emojis do vault
vclean_emoji() {
    __cdb_header "LIMPANDO EMOJIS" "$D_CYAN"
    read -q "REPLY?Tem certeza que deseja remover todos os emojis? (s/N) "
    echo ""
    if [[ "$REPLY" == "s" ]]; then
        python3 "$VAULT_DIR/.sistema/scripts/emoji_guardian.py" --fix
    fi
}

# Limpeza completa (inclui Desenvolvimento)
vclean_emoji_full() {
    __cdb_header "LIMPEZA COMPLETA DE EMOJIS" "$D_CYAN"
    bash "$VAULT_DIR/.sistema/scripts/limpeza_emoji_completa.sh"
}

# Hook para prevenir commits com emojis (se houver git)
vinstall_emoji_hook() {
    python3 "$VAULT_DIR/.sistema/scripts/emoji_guardian.py" --install-hook
}

# Verificar arquivo especifico
vcheck_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        if grep -q "['''''️''''️''''''''''''️''''''''''''''️''''''️''''''''''''''''''️''''''''🟡''🟢''''''''''']" "$file" 2>/dev/null; then
            __err "Emojis encontrados em: $file"
            return 1
        else
            __ok "Nenhum emoji em: $file"
            return 0
        fi
    else
        __err "Arquivo nao encontrado: $file"
        return 1
    fi
}

