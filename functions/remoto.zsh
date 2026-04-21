#!/bin/zsh

__conectar_rsync() {
    local usuario="$1"
    local host="$2"
    local pasta_remota="$3"
    local pasta_local="${4:-$HOME/Beholder/}"
    local max_tentativas="${5:-5}"
    local tentativa=0

    __header "CONEXÃO REMOTA" "$D_CYAN"
    __item "Host" "$host" "$D_COMMENT" "$D_CYAN"
    __item "Usuário" "$usuario" "$D_COMMENT" "$D_FG"
    __item "Remoto" "$pasta_remota" "$D_COMMENT" "$D_FG"
    __item "Local" "$pasta_local" "$D_COMMENT" "$D_GREEN"
    echo ""

    mkdir -p "$pasta_local"

    while [ $tentativa -lt $max_tentativas ]; do
        echo -e "  ${D_COMMENT}Tentativa $((tentativa + 1))/$max_tentativas...${D_RESET}"

        if rsync -avzP --exclude='.cache' --exclude='venv' -e "ssh -p 22" \
            "${usuario}@${host}:${pasta_remota}" "$pasta_local"; then
            echo ""
            __ok "Sincronização com '$usuario@$host' concluída."
            echo ""
            return 0
        fi

        ((tentativa++))
        if [ $tentativa -lt $max_tentativas ]; then
            __warn "Falha ($tentativa/$max_tentativas). Tentando em 10s..."
            sleep 10
        fi
    done

    echo ""
    __err "Não foi possível conectar em '$host' após $max_tentativas tentativas."
    echo -e "  ${D_COMMENT}Verifique se a máquina está ligada e acessível na rede.${D_RESET}"
    echo ""
    return 1
}

# Propósito: Sincronizar Beholder com a máquina da Maria via rsync
# Uso: conectar_maria
conectar_maria() {
    __conectar_rsync "vitoriamaria" "vitoriamaria.local" "/home/vitoriamaria/Beholder/"
}

# Propósito: Sincronizar Beholder com o Nitro5 via rsync
# Uso: conectar_andre
conectar_andre() {
    __conectar_rsync "andrefarias" "nitro5.local" "/home/andrefarias/Beholder/"
}
