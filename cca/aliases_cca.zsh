# Aliases para controle de uso do Claude

# Propósito: Exportar variáveis de ambiente consumidas pelo hook session-start-briefing.py
# Uso: __cca_export_contexto (interno, não chamar direto)
__cca_export_contexto() {
    local _root
    _root=$(git rev-parse --show-toplevel 2>/dev/null)
    if [ -n "$_root" ]; then
        export CLAUDE_PROJECT_ROOT="$_root"
        export CLAUDE_PROJECT_NAME="$(basename "$_root")"
        export CLAUDE_BRIEF_PATH="$_root/VALIDATOR_BRIEF.md"
        if [ -f "$CLAUDE_BRIEF_PATH" ]; then
            export CLAUDE_BRIEF_STATUS="exists"
        else
            export CLAUDE_BRIEF_STATUS="missing"
        fi
        local _proj_lower
        _proj_lower=$(basename "$_root" | tr '[:upper:]' '[:lower:]')
        case "$_proj_lower" in
            luna)                export CLAUDE_PROJECT_KIND="luna" ;;
            nyx-code)            export CLAUDE_PROJECT_KIND="nyx-code" ;;
            protocolo-ouroboros) export CLAUDE_PROJECT_KIND="protocolo-ouroboros" ;;
            *)                   export CLAUDE_PROJECT_KIND="generic" ;;
        esac
        export CLAUDE_SANTUARIO_READY=1
    fi
    export CLAUDE_VISUAL_TOOLS_EXPECTED=1
    export CLAUDE_SPRINT_CICLO_MAX_RETRIES="${CLAUDE_SPRINT_CICLO_MAX_RETRIES:-3}"
}

__cca_unset_contexto() {
    unset CLAUDE_PROJECT_ROOT CLAUDE_PROJECT_NAME CLAUDE_BRIEF_PATH \
          CLAUDE_BRIEF_STATUS CLAUDE_PROJECT_KIND CLAUDE_SANTUARIO_READY \
          CLAUDE_VISUAL_TOOLS_EXPECTED CLAUDE_SPRINT_CICLO_MAX_RETRIES
}

# Proposito: Wrapper seguro para Claude Code com quota guard
# Uso: claude <args>
claude-safe() {
    bash "$HOME/.config/zsh/cca/cca_guard.sh" before || return 1
    __cca_export_contexto

    local start_time=$(date +%s)
    command claude "$@"
    local exit_code=$?
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    __cca_unset_contexto
    local estimated_tokens=$((duration * 100))
    bash "$HOME/.config/zsh/cca/cca_guard.sh" after "$estimated_tokens"

    return $exit_code
}

# Proposito: Verificar quota de uso do Claude Code
# Uso: claude-quota
claude-quota() {
    bash "$HOME/.config/zsh/cca/cca_quota_manager.sh" check
}

# Resetar quota (início de nova semana)
claude-quota-reset() {
    echo "[!] Tem certeza que quer resetar a quota? (y/n)"
    read -r response
    if [ "$response" = "y" ]; then
        bash "$HOME/.config/zsh/cca/cca_quota_manager.sh" reset
    fi
}

# Proposito: Estimar custo em tokens de um arquivo antes de enviar
# Uso: claude-estimate <arquivo>
claude-estimate() {
    if [ -z "$1" ]; then
        echo "Uso: claude-estimate <arquivo>"
        return 1
    fi

    bash "$HOME/.config/zsh/cca/cca_guard.sh" check-file "$1"
}

# Proposito: Preview rapido de arquivo (head/tail) sem consumir quota
# Uso: claude-peek <arquivo>
claude-peek() {
    if [ -z "$1" ]; then
        echo "Uso: claude-peek <arquivo>"
        return 1
    fi

    local file="$1"
    local lines=$(wc -l < "$file")
    local size=$(du -h "$file" | cut -f1)

    echo "=== PREVIEW: $file ==="
    echo "Tamanho: $size | Linhas: $lines"
    echo ""
    echo "--- INÍCIO (50 linhas) ---"
    head -n 50 "$file"
    echo ""
    echo "--- FIM (50 linhas) ---"
    tail -n 50 "$file"
    echo ""
    echo "[DICA] Use grep, sed ou awk para análises específicas sem consumir quota"
}

# Forçar comando ignorando limites (use com cuidado)
claude-force() {
    echo "[!] FORCANDO comando sem verificacoes!"
    CLAUDE_FORCE=1 command claude "$@"
}

# Proposito: Relatorio semanal de uso e dicas para economizar quota
# Uso: claude-report
claude-report() {
    echo "=== RELATÓRIO SEMANAL DE USO ==="
    bash "$HOME/.config/zsh/cca/cca_quota_manager.sh" check
    echo ""
    echo "=== DICAS PARA ECONOMIZAR ==="
    echo "1. Use grep/sed/awk para buscas rápidas"
    echo "2. Leia arquivos em seções (head/tail)"
    echo "3. Use --skip-context quando não precisar de histórico"
    echo "4. Resuma contextos grandes antes de perguntar"
    echo "5. Evite ler arquivos > 100KB diretamente"
}

# Inicializar sistema de quota
claude-init() {
    bash "$HOME/.config/zsh/cca/cca_quota_manager.sh" init
    bash "$HOME/.config/zsh/cca/cca_guard.sh" init

    echo "[OK] Sistema de quota inicializado"
    echo "[OK] Guard configurado"
    echo ""
    echo "Comandos disponíveis:"
    echo "  claude-safe        - Wrapper seguro (recomendado)"
    echo "  claude-quota       - Ver uso atual"
    echo "  claude-estimate    - Estimar custo de arquivo"
    echo "  claude-peek        - Preview sem consumir quota"
    echo "  claude-report      - Relatório semanal"
    echo "  claude-force       - Forçar (não recomendado)"
}

# Aurora 2.0 - helper interno: executa Claude com slice + token tracking real
# Não chamar direto. Use 'cca'.
__cca_run() {
    bash "$HOME/.config/zsh/cca/cca_guard.sh" before || return 1
    __cca_export_contexto

    # Token tracking REAL: tamanho do dir de transcripts antes/depois
    local enc_dir="$HOME/.claude/projects/$(printf '%s' "$PWD" | sed 's|/|-|g')"
    local pre_size=0 post_size=0
    [ -d "$enc_dir" ] && pre_size=$(du -bs "$enc_dir" 2>/dev/null | awk '{print $1}')

    local exit_code
    # Se claude.slice esta instalado no user systemd, rodar dentro dele (limites de memoria)
    if systemctl --user list-unit-files 2>/dev/null | grep -q '^claude.slice'; then
        systemd-run --user --slice=claude.slice --scope --quiet --collect \
            command claude --dangerously-skip-permissions "$@"
        exit_code=$?
    else
        command claude --dangerously-skip-permissions "$@"
        exit_code=$?
    fi

    [ -d "$enc_dir" ] && post_size=$(du -bs "$enc_dir" 2>/dev/null | awk '{print $1}')
    local delta=$(( post_size - pre_size ))
    [ $delta -lt 0 ] && delta=0
    local estimated_tokens=$(( delta / 4 ))   # ~4 bytes por token (heuristica realista)

    __cca_unset_contexto
    bash "$HOME/.config/zsh/cca/cca_guard.sh" after "$estimated_tokens"

    return $exit_code
}

# Propósito: Claude Code com permissões completas + auto-tmux + memory slice
# Uso: cca [args]
cca() {
    if ! command -v claude &> /dev/null; then
        echo "[ERRO] Claude Code não instalado. Rode: npm install -g @anthropic-ai/claude-code"
        return 1
    fi

    # Se ja em tmux, rodar direto (sem nesting)
    if [ -n "${TMUX:-}" ]; then
        __cca_run "$@"
        return $?
    fi

    # Sem tmux instalado? Fallback para execução direta (com warning)
    if ! command -v tmux &> /dev/null; then
        echo "[cca][WARN] tmux não instalado - rodando sem proteção contra freeze do DE"
        __cca_run "$@"
        return $?
    fi

    # Nome de sessão deterministico por cwd
    local sha proj sess
    sha=$(printf '%s' "$PWD" | sha1sum | awk '{print substr($1,1,6)}')
    proj=$(basename "$PWD")
    sess="claude-${proj}-${sha}"

    if tmux has-session -t "$sess" 2>/dev/null; then
        echo "[cca] Sessão tmux '$sess' ja existe. Anexando (Ctrl-b d para detach)..."
        exec tmux attach -t "$sess"
    fi

    echo "[cca] Criando sessão tmux: $sess (Ctrl-b d para detach, sobrevive freeze do DE)"
    if [ $# -eq 0 ]; then
        exec tmux new -s "$sess" -c "$PWD" "zsh -ic '__cca_run'"
    else
        local args_str="$*"
        exec tmux new -s "$sess" -c "$PWD" "zsh -ic '__cca_run ${args_str}'"
    fi
}

# Propósito: Listar sessões tmux do Claude ativas
# Uso: cca-list
cca-list() {
    if ! command -v tmux &> /dev/null; then
        echo "tmux não instalado"
        return 1
    fi
    echo "=== Sessões Claude ativas (tmux) ==="
    tmux ls 2>/dev/null | grep -E '^claude-' || echo "(nenhuma)"
}

# Propósito: Retomar última sessão Claude no cwd atual
# Uso: cca-resume [args]
cca-resume() {
    if [ -n "${TMUX:-}" ]; then
        bash "$HOME/.config/zsh/cca/cca_guard.sh" before || return 1
        __cca_export_contexto
        if systemctl --user list-unit-files 2>/dev/null | grep -q '^claude.slice'; then
            systemd-run --user --slice=claude.slice --scope --quiet --collect \
                command claude --continue --dangerously-skip-permissions "$@"
        else
            command claude --continue --dangerously-skip-permissions "$@"
        fi
        local rc=$?
        __cca_unset_contexto
        return $rc
    fi
    # Embrulha em tmux como o cca normal
    local sha proj sess
    sha=$(printf '%s' "$PWD" | sha1sum | awk '{print substr($1,1,6)}')
    proj=$(basename "$PWD")
    sess="claude-${proj}-${sha}"
    if tmux has-session -t "$sess" 2>/dev/null; then
        exec tmux attach -t "$sess"
    fi
    exec tmux new -s "$sess" -c "$PWD" "zsh -ic 'cca-resume $*'"
}

# Proposito: Claude Code com wrapper seguro
# Uso: claude <args>
# NOTA: Alias removido - usar 'claude-safe' diretamente ou 'cca'
# Proposito: Verificar quota do Claude
# Uso: cq
alias cq='claude-quota'
# Proposito: Estimar custo de arquivo em tokens
# Uso: ce <arquivo>
alias ce='claude-estimate'
# Proposito: Preview de arquivo sem consumir quota
# Uso: cp-file <arquivo>
alias cp-file='claude-peek'
# Proposito: Relatorio de uso semanal do Claude
# Uso: cr
alias cr='claude-report'
