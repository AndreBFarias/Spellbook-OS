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
# Carrega chaves de API e tokens (GitHub, Gemini, etc)
[ -f "$ZDOTDIR/.zsh_secrets" ] && source "$ZDOTDIR/.zsh_secrets"

# --- 4. ARSENAL (ALIASES E FUNÇÕES) ---
[ -f "$ZDOTDIR/aliases.zsh" ] && source "$ZDOTDIR/aliases.zsh"
[ -f "$ZDOTDIR/functions.zsh" ] && source "$ZDOTDIR/functions.zsh"

# --- 4.5. AI TOOLS (CCA) ---
[ -f "${ZDOTDIR:-$HOME/.config/zsh}/cca/aliases_cca.zsh" ] && source "${ZDOTDIR:-$HOME/.config/zsh}/cca/aliases_cca.zsh"

# --- 5. FERRAMENTAS ESPECÍFICAS ---
# Pyenv
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

# --- 6. BASH COMPLETION ---
autoload -U bashcompinit && bashcompinit

# --- STATUS MONITOR (GPU) ---
() {
    # 1. NVIDIA
    if command -v nvidia-smi &> /dev/null; then
        local info=$(nvidia-smi --query-gpu=name,temperature.gpu --format=csv,noheader)
        local mem_data=$(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits)
        local used=$(echo $mem_data | cut -d',' -f1 | xargs)
        local total=$(echo $mem_data | cut -d',' -f2 | xargs)
        local percent=$(( (used * 100) / total ))
        local color="\033[0;32m"
        if [ $percent -ge 80 ]; then color="\033[0;31m"; elif [ $percent -ge 50 ]; then color="\033[1;33m"; fi
        echo ""
        echo -e "GPU: ${info} | VRAM: ${color}${used}/${total} MiB (${percent}%)\033[0m"
    fi
}

# ==========================================
# Kimi CLI Ultra - Dracula Theme
# ==========================================

# YOLO mode: executa ferramentas sem confirmacao
export KIMI_YOLO=1

[ -f "$ZDOTDIR/kca/aliases_kca.zsh" ] && source "$ZDOTDIR/kca/aliases_kca.zsh"

# --- 7. SPELLBOOK SYNC (ao abrir terminal) ---
if [[ -o interactive && -z "${SPELLBOOK_SYNC_DONE:-}" ]]; then
    export SPELLBOOK_SYNC_DONE=1
    spellbook_sync_pull
fi

# --- 99. SPELLBOOK SYNC (ao fechar terminal) ---
zshexit() {
    spellbook_sync_push 2>/dev/null
}
