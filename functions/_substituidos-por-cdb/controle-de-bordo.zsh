#!/bin/zsh
# Controle de Bordo -- CLI v3.0
# Funções de navegação, criação e consulta do vault Obsidian

# ============================================
# CONFIGURAÇÃO
# ============================================

VAULT_DIR="${CONTROLE_BORDO_DIR:-$HOME/Controle de Bordo}"
SISTEMA_DIR="$VAULT_DIR/.sistema"
SCRIPTS_DIR="$SISTEMA_DIR/scripts"
TEMPLATES_DIR="$SISTEMA_DIR/templates"
LOGS_DIR="$SISTEMA_DIR/logs"

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
# DETECÇÃO DE AUTOR
# ============================================

__cdb_get_autor() {
    local host=$(hostname | tr '[:upper:]' '[:lower:]')
    case "$host" in
        nitro-5|nitro5)  echo "andre" ;;
        notebook)        echo "vitoria" ;;
        mobile)          echo "andre" ;;
        tablet)          echo "vitoria" ;;
        *)               echo "andre" ;;
    esac
}

# ============================================
# MESES EM PORTUGUÊS
# ============================================

__cdb_mes_nome() {
    setopt LOCAL_OPTIONS NO_KSH_ARRAYS
    local mes_num="$1"
    local meses=(
        "Janeiro" "Fevereiro" "Março" "Abril"
        "Maio" "Junho" "Julho" "Agosto"
        "Setembro" "Outubro" "Novembro" "Dezembro"
    )
    echo "${meses[$mes_num]}"
}

# ============================================
# NAVEGAÇÃO
# ============================================

# Propósito: Navegar para o diretório raiz do vault Obsidian
# Uso: cdb
cdb() {
    cd "$VAULT_DIR" || { __err "Diretório não encontrado: $VAULT_DIR"; return 1; }
    __ok "Diretório: $VAULT_DIR"
}

# Propósito: Abrir o vault Obsidian pelo URI
# Uso: vopen
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

    __ok "Obsidian aberto"
}

# ============================================
# CRIAÇÃO DE NOTAS -- vtask
# ============================================

# Propósito: Criar/editar nota quinzenal de tarefas para um cliente
# Uso: vtask <cliente> [quinzena]
# Completa:
#   <cliente>=__vtask_clientes
vtask() {
    local cliente="$1"
    local quinzena="$2"

    if [[ -z "$cliente" ]]; then
        __err "Uso: vtask <cliente> [quinzena]"
        echo ""
        echo -e "  ${D_COMMENT}Clientes disponíveis:${D_RESET}"
        echo -e "  ${D_FG}  mec       ${D_COMMENT}-- Vitória, MEC direto${D_RESET}"
        echo -e "  ${D_FG}  g4f       ${D_COMMENT}-- André, G4F (contractor MEC)${D_RESET}"
        echo -e "  ${D_FG}  energisa  ${D_COMMENT}-- André, Energisa${D_RESET}"
        echo -e "  ${D_FG}  mulher    ${D_COMMENT}-- Vitória, Projeto Mulher${D_RESET}"
        echo -e "  ${D_FG}  pessoal   ${D_COMMENT}-- Casal, tarefas pessoais${D_RESET}"
        return 1
    fi

    local autor=$(__cdb_get_autor)
    local target_dir=""
    local responsavel=""
    local cliente_tag=""

    case "$cliente" in
        mec)
            target_dir="$VAULT_DIR/Trabalho/Vitoria/MEC/Tasks"
            responsavel="vitoria"
            cliente_tag="mec"
            ;;
        g4f)
            target_dir="$VAULT_DIR/Trabalho/Andre/G4F/Tasks"
            responsavel="andre"
            cliente_tag="g4f"
            ;;
        energisa)
            target_dir="$VAULT_DIR/Trabalho/Andre/Energisa/Tasks"
            responsavel="andre"
            cliente_tag="energisa"
            ;;
        mulher)
            target_dir="$VAULT_DIR/Trabalho/Vitoria/Projeto Mulher/Tasks"
            responsavel="vitoria"
            cliente_tag="projeto-mulher"
            ;;
        pessoal)
            target_dir="$VAULT_DIR/Pessoal/Casal/Tasks"
            responsavel="$autor"
            cliente_tag="pessoal"
            ;;
        *)
            __err "Cliente desconhecido: $cliente"
            __warn "Opções: mec, g4f, energisa, mulher, pessoal"
            return 1
            ;;
    esac

    local dia_atual=$(date +%d)
    if [[ -z "$quinzena" ]]; then
        if (( dia_atual <= 15 )); then
            quinzena=1
        else
            quinzena=2
        fi
    fi

    if [[ "$quinzena" != "1" && "$quinzena" != "2" ]]; then
        __err "Quinzena deve ser 1 ou 2"
        return 1
    fi

    local mes_num=$(date +%-m)
    local mes_nome=$(__cdb_mes_nome "$mes_num")
    local ano=$(date +%Y)

    local sufixo="${quinzena}a"
    local filename="Tasks - ${mes_nome} - ${sufixo} Quinzena.md"
    local filepath="$target_dir/$filename"

    mkdir -p "$target_dir"

    if [[ -f "$filepath" ]]; then
        __ok "Arquivo já existe: $filename"
        if [[ -n "$EDITOR" ]]; then
            $EDITOR "$filepath"
        fi
        return 0
    fi

    local template_file="$TEMPLATES_DIR/quinzena.md"
    if [[ ! -f "$template_file" ]]; then
        __err "Template quinzena.md não encontrado"
        return 1
    fi

    local title="Tasks - ${mes_nome} - ${sufixo} Quinzena"
    local today=$(date +%Y-%m-%d)

    if (( quinzena == 1 )); then
        local período="${ano}-${(l:2::0:)mes_num}-01 a ${ano}-${(l:2::0:)mes_num}-15"
    else
        local ultimo_dia=$(date -d "${ano}-${(l:2::0:)mes_num}-01 +1 month -1 day" +%d 2>/dev/null || echo "30")
        local período="${ano}-${(l:2::0:)mes_num}-16 a ${ano}-${(l:2::0:)mes_num}-${ultimo_dia}"
    fi

    local content=$(<"$template_file")
    content="${content//\{\{title\}\}/$title}"
    content="${content//\{\{date:YYYY-MM-DD\}\}/$today}"

    content=$(echo "$content" | sed "s/^autor: $/autor: $responsavel/")
    content=$(echo "$content" | sed "s/^cliente: $/cliente: $cliente_tag/")
    content=$(echo "$content" | sed "s/^responsável: $/responsável: $responsavel/")
    content=$(echo "$content" | sed "s/^quinzena: $/quinzena: $quinzena/")
    content=$(echo "$content" | sed "s/^período: \"\"$/período: \"$período\"/")

    content=$(echo "$content" | sed "s|> \*\*Origem:\*\*|> **Origem:** $cliente_tag|")
    content=$(echo "$content" | sed "s|> \*\*Período:\*\*|> **Período:** $período|")
    content=$(echo "$content" | sed "s|> \*\*Responsavel:\*\*|> **Responsável:** $responsavel|")

    echo "$content" > "$filepath"
    __ok "Criado: $filepath"
    __cdb_log "INFO" "vtask: criado $filename ($cliente_tag, $responsavel)"

    if [[ -n "$EDITOR" ]]; then
        $EDITOR "$filepath"
    fi
}

# ============================================
# CRIAÇÃO DE NOTAS -- vnova
# ============================================

# Propósito: Criar nova nota no vault a partir de template por tipo
# Uso: vnova <tipo> [nome]
# Completa:
#   <tipo>=__vnova_tipos
vnova() {
    local tipo="$1"
    local nome="$2"

    if [[ -z "$tipo" ]]; then
        __err "Uso: vnova <tipo> [nome]"
        echo ""
        echo -e "  ${D_COMMENT}Tipos disponíveis:${D_RESET}"
        echo -e "  ${D_FG}  daily     ${D_COMMENT}-- Nota diária${D_RESET}"
        echo -e "  ${D_FG}  projeto   ${D_COMMENT}-- Projeto de código${D_RESET}"
        echo -e "  ${D_FG}  trabalho  ${D_COMMENT}-- Nota de trabalho${D_RESET}"
        echo -e "  ${D_FG}  conceito  ${D_COMMENT}-- Referência/conhecimento${D_RESET}"
        echo -e "  ${D_FG}  pessoal   ${D_COMMENT}-- Nota pessoal${D_RESET}"
        echo -e "  ${D_FG}  saude     ${D_COMMENT}-- Registro de saúde${D_RESET}"
        echo -e "  ${D_FG}  habito    ${D_COMMENT}-- Hábito${D_RESET}"
        echo -e "  ${D_FG}  meta      ${D_COMMENT}-- Meta pessoal${D_RESET}"
        echo -e "  ${D_FG}  estudo    ${D_COMMENT}-- Anotação de estudo${D_RESET}"
        echo -e "  ${D_FG}  evento    ${D_COMMENT}-- Evento/agenda${D_RESET}"
        echo -e "  ${D_FG}  conta     ${D_COMMENT}-- Conta/financeiro${D_RESET}"
        return 1
    fi

    local template_file="$TEMPLATES_DIR/${tipo}.md"
    if [[ ! -f "$template_file" ]]; then
        __err "Template não encontrado: $tipo"
        return 1
    fi

    local autor=$(__cdb_get_autor)
    local target_dir=""

    case "$tipo" in
        daily)
            target_dir="$VAULT_DIR/Diario/$(date +%Y)"
            [[ -z "$nome" ]] && nome="$(date +%Y-%m-%d)"
            ;;
        projeto)
            target_dir="$VAULT_DIR/Projetos"
            ;;
        trabalho)
            if [[ "$autor" == "andre" ]]; then
                target_dir="$VAULT_DIR/Trabalho/Andre"
            else
                target_dir="$VAULT_DIR/Trabalho/Vitoria"
            fi
            ;;
        conceito|estudo)
            target_dir="$VAULT_DIR/Conceitos"
            ;;
        pessoal)
            if [[ "$autor" == "andre" ]]; then
                target_dir="$VAULT_DIR/Pessoal/Andre"
            else
                target_dir="$VAULT_DIR/Pessoal/Vitoria"
            fi
            ;;
        saude)
            if [[ "$autor" == "andre" ]]; then
                target_dir="$VAULT_DIR/Pessoal/Andre/Saude"
            else
                target_dir="$VAULT_DIR/Pessoal/Vitoria/Saude"
            fi
            ;;
        habito)
            if [[ "$autor" == "andre" ]]; then
                target_dir="$VAULT_DIR/Pessoal/Andre/Habitos"
            else
                target_dir="$VAULT_DIR/Pessoal/Vitoria/Habitos"
            fi
            ;;
        meta)
            target_dir="$VAULT_DIR/Pessoal/Casal/Metas"
            ;;
        evento)
            target_dir="$VAULT_DIR/Pessoal/Casal/Eventos"
            ;;
        conta)
            target_dir="$VAULT_DIR/Pessoal/Casal/Contas"
            ;;
        *)
            target_dir="$VAULT_DIR/Inbox"
            ;;
    esac

    if [[ -z "$nome" ]]; then
        __err "Nome obrigatório para tipo '$tipo'"
        __warn "Uso: vnova $tipo \"Nome da Nota\""
        return 1
    fi

    mkdir -p "$target_dir"

    local filename
    local today=$(date +%Y-%m-%d)

    if [[ "$tipo" == "daily" ]]; then
        filename="${nome}.md"
    else
        filename="${today}_$(echo "$nome" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-' | cut -c1-60).md"
    fi

    local filepath="$target_dir/$filename"

    if [[ -f "$filepath" ]]; then
        __ok "Arquivo já existe: $filename"
        if [[ -n "$EDITOR" ]]; then
            $EDITOR "$filepath"
        fi
        return 0
    fi

    local content=$(<"$template_file")
    content="${content//\{\{title\}\}/$nome}"
    content="${content//\{\{date:YYYY-MM-DD\}\}/$today}"
    content="${content//\{\{date:dddd\}\}/$(date +%A)}"
    content="${content//\{\{date:YYYY-MM-DD HH:mm\}\}/${today} $(date +%H:%M)}"

    content=$(echo "$content" | sed "s/^autor: $/autor: $autor/")

    echo "$content" > "$filepath"
    __ok "Criado: $filepath"
    __cdb_log "INFO" "vnova: criado $filename (tipo=$tipo, autor=$autor)"

    if [[ -n "$EDITOR" ]]; then
        $EDITOR "$filepath"
    fi
}

# ============================================
# INBOX
# ============================================

# Propósito: Listar e processar arquivos do Inbox do vault
# Uso: vinbox
vinbox() {
    local inbox_dir="$VAULT_DIR/Inbox"

    if [[ ! -d "$inbox_dir" ]]; then
        __warn "Diretório Inbox não encontrado"
        return 1
    fi

    __cdb_header "INBOX" "$D_CYAN"

    local arquivos=("$inbox_dir"/*.md(N))

    if (( ${#arquivos[@]} == 0 )); then
        echo ""
        echo -e "  ${D_GREEN}Inbox vazio!${D_RESET}"
        echo ""
        return 0
    fi

    echo ""
    echo -e "  ${D_COMMENT}${#arquivos[@]} arquivo(s) encontrado(s):${D_RESET}"
    echo ""

    for arquivo in "${arquivos[@]}"; do
        local nome=$(basename "$arquivo" .md)
        local tamanho=$(du -h "$arquivo" 2>/dev/null | cut -f1)
        local primeira_linha=""

        while IFS= read -r linha; do
            [[ "$linha" == "---" ]] && continue
            [[ -z "$linha" ]] && continue
            [[ "$linha" =~ ^[a-z_]+: ]] && continue
            [[ "$linha" =~ ^"  -" ]] && continue
            primeira_linha="$linha"
            break
        done < "$arquivo"

        if [[ ${#primeira_linha} -gt 60 ]]; then
            primeira_linha="${primeira_linha:0:57}..."
        fi

        echo -e "  ${D_COMMENT}|${D_RESET} ${D_FG}${nome}${D_RESET} ${D_COMMENT}(${tamanho})${D_RESET}"
        if [[ -n "$primeira_linha" ]]; then
            echo -e "  ${D_COMMENT}|  ${primeira_linha}${D_RESET}"
        fi
    done

    local count=${#arquivos[@]}
    echo ""
    echo -e "  ${D_COMMENT}$count arquivo(s) no Inbox${D_RESET}"
    if [[ -f "$SCRIPTS_DIR/inbox_processor.py" ]]; then
        echo ""
        echo -e "  ${D_CYAN}[p]${D_RESET} Processar com Inbox Inteligente"
        echo -e "  ${D_CYAN}[d]${D_RESET} Dry-run (apenas sugestões)"
        echo -e "  ${D_CYAN}[q]${D_RESET} Sair"
        echo ""
        read -k1 "resposta?  Opção: "
        echo ""
        case "$resposta" in
            p) python3 "$SCRIPTS_DIR/inbox_processor.py" ;;
            d) python3 "$SCRIPTS_DIR/inbox_processor.py" --dry-run ;;
            *) return 0 ;;
        esac
    fi
}

# ============================================
# ESTATÍSTICAS
# ============================================

# Propósito: Estatísticas do vault (notas, tamanho, hubs, responsáveis)
# Uso: vstats
vstats() {
    __cdb_header "ESTATÍSTICAS DO VAULT" "$D_CYAN"

    local total_notes=$(find "$VAULT_DIR" -name "*.md" -not -path "*/\.*" -not -path "*/Arquivo/*" 2>/dev/null | wc -l)
    local vault_size=$(du -sh "$VAULT_DIR" 2>/dev/null | cut -f1)
    local sync_size=$(du -sh --exclude=Arquivo "$VAULT_DIR" 2>/dev/null | cut -f1)

    echo ""
    echo -e "  ${D_COMMENT}Notas:${D_RESET} ${D_FG}$total_notes${D_RESET}"
    echo -e "  ${D_COMMENT}Total:${D_RESET} ${D_FG}$vault_size${D_RESET}"
    echo -e "  ${D_COMMENT}Sync:${D_RESET}  ${D_FG}$sync_size${D_RESET}"
    echo ""

    echo -e "${D_PURPLE}Por Hub:${D_RESET}"
    for hub in Pessoal Trabalho Projetos Conceitos Diario; do
        local count=$(find "$VAULT_DIR/$hub" -name "*.md" 2>/dev/null | wc -l)
        printf "  ${D_COMMENT}|${D_RESET} ${D_FG}%-15s${D_RESET} %4d notas\n" "$hub:" $count
    done
    echo ""

    echo -e "${D_PURPLE}Por Responsável:${D_RESET}"
    for pessoa_dir in "Trabalho/Andre" "Trabalho/Vitoria" "Pessoal/Andre" "Pessoal/Vitoria" "Pessoal/Casal"; do
        local dir_path="$VAULT_DIR/$pessoa_dir"
        if [[ -d "$dir_path" ]]; then
            local count=$(find "$dir_path" -name "*.md" 2>/dev/null | wc -l)
            printf "  ${D_COMMENT}|${D_RESET} ${D_FG}%-25s${D_RESET} %4d notas\n" "$pessoa_dir:" $count
        fi
    done
    echo ""

    echo -e "${D_PURPLE}Inbox:${D_RESET}"
    local inbox_count=$(find "$VAULT_DIR/Inbox" -name "*.md" 2>/dev/null | wc -l)
    echo -e "  ${D_COMMENT}|${D_RESET} ${D_FG}$inbox_count${D_RESET} arquivo(s) pendente(s)"
    echo ""

    echo -e "${D_PURPLE}Recentes (7 dias):${D_RESET}"
    find "$VAULT_DIR" -name "*.md" -mtime -7 -not -path "*/\.*" -not -path "*/Arquivo/*" 2>/dev/null | head -5 | while read f; do
        echo -e "  ${D_COMMENT}|${D_RESET} $(basename "$f")"
    done
    echo ""
}

# ============================================
# BUSCA
# ============================================

# Propósito: Buscar notas no vault por título e conteúdo
# Uso: vault_buscar <termo>
vault_buscar() {
    local query="$1"
    [[ -z "$query" ]] && { __err "Uso: vault_buscar <termo>"; return 1; }

    __cdb_header "BUSCANDO: $query" "$D_CYAN"

    echo ""
    echo -e "${D_PURPLE}Em títulos:${D_RESET}"
    local encontrou_titulo=0
    while read f; do
        local nome=$(basename "$f" .md)
        if echo "$nome" | grep -qi "$query"; then
            echo -e "  ${D_COMMENT}|${D_RESET} ${D_FG}${nome}${D_RESET}"
            echo -e "  ${D_COMMENT}|  -> ${f}${D_RESET}"
            encontrou_titulo=1
        fi
    done < <(find "$VAULT_DIR" -name "*.md" -not -path "*/\.*" -not -path "*/Arquivo/*" 2>/dev/null)

    echo ""
    echo -e "${D_PURPLE}Em conteúdo:${D_RESET}"
    grep -r -l -i "$query" "$VAULT_DIR" --include="*.md" 2>/dev/null | grep -v "/\." | grep -v "/Arquivo/" | head -10 | while read f; do
        echo -e "  ${D_COMMENT}|${D_RESET} $(basename "$f")"
    done
    echo ""
}

# ============================================
# TAMANHO
# ============================================

# Propósito: Exibir tamanho do vault por pasta
# Uso: vsize
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
    local sync=$(du -sh --exclude=Arquivo "$VAULT_DIR" 2>/dev/null | cut -f1)
    echo -e "  ${D_COMMENT}Total:${D_RESET} $total"
    echo -e "  ${D_COMMENT}Sync:${D_RESET}  $sync"
    echo ""
}

# ============================================
# BACKUP E RECUPERAÇÃO
# ============================================

# Propósito: Restaurar arquivo do vault a partir de backup
# Uso: vrestore <caminho>
vrestore() {
    if [[ ! -f "$SCRIPTS_DIR/vault_backup.py" ]]; then
        __err "Script de backup não encontrado"
        return 1
    fi
    python3 "$SCRIPTS_DIR/vault_backup.py" --restore "$@"
}

# Propósito: Listar backups disponíveis do vault
# Uso: vbackups [filtro]
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
# HELP
# ============================================

# Propósito: Exibir ajuda do Controle de Bordo (comandos e aliases)
# Uso: vhelp
vhelp() {
    __cdb_header "CONTROLE DE BORDO -- AJUDA" "$D_CYAN"
    echo ""

    echo -e "${D_PURPLE}Navegação:${D_RESET}"
    echo -e "  ${D_FG}cdb${D_RESET}                       ${D_COMMENT}Ir para o diretório do vault${D_RESET}"
    echo -e "  ${D_FG}vopen${D_RESET}                     ${D_COMMENT}Abrir vault no Obsidian${D_RESET}"
    echo ""

    echo -e "${D_PURPLE}Criação:${D_RESET}"
    echo -e "  ${D_FG}vtask <cliente> [quinzena]${D_RESET} ${D_COMMENT}Criar nota quinzenal de tarefas${D_RESET}"
    echo -e "  ${D_FG}  ${D_COMMENT}Clientes: mec, g4f, energisa, mulher, pessoal${D_RESET}"
    echo -e "  ${D_FG}vnova <tipo> [nome]${D_RESET}       ${D_COMMENT}Criar nota com autor automático${D_RESET}"
    echo -e "  ${D_FG}  ${D_COMMENT}Tipos: daily, projeto, trabalho, conceito, pessoal,${D_RESET}"
    echo -e "  ${D_FG}  ${D_COMMENT}       saude, habito, meta, estudo, evento, conta${D_RESET}"
    echo ""

    echo -e "${D_PURPLE}Consulta:${D_RESET}"
    echo -e "  ${D_FG}vstats${D_RESET}                    ${D_COMMENT}Estatísticas do vault${D_RESET}"
    echo -e "  ${D_FG}vsize${D_RESET}                     ${D_COMMENT}Tamanho por pasta${D_RESET}"
    echo -e "  ${D_FG}vault_buscar <termo>${D_RESET}      ${D_COMMENT}Buscar notas por título e conteúdo${D_RESET}"
    echo -e "  ${D_FG}vinbox${D_RESET}                    ${D_COMMENT}Listar Inbox com preview${D_RESET}"
    echo ""

    echo -e "${D_PURPLE}Criação rápida (do Andromeda):${D_RESET}"
    echo -e "  ${D_FG}vdaily${D_RESET}                    ${D_COMMENT}Nova daily note${D_RESET}"
    echo -e "  ${D_FG}vproj/vwork/vconc/vpess${D_RESET}   ${D_COMMENT}Projeto / trabalho / conceito / pessoal${D_RESET}"
    echo ""

    echo -e "${D_PURPLE}Automação (do Andromeda):${D_RESET}"
    echo -e "  ${D_FG}vauto${D_RESET}                     ${D_COMMENT}Auto-tags e relações${D_RESET}"
    echo -e "  ${D_FG}vpad${D_RESET}                      ${D_COMMENT}Padronizar documentos${D_RESET}"
    echo -e "  ${D_FG}vcheck${D_RESET}                    ${D_COMMENT}Verificar consistência${D_RESET}"
    echo -e "  ${D_FG}vhealth${D_RESET}                   ${D_COMMENT}Health check do vault${D_RESET}"
    echo -e "  ${D_FG}vmaint${D_RESET}                    ${D_COMMENT}Manutenção completa${D_RESET}"
    echo -e "  ${D_FG}controle_de_bordo / cbordo${D_RESET} ${D_COMMENT}Pipeline completo (--dry-run, --no-open)${D_RESET}"
    echo ""

    echo -e "${D_PURPLE}Sync e exportação (do Andromeda):${D_RESET}"
    echo -e "  ${D_FG}vsync / vquick${D_RESET}            ${D_COMMENT}Sync completo / rápido (com lock)${D_RESET}"
    echo -e "  ${D_FG}vexport <device>${D_RESET}          ${D_COMMENT}Exportar para dispositivo${D_RESET}"
    echo -e "  ${D_FG}vmobile${D_RESET}                   ${D_COMMENT}Preparar pacote mobile${D_RESET}"
    echo -e "  ${D_FG}vinbox_clean${D_RESET}              ${D_COMMENT}Mover imagens para _Attachments${D_RESET}"
    echo ""

    echo -e "${D_PURPLE}Emojis (do Andromeda):${D_RESET}"
    echo -e "  ${D_FG}vcheck_emoji / vclean_emoji${D_RESET} ${D_COMMENT}Detectar / limpar emojis no vault${D_RESET}"
    echo -e "  ${D_FG}vinstall_emoji_hook${D_RESET}       ${D_COMMENT}Hook pre-commit anti-emoji${D_RESET}"
    echo ""

    echo -e "${D_PURPLE}Sistema:${D_RESET}"
    echo -e "  ${D_FG}vbackups [filtro]${D_RESET}         ${D_COMMENT}Listar backups disponíveis${D_RESET}"
    echo -e "  ${D_FG}vrestore <caminho>${D_RESET}        ${D_COMMENT}Restaurar arquivo do backup${D_RESET}"
    echo -e "  ${D_FG}vhelp${D_RESET}                     ${D_COMMENT}Esta ajuda${D_RESET}"
    echo ""
}

# ============================================
# COMPLETION
# ============================================

if [[ -n "$ZSH_VERSION" ]]; then
    _vtask_clients() {
        local -a clients
        clients=('mec:MEC direto (Vitória)' 'g4f:G4F contractor (André)' 'energisa:Energisa (André)' 'mulher:Projeto Mulher (Vitória)' 'pessoal:Tarefas pessoais (Casal)')
        _describe 'cliente' clients
    }

    _vnova_tipos() {
        local -a tipos
        tipos=('daily:Nota diária' 'projeto:Projeto de código' 'trabalho:Nota de trabalho' 'conceito:Referência' 'pessoal:Nota pessoal' 'saude:Registro de saúde' 'habito:Hábito' 'meta:Meta pessoal' 'estudo:Anotação de estudo' 'evento:Evento' 'conta:Conta financeira')
        _describe 'tipo' tipos
    }

    _vfiles() { _files -W "$VAULT_DIR" -g "*.md"; }

    compdef _vtask_clients vtask
    compdef _vnova_tipos vnova
    compdef _vfiles vault_buscar
fi

# ============================================
# PORTADO DO ANDROMEDA-OS (mediação 2026-07-21)
# ============================================

# ============================================
# CRIAÇÃO DE NOTAS -- templates rápidos
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
# LIMPEZA DO INBOX
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

# ============================================
# AUTOMAÇÃO COMPLETA
# ============================================

__sync_spellbook() {
    local spellbook="$HOME/Desenvolvimento/Spellbook-OS"
    [[ ! -d "$spellbook" ]] && { __warn "Spellbook-OS não encontrado"; return 0; }

    local src="$HOME/.config/zsh/functions"
    local dst="$spellbook/functions"

    for f in controle-de-bordo.zsh sync.zsh; do
        if [[ -f "$src/$f" ]]; then
            cp "$src/$f" "$dst/$f"
        fi
    done

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

# Completion das funções portadas
if [[ -n "$ZSH_VERSION" ]]; then
    compdef _vfiles vpad vcheck
fi

# ============================================
# INICIALIZAÇÃO
# ============================================

__cdb_log "INFO" "Controle de Bordo v3.0 carregado (autor: $(__cdb_get_autor))"

# "A liberdade consiste em fazer tudo o que não prejudica o próximo." -- Declaração dos Direitos do Homem e do Cidadão, 1789
