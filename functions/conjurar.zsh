#!/bin/zsh

# Proposito: Menu FZF interativo de todos os aliases e funcoes disponiveis
# Uso: conjurar
conjurar() {
    __verificar_dependencias "fzf" "python3" || return 1

    local helper_script="${ZDOTDIR:-$HOME/.config/zsh}/scripts/conjurar-helper.py"
    local alias_file="${ZDOTDIR:-$HOME/.config/zsh}/aliases.zsh"
    local func_dir="${ZDOTDIR:-$HOME/.config/zsh}/functions"
    local claude_file="${ZDOTDIR:-$HOME/.config/zsh}/cca/aliases_cca.zsh"

    [ -f "$helper_script" ] || { __err "Helper nao encontrado: $helper_script"; return 1; }
    [ -f "$alias_file" ]    || { __err "aliases.zsh nao encontrado."; return 1; }
    [ -d "$func_dir" ]      || { __err "Diretorio functions/ nao encontrado."; return 1; }

    local -a sources=("$alias_file" "$func_dir")
    [ -f "$claude_file" ] && sources+=("$claude_file")

    local -a fzf_opts=(
        --height=60% --layout=reverse --border=rounded
        --margin=1 --padding=1
        --prompt="  Conjurar > "
        --header="  ENTER executar | ESC sair"
        --color="bg+:#44475a,fg+:#f8f8f2,hl:#bd93f9,hl+:#ff79c6,pointer:#50fa7b,marker:#50fa7b,prompt:#bd93f9,header:#6272a4,border:#6272a4"
        --preview-window="right:50%:wrap"
        --delimiter='\t' --with-nth=1
        "--preview=python3 $helper_script --preview {}"
    )

    local selecao
    selecao=$(fzf "${fzf_opts[@]}" < <(python3 "$helper_script" "${sources[@]}"))
    local exit_code=$?

    if [[ $exit_code -eq 130 ]]; then
        echo -e "  ${D_COMMENT}Cancelado.${D_RESET}"
        return 0
    fi

    [[ $exit_code -ne 0 || -z "$selecao" ]] && return 0

    local comando=$(echo "$selecao" | cut -d$'\t' -f1)
    local uso=$(echo "$selecao" | cut -d$'\t' -f5)
    local descricao=$(echo "$selecao" | cut -d$'\t' -f4)

    local args_part="${uso#$comando}"
    args_part="${args_part# }"

    if [[ -z "$args_part" ]]; then
        echo -e "\n  ${D_PURPLE}>>>${D_RESET} ${D_FG}${comando}${D_RESET}\n"
        ${(z)comando}
        return
    fi

    if [[ "$args_part" == *"<"* ]]; then
        echo ""
        echo -e "  ${D_PURPLE}${comando}${D_RESET} ${D_COMMENT}${args_part}${D_RESET}"
        [ -n "$descricao" ] && echo -e "  ${D_DIM}${descricao}${D_RESET}"
        echo ""

        local cmd_args=()
        local remaining="$args_part"

        while [[ "$remaining" =~ '<([^>]+)>' ]]; do
            local arg_name="${match[1]}"
            echo -e -n "  ${D_CYAN}${arg_name}${D_RESET}: "
            local valor=""
            read valor
            if [[ -z "$valor" ]]; then
                echo -e "\n  ${D_COMMENT}Cancelado.${D_RESET}"
                return 0
            fi
            cmd_args+=("$valor")
            remaining="${remaining#*>}"
            remaining="${remaining# }"
        done

        while [[ "$remaining" =~ '\[([^\]]+)\]' ]]; do
            local arg_name="${match[1]}"
            if [[ "$arg_name" == --* ]]; then
                echo -e -n "  ${D_YELLOW}${arg_name}${D_RESET}? (s/N) "
                local flag_reply=""
                read -k 1 flag_reply
                echo ""
                [[ "$flag_reply" =~ [sS] ]] && cmd_args+=("$arg_name")
            else
                echo -e -n "  ${D_YELLOW}${arg_name}${D_RESET} ${D_COMMENT}(ENTER pula):${D_RESET} "
                local valor=""
                read valor
                [[ -n "$valor" ]] && cmd_args+=("$valor")
            fi
            remaining="${remaining#*]}"
            remaining="${remaining# }"
        done

        local full_cmd="$comando"
        for arg in "${cmd_args[@]}"; do
            full_cmd+=" ${(q)arg}"
        done

        echo -e "\n  ${D_PURPLE}>>>${D_RESET} ${D_FG}${full_cmd}${D_RESET}\n"
        ${(z)full_cmd}
    else
        echo ""
        echo -e "  ${D_PURPLE}${comando}${D_RESET} ${D_COMMENT}${args_part}${D_RESET}"
        [ -n "$descricao" ] && echo -e "  ${D_DIM}${descricao}${D_RESET}"
        echo ""
        echo -e -n "  ${D_CYAN}args${D_RESET}: "
        local args_input=""
        read args_input
        if [[ -z "$args_input" ]]; then
            echo -e "\n  ${D_COMMENT}Cancelado.${D_RESET}"
            return 0
        fi
        echo -e "\n  ${D_PURPLE}>>>${D_RESET} ${D_FG}${comando} ${args_input}${D_RESET}\n"
        eval "${(q)comando} $args_input"
    fi
}
