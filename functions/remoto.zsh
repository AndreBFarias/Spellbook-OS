#!/bin/zsh

# ============================================================================
# Ponte entre as duas maquinas da casa (mesma rede: wifi ou cabo ethernet)
#
#   conectar_andre  — roda no PC (MeowSystem): monta o SSD do notebook (Nitro5)
#                     em ~/Remotos/Spellbook-OS
#   conectar_maria  — roda no notebook: monta o SSD do PC em ~/Remotos/Andromeda-OS
#   desconectar_andre / desconectar_maria — desmontam
#   (2026-07-21: as pastas levam o nome do SISTEMA remoto, nao da pessoa;
#    symlinks ~/Remotos/andre e ~/Remotos/maria mantidos por compatibilidade)
#   conectar_nitro5 — rsync da pasta Beholder (historico, continua valendo)
#
# Sem senha e sem sudo no dia-a-dia: a 1a execucao gera a chave
# ~/.ssh/id_ed25519_lan, escreve o bloco Host no ~/.ssh/config e roda
# ssh-copy-id (pede a senha da OUTRA maquina uma unica vez). Dali em diante
# tudo e por chave; a user unit aurora-conectar-<alvo>.service (instalada
# automaticamente na 1a conexao; no PC tambem pelo self-heal v3.32) monta no
# boot e fica re-tentando a cada 60s ate a outra maquina aparecer na rede.
# ============================================================================

__LAN_KEY="$HOME/.ssh/id_ed25519_lan"

__lan_sou_eu() {
    # Nao deixar a maquina conectar nela mesma
    local alvo="$1" eu="${(L)HOST}"
    case "$alvo" in
        maria) [[ "$eu" == meowsystem* ]] ;;
        andre) [[ "$eu" == nitro-5* || "$eu" == nitro5* ]] ;;
        *) return 1 ;;
    esac
}

__lan_ponto() {
    # Nome da pasta de montagem = nome do SISTEMA remoto (nao da pessoa)
    case "$1" in
        andre) echo "Spellbook-OS" ;;
        maria) echo "Andromeda-OS" ;;
        *) echo "$1" ;;
    esac
}

__lan_preparar_chave() {
    # Gera a chave LAN e o bloco Host no ~/.ssh/config (idempotente)
    local alvo="$1" usuario="$2" host="$3"
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    if [[ ! -f "$__LAN_KEY" ]]; then
        __warn "Gerando chave LAN: $__LAN_KEY"
        ssh-keygen -t ed25519 -C "lan-${HOST}" -f "$__LAN_KEY" -N "" >/dev/null || return 1
    fi
    if ! grep -qE "^Host[[:space:]]+$alvo\$" "$HOME/.ssh/config" 2>/dev/null; then
        {
            echo ""
            echo "# --- LAN: $alvo ($usuario@$host) ---"
            echo "Host $alvo"
            echo "    HostName $host"
            echo "    User $usuario"
            echo "    IdentityFile $__LAN_KEY"
            echo "    IdentitiesOnly yes"
            echo "    StrictHostKeyChecking accept-new"
        } >>"$HOME/.ssh/config"
        chmod 600 "$HOME/.ssh/config"
        __ok "Bloco 'Host $alvo' criado no ~/.ssh/config"
    fi
}

__lan_parear() {
    # Garante que a nossa chave esta autorizada la (ssh-copy-id na 1a vez)
    local alvo="$1"
    ssh -o BatchMode=yes -o ConnectTimeout=5 "$alvo" true 2>/dev/null && return 0
    __warn "Chave ainda nao autorizada em '$alvo'."
    __warn "Rodando ssh-copy-id — digite a senha da outra maquina (so desta vez)."
    ssh-copy-id -i "${__LAN_KEY}.pub" -o ConnectTimeout=10 "$alvo" || return 1
    ssh -o BatchMode=yes -o ConnectTimeout=5 "$alvo" true 2>/dev/null
}

__lan_unit_instalar() {
    # Cria/atualiza a user unit que monta no boot e re-tenta a cada 60s.
    # No PC o self-heal v3.32 instala a mesma unit (fonte em scripts/) — o
    # template abaixo e identico pra nao haver churn entre os dois caminhos.
    local alvo="$1" usuario="$2" host="$3"
    local ponto_nome="$(__lan_ponto "$alvo")"
    local unit_dir="$HOME/.config/systemd/user"
    mkdir -p "$unit_dir"
    cat >"$unit_dir/aurora-conectar-$alvo.service" <<EOF
[Unit]
Description=Ritual da Aurora: SSD remoto '$alvo' montado em ~/Remotos/$ponto_nome (sshfs)

[Service]
Type=simple
ExecStartPre=/bin/mkdir -p %h/Remotos/$ponto_nome
ExecStart=/usr/bin/sshfs -f $usuario@$host:/ %h/Remotos/$ponto_nome -o BatchMode=yes,ConnectTimeout=10,StrictHostKeyChecking=accept-new,IdentityFile=%h/.ssh/id_ed25519_lan,reconnect,ServerAliveInterval=15,ServerAliveCountMax=3,idmap=user,follow_symlinks
ExecStop=/bin/fusermount3 -u -z %h/Remotos/$ponto_nome
Restart=always
RestartSec=60

[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload 2>/dev/null
    systemctl --user enable "aurora-conectar-$alvo.service" >/dev/null 2>&1
}

__conectar_ssd() {
    local alvo="$1" usuario="$2" host="$3"
    local ponto="$HOME/Remotos/$(__lan_ponto "$alvo")"
    local unit="aurora-conectar-$alvo.service"

    __header "SSD REMOTO: ${(U)alvo}" "$D_CYAN"
    __item "Host" "$usuario@$host" "$D_COMMENT" "$D_CYAN"
    __item "Monta em" "$ponto" "$D_COMMENT" "$D_GREEN"
    echo ""

    if __lan_sou_eu "$alvo"; then
        __err "Esta maquina JA E '$alvo' — na outra maquina, rode a funcao oposta."
        return 1
    fi
    if ! command -v sshfs >/dev/null 2>&1; then
        __err "sshfs nao esta instalado."
        echo -e "  ${D_COMMENT}No PC o self-heal instala sozinho; manual: sudo apt install sshfs${D_RESET}"
        return 1
    fi
    if mountpoint -q "$ponto" 2>/dev/null; then
        __ok "Ja esta montado em $ponto"
        return 0
    fi

    __lan_preparar_chave "$alvo" "$usuario" "$host" || return 1

    local tentativa=1 max=5
    while ! ping -c 1 -W 2 "$host" >/dev/null 2>&1; do
        if (( tentativa >= max )); then
            __err "'$host' nao respondeu apos $max tentativas."
            echo -e "  ${D_COMMENT}Confira: outra maquina ligada, na mesma rede (wifi/cabo) e com sshd ativo la.${D_RESET}"
            return 1
        fi
        __warn "'$host' fora do ar ($tentativa/$max). Nova tentativa em 5s..."
        sleep 5
        ((tentativa++))
    done

    __lan_parear "$alvo" || { __err "Pareamento por chave falhou."; return 1; }

    # A unit cuida da montagem (e da remontagem no boot / se a rede cair)
    __lan_unit_instalar "$alvo" "$usuario" "$host"
    systemctl --user restart "$unit" 2>/dev/null

    local i
    for i in {1..15}; do
        mountpoint -q "$ponto" 2>/dev/null && break
        sleep 1
    done

    if mountpoint -q "$ponto" 2>/dev/null; then
        __ok "SSD de '$alvo' montado em $ponto (re-monta sozinho a cada boot)."
    else
        __warn "A unit nao montou em 15s — tentando sshfs direto..."
        mkdir -p "$ponto"
        if sshfs "$alvo:/" "$ponto" -o reconnect,ServerAliveInterval=15,ServerAliveCountMax=3,idmap=user,follow_symlinks; then
            __ok "SSD de '$alvo' montado em $ponto."
        else
            __err "Falhou. Diagnostico: journalctl --user -u $unit -n 20"
            return 1
        fi
    fi
}

__desconectar_ssd() {
    local alvo="$1"
    local ponto="$HOME/Remotos/$(__lan_ponto "$alvo")"
    systemctl --user stop "aurora-conectar-$alvo.service" 2>/dev/null
    if mountpoint -q "$ponto" 2>/dev/null; then
        fusermount3 -u -z "$ponto" 2>/dev/null || fusermount -u -z "$ponto" 2>/dev/null
    fi
    if mountpoint -q "$ponto" 2>/dev/null; then
        __err "Nao consegui desmontar $ponto (algum arquivo aberto?)."
        return 1
    fi
    __ok "'$alvo' desconectado."
}

# Proposito: Montar o SSD do notebook (Nitro5) neste PC, em ~/Remotos/Spellbook-OS
# Uso: conectar_andre
conectar_andre() { __conectar_ssd andre andrefarias nitro-5.local; }

# Proposito: Montar o SSD do PC (MeowSystem) no notebook, em ~/Remotos/Andromeda-OS
# Uso: conectar_maria
conectar_maria() { __conectar_ssd maria vitoriamaria meowsystem.local; }

# Proposito: Desmontar o SSD remoto (e parar a unit ate o proximo boot)
desconectar_andre() { __desconectar_ssd andre; }
desconectar_maria() { __desconectar_ssd maria; }

# ============================================================================
# Sincronizacao rsync (historico) — copia a pasta Beholder, nao monta nada
# ============================================================================

__conectar_rsync() {
    local usuario="$1"
    local host="$2"
    local pasta_remota="$3"
    local pasta_local="${4:-$HOME/Beholder/}"
    local max_tentativas="${5:-5}"
    local tentativa=0

    __header "CONEXAO REMOTA" "$D_CYAN"
    __item "Host" "$host" "$D_COMMENT" "$D_CYAN"
    __item "Usuario" "$usuario" "$D_COMMENT" "$D_FG"
    __item "Remoto" "$pasta_remota" "$D_COMMENT" "$D_FG"
    __item "Local" "$pasta_local" "$D_COMMENT" "$D_GREEN"
    echo ""

    mkdir -p "$pasta_local"

    while [ $tentativa -lt $max_tentativas ]; do
        echo -e "  ${D_COMMENT}Tentativa $((tentativa + 1))/$max_tentativas...${D_RESET}"

        if rsync -avzP --exclude='.cache' --exclude='venv' -e "ssh -p 22" \
            "${usuario}@${host}:${pasta_remota}" "$pasta_local"; then
            echo ""
            __ok "Sincronia com '$usuario@$host' concluida."
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
    __err "Nao foi possivel conectar em '$host' apos $max_tentativas tentativas."
    echo -e "  ${D_COMMENT}Verifique se a maquina esta ligada e acessivel na rede.${D_RESET}"
    echo ""
    return 1
}

# Proposito: Sincronizar Beholder com o Nitro5 via rsync
# Uso: conectar_nitro5
conectar_nitro5() {
    __conectar_rsync "andrefarias" "nitro-5.local" "/home/andrefarias/Beholder/"
}

# Proposito: Backup local do Beholder para pasta local
# Uso: conectar_local [destino]
conectar_local() {
    local destino="${1:-$HOME/Beholder/}"
    mkdir -p "$destino"
    rsync -avzP --exclude='.cache' --exclude='venv' "$HOME/Beholder/" "$destino"
}
