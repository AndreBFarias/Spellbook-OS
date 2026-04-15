#!/bin/zsh
# Funções integradas do Controle de Bordo v2.0
# Sistema completo de automação, sync e QOL

# Configurações
VAULT_DIR="${BORDO_DIR:-$HOME/Controle de Bordo}"
SISTEMA_DIR="$VAULT_DIR/.sistema"
SCRIPTS_DIR="$SISTEMA_DIR/scripts"
HOOKS_DIR="$SISTEMA_DIR/hooks"
LOGS_DIR="$SISTEMA_DIR/logs"

# Garantir diretórios existam
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
# NAVEGAÇÃO
# ============================================

# Ir para o vault
cdb() {
    cd "$VAULT_DIR"
    __ok "Diretório: $VAULT_DIR"
}

# Abrir no Obsidian
vopen() {
    local uri="obsidian://open?vault=Controle%20de%20Bordo"

    if command -v obsidian &> /dev/null; then
        obsidian "$uri" &> /dev/null &
        disown
    elif flatpak list --app 2>/dev/null | grep -q md.obsidian.Obsidian; then
        flatpak run md.obsidian.Obsidian "$uri" &> /dev/null &
        disown
    elif command -v xdg-open &> /dev/null; then
        xdg-open "$uri" &> /dev/null &
        disown
    else
        __err "Obsidian não encontrado (nem binário, nem Flatpak)"
        return 1
    fi
}

# ============================================
# CRIAÇÃO DE NOTAS
# ============================================

__nova_nota_template() {
    local tipo="$1"
    local nome="$2"
    local template_file="$SISTEMA_DIR/templates/$tipo.md"

    if [[ ! -f "$template_file" ]]; then
        __err "Template não encontrado: $tipo"
        return 1
    fi

    # Determinar diretório
    local target_dir
    case "$tipo" in
        daily) target_dir="$VAULT_DIR/Diario/$(date +%Y)" ;;
        projeto) target_dir="$VAULT_DIR/Projetos" ;;
        trabalho) target_dir="$VAULT_DIR/Trabalho" ;;
        conceito) target_dir="$VAULT_DIR/Conceitos" ;;
        pessoal) target_dir="$VAULT_DIR/Pessoal" ;;
        *) target_dir="$VAULT_DIR/Inbox" ;;
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
        __err "Processador de inbox não encontrado"
        return 1
    fi

    __cdb_header "PROCESSANDO INBOX" "$D_CYAN"
    python3 "$SCRIPTS_DIR/inbox_processor.py" "$@"
}

# ============================================
# AUTOMAÇÃO
# ============================================

vauto() {
    if [[ ! -f "$SCRIPTS_DIR/automatizar_vault.py" ]]; then
        __err "Script de automação não encontrado"
        return 1
    fi

    __cdb_header "AUTO-TAGS E RELAÇÕES" "$D_CYAN"
    python3 "$SCRIPTS_DIR/automatizar_vault.py" "$@"
}

vpad() {
    if [[ ! -f "$SCRIPTS_DIR/padronizar_documentos.py" ]]; then
        __err "Script de padronização não encontrado"
        return 1
    fi

    __cdb_header "PADRONIZANDO DOCUMENTOS" "$D_CYAN"
    python3 "$SCRIPTS_DIR/padronizar_documentos.py" "$@"
}

vcheck() {
    if [[ ! -f "$SCRIPTS_DIR/verificar_consistencia.py" ]]; then
        __err "Script de consistência não encontrado"
        return 1
    fi

    __cdb_header "VERIFICANDO CONSISTÊNCIA" "$D_CYAN"
    python3 "$SCRIPTS_DIR/verificar_consistencia.py" "$@"
}

vhealth() {
    if [[ ! -f "$SCRIPTS_DIR/health_check.py" ]]; then
        __err "Script de health check não encontrado"
        return 1
    fi

    python3 "$SCRIPTS_DIR/health_check.py" "$@"
}

# ============================================
# SINCRONIZAÇÃO INTEGRADA
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

    __cdb_header "SINCRONIZAÇÃO INTEGRADA" "$D_CYAN"
    echo -e "  ${D_COMMENT}Início:${D_RESET} $(date '+%H:%M:%S')"
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
        if [[ -d "$VAULT_DIR/Inbox" ]]; then
            local inbox_count=$(find "$VAULT_DIR/Inbox" -name "*.md" -type f 2>/dev/null | wc -l)
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
    echo -e "${D_COMMENT}[3/6] Auto-tags e relações...${D_RESET}"
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
            echo -e "  ${D_COMMENT}Sem mudanças${D_RESET}"
        fi
    fi

    # 6. Update Dashboards
    echo -e "${D_COMMENT}[6/6] Atualizando dashboards...${D_RESET}"
    for dash in home.md Pessoal/dashboard-pessoal.md Trabalho/dashboard-trabalho.md \
                Projetos/dashboard-projetos.md Conceitos/dashboard-conceitos.md \
                Diario/dashboard-diario.md; do
        local dash_path="$VAULT_DIR/$dash"
        if [[ -f "$dash_path" ]]; then
            sed -i "s/modified: .*/modified: $(date +%Y-%m-%d)/" "$dash_path" 2>/dev/null
            touch "$dash_path"
        fi
    done
    echo -e "  ${D_GREEN}OK${D_RESET}"

    # Relatório
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    echo ""
    __cdb_header "SINCRONIZAÇÃO CONCLUÍDA" "$D_GREEN"
    echo -e "  ${D_COMMENT}Duração:${D_RESET} ${duration}s"

    local total_notes=$(find "$VAULT_DIR" -name "*.md" -not -path "*/\.*" -not -path "*/Arquivo/*" 2>/dev/null | wc -l)
    local sync_size=$(du -sh --exclude=Arquivo --exclude=_reorganizacao_backup "$VAULT_DIR" 2>/dev/null | cut -f1)

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
# ESTATÍSTICAS E BUSCA
# ============================================

vstats() {
    __cdb_header "ESTATÍSTICAS DO VAULT" "$D_CYAN"

    local total_notes=$(find "$VAULT_DIR" -name "*.md" -not -path "*/\.*" -not -path "*/Arquivo/*" 2>/dev/null | wc -l)
    local vault_size=$(du -sh "$VAULT_DIR" 2>/dev/null | cut -f1)
    local sync_size=$(du -sh --exclude=Arquivo --exclude=_reorganizacao_backup "$VAULT_DIR" 2>/dev/null | cut -f1)

    echo ""
    echo -e "  ${D_COMMENT}Notas:${D_RESET} ${D_FG}$total_notes${D_RESET}"
    echo -e "  ${D_COMMENT}Total:${D_RESET} ${D_FG}$vault_size${D_RESET}"
    echo -e "  ${D_COMMENT}Sync:${D_RESET} ${D_FG}$sync_size${D_RESET}"
    echo ""

    echo -e "${D_PURPLE}Por Hub:${D_RESET}"
    for hub in Pessoal Trabalho Projetos Conceitos Diario; do
        local count=$(find "$VAULT_DIR/$hub" -name "*.md" 2>/dev/null | wc -l)
        printf "  ${D_COMMENT}|${D_RESET} ${D_FG}%-15s${D_RESET} %4d notas\n" "$hub:" $count
    done
    echo ""

    echo -e "${D_PURPLE}Recentes (7 dias):${D_RESET}"
    find "$VAULT_DIR" -name "*.md" -mtime -7 -not -path "*/\.*" -not -path "*/Arquivo/*" 2>/dev/null | head -5 | while read f; do
        echo -e "  ${D_COMMENT}|${D_RESET} $(basename "$f")"
    done
    echo ""
}

vault_buscar() {
    local query="$1"
    [[ -z "$query" ]] && { __err "Uso: vault_buscar <termo>"; return 1; }

    __cdb_header "BUSCANDO: $query" "$D_CYAN"

    echo -e "${D_PURPLE}Em titulos:${D_RESET}"
    find "$VAULT_DIR" -name "*.md" -not -path "*/\.*" -not -path "*/Arquivo/*" 2>/dev/null | while read f; do
        basename "$f" .md | grep -i "$query" && echo -e "  ${D_COMMENT}->${D_RESET} $f"
    done | head -10

    echo ""
    echo -e "${D_PURPLE}Em conteudo:${D_RESET}"
    grep -r -l -i "$query" "$VAULT_DIR" --include="*.md" 2>/dev/null | grep -v "/\." | grep -v "/Arquivo/" | head -10 | while read f; do
        echo -e "  ${D_COMMENT}|${D_RESET} $(basename "$f")"
    done
    echo ""
}

# ============================================
# MANUTENÇÃO
# ============================================

vmaint() {
    __cdb_header "MANUTENÇÃO COMPLETA" "$D_CYAN"
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

    # 4. Padronização
    echo -e "${D_COMMENT}[4/5] Padronização...${D_RESET}"
    read -q "REPLY?Executar padronização? (s/N) "
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
# EXPORTAÇÃO
# ============================================

vexport() {
    local device="${1:-mobile}"

    if [[ -f "$SCRIPTS_DIR/export_to_other_devices.py" ]]; then
        python3 "$SCRIPTS_DIR/export_to_other_devices.py" "$device"
    else
        __err "Script de exportação não encontrado"
        return 1
    fi
}

vmobile() {
    if [[ -f "$SCRIPTS_DIR/mobile_sync.sh" ]]; then
        bash "$SCRIPTS_DIR/mobile_sync.sh"
    else
        __err "Script mobile não encontrado"
        return 1
    fi
}

# ============================================
# SYNC DE DOCUMENTAÇÃO DOS PROJETOS
# ============================================

vsync_projetos() {
    local DEV_DIR="$HOME/Desenvolvimento"
    local PROJETOS_DIR="$VAULT_DIR/Projetos"
    local LOG_FILE="$LOGS_DIR/sync_projetos_$(date +%Y%m%d).log"

    local -A PROJETOS=(
        ["protocolo-ouroboros"]="Protocolo Ouroboros"
        ["Controle_de_Bordo_OS"]="Controle de Bordo OS"
        ["Luna"]="Luna"
        ["Spellbook-OS"]="Spellbook OS"
        ["Detector-de-Doppelganger"]="Detector de Doppelganger"
        ["Neurosonancy"]="Neurosonancy"
        ["FogStripper-Removedor-Background"]="FogStripper"
    )

    __cdb_header "SYNC DOCUMENTAÇÃO DOS PROJETOS" "$D_CYAN"
    echo -e "  ${D_COMMENT}Origem:${D_RESET} $DEV_DIR"
    echo -e "  ${D_COMMENT}Destino:${D_RESET} $PROJETOS_DIR"
    echo ""

    local synced=0 skipped=0

    for projeto_dir nome_vault in ${(kv)PROJETOS}; do
        local origem="$DEV_DIR/$projeto_dir"
        local destino="$PROJETOS_DIR/$nome_vault"

        if [[ ! -d "$origem" ]]; then
            echo -e "  ${D_YELLOW}[SKIP]${D_RESET} $projeto_dir não encontrado"
            ((skipped++))
            continue
        fi

        echo -e "  ${D_CYAN}[SYNC]${D_RESET} $projeto_dir -> Projetos/$nome_vault"
        mkdir -p "$destino"

        rsync -av --delete --delete-excluded \
            --exclude='.git/' \
            --exclude='node_modules/' \
            --exclude='__pycache__/' \
            --exclude='.venv/' \
            --exclude='venv/' \
            --exclude='venv_*/' \
            --exclude='.dev_venv/' \
            --exclude='*_venv/' \
            --exclude='data/' \
            --exclude='.env' \
            --exclude='*.pyc' \
            --exclude='*.egg-info/' \
            --exclude='dist/' \
            --exclude='build/' \
            --exclude='.ruff_cache/' \
            --exclude='.pytest_cache/' \
            --exclude='.obsidian/' \
            --exclude='.mypy_cache/' \
            --exclude='target/' \
            --exclude='site-packages/' \
            --include='*/' \
            --include='*.md' \
            --include='*.yaml' \
            --include='*.yml' \
            --include='*.toml' \
            --exclude='*' \
            "$origem/" "$destino/" >> "$LOG_FILE" 2>&1

        ((synced++))
    done

    echo ""
    echo -e "  ${D_GREEN}Sincronizados: $synced${D_RESET} | ${D_YELLOW}Ignorados: $skipped${D_RESET}"
    echo -e "  ${D_COMMENT}Log: $LOG_FILE${D_RESET}"
    __cdb_log "INFO" "vsync_projetos: $synced synced, $skipped skipped"
}

alias vsyncproj='vsync_projetos'

# ============================================
# LIMPEZA E TAMANHO
# ============================================

vinbox_clean() {
    __cdb_header "LIMPANDO INBOX" "$D_CYAN"
    local inbox_dir="$VAULT_DIR/Inbox"
    local attach_dir="$VAULT_DIR/_Attachments"

    mkdir -p "$attach_dir"

    local img_count=0
    for ext in png jpg jpeg gif svg webp; do
        for f in "$inbox_dir"/*."$ext"(N); do
            mv "$f" "$attach_dir/"
            ((img_count++))
        done
    done

    if (( img_count > 0 )); then
        __ok "$img_count imagens movidas para _Attachments"
    else
        echo -e "  ${D_COMMENT}Nenhuma imagem encontrada${D_RESET}"
    fi
    __cdb_log "INFO" "Inbox cleanup: $img_count images moved"
}

vsize() {
    __cdb_header "TAMANHO POR PASTA" "$D_CYAN"
    echo ""
    for dir in Pessoal Trabalho Projetos Conceitos Diario Inbox _Attachments Arquivo; do
        local dir_path="$VAULT_DIR/$dir"
        if [[ -d "$dir_path" ]]; then
            local size=$(du -sh "$dir_path" 2>/dev/null | cut -f1)
            printf "  ${D_COMMENT}|${D_RESET} ${D_FG}%-15s${D_RESET} %s\n" "$dir:" "$size"
        fi
    done
    echo ""
    local total=$(du -sh "$VAULT_DIR" 2>/dev/null | cut -f1)
    local sync=$(du -sh --exclude=Arquivo --exclude=_reorganizacao_backup "$VAULT_DIR" 2>/dev/null | cut -f1)
    echo -e "  ${D_COMMENT}Total:${D_RESET} $total"
    echo -e "  ${D_COMMENT}Sync:${D_RESET} $sync"
    echo ""
}

# ============================================
# HELP
# ============================================

vhelp() {
    cat << 'EOF'

CONTROLE DE BORDO - AJUDA
=========================

NAVEGAÇÃO
  cdb                    Ir para o diretório do vault
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
  vinbox_clean           Mover imagens para _Attachments

AUTOMAÇÃO
  vauto                  Auto-tags e relações
  vpad                   Padronizar documentos
  vcheck                 Verificar consistência
  vhealth                Health check

AUTOMAÇÃO COMPLETA
  controle_de_bordo      Executa pipeline completo de automação
  cbordo                 Alias para controle_de_bordo
    --dry-run            Simula sem alterar
    --no-open            Não abre Obsidian ao final
    --verbose            Modo verboso

BACKUP E RECUPERAÇÃO
  vbackups               Lista todos os backups
  vbackups "termo"       Filtra backups por nome
  vrestore "caminho"     Restaura arquivo do backup mais recente

SYNC
  vsync                  Sync completo
  vquick                 Sync rápido (sem git/dev)
  vmaint                 Manutenção completa

INFO
  vstats                 Estatísticas
  vsize                  Tamanho por pasta
  vault_buscar "termo"   Buscar no vault

EXPORTAÇÃO
  vexport <device>       Exportar para dispositivo
  vmobile                Preparar pacote mobile

Para mais detalhes: cat "$HOME/Controle de Bordo/.sistema/docs/INTEGRACAO.md"

EOF
}

# ============================================
# BACKUP E RECUPERAÇÃO
# ============================================

vrestore() {
    if [[ ! -f "$SCRIPTS_DIR/vault_backup.py" ]]; then
        __err "Script de backup não encontrado"
        return 1
    fi
    python3 "$SCRIPTS_DIR/vault_backup.py" --restore "$@"
}

vbackups() {
    if [[ ! -f "$SCRIPTS_DIR/vault_backup.py" ]]; then
        __err "Script de backup não encontrado"
        return 1
    fi
    local args=("--list")
    if [[ -n "$1" ]]; then
        args+=("--file" "$1")
    fi
    python3 "$SCRIPTS_DIR/vault_backup.py" "${args[@]}"
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
# AUTOMAÇÃO COMPLETA
# ============================================

__sync_spellbook() {
    local spellbook="$HOME/Desenvolvimento/Spellbook-OS"
    [[ ! -d "$spellbook" ]] && { __warn "Spellbook-OS não encontrado"; return 0; }

    local src="$HOME/.config/zsh/functions"
    local dst="$spellbook/functions"

    for f in controle-de-bordo.zsh sync-integrado.zsh sync.zsh; do
        if [[ -f "$src/$f" ]]; then
            cp "$src/$f" "$dst/$f"
        fi
    done

    [[ -f "$dst/vault-automation.zsh" ]] && rm "$dst/vault-automation.zsh"

    if [[ -d "$spellbook/.git" ]]; then
        cd "$spellbook"
        if [[ -n $(git status --porcelain 2>/dev/null) ]]; then
            git add -A > /dev/null 2>&1
            git commit -m "chore: sincronização automática controle-de-bordo" > /dev/null 2>&1
            __ok "Spellbook-OS sincronizado e commitado"
        else
            __ok "Spellbook-OS sem alterações"
        fi
        cd - > /dev/null 2>&1
    else
        __ok "Spellbook-OS sincronizado"
    fi
}

controle_de_bordo() {
    local skip_open=0 dry_run=0 verbose=0
    for arg in "$@"; do
        case "$arg" in
            --no-open)   skip_open=1 ;;
            --dry-run)   dry_run=1 ;;
            --verbose)   verbose=1 ;;
        esac
    done

    __cdb_header "CONTROLE DE BORDO - AUTOMAÇÃO COMPLETA" "$D_CYAN"

    local apply_flag="--fix"
    (( dry_run )) && apply_flag="--check"

    echo -e "${D_COMMENT}[1/10] Limpando backups antigos...${D_RESET}"
    python3 "$SCRIPTS_DIR/vault_backup.py" --cleanup

    echo -e "${D_COMMENT}[2/10] Sanitizando atribuições de IA...${D_RESET}"
    python3 "$SCRIPTS_DIR/sanitizar_ia.py" $apply_flag

    echo -e "${D_COMMENT}[3/10] Removendo emojis...${D_RESET}"
    if (( dry_run )); then
        python3 "$SCRIPTS_DIR/emoji_guardian.py" check "$VAULT_DIR"
    else
        python3 "$SCRIPTS_DIR/emoji_guardian.py" clean "$VAULT_DIR" --apply
    fi

    echo -e "${D_COMMENT}[4/10] Auto-tags e relações...${D_RESET}"
    if (( dry_run )); then
        python3 "$SCRIPTS_DIR/automatizar_vault.py" --dry-run
    else
        python3 "$SCRIPTS_DIR/automatizar_vault.py" --auto
    fi

    echo -e "${D_COMMENT}[5/10] Normalizando nomes de arquivos...${D_RESET}"
    python3 "$SCRIPTS_DIR/renomear_arquivos.py" $apply_flag

    echo -e "${D_COMMENT}[6/10] Renomeando imagens...${D_RESET}"
    python3 "$SCRIPTS_DIR/renomear_imagens.py" $apply_flag

    echo -e "${D_COMMENT}[7/10] Processando Inbox...${D_RESET}"
    if (( dry_run )); then
        python3 "$SCRIPTS_DIR/inbox_processor.py" --dry-run
    else
        python3 "$SCRIPTS_DIR/inbox_processor.py" --auto-merge
    fi

    echo -e "${D_COMMENT}[8/10] Padronizando frontmatter...${D_RESET}"
    if (( dry_run )); then
        python3 "$SCRIPTS_DIR/padronizar_documentos.py" --merge-only --dry-run
    else
        python3 "$SCRIPTS_DIR/padronizar_documentos.py" --merge-only
    fi

    echo -e "${D_COMMENT}[9/10] Verificando configs Obsidian...${D_RESET}"
    if (( dry_run )); then
        python3 "$SCRIPTS_DIR/verificar_obsidian.py" --check
    else
        python3 "$SCRIPTS_DIR/verificar_obsidian.py" --fix
    fi

    echo -e "${D_COMMENT}[10/10] Sincronizando com Spellbook-OS...${D_RESET}"
    __sync_spellbook

    __cdb_header "AUTOMAÇÃO CONCLUÍDA" "$D_GREEN"

    if (( ! skip_open )); then
        vopen
    fi
}

alias cbordo='controle_de_bordo'

# ============================================
# PROTEÇÃO CONTRA EMOJIS
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
        if grep -q "['''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''🟡''🟢''''''''''']" "$file" 2>/dev/null; then
            __err "Emojis encontrados em: $file"
            return 1
        else
            __ok "Nenhum emoji em: $file"
            return 0
        fi
    else
        __err "Arquivo não encontrado: $file"
        return 1
    fi
}
