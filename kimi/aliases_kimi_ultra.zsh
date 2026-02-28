#!/bin/zsh
# aliases_kimi_ultra.zsh - Kimi CLI Ultra + Dracula Theme
# Pop!_OS 22.04+ | Uso intensivo | Kimi Code CLI
# Cores: https://draculatheme.com

# ============================================================================
# CORES DRACULA
# ============================================================================

# Cores ANSI para terminal
autoload -U colors && colors

RESET="\033[0m"
DRACULA_BG="\033[48;2;40;42;54m"
DRACULA_FG="\033[38;2;248;248;242m"
DRACULA_COMMENT="\033[38;2;98;114;164m"
DRACULA_CYAN="\033[38;2;139;233;253m"
DRACULA_GREEN="\033[38;2;80;250;123m"
DRACULA_ORANGE="\033[38;2;255;184;108m"
DRACULA_PINK="\033[38;2;255;121;198m"
DRACULA_PURPLE="\033[38;2;189;147;249m"
DRACULA_RED="\033[38;2;255;85;85m"
DRACULA_YELLOW="\033[38;2;241;250;140m"

# ============================================================================
# DIRETÓRIOS
# ============================================================================

KIMI_DIR="${ZDOTDIR:-$HOME/.config/zsh}/kimi"

# ============================================================================
# FUNCAO PRINCIPAL: kca (Kimi CLI com YOLO ativado)
# ============================================================================

# kca = kimi com YOLO (sem confirmacao de ferramentas)
kca() {
    if ! command -v kimi &> /dev/null; then
        echo -e "${DRACULA_RED}[ERRO]${RESET} Kimi CLI nao encontrado."
        echo "  Instale com: curl -LsSf https://code.kimi.com/install.sh | bash"
        return 1
    fi

    # Executa kimi com YOLO ativado
    KIMI_YOLO=1 command kimi "$@"
}

# ============================================================================
# ALIASES DE AUTENTICAÇÃO
# ============================================================================

# Iniciar kimi interativo
alias kimi='kca'

# Login (dentro do kimi interativo, digite /login)
alias kimi-login='echo "Execute: kimi  (depois digite /login dentro do kimi)"'

# Setup
alias kimi-setup='kca /setup'

# Logout
alias kimi-logout='kca /logout'

# Status
alias kimi-status='kca /status'

# ============================================================================
# ALIASES DE QUOTA (Kimi Code - não API)
# ============================================================================

kimi-quota() {
    echo -e "${DRACULA_PURPLE}=== KIMI ULTRA STATUS ===${RESET}"
    echo ""
    echo -e "${DRACULA_CYAN}Verifique seu uso em:${RESET}"
    echo "  https://www.kimi.com/code/dashboard"
    echo ""
    echo -e "${DRACULA_COMMENT}Plano recomendado: Ultra (~$49/mês)${RESET}"
    echo -e "${DRACULA_COMMENT}Quota: ~15,000 requests/semana${RESET}"
}

alias kimi-dashboard='xdg-open https://www.kimi.com/code/dashboard 2>/dev/null || open https://www.kimi.com/code/dashboard'
alias kq='kimi-quota'

# ============================================================================
# FUNÇÕES DE PRODUTIVIDADE (Uso Intensivo)
# ============================================================================

# Refatorar arquivo
kimi-refactor() {
    if [ -z "$1" ]; then
        echo -e "${DRACULA_RED}[ERRO]${DRACULA_FG} Uso: kimi-refactor <arquivo> [instruções]"
        return 1
    fi

    local file="$1"
    shift
    local instructions="${*:-melhore este código mantendo a funcionalidade, adicione type hints, logging e error handling adequado}"

    if [ ! -f "$file" ]; then
        echo -e "${DRACULA_RED}[ERRO]${DRACULA_FG} Arquivo não encontrado: $file"
        return 1
    fi

    echo -e "${DRACULA_CYAN}[REFACTOR]${DRACULA_FG} $file"
    kca "refatore o arquivo $file: $instructions. Siga o protocolo KIMI.md - codigo limpo, logging, type hints, zero emojis, PT-BR tecnico."
}

# Documentar arquivo
kimi-doc() {
    if [ -z "$1" ]; then
        echo -e "${DRACULA_RED}[ERRO]${DRACULA_FG} Uso: kimi-doc <arquivo>"
        return 1
    fi

    local file="$1"

    if [ ! -f "$file" ]; then
        echo -e "${DRACULA_RED}[ERRO]${DRACULA_FG} Arquivo não encontrado: $file"
        return 1
    fi

    echo -e "${DRACULA_CYAN}[DOC]${DRACULA_FG} $file"
    kca "documente o arquivo $file adicionando docstrings completas, comentarios explicativos onde necessario, e um header com descricao do modulo. Mantenha o estilo tecnico PT-BR."
}

# Code review
kimi-review() {
    if [ -z "$1" ]; then
        echo -e "${DRACULA_RED}[ERRO]${DRACULA_FG} Uso: kimi-review <arquivo>"
        return 1
    fi

    local file="$1"

    if [ ! -f "$file" ]; then
        echo -e "${DRACULA_RED}[ERRO]${DRACULA_FG} Arquivo não encontrado: $file"
        return 1
    fi

    echo -e "${DRACULA_CYAN}[REVIEW]${DRACULA_FG} $file"
    kca "faca um code review completo do arquivo $file. Identifique: bugs potenciais, code smells, violacoes de clean code, problemas de performance, e sugira melhorias especificas com exemplos de codigo."
}

# Gerar testes
kimi-test() {
    if [ -z "$1" ]; then
        echo -e "${DRACULA_RED}[ERRO]${DRACULA_FG} Uso: kimi-test <arquivo> [framework]"
        return 1
    fi

    local file="$1"
    local framework="${2:-pytest}"

    if [ ! -f "$file" ]; then
        echo -e "${DRACULA_RED}[ERRO]${DRACULA_FG} Arquivo não encontrado: $file"
        return 1
    fi

    echo -e "${DRACULA_CYAN}[TEST]${DRACULA_FG} $file (framework: $framework)"
    kca "ger testes unitarios completos para o arquivo $file usando $framework. Inclua: testes para funcoes principais, casos de borda, mocks quando necessario, e fixtures reutilizaveis. Siga o padrao AAA (Arrange-Act-Assert)."
}

# Explicar código
kimi-explain() {
    if [ -z "$1" ]; then
        echo -e "${DRACULA_RED}[ERRO]${DRACULA_FG} Uso: kimi-explain <arquivo ou conceito>"
        return 1
    fi

    if [ -f "$1" ]; then
        echo -e "${DRACULA_CYAN}[EXPLAIN]${DRACULA_FG} $1"
        kimi-run "explique de forma clara e tecnica o que este codigo faz, seu fluxo de execucao, e quaisquer padroes de design utilizados"
    else
        echo -e "${DRACULA_CYAN}[EXPLAIN]${DRACULA_FG} $1"
        kimi-run "explique de forma tecnica e concisa: $1"
    fi
}

# Otimizar performance
kimi-optimize() {
    if [ -z "$1" ]; then
        echo -e "${DRACULA_RED}[ERRO]${DRACULA_FG} Uso: kimi-optimize <arquivo>"
        return 1
    fi

    local file="$1"

    if [ ! -f "$file" ]; then
        echo -e "${DRACULA_RED}[ERRO]${DRACULA_FG} Arquivo não encontrado: $file"
        return 1
    fi

    echo -e "${DRACULA_CYAN}[OPTIMIZE]${DRACULA_FG} $file"
    kca "analise e otimize o arquivo $file para melhor performance. Identifique gargalos, algoritmos ineficientes, operacoes redundantes, e sugira otimizacoes especificas com benchmarks quando possivel."
}

# Debug assist
kimi-debug() {
    if [ -z "$1" ]; then
        echo -e "${DRACULA_RED}[ERRO]${DRACULA_FG} Uso: kimi-debug <arquivo> [descrição do erro]"
        return 1
    fi

    local file="$1"
    shift
    local error_desc="${*:-encontre e corrija bugs neste código}"

    if [ ! -f "$file" ]; then
        echo -e "${DRACULA_RED}[ERRO]${DRACULA_FG} Arquivo não encontrado: $file"
        return 1
    fi

    echo -e "${DRACULA_CYAN}[DEBUG]${DRACULA_FG} $file"
    kca "debug o arquivo $file: $error_desc. Identifique a causa raiz, explique o problema, e forneca a correcao completa. Adicione logging apropriado para facilitar debug futuro."
}

# ============================================================================
# FUNÇÕES DE PROJETO
# ============================================================================

# Inicializar projeto com KIMI.md
kimi-init-project() {
    if [ ! -f "KIMI.md" ]; then
        if [ -f "$KIMI_DIR/KIMI_ULTRA.md" ]; then
            ln -sf "$KIMI_DIR/KIMI_ULTRA.md" KIMI.md
            echo -e "${DRACULA_GREEN}[OK]${DRACULA_FG} KIMI.md vinculado"
        else
            echo -e "${DRACULA_ORANGE}[!]${DRACULA_FG} KIMI_ULTRA.md não encontrado em $KIMI_DIR"
        fi
    else
        echo -e "${DRACULA_COMMENT}[INFO]${DRACULA_FG} KIMI.md já existe"
    fi
}

# Verificar anonimato no projeto
kimi-check-anon() {
    local dir="${1:-.}"
    echo -e "${DRACULA_PURPLE}=== VERIFICAÇÃO DE ANONIMATO ===${RESET}"
    echo -e "${DRACULA_COMMENT}Diretório: $dir${RESET}"
    echo ""

    local patterns="kimi|moonshot|claude|anthropic|openai|gpt-[0-9]|gemini|copilot"
    local results=$(grep -rniE "$patterns" "$dir" --exclude-dir={node_modules,venv,target,.git,__pycache__,.kimi,.tox,dist,build} --include="*.{py,js,ts,md,txt,rs,go,java,jsx,tsx}" 2>/dev/null | grep -viE "api_key|provider|model|config|client|engine|KIMI_API_KEY|kimi-|\.kimi|/login|/grant" || true)

    if [ -z "$results" ]; then
        echo -e "${DRACULA_GREEN}[OK]${DRACULA_FG} Nenhuma menção a IAs encontrada"
        return 0
    else
        echo -e "${DRACULA_ORANGE}[AVISO]${DRACULA_FG} Possíveis menções encontradas:"
        echo "$results"
        return 1
    fi
}

# ============================================================================
# ALIASES LEGACY (compatibilidade com Claude)
# ============================================================================

# NOTA: cca é do Claude - nao sobrescrever
# O Claude é carregado antes em .zshrc: source "$ZDOTDIR/claude/aliases_claude.zsh"
# alias cca='kca'  # REMOVIDO - cca deve executar o Claude, nao o Kimi

alias claude-safe='kca'
alias claude-quota='kimi-quota'
alias claude-login='kimi-login'
alias cq='kimi-quota'

# ============================================================================
# FUNÇÕES DE ATALHO RÁPIDO
# ============================================================================

# Pergunta rápida
kimi-ask() {
    kca "$@"
}

# Ver configuração
kimi-config() {
    echo -e "${DRACULA_PURPLE}=== KIMI ULTRA CONFIG ===${RESET}"
    echo ""
    echo -e "${DRACULA_CYAN}CLI:${RESET} $(kimi --version 2>/dev/null || echo 'não instalado')"
    echo -e "${DRACULA_CYAN}Diretório:${RESET} $KIMI_DIR"
    echo -e "${DRACULA_CYAN}Config:${RESET} ~/.kimi/config.toml"
    echo ""
    echo -e "${DRACULA_COMMENT}Tema: Dracula${RESET}"
    echo -e "${DRACULA_COMMENT}Plano recomendado: Ultra (~$49/mês)${RESET}"
    echo ""
    echo -e "${DRACULA_CYAN}Comandos disponíveis:${RESET}"
    echo "  /login     - Login via navegador"
    echo "  /setup     - Configurar provider"
    echo "  /logout    - Deslogar"
    echo "  /status    - Status da sessão"
    echo "  /init      - Gerar AGENTS.md"
    echo "  /help      - Ajuda"
}

# ============================================================================
# BOAS-VINDAS (desativado - remova o comentario abaixo para ativar)
# ============================================================================

# echo ""
# echo -e "${DRACULA_PURPLE}=== Kimi Ultra | Dracula Theme ===${RESET}"
# echo -e "${DRACULA_COMMENT}Comandos: kca, kimi-setup, kimi-refactor${RESET}"
# echo ""
