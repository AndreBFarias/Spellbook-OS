#!/bin/zsh

# ============================================================================
# garimpar -- cata os arquivos dos projetos Energisa espalhados pelos discos,
#             classifica cada um e os move para a estrutura dos projetos.
#
#   garimpar            mostra o estado. NÃO muda nada. É o padrão.
#   garimpar inventario varre as partições montadas e lista os candidatos.
#   garimpar classificar pontua cada candidato contra o vocabulário de cada
#                       projeto e grava o catálogo.
#   garimpar estrutura  cria as pastas dos projetos no padrão do 486191.
#   garimpar ensaio     mostra, arquivo por arquivo, para onde cada um iria.
#   garimpar mover      move de verdade. Pede confirmação e grava o desfazer.
#   garimpar desfazer   reverte o último movimento.
#   garimpar windows    monta a partição do Windows em /mnt/win (só leitura).
#
# Por que existe: os artefatos dos dashboards da Multi (CP, Desligamento de
# Chamadas, Mailing) estão espalhados entre a home, o Windows e as pastas de
# download de dois anos. A varredura sozinha não resolve — sem catálogo, o
# arquivo achado hoje some de novo amanhã. Cada passo aqui grava o que fez.
#
# O que ele NUNCA faz: mover sem gravar antes o script que desfaz o movimento.
# ============================================================================

GARIMPO_SCRIPT="${BORDO_DIR:-$HOME/Controle de Bordo}/.sistema/scripts/garimpar_energisa.py"
GARIMPO_TRABALHO="${GARIMPO_TRABALHO:-$HOME/.cache/garimpo-energisa}"
GARIMPO_WIN_DEV="/dev/nvme1n1p3"
GARIMPO_WIN_PONTO="/mnt/win"

__garimpo_py() {
    /usr/bin/python3 "$GARIMPO_SCRIPT" "$@"
}

# -- Quantos arquivos cada etapa já produziu --
__garimpo_conta() {
    local arquivo="$1"
    [[ -f "$arquivo" ]] && echo $(( $(wc -l < "$arquivo") - 1 )) || echo "—"
}

garimpar() {
    local verbo="${1:-estado}"

    if [[ ! -f "$GARIMPO_SCRIPT" ]]; then
        __err "Não achei o garimpeiro em: $GARIMPO_SCRIPT"
        return 1
    fi

    case "$verbo" in

    # ------------------------------------------------------------------
    estado|"")
        __header "GARIMPAR: o que já foi catado" "$D_PURPLE"
        __item "Script" "$GARIMPO_SCRIPT"
        __item "Trabalho" "$GARIMPO_TRABALHO"
        __item "Inventário" "$(__garimpo_conta "$GARIMPO_TRABALHO/inventario.tsv") candidatos"
        __item "Catálogo" "$(__garimpo_conta "$GARIMPO_TRABALHO/catalogo.csv") classificados"

        if mountpoint -q "$GARIMPO_WIN_PONTO" 2>/dev/null; then
            __ok "Windows montado em $GARIMPO_WIN_PONTO"
        else
            __warn "Windows não montado — rode 'garimpar windows' para incluí-lo"
        fi

        if [[ -f "$GARIMPO_TRABALHO/catalogo.csv" ]]; then
            echo ""
            echo -e "  ${D_COMMENT}Por projeto:${D_RESET}"
            tail -n +2 "$GARIMPO_TRABALHO/catalogo.csv" | cut -d';' -f6 \
                | sort | uniq -c | sort -rn \
                | while read -r n classe; do
                    printf "  ${D_CYAN}%6s${D_RESET}  %s\n" "$n" "$classe"
                done
        fi

        local ultimo
        ultimo=$(ls -1t "$GARIMPO_TRABALHO"/desfazer-mover-*.sh 2>/dev/null | head -1)
        [[ -n "$ultimo" ]] && { echo ""; __item "Desfazer" "$(basename "$ultimo")"; }

        echo ""
        echo -e "  ${D_COMMENT}Próximo: garimpar inventario${D_RESET}"
        ;;

    # ------------------------------------------------------------------
    windows|win)
        if mountpoint -q "$GARIMPO_WIN_PONTO" 2>/dev/null; then
            __ok "Já montado em $GARIMPO_WIN_PONTO"
            return 0
        fi
        __header "Montando o Windows (somente leitura)" "$D_CYAN"
        sudo mkdir -p "$GARIMPO_WIN_PONTO"
        if sudo mount -t ntfs3 -o ro,uid=$UID,gid=$GID "$GARIMPO_WIN_DEV" "$GARIMPO_WIN_PONTO" 2>/dev/null \
           || sudo mount -t ntfs-3g -o ro,uid=$UID,gid=$GID "$GARIMPO_WIN_DEV" "$GARIMPO_WIN_PONTO" 2>/dev/null; then
            __ok "Montado em $GARIMPO_WIN_PONTO (ro)"
        else
            __err "Não consegui montar $GARIMPO_WIN_DEV"
            __warn "Confira o device com: lsblk -o NAME,SIZE,FSTYPE"
            return 1
        fi
        ;;

    # ------------------------------------------------------------------
    inventario|inventariar)
        __header "Varrendo as partições" "$D_CYAN"
        mountpoint -q "$GARIMPO_WIN_PONTO" 2>/dev/null \
            || __warn "Windows não montado — os artefatos de lá ficarão de fora"
        GARIMPO_TRABALHO="$GARIMPO_TRABALHO" __garimpo_py inventariar --trabalho "$GARIMPO_TRABALHO"
        __ok "$(__garimpo_conta "$GARIMPO_TRABALHO/inventario.tsv") candidatos"
        echo -e "  ${D_COMMENT}Próximo: garimpar classificar${D_RESET}"
        ;;

    # ------------------------------------------------------------------
    classificar)
        __header "Pontuando cada candidato" "$D_CYAN"
        if [[ ! -f "$GARIMPO_TRABALHO/inventario.tsv" ]]; then
            __err "Sem inventário. Rode 'garimpar inventario' primeiro."
            return 1
        fi
        __garimpo_py classificar --trabalho "$GARIMPO_TRABALHO" "${@:2}"
        __ok "$(__garimpo_conta "$GARIMPO_TRABALHO/catalogo.csv") classificados"
        echo -e "  ${D_COMMENT}Próximo: garimpar ensaio${D_RESET}"
        ;;

    # ------------------------------------------------------------------
    estrutura)
        __header "Criando a estrutura dos projetos" "$D_CYAN"
        __garimpo_py estrutura --trabalho "$GARIMPO_TRABALHO"
        __ok "Pastas criadas no padrão do 486191"
        ;;

    # ------------------------------------------------------------------
    ensaio)
        __header "Ensaio: para onde cada arquivo iria" "$D_YELLOW"
        __garimpo_py mover --trabalho "$GARIMPO_TRABALHO"
        ;;

    # ------------------------------------------------------------------
    mover)
        __header "Mover de verdade" "$D_ORANGE"
        if [[ ! -f "$GARIMPO_TRABALHO/catalogo.csv" ]]; then
            __err "Sem catálogo. Rode 'garimpar classificar' primeiro."
            return 1
        fi
        local n
        n=$(__garimpo_conta "$GARIMPO_TRABALHO/catalogo.csv")
        __warn "Isto MOVE $n arquivos. O original sai do lugar de origem."
        __item "Desfazer" "gravado antes de mover, em $GARIMPO_TRABALHO"
        echo ""
        echo -ne "  ${D_ORANGE}Digite MOVER para confirmar: ${D_RESET}"
        local resposta; read -r resposta
        if [[ "$resposta" != "MOVER" ]]; then
            __warn "Cancelado. Nada foi movido."
            return 1
        fi
        __garimpo_py mover --executar --trabalho "$GARIMPO_TRABALHO"
        __garimpo_py relatorio --trabalho "$GARIMPO_TRABALHO"
        __ok "Movido. Relatórios em cada _catalogo/."
        ;;

    # ------------------------------------------------------------------
    relatorio)
        __garimpo_py relatorio --trabalho "$GARIMPO_TRABALHO"
        __ok "Relatórios gerados."
        ;;

    # ------------------------------------------------------------------
    desfazer)
        local ultimo
        ultimo=$(ls -1t "$GARIMPO_TRABALHO"/desfazer-mover-*.sh 2>/dev/null | head -1)
        if [[ -z "$ultimo" ]]; then
            __err "Nenhum movimento para desfazer."
            return 1
        fi
        __header "Desfazendo o último movimento" "$D_ORANGE"
        __item "Script" "$(basename "$ultimo")"
        __item "Linhas" "$(grep -c '^mv' "$ultimo")"
        echo ""
        echo -ne "  ${D_ORANGE}Digite DESFAZER para confirmar: ${D_RESET}"
        local resposta; read -r resposta
        [[ "$resposta" != "DESFAZER" ]] && { __warn "Cancelado."; return 1; }
        bash "$ultimo" && __ok "Revertido." || __err "Reversão incompleta — leia o erro acima."
        ;;

    # ------------------------------------------------------------------
    *)
        __err "Verbo desconhecido: $verbo"
        echo -e "  ${D_COMMENT}Use: estado, windows, inventario, classificar,${D_RESET}"
        echo -e "  ${D_COMMENT}     estrutura, ensaio, mover, relatorio, desfazer${D_RESET}"
        return 1
        ;;
    esac
}
