# --- 0. CONFIGURAÇÃO LOCAL DA MÁQUINA ---
# Variáveis específicas por máquina (gitignored). Gerado pelo install.sh.
[[ -f "${ZDOTDIR:-$HOME/.config/zsh}/config.local.zsh" ]] && source "${ZDOTDIR:-$HOME/.config/zsh}/config.local.zsh"

# --- 1. TEMA E OH MY ZSH ---
ZSH_THEME="agnoster"
export ZSH_COMPDUMP="$ZDOTDIR/.zcompdump"
export PATH="$HOME/.spicetify:$HOME/.cargo/bin:$HOME/.local/bin:/snap/bin:$PATH"

export ZSH="$HOME/.config/zsh/.oh-my-zsh"
export ZSH_COMPDUMP="$HOME/.config/zsh/.zcompdump"

plugins=(git zsh-autosuggestions zsh-history-substring-search fzf zsh-syntax-highlighting)

if [ -f "$ZSH/oh-my-zsh.sh" ]; then
  source "$ZSH/oh-my-zsh.sh"
fi

# --- 2. HISTORICO DE COMANDOS ---
HISTFILE="$ZDOTDIR/.zsh_history"
HISTSIZE=10000
SAVEHIST=10000
setopt APPEND_HISTORY INC_APPEND_HISTORY SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE

# --- 3. INICIALIZACOES DE FERRAMENTAS ---

# NVM (Lazy Loading -- carrega sob demanda na primeira chamada)
export NVM_DIR="$HOME/.nvm"

__load_nvm() {
    unset -f nvm node npm npx 2>/dev/null
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
}

nvm() { __load_nvm; nvm "$@"; }
node() { __load_nvm; node "$@"; }
npm() { __load_nvm; npm "$@"; }
npx() { __load_nvm; npx "$@"; }

# Outras variaveis
export PKG_CONFIG_PATH=/usr/lib/x86_64-linux-gnu/pkgconfig:$PKG_CONFIG_PATH
export DBT_PROFILES_DIR=dev

# --- 4. RITUAL DE INICIALIZAÇÃO INTERATIVO ---
# Executado apenas em sessões interativas.
if [[ -o interactive && -z "$TMUX" ]]; then
    if command -v fastfetch >/dev/null 2>&1; then clear; fastfetch; fi
fi

# --- 5. PROMPT COM CORES DE FUNDO ---
# Prompt: usuario@hostname com fundo colorido
autoload -U colors && colors

# Fundo azul para usuario@hostname, fundo escuro para diretorio
export PS1='%{$bg[blue]%}%{$fg[white]%} %n@%m %{$reset_color%}%{$bg[black]%}%{$fg[cyan]%} %~ %{$reset_color%} '

# --- 6. SEGREDOS E AJUSTES FINAIS ---
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
export FZF_OMZ_DEFAULT_COMPLETION=1

if [ -f "$HOME/.env" ]; then
    source "$HOME/.env"
fi

# --- 6. SSH AGENT AUTO-START ---
if [ -z "$SSH_AUTH_SOCK" ]; then
    eval "$(ssh-agent -s)" > /dev/null 2>&1
    ssh-add ~/.ssh/id_ed25519 2>/dev/null
    ssh-add ~/.ssh/id_ed25519_vit 2>/dev/null
fi

# --- 7. GITHUB CLI ---
if command -v gh &>/dev/null; then
    # Aliases
    alias ghi="gh issue"
    alias ghil="gh issue list"
    alias ghic="gh issue create"
    alias ghiv="gh issue view"
    alias ghp="gh pr"
    alias ghpl="gh pr list"
    alias ghpc="gh pr create"
    alias ghpv="gh pr view"
    alias ghpm="gh pr merge"
    alias ghr="gh repo"
    alias ghrl="gh repo list"
    alias ghrv="gh repo view --web"
    alias ghs="gh auth status"

    # Completions
    eval "$(gh completion -s zsh)"
fi




