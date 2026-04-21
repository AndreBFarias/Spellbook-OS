#!/bin/zsh

# Propósito: Limpar caches de dev ao abrir terminal (previne pacotes stale e libera disco)
_limpar_caches_dev() {
    local dirs=(
        "$HOME/.npm/_cacache"
        "$HOME/.cache/pip"
        "$HOME/.cargo/registry/cache"
    )
    for d in "${dirs[@]}"; do
        [ -d "$d" ] && rm -rf "$d" 2>/dev/null
    done
}
_limpar_caches_dev

# Proposito: Limpeza interativa do Controle de Bordo com FZF
# Uso: limpeza_interativa
limpeza_interativa() {
    __verificar_dependencias "fzf" || return 1

    local bordo_dir="${BORDO_DIR:-$HOME/Controle de Bordo}"

    if [ ! -d "$bordo_dir" ]; then
        __err "Diretório não encontrado: $bordo_dir"
        return 1
    fi

    __header "LIMPEZA INTERATIVA" "$D_ORANGE"
    echo -e "  ${D_COMMENT}Alvo: ${D_FG}$bordo_dir${D_RESET}"
    echo ""

    local FZF_DRACULA="--color=bg+:#44475a,fg+:#f8f8f2,hl:#bd93f9,hl+:#ff79c6,pointer:#50fa7b,marker:#50fa7b,prompt:#bd93f9,header:#6272a4,border:#6272a4"

    cd "$bordo_dir" || return

    local JUNK_PATTERNS=(-name "*.zip" -o -name "*.exe" -o -path "*/data_input" -o -path "*/data_output")
    local alvos=$(find . \( "${JUNK_PATTERNS[@]}" \) 2>/dev/null | \
        fzf --multi --prompt="  Selecionar > " --header="  TAB para múltiplos" $FZF_DRACULA)

    echo -e -n "  ${D_COMMENT}Buscar padrão customizado? (ex: *.tmp) (s/N)${D_RESET} "
    read -k 1 confirmacao
    echo ""

    if [[ "$confirmacao" == "s" || "$confirmacao" == "S" ]]; then
        echo -e -n "  ${D_COMMENT}Padrão:${D_RESET} "
        read padrao_customizado
        local extras=$(find . -name "$padrao_customizado" 2>/dev/null | \
            fzf --multi --prompt="  Selecionar '$padrao_customizado' > " $FZF_DRACULA)
        [[ -n "$extras" ]] && alvos+=$'\n'"$extras"
    fi

    if [ -z "$alvos" ]; then
        echo -e "  ${D_COMMENT}Nenhuma seleção.${D_RESET}"
        cd - > /dev/null
        echo ""
        return 0
    fi

    echo ""
    echo -e "  ${D_PURPLE}Selecionado para remoção:${D_RESET}"
    echo "$alvos" | sed "s/^/    /"
    echo ""

    echo -e -n "  ${D_RED}Confirmar? (mover para Lixeira) (s/N)${D_RESET} "
    read -k 1 confirmacao
    echo ""

    if [[ "$confirmacao" == "s" || "$confirmacao" == "S" ]]; then
        local trash_dir="${XDG_DATA_HOME:-$HOME/.local/share}/Trash/files"
        mkdir -p "$trash_dir"
        echo "$alvos" | xargs -d '\n' mv --target-directory="$trash_dir" 2>/dev/null
        __ok "Itens movidos para a Lixeira."
    else
        echo -e "  ${D_COMMENT}Cancelado.${D_RESET}"
    fi

    cd - > /dev/null
    echo ""
}

# Proposito: Remover pastas vazias dos projetos (--dry-run para preview)
# Uso: limpar_pastas_vazias [--dry-run]
limpar_pastas_vazias() {
    local base_dir="${DEV_DIR:-$HOME/Desenvolvimento}"
    local dry_run=false

    if [[ "$1" == "--dry-run" ]]; then
        dry_run=true
    fi

    __header "LIMPAR PASTAS VAZIAS" "$D_ORANGE"
    echo -e "  ${D_COMMENT}Alvo: ${D_FG}$base_dir${D_RESET}"

    if [ "$dry_run" = true ]; then
        echo -e "  ${D_YELLOW}[DRY-RUN] Apenas mostrando o que seria removido${D_RESET}"
    fi
    echo ""

    local pastas_alvo=(
        "docs" "logs" "log" "scripts" "tests" "dev"
        "dev-journey" "src/core" "src/services" "src/tools"
    )

    local removidas=0

    for projeto in "$base_dir"/*/; do
        [ -d "$projeto" ] || continue

        for pasta in "${pastas_alvo[@]}"; do
            local caminho="$projeto$pasta"

            if [ -d "$caminho" ]; then
                local conteudo=$(find "$caminho" -mindepth 1 -maxdepth 1 2>/dev/null | head -1)

                if [ -z "$conteudo" ]; then
                    if [ "$dry_run" = true ]; then
                        echo -e "  ${D_YELLOW}[VAZIA]${D_RESET}    $caminho"
                    else
                        rmdir "$caminho" 2>/dev/null && echo -e "  ${D_GREEN}[REMOVIDA]${D_RESET} $caminho"
                    fi
                    ((removidas++))
                fi
            fi
        done

        if [ -d "$projeto/src" ]; then
            local src_conteudo=$(find "$projeto/src" -mindepth 1 -maxdepth 1 2>/dev/null | head -1)
            if [ -z "$src_conteudo" ]; then
                if [ "$dry_run" = true ]; then
                    echo -e "  ${D_YELLOW}[VAZIA]${D_RESET}    ${projeto}src"
                else
                    rmdir "${projeto}src" 2>/dev/null && echo -e "  ${D_GREEN}[REMOVIDA]${D_RESET} ${projeto}src"
                fi
                ((removidas++))
            fi
        fi
    done

    echo ""
    if [ $removidas -eq 0 ]; then
        __ok "Nenhuma pasta vazia encontrada."
    elif [ "$dry_run" = true ]; then
        __warn "$removidas pasta(s) seriam removidas. Rode sem --dry-run para executar."
    else
        __ok "$removidas pasta(s) removidas."
    fi
    echo ""
}
