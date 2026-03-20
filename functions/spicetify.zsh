#!/bin/zsh

# ---------------------------------------------------------------------------
# Helpers privados
# ---------------------------------------------------------------------------

__spicetify_bin() {
    local bin="$HOME/.spicetify/spicetify"
    if [[ ! -x "$bin" ]]; then
        __err "Spicetify nao encontrado em $bin"
        return 1
    fi
    echo "$bin"
}

__spicetify_config_value() {
    local bin key
    bin=$(__spicetify_bin) || return 1
    key="$1"
    "$bin" config "$key" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Funcoes publicas
# ---------------------------------------------------------------------------

spicetify_status() {
    local bin
    bin=$(__spicetify_bin) || return 1

    __header "Spicetify Status"

    local versao
    versao=$("$bin" --version 2>/dev/null || echo "desconhecida")
    __item "Versao:" "$versao" "$D_COMMENT" "$D_GREEN"

    local tema esquema
    tema=$(__spicetify_config_value current_theme)
    esquema=$(__spicetify_config_value color_scheme)
    __item "Tema:" "$tema" "$D_COMMENT" "$D_PURPLE"
    __item "Esquema:" "$esquema" "$D_COMMENT" "$D_PURPLE"

    __header "Extensions" "$D_CYAN"
    local ext
    ext=$(__spicetify_config_value extensions)
    if [[ -n "$ext" ]]; then
        echo "$ext" | while IFS= read -r e; do
            __item "-" "$e" "$D_COMMENT" "$D_FG"
        done
    else
        __warn "Nenhuma extension configurada"
    fi

    __header "Custom Apps" "$D_CYAN"
    local apps
    apps=$(__spicetify_config_value custom_apps)
    if [[ -n "$apps" ]]; then
        echo "$apps" | while IFS= read -r a; do
            __item "-" "$a" "$D_COMMENT" "$D_FG"
        done
    else
        __warn "Nenhum custom app configurado"
    fi

    __header "Preprocesses" "$D_CYAN"
    local flag val cor
    for flag in expose_apis disable_sentry disable_ui_logging remove_rtl_rule; do
        val=$(__spicetify_config_value "$flag")
        cor="$D_GREEN"
        [[ "$val" == "0" ]] && cor="$D_RED"
        __item "$flag:" "$val" "$D_COMMENT" "$cor"
    done
}

spicetify_reparar() {
    local bin
    bin=$(__spicetify_bin) || return 1

    __header "Spicetify Reparacao"

    local ext_esperadas="autoSkipExplicit.js|autoSkipVideo.js|bookmark.js|fullAppDisplay.js|keyboardShortcut.js|loopyLoop.js|popupLyrics.js|shuffle+.js|trashbin.js|webnowplaying.js"
    local apps_esperados="marketplace|lyrics-plus|reddit|new-releases"

    local ext_atual
    ext_atual=$("$bin" config extensions | tr '\n' '|' | sed 's/|$//')

    if [[ "$ext_atual" != "$ext_esperadas" ]]; then
        __warn "Extensions divergem do esperado"
        __item "Atual:" "$ext_atual" "$D_COMMENT" "$D_RED"
        __item "Esperado:" "$ext_esperadas" "$D_COMMENT" "$D_GREEN"

        local ini_file="$HOME/.config/spicetify/config-xpui.ini"
        if [[ -f "$ini_file" ]]; then
            sed -i "s|^extensions.*=.*|extensions            = ${ext_esperadas}|" "$ini_file"
            __ok "Extensions corrigidas no INI"
        fi
    else
        __ok "Extensions OK"
    fi

    local apps_atual
    apps_atual=$("$bin" config custom_apps | tr '\n' '|' | sed 's/|$//')

    if [[ "$apps_atual" != "$apps_esperados" ]]; then
        __warn "Custom apps divergem do esperado"
        "$bin" config custom_apps "$apps_esperados"
        __ok "Custom apps corrigidos"
    else
        __ok "Custom apps OK"
    fi

    # Verificar sidebar_config
    local sidebar
    sidebar=$("$bin" config sidebar_config 2>/dev/null)
    if [[ "$sidebar" != "1" ]]; then
        __warn "sidebar_config desativado — ativando"
        "$bin" config sidebar_config 1
        __ok "sidebar_config ativado"
    else
        __ok "sidebar_config OK"
    fi

    # Verificar prefs_path para Flatpak
    if flatpak list 2>/dev/null | grep -q "com.spotify.Client"; then
        local prefs_atual flatpak_prefs
        prefs_atual=$("$bin" config prefs_path 2>/dev/null)
        flatpak_prefs="$HOME/.var/app/com.spotify.Client/config/spotify/prefs"
        if [[ "$prefs_atual" != "$flatpak_prefs" && -f "$flatpak_prefs" ]]; then
            __warn "prefs_path aponta para path incorreto"
            "$bin" config prefs_path "$flatpak_prefs"
            __ok "prefs_path corrigido para Flatpak"
        else
            __ok "prefs_path OK"
        fi
    fi

    __item "Tema:" "$(__spicetify_config_value current_theme)" "$D_COMMENT" "$D_PURPLE"
    __item "Esquema:" "$(__spicetify_config_value color_scheme)" "$D_COMMENT" "$D_PURPLE"

    __header "Reaplicando" "$D_YELLOW"

    # Limpar cache web do Flatpak
    local cache_dir="$HOME/.var/app/com.spotify.Client/cache/spotify/Default/Cache"
    if [[ -d "$cache_dir" ]]; then
        rm -rf "${cache_dir:?}/"*
        __ok "Cache web do Flatpak limpo"
    fi

    "$bin" restore 2>/dev/null || true
    "$bin" clear 2>/dev/null
    "$bin" backup apply 2>/dev/null

    __ok "Spicetify reparado e reaplicado"
}

spicetify_instalar() {
    local script_dir="${ZDOTDIR:-$HOME/.config/zsh}/scripts/spicetify-setup.sh"

    if [[ ! -f "$script_dir" ]]; then
        __err "Script de setup nao encontrado: $script_dir"
        return 1
    fi

    bash "$script_dir"
}

# "Sem musica, a vida seria um erro." -- Friedrich Nietzsche
