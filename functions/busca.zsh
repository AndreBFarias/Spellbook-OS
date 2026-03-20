#!/bin/zsh

# Proposito: Buscar arquivos por padrao de nome em um diretorio
# Uso: buscar <padrao> <pasta>
buscar() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        echo -e "  ${D_COMMENT}Uso: buscar <padrao> <pasta>${D_RESET}"
        return 1
    fi

    local padrao="$1"
    local caminho="$2"

    if [ ! -d "$caminho" ]; then
        __err "Diretorio nao existe: $caminho"
        return 1
    fi

    echo -e "  ${D_COMMENT}Buscando${D_RESET} ${D_CYAN}'$padrao'${D_RESET} ${D_COMMENT}em${D_RESET} ${D_FG}$caminho${D_RESET}"
    echo ""

    local count=0
    while IFS= read -r -d '' file; do
        ((count++))
        local dir_path=$(realpath "$(dirname "$file")")
        echo -e "  ${D_GREEN}$file${D_RESET}"
        echo -e "  ${D_COMMENT}$dir_path${D_RESET}"
        echo ""
    done < <(find "$caminho" -name "$padrao" -print0)

    if [ $count -eq 0 ]; then
        echo -e "  ${D_COMMENT}Nenhum resultado.${D_RESET}"
    fi
}
