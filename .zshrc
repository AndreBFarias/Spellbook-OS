# --- 1. CONFIGURAÇÕES DE ATUALIZAÇÃO (Deve vir antes do source OMZ) ---
# Define o modo automático sem perguntas
zstyle ':omz:update' mode auto
# Frequência de atualização (em dias)
zstyle ':omz:update' frequency 7

# --- 2. AMBIENTE E FRAMEWORK ---
# Define o caminho do Oh My Zsh explicitamente
export ZSH="$HOME/.config/zsh/.oh-my-zsh"

# Carrega as variáveis de ambiente e o framework (seu env.zsh atual)
if [ -f "$ZDOTDIR/env.zsh" ]; then
    source "$ZDOTDIR/env.zsh"
fi

# --- 3. SEGREDOS E ACESSOS ---
# Carrega chaves de API e tokens de providers externos
[ -f "$ZDOTDIR/.zsh_secrets" ] && source "$ZDOTDIR/.zsh_secrets"

# --- 4. ARSENAL (ALIASES E FUNÇÕES) ---
[ -f "$ZDOTDIR/aliases.zsh" ] && source "$ZDOTDIR/aliases.zsh"
[ -f "$ZDOTDIR/functions.zsh" ] && source "$ZDOTDIR/functions.zsh"

# --- 4.5. WRAPPERS ---
[ -f "${ZDOTDIR:-$HOME/.config/zsh}/cca/aliases_cca.zsh" ] && source "${ZDOTDIR:-$HOME/.config/zsh}/cca/aliases_cca.zsh"
[ -f "${ZDOTDIR:-$HOME/.config/zsh}/cca/aliases_sprint.zsh" ] && source "${ZDOTDIR:-$HOME/.config/zsh}/cca/aliases_sprint.zsh"

# --- 5. FERRAMENTAS ESPECÍFICAS ---
# Pyenv (lazy-load: só inicializa na 1ª invocação)
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && __add_to_path_once "$PYENV_ROOT/bin"
__load_pyenv() {
    unset -f pyenv python python3 2>/dev/null
    eval "$(command pyenv init -)"
}
pyenv()   { __load_pyenv; pyenv "$@"; }
python()  { __load_pyenv; python "$@"; }
python3() { __load_pyenv; python3 "$@"; }

# --- 6. BASH COMPLETION ---
autoload -U bashcompinit && bashcompinit

# --- 7. SPELLBOOK SYNC (background, status cacheado p/ fastfetch) ---
if [[ -o interactive && -z "${SPELLBOOK_SYNC_DONE:-}" ]]; then
    export SPELLBOOK_SYNC_DONE=1
    typeset -f spellbook_sync_pull > /dev/null && ( spellbook_sync_pull >/dev/null 2>&1 ) &!
fi

# --- 7.1. SYNC CLAUDE.md SYMLINKS (silencioso, ao abrir terminal) ---
if [[ -o interactive && -z "${CLAUDE_SYMLINKS_SYNCED:-}" ]]; then
    export CLAUDE_SYMLINKS_SYNCED=1
    typeset -f sync_claude_symlinks > /dev/null && sync_claude_symlinks --quiet 2>/dev/null &!
fi

# --- 7.2. AURORA SELF-HEAL (detecta drift das configs persistentes, cache 1h) ---
if [[ -o interactive && -z "${AURORA_SELF_HEAL_DONE:-}" ]]; then
    export AURORA_SELF_HEAL_DONE=1
    typeset -f aurora-self-heal-cached > /dev/null && aurora-self-heal-cached
fi

# --- 99. SPELLBOOK SYNC (ao fechar terminal) ---
zshexit() {
    fc -A 2>/dev/null  # flush history pendente do shell pro $HISTFILE antes do push
    spellbook_sync_push 2>/dev/null
}
