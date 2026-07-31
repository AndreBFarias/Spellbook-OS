#!/bin/zsh
# Vault Energisa -- CLI
# Navegacao, captura e automacao do vault de projetos Energisa.
# Espelha o padrão de ~/.config/zsh/functions/controle-de-bordo.zsh

# ============================================
# CONFIGURAÇÃO
# ============================================

VAULT_ENERGISA_DIR="${VAULT_ENERGISA_DIR:-$HOME/Vault-Energisa}"
VE_SISTEMA="$VAULT_ENERGISA_DIR/.sistema"
VE_SCRIPTS="$VE_SISTEMA/scripts"
VE_TEMPLATES="$VE_SISTEMA/templates"
VE_LOGS="$VE_SISTEMA/logs"
VE_INBOX="$VAULT_ENERGISA_DIR/Inbox"
VE_PROJETO_ATUAL="10-Projetos/486191 - Visões BI PRIO"

[[ -d "$VE_LOGS" ]] || mkdir -p "$VE_LOGS"

# ============================================
# HELPERS
# ============================================

__ve_log() {
    print -r -- "[$(date '+%Y-%m-%d %H:%M:%S')] [$1] $2" >> "$VE_LOGS/ve.log"
}

__ve_header() {
    local cor="${2:-$D_CYAN}"
    print ""
    print -P "${cor}────────────────────────────────────────${D_RESET:-$reset_color}"
    print -P "${cor}  $1${D_RESET:-$reset_color}"
    print -P "${cor}────────────────────────────────────────${D_RESET:-$reset_color}"
}

__ve_py() {
    # roda um script do .sistema com o vault correto no ambiente
    BORDO_DIR="$VAULT_ENERGISA_DIR" python3 "$VE_SCRIPTS/$1" "${@:2}"
}

__ve_check() {
    if [[ ! -d "$VAULT_ENERGISA_DIR" ]]; then
        print -u2 "Vault não encontrado: $VAULT_ENERGISA_DIR"
        return 1
    fi
}

# ============================================
# NAVEGACAO
# ============================================

ve() {
    __ve_check || return 1
    if [[ -z "$1" ]]; then
        cd "$VAULT_ENERGISA_DIR"
        return
    fi
    local alvo
    case "$1" in
        proj|projeto)  alvo="$VE_PROJETO_ATUAL" ;;
        req|requisitos) alvo="$VE_PROJETO_ATUAL/Requisitos" ;;
        pend|pendencias) alvo="$VE_PROJETO_ATUAL/Pendências" ;;
        reu|reunioes)  alvo="$VE_PROJETO_ATUAL/Reuniões" ;;
        entregas)      alvo="$VE_PROJETO_ATUAL/Entregas" ;;
        fontes)        alvo="$VE_PROJETO_ATUAL/Fontes" ;;
        pessoas)       alvo="90-Pessoas" ;;
        sistemas)      alvo="91-Sistemas" ;;
        dados)         alvo="92-Dados" ;;
        sql)           alvo="92-Dados/Consultas SQL" ;;
        inbox)         alvo="Inbox" ;;
        sistema)       alvo=".sistema" ;;
        *)             alvo="$1" ;;
    esac
    if [[ -d "$VAULT_ENERGISA_DIR/$alvo" ]]; then
        cd "$VAULT_ENERGISA_DIR/$alvo"
    else
        print -u2 "Destino desconhecido: $1"
        print -u2 "Use: ve [proj|req|pend|reu|entregas|fontes|pessoas|sistemas|dados|sql|inbox|sistema]"
        return 1
    fi
}

# ============================================
# ABRIR NO OBSIDIAN
# ============================================

veopen() {
    __ve_check || return 1
    local vault_name="${VAULT_ENERGISA_DIR:t}"
    if [[ -n "$1" ]]; then
        local nota="${1%.md}"
        xdg-open "obsidian://open?vault=$vault_name&file=$(print -r -- "$nota" | sed 's/ /%20/g')" 2>/dev/null
    else
        xdg-open "obsidian://open?vault=$vault_name" 2>/dev/null
    fi
    __ve_log INFO "obsidian aberto: ${1:-raiz}"
}

# ============================================
# INBOX -- CAPTURA RAPIDA
# ============================================

vecap() {
    __ve_check || return 1
    if [[ -z "$1" ]]; then
        print -u2 "uso: vecap <texto da captura>"
        print -u2 "     vecap --arquivo <caminho>   (move arquivo para a Inbox)"
        return 1
    fi

    if [[ "$1" == "--arquivo" || "$1" == "-a" ]]; then
        shift
        for f in "$@"; do
            [[ -e "$f" ]] || { print -u2 "não existe: $f"; continue; }
            mv -n -- "$f" "$VE_INBOX/" && print "-> Inbox/${f:t}"
        done
        __ve_log INFO "arquivos capturados: $#"
        return
    fi

    local ts="$(date '+%Y-%m-%d %H:%M')"
    local slug="$(print -r -- "$*" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]\+/-/g; s/^-//; s/-$//' | cut -c1-60)"
    local arquivo="$VE_INBOX/$(date '+%Y-%m-%d')-${slug:-captura}.md"

    cat > "$arquivo" <<EOF
---
tipo: captura
status: não-processada
capturado_em: $ts
tags: [inbox, tipo/captura]
---

# ${*}

$*

## Contexto

## Encaminhamento

- [ ] classificar e mover para a pasta definitiva
EOF
    print "capturado: ${arquivo:t}"
    __ve_log INFO "captura: ${arquivo:t}"
}

# ============================================
# INBOX -- PROCESSAMENTO
# ============================================

veinbox() {
    __ve_check || return 1
    local n=$(find "$VE_INBOX" -maxdepth 1 -type f ! -name '.*' 2>/dev/null | wc -l)

    if [[ -z "$1" ]]; then
        __ve_header "Inbox -- $n item(ns)"
        if (( n == 0 )); then
            print "  vazia"
        else
            find "$VE_INBOX" -maxdepth 1 -type f ! -name '.*' -printf '  %f\n' 2>/dev/null | sort
        fi
        print ""
        print "  veinbox --dry      simula a classificacao"
        print "  veinbox --auto     aplica a classificacao de alta confianca"
        print "  veinbox -i         processa item a item"
        return
    fi

    case "$1" in
        --dry|--dry-run) __ve_py inbox_processor.py --dry-run ;;
        --auto)          __ve_py inbox_processor.py --auto ;;
        -i|--interativo) __ve_py inbox_processor.py --interativo ;;
        *)               __ve_py inbox_processor.py "$@" ;;
    esac
}

# ============================================
# AUTOMACAO
# ============================================

veauto() {
    __ve_check || return 1
    __ve_header "Organizador -- aplicando alta confianca"
    __ve_py organizar.py --auto
}

vedry() {
    __ve_check || return 1
    __ve_header "Organizador -- simulacao"
    __ve_py organizar.py --dry-run
}

verevisar() {
    __ve_check || return 1
    local bandeja="$VAULT_ENERGISA_DIR/Revisar.md"
    case "$1" in
        --aplicar) __ve_py organizar.py --aplicar-revisar ;;
        *)
            if [[ -f "$bandeja" ]]; then
                ${PAGER:-less} "$bandeja"
            else
                print "bandeja vazia (nenhum item de media confianca)"
            fi
            ;;
    esac
}

vehealth() {
    __ve_check || return 1
    __ve_header "Health check do vault"
    __ve_py health_check.py "$@"
}

vedigest() {
    __ve_check || return 1
    local d="$VAULT_ENERGISA_DIR/00-Sistema/_Digest.md"
    [[ -f "$d" ]] && cat "$d" || print "sem digest ainda -- rode veauto"
}

veundo() {
    __ve_check || return 1
    local ultima=$(find "$VE_SISTEMA/organizacao/rodadas" -maxdepth 1 -type d -name '20*' 2>/dev/null | sort | tail -1)
    if [[ -z "$ultima" ]]; then
        print "nenhuma rodada registrada"
        return 1
    fi
    if [[ ! -f "$ultima/undo.sh" ]]; then
        print "rodada ${ultima:t} não alterou nada (sem undo.sh)"
        return 1
    fi
    __ve_header "Desfazendo rodada ${ultima:t}"
    cat "$ultima/undo.sh"
    print ""
    read "resp?Executar o undo acima? [s/N] "
    [[ "$resp" == [sS] ]] && bash "$ultima/undo.sh" && print "revertido"
}

# ============================================
# BUSCA
# ============================================

vebusca() {
    __ve_check || return 1
    [[ -z "$1" ]] && { print -u2 "uso: vebusca <termo>"; return 1; }
    if command -v rg >/dev/null 2>&1; then
        rg -i --type md -n "$1" "$VAULT_ENERGISA_DIR" \
           --glob '!.sistema' --glob '!99-Arquivo' --glob '!.obsidian'
    else
        grep -rin --include='*.md' "$1" "$VAULT_ENERGISA_DIR" \
             --exclude-dir='.sistema' --exclude-dir='99-Arquivo' --exclude-dir='.obsidian'
    fi
}

vepo() {
    # atalho: tudo que depende do Product Owner
    __ve_check || return 1
    __ve_header "Pendente de confirmacao com o PO"
    vebusca 'A CONFIRMAR COM PO'
}

# ============================================
# STATUS
# ============================================

vestatus() {
    __ve_check || return 1
    local raiz="$VAULT_ENERGISA_DIR"
    local notas=$(find "$raiz" -name '*.md' -not -path '*/99-Arquivo/*' -not -path '*/.sistema/*' 2>/dev/null | wc -l)
    local sql=$(find "$raiz/92-Dados" -name '*.sql' 2>/dev/null | wc -l)
    local inbox=$(find "$VE_INBOX" -maxdepth 1 -type f ! -name '.*' 2>/dev/null | wc -l)
    local pend=$(find "$raiz/$VE_PROJETO_ATUAL/Pendências" -name 'P*.md' 2>/dev/null | wc -l)
    local req=$(find "$raiz/$VE_PROJETO_ATUAL/Requisitos" -name 'RN*.md' 2>/dev/null | wc -l)
    local po=$(grep -rl 'A CONFIRMAR COM PO' "$raiz" --include='*.md' 2>/dev/null | wc -l)

    __ve_header "Vault Energisa"
    print "  notas            $notas"
    print "  requisitos       $req"
    print "  pendencias       $pend"
    print "  queries SQL      $sql"
    print "  inbox            $inbox"
    print "  notas com lacuna do PO   $po"
    print ""
    print "  raiz: $raiz"
    local t=$(systemctl --user list-timers vault-energisa-organizar.timer --all 2>/dev/null | sed -n 2p)
    [[ -n "$t" ]] && print "  timer: $(print -r -- "$t" | awk '{print $1,$2,$3}')"
}

# ============================================
# AJUDA
# ============================================

vehelp() {
    __ve_header "Vault Energisa -- comandos"
    cat <<'EOF'

  NAVEGACAO
    ve [destino]        entra no vault. destinos: proj, req, pend, reu,
                        entregas, fontes, pessoas, sistemas, dados, sql,
                        inbox, sistema
    veopen [nota]       abre no Obsidian

  CAPTURA
    vecap <texto>       cria nota de captura na Inbox
    vecap -a <arquivo>  move arquivo(s) para a Inbox

  INBOX
    veinbox             lista o que esta na Inbox
    veinbox --dry       simula a classificacao
    veinbox --auto      classifica e move o de alta confianca
    veinbox -i          processa item a item

  PRINCIPAL
    energisa            automacao completa + abre o Obsidian
    energisa --dry-run  simula tudo
    energisa --no-open  roda sem abrir o app

  AUTOMACAO
    vedry               simula a organizacao do vault
    veauto              organiza (alta confianca)
    verevisar           abre a bandeja de media confianca
    verevisar --aplicar aplica os itens marcados na bandeja
    veundo              desfaz a ultima rodada
    vehealth            checagem de integridade
    vedigest            resumo da ultima rodada

  BUSCA
    vebusca <termo>     procura nas notas
    vepo                lista tudo que depende do Product Owner

  STATUS
    vestatus            panorama do vault
    vehelp              esta ajuda

EOF
}

alias venergisa='ve'
alias veh='vehelp'

# ============================================
# CICLO COMPLETO DE ORGANIZACAO
# ============================================

veenriquecer() {
    __ve_check || return 1
    __ve_header "Enriquecedor -- tags, links e indices"
    __ve_py enriquecer.py "$@"
}

vesync() {
    __ve_check || return 1
    local aplicar="--aplicar"
    local modo_org="--auto"
    if [[ "$1" == "--dry" || "$1" == "--dry-run" ]]; then
        aplicar=""; modo_org="--dry-run"
        __ve_header "Ciclo completo -- SIMULACAO"
    else
        __ve_header "Ciclo completo do vault"
    fi

    print -P "\n${D_CYAN:-}[1/4]${D_RESET:-} organizando arquivos"
    __ve_py organizar.py $modo_org

    print -P "\n${D_CYAN:-}[2/4]${D_RESET:-} enriquecendo notas"
    __ve_py enriquecer.py $aplicar --quieto

    print -P "\n${D_CYAN:-}[3/4]${D_RESET:-} checando integridade"
    __ve_py health_check.py 2>/dev/null | tail -12

    print -P "\n${D_CYAN:-}[4/4]${D_RESET:-} digest"
    local d="$VAULT_ENERGISA_DIR/00-Sistema/_Digest.md"
    [[ -f "$d" ]] && cat "$d" || print "  (sem digest)"

    __ve_log INFO "vesync ${modo_org}"
    print ""
}

# ============================================
# AUTOMACAO COMPLETA + ABERTURA
# espelha controle_de_bordo() do vault pessoal
# ============================================

energisa() {
    __ve_check || return 1

    local skip_open=0 dry_run=0 verbose=0
    for arg in "$@"; do
        case "$arg" in
            --no-open)  skip_open=1 ;;
            --dry-run)  dry_run=1 ;;
            --verbose)  verbose=1 ;;
            -h|--help)
                print "uso: energisa [--dry-run] [--no-open] [--verbose]"
                print "  --dry-run   simula tudo, não altera nada"
                print "  --no-open   não abre o Obsidian ao final"
                print "  --verbose   mostra a saida completa de cada etapa"
                return 0 ;;
        esac
    done

    __ve_header "VAULT ENERGISA -- AUTOMACAO COMPLETA" "${D_CYAN:-}"

    local flag_org="--auto" flag_enr="--aplicar"
    if (( dry_run )); then
        flag_org="--dry-run"; flag_enr=""
        print -P "${D_YELLOW:-}  modo simulacao: nada sera alterado${D_RESET:-}"
    fi
    local quieto="--quieto"
    (( verbose )) && quieto=""

    # aviso: editar config com o Obsidian aberto pode ser sobrescrito ao fechar
    if pgrep -f "obsidian" >/dev/null 2>&1; then
        if wmctrl -lx 2>/dev/null | grep -qi "Vault-Energisa"; then
            print -P "${D_COMMENT:-}  (Obsidian com o vault aberto -- use Ctrl+R nele ao final)${D_RESET:-}"
        fi
    fi

    print -P "\n${D_COMMENT:-}[1/6] Limpando backups antigos${D_RESET:-}"
    __ve_py vault_backup.py --cleanup 2>/dev/null | tail -3

    print -P "\n${D_COMMENT:-}[2/6] Organizando arquivos${D_RESET:-}"
    __ve_py organizar.py $flag_org

    print -P "\n${D_COMMENT:-}[3/6] Processando a Inbox${D_RESET:-}"
    local n_inbox=$(find "$VE_INBOX" -maxdepth 1 -type f ! -name '.*' 2>/dev/null | wc -l)
    if (( n_inbox > 0 )); then
        if (( dry_run )); then
            __ve_py inbox_processor.py --dry-run
        else
            __ve_py inbox_processor.py --auto
        fi
    else
        print "  Inbox vazia"
    fi

    print -P "\n${D_COMMENT:-}[4/6] Enriquecendo notas (tags, links, indices)${D_RESET:-}"
    __ve_py enriquecer.py $flag_enr $quieto

    print -P "\n${D_COMMENT:-}[5/6] Verificando integridade${D_RESET:-}"
    __ve_py health_check.py 2>/dev/null | tail -10

    print -P "\n${D_COMMENT:-}[6/6] Digest${D_RESET:-}"
    local d="$VAULT_ENERGISA_DIR/00-Sistema/_Digest.md"
    [[ -f "$d" ]] && cat "$d" || print "  (sem digest)"

    __ve_header "AUTOMACAO CONCLUIDA" "${D_GREEN:-}"
    __ve_log INFO "energisa (${flag_org})"

    if (( ! skip_open )); then
        print "\n  abrindo o vault no Obsidian"
        veopen
    fi
}

alias energ='energisa'
