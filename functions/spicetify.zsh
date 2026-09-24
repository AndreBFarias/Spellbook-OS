#!/bin/zsh

# ---------------------------------------------------------------------------
# Helpers privados
# ---------------------------------------------------------------------------

__spicetify_bin() {
    local bin="$HOME/.spicetify/spicetify"
    if [[ ! -x "$bin" ]]; then
        __err "Spicetify não encontrado em $bin"
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
# Funções públicas
# ---------------------------------------------------------------------------

# Propósito: Exibir status do Spicetify (tema, esquema, extensions, custom apps)
# Uso: spicetify_status
spicetify_status() {
    local bin
    bin=$(__spicetify_bin) || return 1

    __header "Spicetify Status"

    local versao
    versao=$("$bin" --version 2>/dev/null || echo "desconhecida")
    __item "Versão:" "$versao" "$D_COMMENT" "$D_GREEN"

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

# Propósito: Reparar extensions, custom apps e sidebar do Spicetify (o tema é do MeowSystem)
# Uso: spicetify_reparar
spicetify_reparar() {
    local bin
    bin=$(__spicetify_bin) || return 1

    __header "Spicetify Reparação"

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

    # [2026-09-23] SAIU O `restore` + `clear` + `backup apply`, E FICOU O `apply`.
    #   O backup do spicetify FOTOGRAFA o que está no disco. Rodado com o tema
    #   do MeowSystem aplicado, ele congela esse tema como se fosse o Spotify de
    #   fábrica, e o `spicetify restore` nunca mais devolve o original — medido
    #   e escrito pelo MeowSystem no scripts/spicetify_setup.sh de lá (recusa
    #   6), que é quem cuida do tema e do backup agora, com a versão conferida
    #   antes. Pela regra do dono de 23/09, o que conflita sai daqui.
    #   O `apply` sozinho não tira foto: aplica o config-xpui.ini como está —
    #   as extensões e os apps acima, que são desta máquina, e o tema que o
    #   MeowSystem escolheu. Se ele recusar (backup de outra versão do Spotify),
    #   quem sabe refazer sem estragar é o MeowSystem.
    if "$bin" apply 2>/dev/null; then
        __ok "Spicetify reparado e reaplicado (o tema é o do MeowSystem)"
    else
        __warn "o spicetify apply recusou — backup e tema são do MeowSystem: meow apps aplicar spotify"
    fi
}

# Propósito: Aviso de que o Spicetify e o tema do Spotify são do MeowSystem (não instala nada)
# Uso: spicetify_instalar
spicetify_instalar() {
    # [2026-09-23] DESATIVADA — o script que ela roda (scripts/spicetify-setup.sh)
    # faz oito coisas, e seis são território do MeowSystem desde 22/09 (sprint
    # P29 de lá): o binário por `curl | sh`, o `prefs_path`, os temas por
    # `git clone`, o Marketplace por `curl | sh`, `current_theme Sleek` e
    # `color_scheme Dracula` no config-xpui.ini — as MESMAS duas chaves que o
    # manifesto do Spotify do MeowSystem escreve a partir do pack — e o
    # `restore` + `backup apply` que congela o tema dele como se fosse o
    # Spotify de fábrica. Dois donos no mesmo arquivo, e o último a rodar
    # vencia. (O `prefs_path` continua também no spicetify_reparar: lá ele só é
    # escrito quando diverge do arquivo que existe no disco, e o valor é o mesmo
    # que o MeowSystem deriva — não há disputa de valor.)
    #
    # O que é desta máquina — as dez extensões e os quatro custom apps — segue
    # vivo no spicetify_reparar, logo acima. Só manual (medido em 23/09: nenhum
    # alias, hook ou timer a chama). Corpo antigo abaixo do return.
    __warn "spicetify_instalar saiu do Spellbook: o Spicetify e o tema do Spotify são do MeowSystem"
    echo -e "  ${D_COMMENT}meow apps aplicar spotify (sem o binário, ele aponta o instalador de lá) · extensões desta máquina: spicetify_reparar${D_RESET}"
    return 0

    local script_dir="${ZDOTDIR:-$HOME/.config/zsh}/scripts/spicetify-setup.sh"

    if [[ ! -f "$script_dir" ]]; then
        __err "Script de setup não encontrado: $script_dir"
        return 1
    fi

    bash "$script_dir"
}

# "Sem musica, a vida seria um erro." -- Friedrich Nietzsche
