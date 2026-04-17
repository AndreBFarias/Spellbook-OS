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
        local periodo="${ano}-${(l:2::0:)mes_num}-01 a ${ano}-${(l:2::0:)mes_num}-15"
    else
        local ultimo_dia=$(date -d "${ano}-${(l:2::0:)mes_num}-01 +1 month -1 day" +%d 2>/dev/null || echo "30")
        local periodo="${ano}-${(l:2::0:)mes_num}-16 a ${ano}-${(l:2::0:)mes_num}-${ultimo_dia}"
    fi

    local content=$(<"$template_file")
    content="${content//\{\{title\}\}/$title}"
    content="${content//\{\{date:YYYY-MM-DD\}\}/$today}"

    content=$(echo "$content" | sed "s/^autor: $/autor: $responsavel/")
    content=$(echo "$content" | sed "s/^cliente: $/cliente: $cliente_tag/")
    content=$(echo "$content" | sed "s/^responsavel: $/responsavel: $responsavel/")
    content=$(echo "$content" | sed "s/^quinzena: $/quinzena: $quinzena/")
    content=$(echo "$content" | sed "s/^periodo: \"\"$/periodo: \"$periodo\"/")

    content=$(echo "$content" | sed "s|> \*\*Origem:\*\*|> **Origem:** $cliente_tag|")
    content=$(echo "$content" | sed "s|> \*\*Periodo:\*\*|> **Período:** $periodo|")
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
# INICIALIZAÇÃO
# ============================================

__cdb_log "INFO" "Controle de Bordo v3.0 carregado (autor: $(__cdb_get_autor))"

# "A liberdade consiste em fazer tudo o que não prejudica o próximo." -- Declaração dos Direitos do Homem e do Cidadão, 1789
