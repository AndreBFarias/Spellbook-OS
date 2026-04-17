#!/bin/zsh

# ---------------------------------------------------------------------------
# Helpers privados
# ---------------------------------------------------------------------------

__restaurar_dir_manifesto() {
    echo "${HOME}/.config/spellbook/manifesto"
}

__restaurar_timestamp() {
    date +"%Y-%m-%dT%H:%M:%S%z"
}

__restaurar_json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    echo "$str"
}

__restaurar_capturar_distro() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release 2>/dev/null
        echo "${PRETTY_NAME:-Linux}"
    else
        echo "Linux"
    fi
}

__restaurar_capturar_desktop() {
    echo "${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-desconhecido}}"
}

__restaurar_capturar_apt() {
    apt-mark showmanual 2>/dev/null | sort
}

__restaurar_capturar_snap() {
    if ! command -v snap &>/dev/null; then
        return
    fi
    snap list 2>/dev/null | tail -n +2 | while IFS= read -r linha; do
        local nome=$(echo "$linha" | awk '{print $1}')
        local canal=$(echo "$linha" | awk '{print $4}')
        [[ "$nome" == "core"* || "$nome" == "bare" || "$nome" == "snapd" ]] && continue
        echo "${nome}|${canal:-stable}"
    done
}

__restaurar_capturar_flatpak() {
    if ! command -v flatpak &>/dev/null; then
        return
    fi
    flatpak list --app --columns=application,name 2>/dev/null | while IFS=$'\t' read -r id nome; do
        [[ -z "$id" ]] && continue
        echo "${id}|${nome}"
    done
}

__restaurar_capturar_pip() {
    if ! command -v pip3 &>/dev/null; then
        return
    fi
    pip3 list --user --format=freeze 2>/dev/null | while IFS='=' read -r nome _ versao; do
        [[ -z "$nome" ]] && continue
        echo "${nome}|${versao}"
    done
}

__restaurar_capturar_npm() {
    if ! command -v npm &>/dev/null; then
        return
    fi
    npm list -g --depth=0 --json 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    deps = data.get('dependencies', {})
    for name, info in deps.items():
        version = info.get('version', '')
        print(f'{name}|{version}')
except Exception:
    pass
" 2>/dev/null
}

__restaurar_capturar_fontes_custom() {
    local dirs=(
        "${HOME}/.local/share/fonts"
        "${HOME}/.fonts"
    )
    for dir in "${dirs[@]}"; do
        [[ -d "$dir" ]] || continue
        find "$dir" -type f \( -name "*.ttf" -o -name "*.otf" -o -name "*.ttc" \) 2>/dev/null
    done | sort
}

__restaurar_capturar_vscode() {
    if ! command -v code &>/dev/null; then
        return
    fi
    code --list-extensions 2>/dev/null | sort
}

__restaurar_capturar_git_config() {
    git config --global --list 2>/dev/null | while IFS='=' read -r chave valor; do
        [[ -z "$chave" ]] && continue
        echo "${chave}|${valor}"
    done
}

__restaurar_capturar_ssh() {
    local ssh_dir="${HOME}/.ssh"
    [[ -d "$ssh_dir" ]] || return
    find "$ssh_dir" -maxdepth 1 -name "id_*" ! -name "*.pub" -type f 2>/dev/null | while IFS= read -r arquivo; do
        basename "$arquivo"
    done | sort
}

__restaurar_capturar_repos_apt() {
    local repos=()

    if [[ -d /etc/apt/sources.list.d/ ]]; then
        for arquivo in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
            [[ -f "$arquivo" ]] || continue
            repos+=("$(basename "$arquivo")")
        done
    fi

    for repo in "${repos[@]}"; do
        echo "$repo"
    done | sort
}

__restaurar_capturar_appimages() {
    local dirs=(
        "${HOME}/Applications"
        "${HOME}/AppImages"
        "${HOME}/.local/bin"
        "${HOME}/Aplicativos"
    )
    for dir in "${dirs[@]}"; do
        [[ -d "$dir" ]] || continue
        find "$dir" -maxdepth 2 -name "*.AppImage" -type f 2>/dev/null
    done | sort
}

__restaurar_capturar_tema() {
    local gtk_tema icones cursor cursor_tamanho wallpaper

    if command -v gsettings &>/dev/null; then
        gtk_tema=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'")
        icones=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")
        cursor=$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null | tr -d "'")
        cursor_tamanho=$(gsettings get org.gnome.desktop.interface cursor-size 2>/dev/null)
        wallpaper=$(gsettings get org.gnome.desktop.background picture-uri 2>/dev/null | tr -d "'")
    fi

    echo "${gtk_tema:-}|${icones:-}|${cursor:-}|${cursor_tamanho:-24}|${wallpaper:-}"
}

__restaurar_capturar_crontabs() {
    crontab -l 2>/dev/null
}

__restaurar_capturar_systemd_user() {
    if command -v systemctl &>/dev/null; then
        systemctl --user list-unit-files --state=enabled --no-pager 2>/dev/null | \
            tail -n +2 | head -n -2 | awk '{print $1}'
    fi
}

__restaurar_capturar_cosmic() {
    local cosmic_dir="${HOME}/.config/cosmic"
    local backup_file="$(__restaurar_dir_manifesto)/cosmic-backup.tar.gz"

    if [[ -d "$cosmic_dir" ]]; then
        mkdir -p "$(__restaurar_dir_manifesto)"
        tar -czf "$backup_file" -C "${HOME}/.config" "cosmic" 2>/dev/null
        echo "$backup_file"
    fi
}

__restaurar_capturar_dconf() {
    if command -v dconf &>/dev/null; then
        local backup_file="$(__restaurar_dir_manifesto)/dconf-backup.ini"
        mkdir -p "$(__restaurar_dir_manifesto)"
        dconf dump / > "$backup_file" 2>/dev/null
        echo "$backup_file"
    fi
}

# ---------------------------------------------------------------------------
# Funções públicas
# ---------------------------------------------------------------------------

# Propósito: Capturar manifesto completo do sistema (APT, Flatpak, SSH, VSCode, git, temas)
# Uso: sistema_capturar [--saida <arquivo>]
# Flags: --saida=Caminho do manifesto de saída (default: $HOME/.sistema/manifestos/AAAA-MM-DD.json)
sistema_capturar() {
    local saida=""

    for arg in "$@"; do
        case "$arg" in
            --saida) ;;
            *) [[ -n "$saida" ]] || saida="$arg" ;;
        esac
    done

    local prev_arg=""
    for arg in "$@"; do
        if [[ "$prev_arg" == "--saida" ]]; then
            saida="$arg"
        fi
        prev_arg="$arg"
    done

    __verificar_dependencias "jq" || return 1

    local manifesto_dir=$(__restaurar_dir_manifesto)
    mkdir -p "$manifesto_dir"

    local timestamp=$(__restaurar_timestamp)
    local nome_arquivo="manifesto_$(date +%Y%m%d_%H%M%S).json"

    if [[ -n "$saida" ]]; then
        nome_arquivo="$saida"
        [[ "$nome_arquivo" != *".json" ]] && nome_arquivo="${nome_arquivo}.json"
    fi

    local caminho_completo="${manifesto_dir}/${nome_arquivo}"

    __header "CAPTURAR ESTADO DO SISTEMA" "$D_GREEN"
    echo -e "  ${D_COMMENT}Destino: ${D_FG}${caminho_completo}${D_RESET}"
    echo ""

    local json="{"
    json+="\"versao_manifesto\":\"1.0\","

    echo -e "  ${D_PURPLE}[1/14]${D_RESET} Metadados do sistema"
    json+="\"meta\":{"
    json+="\"timestamp\":\"${timestamp}\","
    json+="\"hostname\":\"$(hostname)\","
    json+="\"distro\":\"$(__restaurar_capturar_distro)\","
    json+="\"kernel\":\"$(uname -r)\","
    json+="\"desktop\":\"$(__restaurar_capturar_desktop)\""
    json+="},"

    echo -e "  ${D_PURPLE}[2/14]${D_RESET} Pacotes APT (instalados manualmente)"
    local apt_json="["
    local primeiro=true
    while IFS= read -r pkg; do
        [[ -z "$pkg" ]] && continue
        [[ "$primeiro" == true ]] && primeiro=false || apt_json+=","
        apt_json+="\"$(__restaurar_json_escape "$pkg")\""
    done < <(__restaurar_capturar_apt)
    apt_json+="]"
    json+="\"apt_pacotes_manuais\":${apt_json},"

    echo -e "  ${D_PURPLE}[3/14]${D_RESET} Pacotes Snap"
    local snap_json="["
    primeiro=true
    while IFS='|' read -r nome canal; do
        [[ -z "$nome" ]] && continue
        [[ "$primeiro" == true ]] && primeiro=false || snap_json+=","
        snap_json+="{\"nome\":\"$(__restaurar_json_escape "$nome")\",\"canal\":\"$(__restaurar_json_escape "$canal")\"}"
    done < <(__restaurar_capturar_snap)
    snap_json+="]"
    json+="\"snap_pacotes\":${snap_json},"

    echo -e "  ${D_PURPLE}[4/14]${D_RESET} Pacotes Flatpak"
    local flatpak_json="["
    primeiro=true
    while IFS='|' read -r id nome; do
        [[ -z "$id" ]] && continue
        [[ "$primeiro" == true ]] && primeiro=false || flatpak_json+=","
        flatpak_json+="{\"id\":\"$(__restaurar_json_escape "$id")\",\"nome\":\"$(__restaurar_json_escape "$nome")\"}"
    done < <(__restaurar_capturar_flatpak)
    flatpak_json+="]"
    json+="\"flatpak_pacotes\":${flatpak_json},"

    echo -e "  ${D_PURPLE}[5/14]${D_RESET} Pacotes pip globais"
    local pip_json="["
    primeiro=true
    while IFS='|' read -r nome versao; do
        [[ -z "$nome" ]] && continue
        [[ "$primeiro" == true ]] && primeiro=false || pip_json+=","
        pip_json+="{\"nome\":\"$(__restaurar_json_escape "$nome")\",\"versao\":\"$(__restaurar_json_escape "$versao")\"}"
    done < <(__restaurar_capturar_pip)
    pip_json+="]"
    json+="\"pip_global\":${pip_json},"

    echo -e "  ${D_PURPLE}[6/14]${D_RESET} Pacotes npm globais"
    local npm_json="["
    primeiro=true
    while IFS='|' read -r nome versao; do
        [[ -z "$nome" ]] && continue
        [[ "$primeiro" == true ]] && primeiro=false || npm_json+=","
        npm_json+="{\"nome\":\"$(__restaurar_json_escape "$nome")\",\"versao\":\"$(__restaurar_json_escape "$versao")\"}"
    done < <(__restaurar_capturar_npm)
    npm_json+="]"
    json+="\"npm_global\":${npm_json},"

    echo -e "  ${D_PURPLE}[7/14]${D_RESET} Fontes customizadas"
    local fontes_json="["
    primeiro=true
    while IFS= read -r fonte; do
        [[ -z "$fonte" ]] && continue
        [[ "$primeiro" == true ]] && primeiro=false || fontes_json+=","
        fontes_json+="\"$(__restaurar_json_escape "$fonte")\""
    done < <(__restaurar_capturar_fontes_custom)
    fontes_json+="]"
    json+="\"fontes_custom\":${fontes_json},"

    echo -e "  ${D_PURPLE}[8/14]${D_RESET} Tema e aparência"
    local tema_info
    tema_info=$(__restaurar_capturar_tema)
    IFS='|' read -r gtk_tema icones cursor cursor_tamanho wallpaper <<< "$tema_info"
    json+="\"tema\":{"
    json+="\"gtk_tema\":\"$(__restaurar_json_escape "$gtk_tema")\","
    json+="\"icones\":\"$(__restaurar_json_escape "$icones")\","
    json+="\"cursor\":\"$(__restaurar_json_escape "$cursor")\","
    json+="\"cursor_tamanho\":${cursor_tamanho:-24},"
    json+="\"wallpaper\":\"$(__restaurar_json_escape "$wallpaper")\""
    json+="},"

    echo -e "  ${D_PURPLE}[9/14]${D_RESET} Repositórios APT"
    local repos_json="["
    primeiro=true
    while IFS= read -r repo; do
        [[ -z "$repo" ]] && continue
        [[ "$primeiro" == true ]] && primeiro=false || repos_json+=","
        repos_json+="\"$(__restaurar_json_escape "$repo")\""
    done < <(__restaurar_capturar_repos_apt)
    repos_json+="]"
    json+="\"repositorios_apt\":${repos_json},"

    echo -e "  ${D_PURPLE}[10/14]${D_RESET} AppImages"
    local appimages_json="["
    primeiro=true
    while IFS= read -r app; do
        [[ -z "$app" ]] && continue
        [[ "$primeiro" == true ]] && primeiro=false || appimages_json+=","
        appimages_json+="\"$(__restaurar_json_escape "$app")\""
    done < <(__restaurar_capturar_appimages)
    appimages_json+="]"
    json+="\"appimages\":${appimages_json},"

    echo -e "  ${D_PURPLE}[11/14]${D_RESET} Extensões VS Code"
    local vscode_json="["
    primeiro=true
    while IFS= read -r ext; do
        [[ -z "$ext" ]] && continue
        [[ "$primeiro" == true ]] && primeiro=false || vscode_json+=","
        vscode_json+="\"$(__restaurar_json_escape "$ext")\""
    done < <(__restaurar_capturar_vscode)
    vscode_json+="]"
    json+="\"extensoes_vscode\":${vscode_json},"

    echo -e "  ${D_PURPLE}[12/14]${D_RESET} Git config global"
    local git_json="{"
    primeiro=true
    while IFS='|' read -r chave valor; do
        [[ -z "$chave" ]] && continue
        [[ "$primeiro" == true ]] && primeiro=false || git_json+=","
        git_json+="\"$(__restaurar_json_escape "$chave")\":\"$(__restaurar_json_escape "$valor")\""
    done < <(__restaurar_capturar_git_config)
    git_json+="}"
    json+="\"git_config_global\":${git_json},"

    echo -e "  ${D_PURPLE}[13/14]${D_RESET} Chaves SSH"
    local ssh_json="["
    primeiro=true
    while IFS= read -r chave; do
        [[ -z "$chave" ]] && continue
        [[ "$primeiro" == true ]] && primeiro=false || ssh_json+=","
        ssh_json+="\"$(__restaurar_json_escape "$chave")\""
    done < <(__restaurar_capturar_ssh)
    ssh_json+="]"
    json+="\"ssh_chaves\":${ssh_json},"

    echo -e "  ${D_PURPLE}[14/14]${D_RESET} Crontabs e systemd"
    local crontab_content
    crontab_content=$(__restaurar_capturar_crontabs)
    json+="\"crontabs\":\"$(__restaurar_json_escape "$crontab_content")\","

    local systemd_json="["
    primeiro=true
    while IFS= read -r unit; do
        [[ -z "$unit" ]] && continue
        [[ "$primeiro" == true ]] && primeiro=false || systemd_json+=","
        systemd_json+="\"$(__restaurar_json_escape "$unit")\""
    done < <(__restaurar_capturar_systemd_user)
    systemd_json+="]"
    json+="\"systemd_user\":${systemd_json}"

    json+="}"

    echo "$json" | jq '.' > "$caminho_completo" 2>/dev/null

    if [[ $? -ne 0 ]]; then
        echo "$json" > "$caminho_completo"
        __warn "JSON salvo sem formatação (jq falhou na validação)"
    fi

    echo ""

    local cosmic_backup
    cosmic_backup=$(__restaurar_capturar_cosmic)
    [[ -n "$cosmic_backup" ]] && echo -e "  ${D_COMMENT}Backup Cosmic: ${cosmic_backup}${D_RESET}"

    local dconf_backup
    dconf_backup=$(__restaurar_capturar_dconf)
    [[ -n "$dconf_backup" ]] && echo -e "  ${D_COMMENT}Backup dconf: ${dconf_backup}${D_RESET}"

    echo ""
    __ok "Manifesto salvo em ${caminho_completo}"
    local tamanho=$(du -h "$caminho_completo" 2>/dev/null | cut -f1)
    echo -e "  ${D_COMMENT}Tamanho: ${tamanho}${D_RESET}"
    echo ""
}

# Propósito: Restaurar sistema a partir de manifesto salvo por sistema_capturar
# Uso: sistema_restaurar <manifesto.json> [categorias] [--dry-run]
# Flags: --dry-run=Não altera nada, apenas lista o que seria feito
# Completa:
#   <manifesto.json>=_files -g "*.json"
sistema_restaurar() {
    local manifesto="$1"
    local dry_run=false
    local categorias=""

    for arg in "$@"; do
        case "$arg" in
            --dry-run) dry_run=true ;;
            --categorias) ;;
            *) [[ "$arg" != "$manifesto" ]] && categorias="$arg" ;;
        esac
    done

    local prev_arg=""
    for arg in "$@"; do
        if [[ "$prev_arg" == "--categorias" ]]; then
            categorias="$arg"
        fi
        prev_arg="$arg"
    done

    if [[ -z "$manifesto" || ! -f "$manifesto" ]]; then
        __err "Uso: sistema_restaurar <manifesto.json> [--dry-run] [--categorias apt,snap,flatpak,pip,npm,fontes,tema,vscode,git]"
        return 1
    fi

    __verificar_dependencias "jq" || return 1

    if ! jq empty "$manifesto" 2>/dev/null; then
        __err "Manifesto inválido ou corrompido: $manifesto"
        return 1
    fi

    __header "RESTAURAR SISTEMA" "$D_GREEN"
    echo -e "  ${D_COMMENT}Manifesto: ${D_FG}${manifesto}${D_RESET}"
    local meta_distro=$(jq -r '.meta.distro // "desconhecida"' "$manifesto")
    local meta_timestamp=$(jq -r '.meta.timestamp // "desconhecido"' "$manifesto")
    echo -e "  ${D_COMMENT}Capturado em: ${D_FG}${meta_timestamp}${D_RESET}"
    echo -e "  ${D_COMMENT}Distro original: ${D_FG}${meta_distro}${D_RESET}"
    [[ "$dry_run" == true ]] && echo -e "  ${D_YELLOW}Modo dry-run — nenhuma alteração será feita${D_RESET}"
    echo ""

    __restaurar_categoria_ativa() {
        local cat="$1"
        [[ -z "$categorias" ]] && return 0
        [[ ",$categorias," == *",$cat,"* ]] && return 0
        return 1
    }

    if __restaurar_categoria_ativa "apt"; then
        echo -e "  ${D_PURPLE}${D_BOLD}[1/10] Repositórios APT${D_RESET}"
        local repos_count=$(jq -r '.repositorios_apt | length' "$manifesto" 2>/dev/null)
        echo -e "  ${D_COMMENT}${repos_count:-0} repositório(s) no manifesto${D_RESET}"
        echo ""

        echo -e "  ${D_PURPLE}${D_BOLD}[2/10] Pacotes APT${D_RESET}"
        local apt_count=$(jq -r '.apt_pacotes_manuais | length' "$manifesto" 2>/dev/null)
        echo -e "  ${D_COMMENT}${apt_count:-0} pacote(s) no manifesto${D_RESET}"

        if [[ "$dry_run" == false && ${apt_count:-0} -gt 0 ]]; then
            echo -e "  ${D_COMMENT}Atualizando índices...${D_RESET}"
            sudo apt update -qq 2>/dev/null

            local pacotes_apt
            pacotes_apt=$(jq -r '.apt_pacotes_manuais[]' "$manifesto" 2>/dev/null)
            echo "$pacotes_apt" | xargs sudo apt install -y -qq 2>/dev/null
            __ok "Pacotes APT processados"
        fi
        echo ""
    fi

    if __restaurar_categoria_ativa "snap"; then
        echo -e "  ${D_PURPLE}${D_BOLD}[3/10] Pacotes Snap${D_RESET}"
        local snap_count=$(jq -r '.snap_pacotes | length' "$manifesto" 2>/dev/null)
        echo -e "  ${D_COMMENT}${snap_count:-0} pacote(s) no manifesto${D_RESET}"

        if [[ "$dry_run" == false && ${snap_count:-0} -gt 0 ]] && command -v snap &>/dev/null; then
            jq -r '.snap_pacotes[] | "\(.nome) \(.canal)"' "$manifesto" 2>/dev/null | \
                while IFS=' ' read -r nome canal; do
                    [[ -z "$nome" ]] && continue
                    sudo snap install "$nome" --channel="${canal:-stable}" 2>/dev/null && \
                        __ok "Snap: $nome" || __warn "Snap falhou: $nome"
                done
        fi
        echo ""
    fi

    if __restaurar_categoria_ativa "flatpak"; then
        echo -e "  ${D_PURPLE}${D_BOLD}[4/10] Pacotes Flatpak${D_RESET}"
        local flatpak_count=$(jq -r '.flatpak_pacotes | length' "$manifesto" 2>/dev/null)
        echo -e "  ${D_COMMENT}${flatpak_count:-0} pacote(s) no manifesto${D_RESET}"

        if [[ "$dry_run" == false && ${flatpak_count:-0} -gt 0 ]] && command -v flatpak &>/dev/null; then
            jq -r '.flatpak_pacotes[].id' "$manifesto" 2>/dev/null | \
                while IFS= read -r id; do
                    [[ -z "$id" ]] && continue
                    flatpak install -y flathub "$id" 2>/dev/null && \
                        __ok "Flatpak: $id" || __warn "Flatpak falhou: $id"
                done
        fi
        echo ""
    fi

    if __restaurar_categoria_ativa "pip"; then
        echo -e "  ${D_PURPLE}${D_BOLD}[5/10] Pacotes pip${D_RESET}"
        local pip_count=$(jq -r '.pip_global | length' "$manifesto" 2>/dev/null)
        echo -e "  ${D_COMMENT}${pip_count:-0} pacote(s) no manifesto${D_RESET}"

        if [[ "$dry_run" == false && ${pip_count:-0} -gt 0 ]] && command -v pip3 &>/dev/null; then
            jq -r '.pip_global[] | "\(.nome)==\(.versao)"' "$manifesto" 2>/dev/null | \
                xargs pip3 install --user 2>/dev/null
            __ok "Pacotes pip processados"
        fi
        echo ""
    fi

    if __restaurar_categoria_ativa "npm"; then
        echo -e "  ${D_PURPLE}${D_BOLD}[6/10] Pacotes npm${D_RESET}"
        local npm_count=$(jq -r '.npm_global | length' "$manifesto" 2>/dev/null)
        echo -e "  ${D_COMMENT}${npm_count:-0} pacote(s) no manifesto${D_RESET}"

        if [[ "$dry_run" == false && ${npm_count:-0} -gt 0 ]] && command -v npm &>/dev/null; then
            jq -r '.npm_global[] | "\(.nome)@\(.versao)"' "$manifesto" 2>/dev/null | \
                xargs npm install -g 2>/dev/null
            __ok "Pacotes npm processados"
        fi
        echo ""
    fi

    if __restaurar_categoria_ativa "fontes"; then
        echo -e "  ${D_PURPLE}${D_BOLD}[7/10] Fontes${D_RESET}"
        local fontes_count=$(jq -r '.fontes_custom | length' "$manifesto" 2>/dev/null)
        echo -e "  ${D_COMMENT}${fontes_count:-0} fonte(s) customizada(s) no manifesto${D_RESET}"

        if [[ "$dry_run" == false ]]; then
            if command -v fontes_instalar &>/dev/null; then
                fontes_instalar
            else
                __warn "Função fontes_instalar não disponível"
            fi
        fi
        echo ""
    fi

    if __restaurar_categoria_ativa "tema"; then
        echo -e "  ${D_PURPLE}${D_BOLD}[8/10] Tema e aparência${D_RESET}"
        local gtk_tema=$(jq -r '.tema.gtk_tema // ""' "$manifesto" 2>/dev/null)
        local icones=$(jq -r '.tema.icones // ""' "$manifesto" 2>/dev/null)
        local cursor=$(jq -r '.tema.cursor // ""' "$manifesto" 2>/dev/null)
        local cursor_tamanho=$(jq -r '.tema.cursor_tamanho // 24' "$manifesto" 2>/dev/null)
        local wallpaper=$(jq -r '.tema.wallpaper // ""' "$manifesto" 2>/dev/null)

        echo -e "  ${D_COMMENT}GTK: ${gtk_tema}, Ícones: ${icones}, Cursor: ${cursor}${D_RESET}"

        if [[ "$dry_run" == false ]] && command -v gsettings &>/dev/null; then
            [[ -n "$gtk_tema" ]] && gsettings set org.gnome.desktop.interface gtk-theme "$gtk_tema" 2>/dev/null
            [[ -n "$icones" ]] && gsettings set org.gnome.desktop.interface icon-theme "$icones" 2>/dev/null
            [[ -n "$cursor" ]] && gsettings set org.gnome.desktop.interface cursor-theme "$cursor" 2>/dev/null
            [[ -n "$cursor_tamanho" ]] && gsettings set org.gnome.desktop.interface cursor-size "$cursor_tamanho" 2>/dev/null
            [[ -n "$wallpaper" ]] && gsettings set org.gnome.desktop.background picture-uri "$wallpaper" 2>/dev/null
            __ok "Tema aplicado via gsettings"

            local dconf_backup="$(__restaurar_dir_manifesto)/dconf-backup.ini"
            if [[ -f "$dconf_backup" ]]; then
                dconf load / < "$dconf_backup" 2>/dev/null
                __ok "Configurações dconf restauradas"
            fi
        fi

        local cosmic_backup="$(__restaurar_dir_manifesto)/cosmic-backup.tar.gz"
        if [[ -f "$cosmic_backup" && "$dry_run" == false ]]; then
            tar -xzf "$cosmic_backup" -C "${HOME}/.config/" 2>/dev/null
            __ok "Configurações Cosmic restauradas"
        fi
        echo ""
    fi

    if __restaurar_categoria_ativa "vscode"; then
        echo -e "  ${D_PURPLE}${D_BOLD}[9/10] Extensões VS Code${D_RESET}"
        local vscode_count=$(jq -r '.extensoes_vscode | length' "$manifesto" 2>/dev/null)
        echo -e "  ${D_COMMENT}${vscode_count:-0} extensão(ões) no manifesto${D_RESET}"

        if [[ "$dry_run" == false && ${vscode_count:-0} -gt 0 ]] && command -v code &>/dev/null; then
            jq -r '.extensoes_vscode[]' "$manifesto" 2>/dev/null | \
                while IFS= read -r ext; do
                    [[ -z "$ext" ]] && continue
                    code --install-extension "$ext" --force 2>/dev/null
                done
            __ok "Extensões VS Code processadas"
        fi
        echo ""
    fi

    if __restaurar_categoria_ativa "git"; then
        echo -e "  ${D_PURPLE}${D_BOLD}[10/10] Git config global${D_RESET}"

        if [[ "$dry_run" == false ]]; then
            jq -r '.git_config_global | to_entries[] | "\(.key) \(.value)"' "$manifesto" 2>/dev/null | \
                while IFS=' ' read -r chave valor; do
                    [[ -z "$chave" ]] && continue
                    git config --global "$chave" "$valor" 2>/dev/null
                done
            __ok "Git config global restaurado"
        fi
        echo ""
    fi

    echo ""
    if [[ "$dry_run" == true ]]; then
        __ok "Dry-run concluído — nenhuma alteração feita"
    else
        __ok "Restauração concluída"
    fi
    echo ""

    unfunction __restaurar_categoria_ativa 2>/dev/null
}

# Propósito: Comparar manifesto salvo com estado atual do sistema
# Uso: sistema_diff [manifesto.json]
# Completa:
#   [manifesto.json]=_files -g "*.json"
sistema_diff() {
    local manifesto="$1"

    if [[ -z "$manifesto" ]]; then
        local manifesto_dir=$(__restaurar_dir_manifesto)
        manifesto=$(ls -t "$manifesto_dir"/*.json 2>/dev/null | head -1)
    fi

    if [[ -z "$manifesto" || ! -f "$manifesto" ]]; then
        __err "Nenhum manifesto encontrado. Use: sistema_diff <manifesto.json>"
        return 1
    fi

    __verificar_dependencias "jq" || return 1

    __header "COMPARAÇÃO COM MANIFESTO" "$D_ORANGE"
    echo -e "  ${D_COMMENT}Manifesto: ${D_FG}$(basename "$manifesto")${D_RESET}"
    local meta_timestamp=$(jq -r '.meta.timestamp // "desconhecido"' "$manifesto")
    echo -e "  ${D_COMMENT}Data: ${D_FG}${meta_timestamp}${D_RESET}"
    echo ""

    echo -e "  ${D_PURPLE}${D_BOLD}Pacotes APT${D_RESET}"
    local apt_manifesto=$(jq -r '.apt_pacotes_manuais[]' "$manifesto" 2>/dev/null | sort)
    local apt_atual=$(__restaurar_capturar_apt)

    local apenas_manifesto=$(comm -23 <(echo "$apt_manifesto") <(echo "$apt_atual"))
    local apenas_atual=$(comm -13 <(echo "$apt_manifesto") <(echo "$apt_atual"))

    local faltantes=$(echo "$apenas_manifesto" | grep -c '[^ ]' 2>/dev/null)
    local novos=$(echo "$apenas_atual" | grep -c '[^ ]' 2>/dev/null)

    if [[ ${faltantes:-0} -gt 0 ]]; then
        echo -e "  ${D_RED}Faltantes (no manifesto, não no sistema): ${faltantes}${D_RESET}"
        echo "$apenas_manifesto" | head -10 | while IFS= read -r pkg; do
            [[ -z "$pkg" ]] && continue
            echo -e "    ${D_RED}- ${pkg}${D_RESET}"
        done
        [[ ${faltantes:-0} -gt 10 ]] && echo -e "    ${D_COMMENT}... e mais $((faltantes - 10))${D_RESET}"
    fi

    if [[ ${novos:-0} -gt 0 ]]; then
        echo -e "  ${D_GREEN}Novos (no sistema, não no manifesto): ${novos}${D_RESET}"
        echo "$apenas_atual" | head -10 | while IFS= read -r pkg; do
            [[ -z "$pkg" ]] && continue
            echo -e "    ${D_GREEN}+ ${pkg}${D_RESET}"
        done
        [[ ${novos:-0} -gt 10 ]] && echo -e "    ${D_COMMENT}... e mais $((novos - 10))${D_RESET}"
    fi

    if [[ ${faltantes:-0} -eq 0 && ${novos:-0} -eq 0 ]]; then
        __ok "Pacotes APT idênticos ao manifesto"
    fi
    echo ""

    echo -e "  ${D_PURPLE}${D_BOLD}Extensões VS Code${D_RESET}"
    local vscode_manifesto=$(jq -r '.extensoes_vscode[]' "$manifesto" 2>/dev/null | sort)
    local vscode_atual=$(__restaurar_capturar_vscode)

    if [[ -n "$vscode_atual" ]]; then
        local ext_faltantes=$(comm -23 <(echo "$vscode_manifesto") <(echo "$vscode_atual") | grep -c '[^ ]' 2>/dev/null)
        local ext_novas=$(comm -13 <(echo "$vscode_manifesto") <(echo "$vscode_atual") | grep -c '[^ ]' 2>/dev/null)
        echo -e "  ${D_COMMENT}Faltantes: ${ext_faltantes:-0} | Novas: ${ext_novas:-0}${D_RESET}"
    else
        __warn "VS Code não encontrado no sistema"
    fi
    echo ""

    echo -e "  ${D_PURPLE}${D_BOLD}Resumo${D_RESET}"
    echo -e "  ${D_RED}Faltantes no sistema: ${faltantes:-0} pacote(s) APT${D_RESET}"
    echo -e "  ${D_GREEN}Novos no sistema:     ${novos:-0} pacote(s) APT${D_RESET}"
    echo ""
}

# Propósito: Gerenciar manifestos salvos (exibir ou listar)
# Uso: sistema_manifesto [--listar]
# Flags: --listar=Lista todos os manifestos ao invés do último
sistema_manifesto() {
    local listar=false

    for arg in "$@"; do
        [[ "$arg" == "--listar" ]] && listar=true
    done

    local manifesto_dir=$(__restaurar_dir_manifesto)

    __header "MANIFESTOS DO SISTEMA" "$D_GREEN"
    echo -e "  ${D_COMMENT}Diretório: ${D_FG}${manifesto_dir}${D_RESET}"
    echo ""

    if [[ ! -d "$manifesto_dir" ]] || [[ -z "$(ls -A "$manifesto_dir"/*.json 2>/dev/null)" ]]; then
        __warn "Nenhum manifesto encontrado"
        echo -e "  ${D_COMMENT}Execute 'sistema_capturar' para criar o primeiro${D_RESET}"
        echo ""
        return 0
    fi

    printf "  ${D_PURPLE}%-35s %-10s %-20s${D_RESET}\n" "ARQUIVO" "TAMANHO" "DATA"
    printf "  ${D_COMMENT}%s${D_RESET}\n" "$(printf '%.0s─' {1..65})"

    ls -t "$manifesto_dir"/*.json 2>/dev/null | while IFS= read -r arquivo; do
        local nome=$(basename "$arquivo")
        local tamanho=$(du -h "$arquivo" 2>/dev/null | cut -f1)
        local data_captura=""

        if command -v jq &>/dev/null; then
            data_captura=$(jq -r '.meta.timestamp // ""' "$arquivo" 2>/dev/null)
            data_captura="${data_captura:0:19}"
        fi

        printf "  ${D_FG}%-35s${D_RESET} ${D_COMMENT}%-10s${D_RESET} ${D_FG}%-20s${D_RESET}\n" \
            "${nome:0:35}" "$tamanho" "$data_captura"
    done
    echo ""

    local total=$(ls "$manifesto_dir"/*.json 2>/dev/null | wc -l)
    __ok "${total} manifesto(s) encontrado(s)"
    echo ""
}

# "A máquina não isola o homem dos grandes problemas da natureza, mas mergulha-o mais profundamente neles." — Antoine de Saint-Exupéry
