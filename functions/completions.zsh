#!/bin/zsh

# Propósito: Regera arquivos _<função> em completions/ a partir dos metadados
# Uso: recompilar_completions [--verbose] [--func NOME]
# Flags: --verbose=Mostra progresso detalhado
#        --func=Regera apenas uma função específica
recompilar_completions() {
    local script="${ZDOTDIR:-$HOME/.config/zsh}/scripts/gerar-completions.py"
    if [[ ! -f "$script" ]]; then
        __err "Script não encontrado: $script"
        return 1
    fi
    python3 "$script" "$@" || return $?
    # Recarrega compinit para capturar novos arquivos
    rm -f "${ZSH_COMPDUMP:-$HOME/.zcompdump}"
    autoload -U compinit && compinit -u
    __ok "Completions recompiladas. Pressione Tab para testar."
}

# Propósito: Lista funções sem metadados de completion (# Propósito + # Uso)
# Uso: validar_completions
validar_completions() {
    local script="${ZDOTDIR:-$HOME/.config/zsh}/scripts/gerar-completions.py"
    if [[ ! -f "$script" ]]; then
        __err "Script não encontrado: $script"
        return 1
    fi
    __header "VALIDAR COMPLETIONS" "$D_PURPLE"
    python3 "$script" --dry-run --verbose 2>&1 | grep -E "(Sem metadados|Total:)"
}
