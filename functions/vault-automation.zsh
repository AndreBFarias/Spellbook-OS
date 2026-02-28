#!/bin/zsh
# Funcoes de automacao do Controle de Bordo

# Diretorio do vault
VAULT_DIR="${BORDO_DIR:-$HOME/Controle de Bordo}"
SISTEMA_DIR="$VAULT_DIR/.sistema"
SCRIPTS_DIR="$SISTEMA_DIR/scripts"

# Criar nova nota com template
nova_nota() {
    local tipo="${1:-nota}"
    local nome="${2:-}"

    if [[ -z "$nome" ]]; then
        __err "Uso: nova_nota <tipo> <nome>"
        echo "Tipos: daily, projeto, trabalho, conceito, pessoal"
        return 1
    fi

    local template_file="$SISTEMA_DIR/templates/$tipo.md"
    if [[ ! -f "$template_file" ]]; then
        __err "Template nao encontrado: $tipo"
        return 1
    fi

    # Determinar diretorio baseado no tipo
    local target_dir
    case "$tipo" in
        daily) target_dir="$VAULT_DIR/05_Diario/2026" ;;
        projeto) target_dir="$VAULT_DIR/03_Projetos" ;;
        trabalho) target_dir="$VAULT_DIR/02_Trabalho" ;;
        conceito) target_dir="$VAULT_DIR/04_Conceitos" ;;
        pessoal) target_dir="$VAULT_DIR/01_Pessoal" ;;
        *) target_dir="$VAULT_DIR/Inbox" ;;
    esac

    # Criar nome do arquivo
    local date_prefix=""
    if [[ "$tipo" == "daily" ]]; then
        date_prefix="$(date +%Y-%m-%d)"
    else
        date_prefix="$(date +%Y-%m-%d)_"
    fi

    # Normalizar nome (kebab-case)
    local normalized_name=$(echo "$nome" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-')
    local filename="${date_prefix}${normalized_name}.md"
    local filepath="$target_dir/$filename"

    # Ler template e substituir variaveis
    local content=$(<"$template_file")
    content="${content//\{\{date:YYYY-MM-DD\}\}/$(date +%Y-%m-%d)}"
    content="${content//\{\{date:dddd\}\}/$(date +%A)}"
    content="${content//\{\{title\}\}/$nome}"

    # Criar arquivo
    echo "$content" > "$filepath"
    __ok "Nota criada: $filepath"

    # Abrir no obsidian (se disponivel)
    if command -v obsidian &> /dev/null; then
        obsidian "obsidian://open?vault=Controle%20de%20Bordo&file=$(echo "$filepath" | sed "s|$VAULT_DIR/||" | sed 's/ /%20/g')"
    fi
}

# Alias para tipos especificos
nova_daily() { nova_nota daily "$(date +%Y-%m-%d)"; }
novo_projeto() { nova_nota projeto "$@"; }
novo_trabalho() { nova_nota trabalho "$@"; }
novo_conceito() { nova_nota conceito "$@"; }
novo_pessoal() { nova_nota pessoal "$@"; }

# Executar automacao do vault
vault_automacao() {
    local script="${1:-automatizar_vault.py}"
    local args="${@:2}"

    if [[ ! -f "$SCRIPTS_DIR/$script" ]]; then
        __err "Script nao encontrado: $script"
        return 1
    fi

    __header "EXECUTANDO: $script" "$D_CYAN"
    python3 "$SCRIPTS_DIR/$script" $args
}

# Verificar consistencia
vault_check() {
    vault_automacao verificar_consistencia.py "$@"
}

# Padronizar documentos
vault_padronizar() {
    vault_automacao padronizar_documentos.py "$@"
}

# Auto-tags e relacoes
vault_autotags() {
    vault_automacao automatizar_vault.py "$@"
}

# Pipeline completo de manutencao
vault_manutencao() {
    __header "MANUTENCAO DO VAULT" "$D_CYAN"
    echo ""

    # 1. Verificar consistencia
    echo -e "${D_COMMENT}[1/4] Verificando consistencia...${D_RESET}"
    vault_check
    echo ""

    # 2. Auto-tags
    echo -e "${D_COMMENT}[2/4] Processando auto-tags...${D_RESET}"
    vault_autotags --auto
    echo ""

    # 3. Padronizar
    echo -e "${D_COMMENT}[3/4] Padronizando documentos...${D_RESET}"
    echo -e "${D_FG}Pular padronizacao? (s/N)${D_RESET}"
    read -k 1 reply
    echo ""
    if [[ "$reply" != [Ss] ]]; then
        vault_padronizar --dry-run
        echo ""
        echo -e "${D_FG}Aplicar padronizacao? (S/n)${D_RESET}"
        read -k 1 reply
        echo ""
        if [[ "$reply" != [Nn] ]]; then
            vault_padronizar
        fi
    fi
    echo ""

    # 4. Verificar tamanho
    echo -e "${D_COMMENT}[4/4] Verificando tamanho...${D_RESET}"
    local vault_size=$(du -sh "$VAULT_DIR" 2>/dev/null | cut -f1)
    local sync_size=$(du -sh --exclude=99_Arquivo --exclude=_reorganizacao_backup "$VAULT_DIR" 2>/dev/null | cut -f1)
    echo "  Total: $vault_size"
    echo "  Sync:  $sync_size"
    echo ""

    __ok "Manutencao concluida!"
}

# Buscar no vault
vault_buscar() {
    local query="$1"
    if [[ -z "$query" ]]; then
        __err "Uso: vault_buscar <termo>"
        return 1
    fi

    __header "BUSCANDO: $query" "$D_CYAN"

    # Buscar em titulos
    echo -e "${D_PURPLE}Em titulos:${D_RESET}"
    find "$VAULT_DIR" -name "*.md" -not -path "*/\.*" -not -path "*/99_Arquivo/*" -not -path "*/_reorganizacao_backup/*" | while read f; do
        basename "$f" .md | grep -i "$query" && echo "  $f"
    done

    # Buscar em conteudo
    echo ""
    echo -e "${D_PURPLE}Em conteudo:${D_RESET}"
    grep -r -l -i "$query" "$VAULT_DIR" --include="*.md" 2>/dev/null | grep -v "/\." | grep -v "/99_Arquivo/" | grep -v "/_reorganizacao_backup/" | head -10 | while read f; do
        echo "  $(basename "$f")"
    done
}

# Stats do vault
vault_stats() {
    __header "ESTATISTICAS DO VAULT" "$D_CYAN"

    local total_notes=$(find "$VAULT_DIR" -name "*.md" -not -path "*/\.*" -not -path "*/99_Arquivo/*" -not -path "*/_reorganizacao_backup/*" | wc -l)
    local vault_size=$(du -sh "$VAULT_DIR" 2>/dev/null | cut -f1)
    local sync_size=$(du -sh --exclude=99_Arquivo --exclude=_reorganizacao_backup "$VAULT_DIR" 2>/dev/null | cut -f1)

    echo ""
    echo -e "  ${D_COMMENT}Notas:${D_RESET} ${D_FG}$total_notes${D_RESET}"
    echo -e "  ${D_COMMENT}Tamanho total:${D_RESET} ${D_FG}$vault_size${D_RESET}"
    echo -e "  ${D_COMMENT}Tamanho sync:${D_RESET} ${D_FG}$sync_size${D_RESET}"
    echo ""

    # Contagem por hub
    echo -e "${D_PURPLE}Por Hub:${D_RESET}"
    for hub in 01_Pessoal 02_Trabalho 03_Projetos 04_Conceitos 05_Diario; do
        local count=$(find "$VAULT_DIR/$hub" -name "*.md" 2>/dev/null | wc -l)
        echo -e "  ${D_COMMENT}|${D_RESET} ${D_FG}$hub:${D_RESET} $count notas"
    done
    echo ""

    # Notas recentes
    echo -e "${D_PURPLE}Notas recentes (7 dias):${D_RESET}"
    find "$VAULT_DIR" -name "*.md" -mtime -7 -not -path "*/\.*" -not -path "*/99_Arquivo/*" -not -path "*/_reorganizacao_backup/*" | head -5 | while read f; do
        echo -e "  ${D_COMMENT}|${D_RESET} $(basename "$f")"
    done
}

# Comandos de atalho
alias vauto='vault_autotags'
alias vcheck='vault_check'
alias vpad='vault_padronizar'
alias vmaint='vault_manutencao'
alias vstats='vault_stats'
alias vnew='nova_nota'
alias vproj='novo_projeto'
alias vwork='novo_trabalho'
alias vconc='novo_conceito'
alias vpess='novo_pessoal'
alias vdaily='nova_daily'
