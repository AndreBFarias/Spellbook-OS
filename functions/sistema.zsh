#!/bin/zsh

# Proposito: Reconstruir caches de icones de todos os temas e desktop database
# Uso: _reconstruir_caches_icones (chamado por atualizar_tudo, limpar_cache, atualizar_icones)
_reconstruir_caches_icones() {
    __header "CACHES DE ICONES" "$D_CYAN"

    sudo update-desktop-database 2>/dev/null
    __ok "Desktop database atualizado"

    local falhas=0
    for tema_dir in /usr/share/icons/*/; do
        [ -f "${tema_dir}index.theme" ] || continue
        local tema=$(basename "$tema_dir")
        if sudo gtk-update-icon-cache -f -q "$tema_dir" 2>/dev/null; then
            echo -e "  ${D_GREEN}[OK]${D_RESET} $tema"
        else
            echo -e "  ${D_YELLOW}[!]${D_RESET}  $tema (cache invalido, pode haver arquivos corrompidos)"
            ((falhas++))
        fi
    done

    if [ -d "$HOME/.local/share/flatpak/exports/share/icons/hicolor" ]; then
        if gtk-update-icon-cache -f -q "$HOME/.local/share/flatpak/exports/share/icons/hicolor/" 2>/dev/null; then
            __ok "Flatpak (user)"
        else
            __warn "Flatpak (user) - falha no cache"
            ((falhas++))
        fi
    fi

    echo ""
    if [ $falhas -eq 0 ]; then
        __ok "Todos os caches reconstruidos"
    else
        __warn "$falhas tema(s) com problemas (verifique arquivos com nomes invalidos)"
    fi
    echo ""
}

# Proposito: Exibir contexto de usuario no prompt (SSH e usuarios nao-padrao)
# Uso: prompt_context
prompt_context() {
  if [[ "$USER" != "$DEFAULT_USER" || -n "$SSH_CLIENT" ]]; then
    prompt_segment black default "%n@%m"
  fi
}

# Proposito: Reinstalar um pacote via apt
# Uso: reinstalar <pacote>
reinstalar() { if [ -z "$1" ]; then echo "Uso: reinstalar <pacote>"; return 1; fi; sudo apt install --reinstall "$1"; }

# Proposito: Descobrir qual pacote instalou um arquivo
# Uso: quem_instalou <caminho>
quem_instalou() { if [ -z "$1" ]; then echo "Uso: quem_instalou <caminho>"; return 1; fi; dpkg -S "$1"; }

# Proposito: Listar todos os arquivos de um pacote instalado
# Uso: arquivos_pacote <pacote>
arquivos_pacote() { if [ -z "$1" ]; then echo "Uso: arquivos_pacote <pacote>"; return 1; fi; dpkg -L "$1"; }

# Proposito: Status de um servico systemd
# Uso: servico_status <servico>
servico_status() { systemctl status "$1"; }
# Proposito: Iniciar um servico systemd
# Uso: servico_iniciar <servico>
servico_iniciar() { sudo systemctl start "$1"; }
# Proposito: Parar um servico systemd
# Uso: servico_parar <servico>
servico_parar() { sudo systemctl stop "$1"; }
# Proposito: Reiniciar um servico systemd
# Uso: servico_reiniciar <servico>
servico_reiniciar() { sudo systemctl restart "$1"; }

# Proposito: Gerar diagnostico completo do Pop!_OS (kernel, disco, processos, erros)
# Uso: diagnostico_pop <profundidade>
diagnostico_pop() {
    if ! [[ "$1" =~ ^[0-9]+$ ]] || [ -z "$1" ]; then
        echo -e "  ${D_COMMENT}Uso: diagnostico_pop <profundidade>${D_RESET}"
        return 1
    fi

    local profundidade="$1"
    local timestamp=$(date +'%Y-%m-%d_%Hh%M')
    local output_file="diagnostico_popos_${timestamp}.txt"

    __header "DIAGNOSTICO POP!_OS" "$D_ORANGE"

    {
        echo "--- DIAGNÓSTICO DO SISTEMA POP!_OS ---"
        echo "Gerado em: $(date)"; echo
        echo "--- VERSÃO DO SISTEMA ---"; lsb_release -a; echo
        echo "--- KERNEL ---"; uname -r; echo
        echo "--- FASTFETCH ---"; fastfetch; echo
        if command -v nvidia-smi &> /dev/null; then
            echo "--- GPU NVIDIA ---"; nvidia-smi; echo
        fi
        echo "--- DISCO ---"; df -h; echo
        echo "--- TOP 20 PROCESSOS ---"; top -b -n 1 | head -n 20; echo
        echo "--- ÚLTIMOS 50 ERROS ---"; journalctl -p 3 -xb -n 50; echo
        echo "--- KERNEL ERRORS ---"; sudo dmesg -l err,warn; echo
        echo "--- TREE HOME (PROF. ${profundidade}) ---"
        __verificar_dependencias "tree" && command tree "$HOME" -L "$profundidade" -I "Desenvolvimento|Downloads|*.cache*|snap|*local/share*|go"
    } > "$output_file"

    __ok "Salvo em: $output_file"
    echo ""
}

# Proposito: Reparo automatico do sistema (deps, pacotes, limpeza, atualizacao)
# Uso: reparo_pop
reparo_pop() {
    __header "REPARO DO SISTEMA" "$D_RED"

    local timestamp=$(date +'%Y-%m-%d_%Hh%M')
    local log_file="$HOME/reparo_pop_log_${timestamp}.txt"
    exec > >(tee "$log_file") 2>&1

    echo -e "  ${D_COMMENT}Corrigindo dependências...${D_RESET}";  sudo apt install -f
    echo -e "  ${D_COMMENT}Reconfigurando pacotes...${D_RESET}";   sudo dpkg --configure -a
    echo -e "  ${D_COMMENT}Limpando orfaos...${D_RESET}";          sudo apt autoremove --purge -y; sudo apt clean
    echo -e "  ${D_COMMENT}Atualizando sistema...${D_RESET}";      sudo apt update; sudo apt full-upgrade -y
    echo -e "  ${D_COMMENT}Reparando Flatpak...${D_RESET}";        flatpak repair --user 2>/dev/null; sudo flatpak repair 2>/dev/null
    echo -e "  ${D_COMMENT}Reconstruindo icones...${D_RESET}";     _reconstruir_caches_icones

    exec >&2

    __ok "Reparo concluido. Log: $log_file"
    echo ""

    read -p "  Reiniciar agora? (s/N) " confirmacao
    if [[ "$confirmacao" == "s" || "$confirmacao" == "S" ]]; then
        echo "  Reiniciando em 5s..."; sleep 5; sudo reboot
    fi
}
