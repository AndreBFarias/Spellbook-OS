#!/bin/zsh

__conjurar_log_file() {
    local logdir="${XDG_CACHE_HOME:-$HOME/.cache}/conjurar"
    mkdir -p "$logdir"
    echo "$logdir/conjurar.log"
}

__conjurar_log() {
    local comando="$1"
    local exit_code="${2:-0}"
    local log="$(__conjurar_log_file)"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] exit=$exit_code :: $comando" >> "$log"

    # Rotação: se ultrapassar 1MB, roda para .1 e cria novo
    local size=$(stat -c%s "$log" 2>/dev/null || echo 0)
    if (( size > 1048576 )); then
        mv "$log" "${log}.1"
    fi
}

__conjurar_recent() {
    local log="$(__conjurar_log_file)"
    [[ -f "$log" ]] || { echo ""; return; }
    tail -n 200 "$log" | awk -F' :: ' 'NF==2 {print $2}' | awk '!seen[$0]++' | tail -n 5
}

__conjurar_read_timeout() {
    local prompt="$1"
    local timeout="${CONJURAR_TIMEOUT:-30}"
    local valor=""
    echo -e -n "$prompt"
    if read -t "$timeout" valor; then
        echo "$valor"
        return 0
    else
        echo ""
        __err "Tempo limite excedido (${timeout}s)"
        return 1
    fi
}

__conjurar_help() {
    __header "CONJURAR" "$D_PURPLE"
    echo -e "  ${D_COMMENT}Menu FZF de aliases e funções do Spellbook${D_RESET}"
    echo ""
    echo -e "  ${D_PURPLE}${D_BOLD}Uso:${D_RESET}"
    echo -e "    ${D_FG}conjurar${D_RESET}                   Abre menu interativo"
    echo -e "    ${D_FG}conjurar --help${D_RESET}            Esta ajuda"
    echo -e "    ${D_FG}conjurar --list${D_RESET}            Listagem sem FZF (coluna)"
    echo -e "    ${D_FG}conjurar --search <termo>${D_RESET}  Abre menu com filtro inicial"
    echo -e "    ${D_FG}conjurar --recent${D_RESET}          Últimos 5 comandos executados"
    echo ""
    echo -e "  ${D_PURPLE}${D_BOLD}Ambiente:${D_RESET}"
    echo -e "    ${D_COMMENT}CONJURAR_TIMEOUT${D_RESET} ${D_FG}Timeout do prompt de argumentos (s, default 30)${D_RESET}"
    echo -e "    ${D_COMMENT}XDG_CACHE_HOME${D_RESET}   ${D_FG}Base do log (default \$HOME/.cache)${D_RESET}"
    echo ""
    echo -e "  ${D_PURPLE}${D_BOLD}Log:${D_RESET} ${D_FG}$(__conjurar_log_file)${D_RESET}"
    echo ""
}

# Propósito: Menu FZF interativo de aliases e funções do Spellbook
# Uso: conjurar [--help] [--list] [--search <termo>] [--recent]
# Flags: --help=Exibe ajuda
#        --list=Listagem sem FZF
#        --search=Abre menu com filtro inicial
#        --recent=Últimos 5 comandos executados
conjurar() {
    local modo="interativo"
    local termo_busca=""

    while (( $# > 0 )); do
        case "$1" in
            --help|-h) __conjurar_help; return 0 ;;
            --list|-l) modo="list" ;;
            --search|-s)
                modo="search"
                shift
                termo_busca="${1:-}"
                ;;
            --recent|-r) modo="recent" ;;
            *)
                __err "Opção desconhecida: $1"
                echo -e "  ${D_COMMENT}Use: conjurar --help${D_RESET}"
                return 1
                ;;
        esac
        shift
    done

    __verificar_dependencias "fzf" "python3" || return 1

    local helper_script="${ZDOTDIR:-$HOME/.config/zsh}/scripts/conjurar-helper.py"
    local alias_file="${ZDOTDIR:-$HOME/.config/zsh}/aliases.zsh"
    local func_dir="${ZDOTDIR:-$HOME/.config/zsh}/functions"
    local claude_file="${ZDOTDIR:-$HOME/.config/zsh}/cca/aliases_cca.zsh"

    [ -f "$helper_script" ] || { __err "Helper não encontrado: $helper_script"; return 1; }
    [ -f "$alias_file" ]    || { __err "aliases.zsh não encontrado."; return 1; }
    [ -d "$func_dir" ]      || { __err "Diretório functions/ não encontrado."; return 1; }

    local -a sources=("$alias_file" "$func_dir")
    [ -f "$claude_file" ] && sources+=("$claude_file")

    if [[ "$modo" == "list" ]]; then
        __header "CONJURAR — LISTAGEM" "$D_PURPLE"
        python3 "$helper_script" "${sources[@]}" | \
            awk -F'\t' 'BEGIN{OFS="  "} {printf "  %-28s %-8s %s\n", $1, $2, $4}'
        echo ""
        return 0
    fi

    if [[ "$modo" == "recent" ]]; then
        __header "CONJURAR — RECENTES" "$D_PURPLE"
        local recent="$(__conjurar_recent)"
        if [[ -z "$recent" ]]; then
            echo -e "  ${D_COMMENT}Nenhum comando executado ainda.${D_RESET}"
            echo ""
            return 0
        fi
        echo "$recent" | while IFS= read -r linha; do
            echo -e "  ${D_COMMENT}$ ${D_RESET}${D_FG}${linha}${D_RESET}"
        done
        echo ""
        return 0
    fi

    local -a fzf_opts=(
        --height=60% --layout=reverse --border=rounded
        --margin=1 --padding=1
        --prompt="  Conjurar > "
        --header="  ENTER executar | ESC sair | Ctrl-R recentes"
        --color="bg+:#44475a,fg+:#f8f8f2,hl:#bd93f9,hl+:#ff79c6,pointer:#50fa7b,marker:#50fa7b,prompt:#bd93f9,header:#6272a4,border:#6272a4"
        --preview-window="right:50%:wrap"
        --delimiter='\t' --with-nth=1
        "--preview=python3 $helper_script --preview {}"
    )

    [[ "$modo" == "search" && -n "$termo_busca" ]] && fzf_opts+=(--query="$termo_busca")

    local seleção
    seleção=$(fzf "${fzf_opts[@]}" < <(python3 "$helper_script" "${sources[@]}"))
    local exit_code=$?

    if [[ $exit_code -eq 130 ]]; then
        echo -e "  ${D_COMMENT}Cancelado.${D_RESET}"
        return 0
    fi

    [[ $exit_code -ne 0 || -z "$seleção" ]] && return 0

    local comando=$(echo "$seleção" | cut -d$'\t' -f1)
    local uso=$(echo "$seleção" | cut -d$'\t' -f5)
    local descrição=$(echo "$seleção" | cut -d$'\t' -f4)

    local args_part="${uso#$comando}"
    args_part="${args_part# }"

    local full_cmd=""
    local rc=0

    if [[ -z "$args_part" ]]; then
        full_cmd="$comando"
        echo -e "\n  ${D_PURPLE}>>>${D_RESET} ${D_FG}${full_cmd}${D_RESET}\n"
        ${(z)comando}
        rc=$?
    elif [[ "$args_part" == *"<"* || "$args_part" == *"["* ]]; then
        echo ""
        echo -e "  ${D_PURPLE}${comando}${D_RESET} ${D_COMMENT}${args_part}${D_RESET}"
        [ -n "$descrição" ] && echo -e "  ${D_DIM}${descrição}${D_RESET}"
        echo ""

        local -a cmd_args=()
        local remaining="$args_part"

        while [[ "$remaining" =~ '<([^>]+)>' ]]; do
            local arg_name="${match[1]}"
            local valor
            valor=$(__conjurar_read_timeout "  ${D_CYAN}${arg_name}${D_RESET}: ") || return 0
            if [[ -z "$valor" ]]; then
                echo -e "\n  ${D_COMMENT}Cancelado (argumento obrigatório vazio).${D_RESET}"
                return 0
            fi
            cmd_args+=("$valor")
            remaining="${remaining#*>}"
            remaining="${remaining# }"
        done

        while [[ "$remaining" =~ '\[([^\]]+)\]' ]]; do
            local arg_name="${match[1]}"
            if [[ "$arg_name" == --* || "$arg_name" == -* ]]; then
                echo -e -n "  ${D_YELLOW}${arg_name}${D_RESET}? (s/N) "
                local flag_reply=""
                read -t "${CONJURAR_TIMEOUT:-30}" -k 1 flag_reply
                echo ""
                [[ "$flag_reply" =~ [sS] ]] && cmd_args+=("${arg_name%% *}")
            else
                local valor
                valor=$(__conjurar_read_timeout "  ${D_YELLOW}${arg_name}${D_RESET} ${D_COMMENT}(ENTER pula):${D_RESET} ") || true
                [[ -n "$valor" ]] && cmd_args+=("$valor")
            fi
            remaining="${remaining#*]}"
            remaining="${remaining# }"
        done

        full_cmd="$comando"
        for arg in "${cmd_args[@]}"; do
            full_cmd+=" ${(q)arg}"
        done

        echo -e "\n  ${D_PURPLE}>>>${D_RESET} ${D_FG}${full_cmd}${D_RESET}\n"
        ${(z)full_cmd}
        rc=$?
    else
        echo ""
        echo -e "  ${D_PURPLE}${comando}${D_RESET} ${D_COMMENT}${args_part}${D_RESET}"
        [ -n "$descrição" ] && echo -e "  ${D_DIM}${descrição}${D_RESET}"
        echo ""
        local args_input
        args_input=$(__conjurar_read_timeout "  ${D_CYAN}args${D_RESET}: ") || return 0
        if [[ -z "$args_input" ]]; then
            echo -e "\n  ${D_COMMENT}Cancelado.${D_RESET}"
            return 0
        fi
        full_cmd="$comando $args_input"
        echo -e "\n  ${D_PURPLE}>>>${D_RESET} ${D_FG}${full_cmd}${D_RESET}\n"
        eval "${(q)comando} $args_input"
        rc=$?
    fi

    __conjurar_log "$full_cmd" "$rc"
    if (( rc != 0 )); then
        __warn "Comando retornou exit code $rc"
    fi
    return $rc
}

# "Os mapas não são o território; mas sem mapa ninguém sabe onde pisa." — Alfred Korzybski
