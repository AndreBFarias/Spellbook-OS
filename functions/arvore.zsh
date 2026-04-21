#!/bin/zsh

# Propósito: Árvore de diretórios com filtros e exportação para arquivo
# Uso: tree <profundidade> [diretório]
tree() {
    __verificar_dependencias "tree" || return 1

    if ! [[ "$1" =~ ^[0-9]+$ ]] || [ -z "$1" ]; then
        echo -e "  ${D_COMMENT}Uso: tree <profundidade> [diretório] (0 = infinito)${D_RESET}"
        return 1
    fi

    local niveis_arg="$1"
    local diretorio_alvo="${2:-.}"

    if [ ! -d "$diretorio_alvo" ]; then
        __err "Diretório '$diretorio_alvo' não existe."
        return 1
    fi

    local tree_cmd=(command tree)

    if [ "$niveis_arg" -ne 0 ]; then
        tree_cmd+=(-L "$niveis_arg")
    fi

    local folder_name=$(basename "$(realpath "$diretorio_alvo")")
    local timestamp=$(date +'%Y-%m-%d_%Hh%M')
    local output_file="${folder_name}_tree_${timestamp}.txt"
    local ignore_pattern=".git|venv|.venv|__pycache__|node_modules|*site-packages*|.cache"

    local depth_label="$niveis_arg"
    [ "$niveis_arg" -eq 0 ] && depth_label="infinita"

    __header "${folder_name} (prof. ${depth_label})" "$D_PURPLE"

    tree_cmd+=(-I "$ignore_pattern" "$diretorio_alvo")

    "${tree_cmd[@]}" | tee "$output_file"

    echo ""
    echo -e "  ${D_COMMENT}Salvo em:${D_RESET} ${D_CYAN}${output_file}${D_RESET}"
    echo ""
}
