#!/bin/bash
# Instalador e configurador do Spicetify para Spellbook-OS
# Detecta tipo de instalação do Spotify, instala Spicetify e aplica config padrao

set -euo pipefail

SPICETIFY_BIN="$HOME/.spicetify/spicetify"
SPICETIFY_DIR="$HOME/.spicetify"
THEMES_DIR="$HOME/.config/spicetify/Themes"
CUSTOM_APPS_DIR="$SPICETIFY_DIR/CustomApps"

# Cores
_C_CYAN='\033[0;36m'
_C_GREEN='\033[0;32m'
_C_YELLOW='\033[0;33m'
_C_RED='\033[0;31m'
_C_DIM='\033[2m'
_C_BOLD='\033[1m'
_C_RESET='\033[0m'

_info()  { echo -e "  ${_C_CYAN}>>${_C_RESET} $*"; }
_ok()    { echo -e "  ${_C_GREEN}OK${_C_RESET}  $*"; }
_warn()  { echo -e "  ${_C_YELLOW}!!${_C_RESET} $*" >&2; }
_err()   { echo -e "  ${_C_RED}ERRO${_C_RESET} $*" >&2; exit 1; }

# --- Configuração padrao ---
TEMA="Sleek"
ESQUEMA="Dracula"
EXTENSIONS="autoSkipExplicit.js|autoSkipVideo.js|bookmark.js|fullAppDisplay.js|keyboardShortcut.js|loopyLoop.js|popupLyrics.js|shuffle+.js|trashbin.js|webnowplaying.js"
CUSTOM_APPS="marketplace|lyrics-plus|reddit|new-releases"

# --- Deteccao do Spotify ---
detectar_spotify() {
    if flatpak list 2>/dev/null | grep -q "com.spotify.Client"; then
        echo "flatpak"
    elif snap list 2>/dev/null | grep -q "spotify"; then
        echo "snap"
    elif command -v spotify &>/dev/null; then
        echo "nativo"
    elif [[ -d "/opt/spotify" ]]; then
        echo "nativo"
    else
        echo "nenhum"
    fi
}

# --- Instalar Spicetify ---
instalar_spicetify() {
    if [[ -x "$SPICETIFY_BIN" ]]; then
        local versao
        versao=$("$SPICETIFY_BIN" --version 2>/dev/null || echo "desconhecida")
        _ok "Spicetify já instalado (v${versao})"
        return 0
    fi

    _info "Instalando Spicetify..."
    curl -fsSL https://raw.githubusercontent.com/spicetify/cli/main/install.sh | sh
    if [[ -x "$SPICETIFY_BIN" ]]; then
        _ok "Spicetify instalado ($("$SPICETIFY_BIN" --version))"
    else
        _err "Falha ao instalar Spicetify"
    fi
}

# --- Instalar temas ---
instalar_temas() {
    if [[ -d "$THEMES_DIR/$TEMA" ]]; then
        _ok "Tema $TEMA já presente"
        return 0
    fi

    _info "Clonando repositorio de temas..."
    local tmp_dir
    tmp_dir=$(mktemp -d)
    git clone --depth=1 https://github.com/spicetify/spicetify-themes.git "$tmp_dir"
    mkdir -p "$THEMES_DIR"
    cp -r "$tmp_dir"/* "$THEMES_DIR/"
    rm -rf "$tmp_dir"

    if [[ -d "$THEMES_DIR/$TEMA" ]]; then
        _ok "Temas instalados (tema ativo: $TEMA)"
    else
        _warn "Clone concluido mas tema $TEMA não encontrado"
    fi
}

# --- Instalar Marketplace ---
instalar_marketplace() {
    if [[ -d "$CUSTOM_APPS_DIR/marketplace" ]]; then
        _ok "Marketplace já instalado"
        return 0
    fi

    _info "Instalando Marketplace custom app..."
    curl -fsSL https://raw.githubusercontent.com/spicetify/marketplace/main/resources/install.sh | sh
    if [[ -d "$CUSTOM_APPS_DIR/marketplace" ]]; then
        _ok "Marketplace instalado"
    else
        _warn "Marketplace não encontrado após instalação"
    fi
}

# --- Configurar paths por tipo de instalação ---
configurar_paths() {
    local tipo="$1"

    _info "Configurando paths para instalação $tipo..."

    case "$tipo" in
        flatpak)
            local flatpak_prefs="$HOME/.var/app/com.spotify.Client/config/spotify/prefs"
            if [[ -f "$flatpak_prefs" ]]; then
                "$SPICETIFY_BIN" config prefs_path "$flatpak_prefs"
                _ok "prefs_path configurado para Flatpak"
            else
                _warn "prefs do Flatpak não encontrado — abra o Spotify uma vez primeiro"
                _info "Iniciando Spotify para gerar prefs..."
                flatpak run com.spotify.Client &>/dev/null &
                local pid=$!
                for i in $(seq 1 15); do
                    [[ -f "$flatpak_prefs" ]] && break
                    sleep 2
                done
                kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
                if [[ -f "$flatpak_prefs" ]]; then
                    "$SPICETIFY_BIN" config prefs_path "$flatpak_prefs"
                    _ok "prefs_path configurado para Flatpak"
                else
                    _warn "Falha ao gerar prefs — configure prefs_path manualmente"
                fi
            fi
            ;;
        snap)
            local snap_prefs="$HOME/snap/spotify/current/.config/spotify/prefs"
            if [[ -f "$snap_prefs" ]]; then
                "$SPICETIFY_BIN" config prefs_path "$snap_prefs"
                _ok "prefs_path configurado para Snap"
            fi
            ;;
        nativo)
            _ok "prefs_path padrao para instalação nativa"
            ;;
    esac
}

# --- Aplicar configuração via CLI ---
aplicar_config() {
    _info "Aplicando configuração..."

    "$SPICETIFY_BIN" config current_theme "$TEMA"
    "$SPICETIFY_BIN" config color_scheme "$ESQUEMA"

    "$SPICETIFY_BIN" config inject_css 1
    "$SPICETIFY_BIN" config replace_colors 1
    "$SPICETIFY_BIN" config overwrite_assets 1
    "$SPICETIFY_BIN" config inject_theme_js 1

    "$SPICETIFY_BIN" config sidebar_config 1
    "$SPICETIFY_BIN" config experimental_features 1
    "$SPICETIFY_BIN" config home_config 1

    "$SPICETIFY_BIN" config expose_apis 1
    "$SPICETIFY_BIN" config disable_sentry 1
    "$SPICETIFY_BIN" config disable_ui_logging 1
    "$SPICETIFY_BIN" config remove_rtl_rule 1

    _ok "Configuração aplicada via CLI"
}

# --- Configurar extensions e custom apps ---
aplicar_extensions() {
    _info "Configurando extensions e custom apps..."

    "$SPICETIFY_BIN" config extensions "$EXTENSIONS"
    "$SPICETIFY_BIN" config custom_apps "$CUSTOM_APPS"

    # Remover entrada espuria 'custom_apps' da lista de extensions se presente
    local ext_atual
    ext_atual=$("$SPICETIFY_BIN" config extensions | tr '\n' '|' | sed 's/|$//')
    if echo "$ext_atual" | grep -q '|custom_apps|'; then
        ext_atual=$(echo "$ext_atual" | sed 's/|custom_apps|/|/g; s/^custom_apps|//; s/|custom_apps$//')
        local ini_file="$HOME/.config/spicetify/config-xpui.ini"
        if [[ -f "$ini_file" ]]; then
            sed -i "s|^extensions.*=.*|extensions            = ${ext_atual}|" "$ini_file"
        fi
    fi

    _ok "Extensions e custom apps configurados"
}

# --- Restaurar e aplicar ---
restaurar_e_aplicar() {
    local tipo="$1"

    # Limpar cache web do Flatpak/Snap para evitar CSS/JS stale
    if [[ "$tipo" == "flatpak" ]]; then
        local cache_dir="$HOME/.var/app/com.spotify.Client/cache/spotify/Default/Cache"
        if [[ -d "$cache_dir" ]]; then
            rm -rf "${cache_dir:?}/"*
            _ok "Cache web do Flatpak limpo"
        fi
    fi

    _info "Restaurando Spotify ao estado original..."
    "$SPICETIFY_BIN" restore 2>/dev/null || true

    _info "Limpando backup anterior..."
    "$SPICETIFY_BIN" clear

    _info "Criando backup e aplicando customizacoes..."
    "$SPICETIFY_BIN" backup apply

    _ok "Spicetify aplicado com sucesso"
}

# --- Validação ---
validar() {
    local erros=0

    _info "Validando instalação..."

    if ! "$SPICETIFY_BIN" config extensions | grep -q "bookmark.js"; then
        _warn "Extensions não configuradas corretamente"
        ((erros++))
    fi

    if ! "$SPICETIFY_BIN" config custom_apps | grep -q "marketplace"; then
        _warn "Custom apps não configurados corretamente"
        ((erros++))
    fi

    local tema_atual
    tema_atual=$("$SPICETIFY_BIN" config current_theme 2>/dev/null || echo "")
    if [[ "$tema_atual" != "$TEMA" ]]; then
        _warn "Tema atual ($tema_atual) difere do esperado ($TEMA)"
        ((erros++))
    fi

    if [[ $erros -eq 0 ]]; then
        _ok "Validação completa: tudo OK"
    else
        _warn "$erros problema(s) detectado(s)"
        return 1
    fi
}

# --- Main ---
main() {
    echo ""
    echo -e "  ${_C_BOLD}Spicetify Setup — Spellbook-OS${_C_RESET}"
    echo -e "  ${_C_DIM}$(printf '%.0s─' {1..40})${_C_RESET}"

    local tipo_spotify
    tipo_spotify=$(detectar_spotify)
    _info "Spotify detectado: $tipo_spotify"

    if [[ "$tipo_spotify" == "nenhum" ]]; then
        _err "Spotify não encontrado. Instale o Spotify primeiro."
    fi

    instalar_spicetify
    configurar_paths "$tipo_spotify"
    instalar_temas
    instalar_marketplace
    aplicar_config
    aplicar_extensions
    restaurar_e_aplicar "$tipo_spotify"
    validar

    echo ""
    echo -e "  ${_C_GREEN}${_C_BOLD}Spicetify configurado com sucesso.${_C_RESET}"
    echo -e "  ${_C_DIM}Abra o Spotify para verificar.${_C_RESET}"
}

main "$@"

# "A musica e a arte das musas." -- Platao
