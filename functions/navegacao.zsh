#!/bin/zsh

# Proposito: Navegacao rapida entre projetos com FZF (preview de git log e ls)
# Uso: ir
ir() {
    __verificar_dependencias "fzf" || return 1

    if [ ! -d "$DEV_DIR" ]; then
        __err "Diretório '$DEV_DIR' não encontrado."
        return 1
    fi

    local destino=$(find "$DEV_DIR" -maxdepth 2 -type d -name ".git" -prune | sed 's/\/\.git//' | sort | \
        fzf --height=50% --layout=reverse --border=rounded \
            --prompt="  Ir para > " \
            --header="  Projetos em $DEV_DIR" \
            --color="bg+:#44475a,fg+:#f8f8f2,hl:#bd93f9,hl+:#ff79c6,pointer:#50fa7b,marker:#50fa7b,prompt:#bd93f9,header:#6272a4,border:#6272a4" \
            --preview 'echo -e "\033[38;2;189;147;249m$(basename {})\033[0m"; echo ""; git -C {} log --oneline --graph -8 2>/dev/null || echo "(sem historico git)"; echo ""; ls -la --color=always {} 2>/dev/null | head -15')

    if [ -n "$destino" ]; then
        cd "$destino" || return
        local branch=$(git branch --show-current 2>/dev/null || echo 'sem git')
        echo -e "\n  ${D_PURPLE}$(basename "$destino")${D_RESET} ${D_COMMENT}::${D_RESET} ${D_CYAN}${branch}${D_RESET}\n"
    fi
}
