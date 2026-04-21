#!/bin/zsh

# Propósito: Escanear todos os repos por violações de anonimato (co-autoria, IA, emojis)
# Uso: auditar_repos [diretório_base]
auditar_repos() {
    local base_dir="${1:-$DEV_DIR}"
    local script_path="$HOME/.config/zsh/scripts/auditoria-repos.sh"

    if [ ! -f "$script_path" ]; then
        __err "Script de auditoria não encontrado em $script_path"
        return 1
    fi

    bash "$script_path" "$base_dir"
}
