#!/bin/zsh

# Propósito: Extrair arquivos compactados (tar, zip, rar, 7z, gz, xz, zst)
# Uso: extrair <arquivo>
extrair() {
    if [ -z "$1" ]; then
        echo -e "  ${D_COMMENT}Uso: extrair <arquivo>${D_RESET}"
        return 1
    fi

    if [ ! -f "$1" ]; then
        __err "'$1' não é um arquivo válido."
        return 1
    fi

    local nome=$(basename "$1")
    echo -e "  ${D_COMMENT}Extraindo:${D_RESET} ${D_CYAN}$nome${D_RESET}"

    case "$1" in
        *.tar.bz2)    tar xvjf "$1"    ;;
        *.tar.gz)     tar xvzf "$1"    ;;
        *.bz2)        bunzip2 "$1"     ;;
        *.rar)        unrar x "$1"     ;;
        *.gz)         gunzip "$1"      ;;
        *.tar)        tar xvf "$1"     ;;
        *.tbz2)       tar xvjf "$1"    ;;
        *.tgz)        tar xvzf "$1"    ;;
        *.zip)        unzip "$1"       ;;
        *.Z)          uncompress "$1"  ;;
        *.7z)         7z x "$1"        ;;
        *.xz)         unxz "$1"        ;;
        *.tar.xz)     tar xvJf "$1"    ;;
        *.zst)        unzstd "$1"      ;;
        *.tar.zst)    tar --zstd -xvf "$1" ;;
        *)
            __err "Formato não suportado: $nome"
            echo -e "  ${D_COMMENT}Formatos: tar.gz, tar.bz2, tar.xz, tar.zst, zip, rar, 7z, gz, bz2, xz, zst${D_RESET}"
            return 1
            ;;
    esac
}
