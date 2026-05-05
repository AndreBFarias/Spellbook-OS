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
# Pyenv
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

# --- 6. BASH COMPLETION ---
autoload -U bashcompinit && bashcompinit

# --- STATUS MONITOR (GPU) ---
() {
    # 1. NVIDIA — em laptops Optimus/on-demand, nvidia-smi pode retornar
    #    [N/A] ou texto descritivo quando dGPU esta suspensa; valida numeros
    #    antes de avaliar expressao aritmetica para nao quebrar o prompt.
    command -v nvidia-smi >/dev/null 2>&1 || return 0
    local info mem_data used total percent color
    info=$(nvidia-smi --query-gpu=name,temperature.gpu --format=csv,noheader 2>/dev/null) || return 0
    mem_data=$(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null) || return 0
    used=${${(s:,:)mem_data}[1]// /}
    total=${${(s:,:)mem_data}[2]// /}
    [[ "$used" =~ ^[0-9]+$ && "$total" =~ ^[0-9]+$ && $total -gt 0 ]] || return 0
    percent=$(( (used * 100) / total ))
    color=$'\033[0;32m'
    if (( percent >= 80 )); then color=$'\033[0;31m'; elif (( percent >= 50 )); then color=$'\033[1;33m'; fi
    print
    print -P "GPU: ${info} | VRAM: ${color}${used}/${total} MiB (${percent}%)\033[0m"
}

# --- 4.6. WRAPPER AUXILIAR ---
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
