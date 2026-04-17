#!/bin/zsh

# Propósito: Reconstruir caches de ícones de todos os temas e desktop database
# Uso: _reconstruir_caches_icones (chamado por atualizar_tudo, limpar_cache, atualizar_icones)
_reconstruir_caches_icones() {
    __header "CACHES DE ICONES" "$D_CYAN"

    sudo update-desktop-database 2>/dev/null
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null
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

    # Temas instalados em nivel user (~/.local/share/icons)
    for tema_dir in "$HOME/.local/share/icons/"*/; do
        [ -f "${tema_dir}index.theme" ] || continue
        local tema=$(basename "$tema_dir")
        if gtk-update-icon-cache -f -q "$tema_dir" 2>/dev/null; then
            echo -e "  ${D_GREEN}[OK]${D_RESET} $tema (user)"
        else
            echo -e "  ${D_YELLOW}[!]${D_RESET}  $tema (user, cache invalido)"
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

    if [ -d /var/lib/flatpak/exports/share/icons/hicolor ]; then
        if sudo gtk-update-icon-cache -f -q /var/lib/flatpak/exports/share/icons/hicolor/ 2>/dev/null; then
            __ok "Flatpak (system)"
        else
            __warn "Flatpak (system) - falha no cache"
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

# Propósito: Reaplicar Icon= corretos em .desktop de Flatpaks com path absoluto quebrado
# Uso: _fix_flatpak_icons (chamado após flatpak update/repair em limpar_cache e atualizar_tudo)
# Contexto: alguns .desktop de Flatpaks vêm com Icon= apontando para ~/.icons/Dracula-Icones/
#           scalable/ que não existe. Esta função sobrescreve para nomes canonicos.
_fix_flatpak_icons() {
    local exports_dir="$HOME/.local/share/flatpak/exports/share/applications"
    [ -d "$exports_dir" ] || return 0

    __header "ICONES FLATPAK (.desktop)" "$D_CYAN"

    local -A mapeamento=(
        "com.visualstudio.code.desktop"                              "vscode"
        "com.visualstudio.code-url-handler.desktop"                  "vscode"
        "io.github.electronstudio.WeylusCommunityEdition.desktop"    "weylus"
        "org.gnome.gitlab.somas.Apostrophe.desktop"                  "org.gnome.gitlab.somas.Apostrophe"
    )

    local ajustados=0
    for arquivo in ${(k)mapeamento}; do
        local caminho="$exports_dir/$arquivo"
        [ -f "$caminho" ] || continue
        local icon_novo="${mapeamento[$arquivo]}"
        if grep -q "^Icon=${icon_novo}$" "$caminho"; then
            continue
        fi
        sed -i -E "s|^Icon=.*|Icon=${icon_novo}|" "$caminho"
        echo -e "  ${D_GREEN}[OK]${D_RESET} $arquivo -> Icon=$icon_novo"
        ((ajustados++))
    done

    if [ $ajustados -eq 0 ]; then
        __ok "Nenhum ajuste necessario"
    else
        __ok "$ajustados .desktop corrigido(s)"
    fi
    echo ""
}

# Proposito: Reconstruir Dracula_OS-Theme do zero (build + install --user)
# Uso: rebuild_dracula_theme [--activate]
rebuild_dracula_theme() {
    local repo="$HOME/Desenvolvimento/Dracula_OS-Theme"
    if [ ! -d "$repo" ]; then
        echo -e "  ${D_YELLOW}[!]${D_RESET} Repo não encontrado em $repo"
        return 1
    fi

    __header "DRACULA_OS-THEME REBUILD" "$D_PURPLE"

    (
        cd "$repo" || return 1

        # Garantir que upstreams estao presentes (.gitignore esconde do repo)
        if [ ! -d "src/icons/upstream/dracula-icons-main" ]; then
            echo -e "  ${D_COMMENT}Baixando upstreams ausentes...${D_RESET}"
            ./scripts/baixar_upstreams.sh || return 1
        fi

        echo -e "  ${D_COMMENT}Regenerando mapping.json...${D_RESET}"
        python3 scripts/extrair_mapeamento.py >/dev/null || return 1

        echo -e "  ${D_COMMENT}Rodando build.sh...${D_RESET}"
        ./build.sh > /tmp/dracula-build.log 2>&1 || {
            echo -e "  ${D_RED}[X]${D_RESET} build.sh falhou (veja /tmp/dracula-build.log)"
            return 1
        }

        echo -e "  ${D_COMMENT}Instalando em ~/.local/share/...${D_RESET}"
        ./install.sh --user "$@" > /tmp/dracula-install.log 2>&1 || {
            echo -e "  ${D_RED}[X]${D_RESET} install.sh falhou (veja /tmp/dracula-install.log)"
            return 1
        }
    ) || return 1

    __ok "Dracula_OS-Theme reconstruido e instalado"
    echo ""
}

# Proposito: Exibir contexto de usuario no prompt (SSH e usuarios não-padrao)
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
