#!/bin/zsh
# Prompt hint: exibe a assinatura (# Uso: ...) da função atual na RPROMPT
# enquanto o usuário digita a linha de comando.
#
# Toggle:
#   PROMPT_HINT_ENABLED=1 (default) / 0 desabilita
#   PROMPT_HINT_MIN_ROOM=60 — se COLUMNS - len(linha) < esse valor, esconde o hint

__prompt_hint_cache_build() {
    # Varre functions/*.zsh e extrai pares <nome>=<uso> para uma hash.
    typeset -gA __PROMPT_HINT_MAP=()
    local func_dir="${ZDOTDIR:-$HOME/.config/zsh}/functions"
    [[ -d "$func_dir" ]] || return 0

    local arquivo current_uso name
    for arquivo in "$func_dir"/*.zsh "$func_dir"/../aliases.zsh "$func_dir"/../cca/aliases_cca.zsh; do
        [[ -f "$arquivo" ]] || continue
        current_uso=""
        while IFS= read -r linha; do
            case "$linha" in
                (\#\ Uso:*|\#\ USO:*)
                    current_uso="${linha#\# [Uu]so:}"
                    current_uso="${current_uso# }"
                    ;;
                ([a-zA-Z_][a-zA-Z0-9_]*\(\)*)
                    name="${linha%%(*}"
                    name="${name## }"
                    if [[ -n "$current_uso" && -n "$name" ]]; then
                        __PROMPT_HINT_MAP[$name]="$current_uso"
                    fi
                    current_uso=""
                    ;;
                (alias\ *)
                    # alias nome='cmd' — sem uso, pula
                    current_uso=""
                    ;;
                ('')
                    current_uso=""
                    ;;
            esac
        done < "$arquivo"
    done
}

__prompt_hint_update() {
    [[ "${PROMPT_HINT_ENABLED:-1}" == "0" ]] && { RPROMPT=""; return; }

    local buf="$BUFFER"
    # Pega primeiro token (comando)
    local cmd="${buf%% *}"
    [[ -z "$cmd" ]] && { RPROMPT=""; return; }

    local uso="${__PROMPT_HINT_MAP[$cmd]:-}"
    [[ -z "$uso" ]] && { RPROMPT=""; return; }

    # Calcula espaço disponível: COLUMNS - len(PROMPT já expandido) - len(buffer)
    local min_room=${PROMPT_HINT_MIN_ROOM:-50}
    local room=$(( COLUMNS - ${#buf} - 20 ))
    (( room < min_room )) && { RPROMPT=""; return; }

    # Mostra apenas a parte de argumentos (remove o próprio nome da função)
    local hint="${uso#$cmd}"
    hint="${hint# }"
    [[ -z "$hint" ]] && { RPROMPT=""; return; }

    # Truncar se ainda passar do espaço
    if (( ${#hint} > room - 4 )); then
        hint="${hint[1,$(( room - 4 ))]}..."
    fi

    RPROMPT="%F{#6272a4}${hint}%f"
}

# Widget que roda a cada redraw da linha (zsh >= 5.8)
__prompt_hint_widget() {
    __prompt_hint_update
}

# Inicialização
if [[ -n "$ZSH_VERSION" ]]; then
    __prompt_hint_cache_build
    autoload -Uz add-zle-hook-widget 2>/dev/null

    zle -N __prompt_hint_widget
    if (( $+functions[add-zle-hook-widget] )); then
        add-zle-hook-widget zle-line-pre-redraw __prompt_hint_widget 2>/dev/null
    fi

    # Hook: regenera cache quando recompilar_completions rodar
    __prompt_hint_refresh() { __prompt_hint_cache_build; }
fi

# Propósito: Recarrega cache de hints da RPROMPT (útil após editar uma função)
# Uso: prompt_hint_refresh
prompt_hint_refresh() {
    __prompt_hint_cache_build
    __ok "Cache de hints recarregado (${#__PROMPT_HINT_MAP[@]} entradas)"
}
