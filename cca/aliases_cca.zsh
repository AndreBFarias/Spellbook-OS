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

# Proposito: Garante que GIT_TOKEN_* estejam na sessão antes de invocar claude.
# Re-source do shim .zsh_secrets é idempotente: usa passphrase-file se houver
# (~/.local/state/zsh-vault-passphrase), gpg-agent cache, ou pinentry como último recurso.
__cca_unlock_secrets() {
    [ -f "$HOME/.config/zsh/vault/secrets.gpg" ] || return 0
    [ -n "${GIT_TOKEN_PESSOAL:-}" ] && return 0  # já populado nesta sessão
    source "$HOME/.config/zsh/.zsh_secrets"
}

# ---------------------------------------------------------------------------
# Preflight de sessão (SPR-2026-07-03-cca-preflight)
# Resolve ANTES de abrir a sessão: login principal, design login, design
# consent (headless via print mode — em bypass o prompt de consent nunca
# aparece) e frescor de plugins (marketplace + update dos desatualizados).
# Checks locais toda sessão (~0.3s); rede em cadência de 1 dia, retry
# automático em falha (timestamp só grava em sucesso).
# Escape: CCA_NO_PREFLIGHT=1. Doctor: cca-preflight (ignora cadência).
# ---------------------------------------------------------------------------

# Propósito: lê uma chave do estado do preflight (formato chave=valor).
__cca_pf_get() {
    local f="${ZDOTDIR:-$HOME/.config/zsh}/cca/.cca_preflight_state"
    [ -f "$f" ] || return 1
    grep -m1 "^${1}=" "$f" 2>/dev/null | cut -d= -f2-
}

# Propósito: grava/substitui uma chave no estado (leitura via grep, nunca source).
__cca_pf_set() {
    local f="${ZDOTDIR:-$HOME/.config/zsh}/cca/.cca_preflight_state"
    local resto=""
    [ -f "$f" ] && resto=$(grep -v "^${1}=" "$f" 2>/dev/null)
    { [ -n "$resto" ] && printf '%s\n' "$resto"; printf '%s=%s\n' "$1" "$2"; } > "$f"
}

# Propósito: preflight de sessão. Interno (__cca_run/cca-resume/claude-safe)
# ou manual via cca-preflight. Com --force ignora cadência.
__cca_preflight() {
    [ -n "${CCA_NO_PREFLIGHT:-}" ] && return 0
    command -v jq >/dev/null 2>&1 || return 0  # sem jq, falha-soft: sessão abre sem preflight

    local force=""
    [ "$1" = "--force" ] && force=1
    local ttl=86400 now creds="$HOME/.claude/.credentials.json"
    now=$(date +%s)
    local seg_login seg_design seg_consent seg_plugins

    # 1. Login principal (local, ~0.3s)
    if timeout 10 command claude auth status --json 2>/dev/null | jq -e '.loggedIn' >/dev/null 2>&1; then
        seg_login="login ${D_GREEN}OK${D_RESET}"
    elif [ -t 0 ]; then
        echo -e "${D_PURPLE}[cca]${D_RESET} deslogado — abrindo login antes da sessão..."
        command claude auth login
        if timeout 10 command claude auth status --json 2>/dev/null | jq -e '.loggedIn' >/dev/null 2>&1; then
            seg_login="login ${D_GREEN}OK${D_RESET}"
        else
            __err "login falhou ou foi abortado — sessão não aberta"
            return 1
        fi
    else
        __warn "deslogado e sem TTY — a sessão vai pedir /login"
        seg_login="login ${D_YELLOW}FALTA${D_RESET}"
    fi

    # 2. Design login (local, instantâneo)
    local client_id
    client_id=$(jq -r '.designOauth.clientId // empty' "$creds" 2>/dev/null)
    if [ -n "$client_id" ]; then
        seg_design="design ${D_GREEN}OK${D_RESET}"
    else
        __warn "design deslogado — rode /design-login dentro da sessão"
        seg_design="design ${D_YELLOW}FALTA${D_RESET}"
    fi

    # 3. Consent do design (1x/dia, ou na hora se o clientId mudou = relogin)
    if [ -n "$client_id" ]; then
        local last_ok saved_id
        last_ok=$(__cca_pf_get last_consent_ok); : "${last_ok:=0}"
        saved_id=$(__cca_pf_get consent_client_id)
        if [ -z "$force" ] && [ "$saved_id" = "$client_id" ] && [ $(( now - last_ok )) -lt $ttl ]; then
            seg_consent="consent ${D_GREEN}OK${D_RESET} ${D_COMMENT}(cache)${D_RESET}"
        elif timeout 30 command claude -p --bare "/design consent" >/dev/null 2>&1; then
            __cca_pf_set last_consent_ok "$now"
            __cca_pf_set consent_client_id "$client_id"
            seg_consent="consent ${D_GREEN}OK${D_RESET}"
        else
            __warn "design consent falhou (rede?) — nova tentativa na próxima sessão"
            seg_consent="consent ${D_YELLOW}FALHOU${D_RESET}"
        fi
    else
        seg_consent="consent ${D_COMMENT}pulado${D_RESET}"
    fi

    # 4. Plugins (1x/dia: marketplace update + update só dos desatualizados)
    local last_sync
    last_sync=$(__cca_pf_get last_plugin_sync); : "${last_sync:=0}"
    if [ -z "$force" ] && [ $(( now - last_sync )) -lt $ttl ]; then
        seg_plugins="plugins ${D_GREEN}OK${D_RESET} ${D_COMMENT}(cache)${D_RESET}"
    elif timeout 60 command claude plugin marketplace update >/dev/null 2>&1; then
        local desatualizados pid old new falha=""
        desatualizados=$(command claude plugin list --json --available 2>/dev/null | jq -r '
            (.available | map({key: .pluginId, value: .version}) | from_entries) as $av
            | .installed[]
            | select(.version != null and .version != "unknown")
            | select(($av[.id] // "unknown") != "unknown" and $av[.id] != .version)
            | "\(.id) \(.version) \($av[.id])"' 2>/dev/null)
        while IFS=' ' read -r pid old new; do
            [ -z "$pid" ] && continue
            if timeout 60 command claude plugin update "$pid" >/dev/null 2>&1; then
                echo -e "${D_PURPLE}[cca]${D_RESET} plugin ${pid%%@*} ${old} -> ${D_GREEN}${new}${D_RESET}"
            else
                falha=1
                __warn "update de ${pid%%@*} falhou"
            fi
        done <<< "$desatualizados"
        if [ -z "$falha" ]; then
            __cca_pf_set last_plugin_sync "$now"
            seg_plugins="plugins ${D_GREEN}OK${D_RESET}"
        else
            seg_plugins="plugins ${D_YELLOW}PARCIAL${D_RESET}"
        fi
    else
        __warn "marketplace update falhou (rede?) — nova tentativa na próxima sessão"
        seg_plugins="plugins ${D_YELLOW}FALHOU${D_RESET}"
    fi

    echo -e "${D_PURPLE}[cca]${D_RESET} preflight: $seg_login · $seg_design · $seg_consent · $seg_plugins"
    return 0
}

# Propósito: doctor do cca — preflight completo ignorando cadência.
# Uso: cca-preflight
cca-preflight() {
    __header "CCA PREFLIGHT" "$D_PURPLE"
    __cca_preflight --force
}

# Proposito: Wrapper seguro para Claude Code com quota guard
# Uso: claude <args>
claude-safe() {
    __cca_unlock_secrets  # falha-soft: continua mesmo se vault não destravou
    bash "$HOME/.config/zsh/cca/cca_guard.sh" before || return 1
    __cca_export_contexto

    local start_time=$(date +%s)
    NODE_OPTIONS="$(__cca_node_opts)" command claude "$@"
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
    CLAUDE_FORCE=1 NODE_OPTIONS="$(__cca_node_opts)" command claude "$@"
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

# Headroom de heap V8: o heap default do V8 nesta maquina e ~2G (medido) -- pequeno pra
# sessões grandes (1M context), que crasham com "JS heap out of memory". Subimos pra 8G,
# mantendo folga DENTRO do teto de 12G do slice (que segue como rede dura via SIGKILL +
# earlyoom). Aplicado como prefixo inline: afeta so o processo claude, não vaza pro shell.
# Preserva NODE_OPTIONS pre-existente. Usado por TODO ponto de entrada do claude (cca,
# cca-here, cca-ghostty, cca-tmux, cca-resume, claude-safe, claude-force).
__cca_node_opts() { printf '%s' "${NODE_OPTIONS:+$NODE_OPTIONS }--max-old-space-size=8192"; }

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
    local node_opts="$(__cca_node_opts)"
    # context7 (lookup de docs) fica OFF por default no settings.json p/ poupar ~168MB de RAM
    # por instancia -- multiplicado por subagente, era o que mais apertava a maquina de 14G.
    # playwright continua sempre on (a validação visual depende dele). Religa context7 sob
    # demanda, sem comando novo: `CCA_CONTEXT7=1 cca` (injeta o server via --mcp-config aditivo).
    local zroot="${ZDOTDIR:-$HOME/.config/zsh}"
    local -a mcp_args=()
    [ -n "${CCA_CONTEXT7:-}" ] && [ -f "$zroot/cca/mcp-context7.json" ] \
        && mcp_args=(--mcp-config "$zroot/cca/mcp-context7.json")
    # Se claude.slice esta instalado no user systemd, rodar dentro dele (limites de memoria)
    if systemctl --user list-unit-files 2>/dev/null | grep -q '^claude.slice'; then
        NODE_OPTIONS="$node_opts" systemd-run --user --slice=claude.slice --scope --quiet --collect \
            claude "${mcp_args[@]}" --dangerously-skip-permissions "$@"
        exit_code=$?
    else
        NODE_OPTIONS="$node_opts" command claude "${mcp_args[@]}" --dangerously-skip-permissions "$@"
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

# Propósito: detecta se terminal atual entende OSC 9 / OSC 9;4 (Ghostty/iTerm/Kitty/WezTerm).
# Retorna 0 (compatível) ou 1 (incompatível, ex: gnome-terminal, xterm).
__cca_terminal_compativel() {
    case "${TERM_PROGRAM:-}" in
        Ghostty|ghostty|kitty|iTerm.app|WezTerm) return 0 ;;
    esac
    [ -n "${GHOSTTY_RESOURCES_DIR:-}" ] && return 0
    [ -n "${GHOSTTY_BIN_DIR:-}" ] && return 0
    [ -n "${KITTY_PID:-}" ] && return 0
    [ -n "${KITTY_WINDOW_ID:-}" ] && return 0
    [ -n "${WEZTERM_PANE:-}" ] && return 0
    [ -n "${ITERM_SESSION_ID:-}" ] && return 0
    return 1
}

# Propósito: retorna comando de lançamento Ghostty (nativo ou flatpak), ou string vazia.
__cca_ghostty_exec() {
    if command -v ghostty &>/dev/null; then
        echo "ghostty"
        return 0
    fi
    if command -v flatpak &>/dev/null && flatpak list 2>/dev/null | grep -q "com.mitchellh.ghostty"; then
        echo "flatpak run com.mitchellh.ghostty"
        return 0
    fi
    echo ""
    return 1
}

# Propósito: dispara Ghostty em background com cca rodando dentro (worker comum
# de cca/cca-ghostty). PWD e argv passados via quoting zsh seguro.
__cca_spawn_ghostty() {
    local launch_cmd="$1"; shift
    local quoted_pwd="${(q)PWD}"
    local quoted_args=""
    if [ $# -gt 0 ]; then
        quoted_args=" ${(@q)@}"
    fi
    setsid sh -c "cd $quoted_pwd && $launch_cmd -e zsh -ic 'cca-here$quoted_args'" </dev/null >/dev/null 2>&1 &
    disown
}

# Propósito: Claude Code in-place (não relança terminal). Use quando já está em
# terminal compatível OU quando quer escape hatch num terminal incompatível.
# Uso: cca-here [args]
cca-here() {
    if ! command -v claude &> /dev/null; then
        echo "[ERRO] Claude Code não instalado. Rode: npm install -g @anthropic-ai/claude-code"
        return 1
    fi
    typeset -f sync_claude_symlinks > /dev/null && sync_claude_symlinks --quiet 2>/dev/null
    __cca_run "$@"
}

# Propósito: força relançamento em Ghostty (janela nova) mesmo que terminal
# atual já seja compatível. Útil pra debug ou pra ter sessão isolada.
# Uso: cca-ghostty [args]
cca-ghostty() {
    if ! command -v claude &> /dev/null; then
        echo "[ERRO] Claude Code não instalado."
        return 1
    fi
    local launch_cmd
    launch_cmd=$(__cca_ghostty_exec)
    if [ -z "$launch_cmd" ]; then
        echo "[ERRO] Ghostty não instalado. Rode: bash ~/.config/zsh/install.sh --update"
        return 1
    fi
    echo "[cca-ghostty] Abrindo janela nova do Ghostty (PWD: $PWD)..."
    __cca_spawn_ghostty "$launch_cmd" "$@"
    return 0
}

# Propósito: Claude Code com permissões completas. Detecta terminal e relança em
# Ghostty automaticamente se terminal atual não suportar OSC 9 (push notif).
# Uso: cca [args]
# Variantes: cca-here (força in-place), cca-ghostty (força relançamento), cca-tmux (tmux).
cca() {
    if ! command -v claude &> /dev/null; then
        echo "[ERRO] Claude Code não instalado. Rode: npm install -g @anthropic-ai/claude-code"
        return 1
    fi
    typeset -f sync_claude_symlinks > /dev/null && sync_claude_symlinks --quiet 2>/dev/null

    # Terminal já suporta OSC 9? Roda in-place.
    if __cca_terminal_compativel; then
        __cca_run "$@"
        return $?
    fi

    # Terminal incompatível: tenta relançar em Ghostty (instalado por install.sh).
    local launch_cmd
    launch_cmd=$(__cca_ghostty_exec)
    if [ -n "$launch_cmd" ]; then
        echo "[cca] Terminal atual (${TERM_PROGRAM:-${TERM:-?}}) não suporta OSC 9 — relançando em Ghostty..."
        __cca_spawn_ghostty "$launch_cmd" "$@"
        return 0
    fi

    # Nem Ghostty instalado: roda in-place com aviso forte.
    cat >&2 <<'EOF'
[cca][AVISO] Terminal atual não suporta OSC 9 e Ghostty/Kitty não estão instalados.
Se push notificações vazarem caracteres tipo ]9; ou ^[]777; no TTY, edite
~/.claude/settings.json setando:
  "preferredNotifChannel": "system"
  "agentPushNotifEnabled": false
Ou instale Ghostty: bash ~/.config/zsh/install.sh --update
EOF
    __cca_run "$@"
}

# Propósito: Claude Code dentro de tmux (sobrevive freeze do DE).
# Trade-off: scroll do mouse não funciona dentro do tmux — o gnome-terminal
# converte wheel em arrow keys no alternate screen, e o Claude Code as
# interpreta como navegação. Use PgUp/PgDn pra scroll quando estiver aqui.
# Uso: cca-tmux [args]
cca-tmux() {
    if ! command -v claude &> /dev/null; then
        echo "[ERRO] Claude Code não instalado. Rode: npm install -g @anthropic-ai/claude-code"
        return 1
    fi
    if ! command -v tmux &> /dev/null; then
        echo "[ERRO] tmux não instalado. Use 'cca' (modo direto) ou rode 'sudo apt install tmux'"
        return 1
    fi
    if [ -n "${TMUX:-}" ]; then
        __cca_run "$@"
        return $?
    fi
    local sha proj sess
    sha=$(printf '%s' "$PWD" | sha1sum | awk '{print substr($1,1,6)}')
    proj=$(basename "$PWD")
    sess="claude-${proj}-${sha}"
    if tmux has-session -t "$sess" 2>/dev/null; then
        echo "[cca-tmux] Sessão tmux '$sess' já existe. Anexando (Ctrl-b d para detach)..."
        exec tmux attach -t "$sess"
    fi
    echo "[cca-tmux] Criando sessão tmux: $sess (Ctrl-b d para detach)"
    if [ $# -eq 0 ]; then
        exec tmux new -s "$sess" -c "$PWD" "zsh -ic '__cca_run'"
    else
        local args_str="$*"
        exec tmux new -s "$sess" -c "$PWD" "zsh -ic '__cca_run ${args_str}'"
    fi
}

# Propósito: Listar sessões tmux do Claude ativas (criadas via cca-tmux)
# Uso: cca-list
cca-list() {
    if ! command -v tmux &> /dev/null; then
        echo "tmux não instalado"
        return 1
    fi
    echo "=== Sessões Claude ativas (tmux) ==="
    tmux ls 2>/dev/null | grep -E '^claude-' || echo "(nenhuma)"
}

# Propósito: Retomar última sessão Claude no cwd atual (modo direto)
# Uso: cca-resume [args]
cca-resume() {
    if ! command -v claude &> /dev/null; then
        echo "[ERRO] Claude Code não instalado."
        return 1
    fi
    bash "$HOME/.config/zsh/cca/cca_guard.sh" before || return 1
    __cca_export_contexto
    local rc
    local node_opts="$(__cca_node_opts)"  # retomar sessão caida e o caso mais propenso a OOM de heap
    if systemctl --user list-unit-files 2>/dev/null | grep -q '^claude.slice'; then
        NODE_OPTIONS="$node_opts" systemd-run --user --slice=claude.slice --scope --quiet --collect \
            claude --continue --dangerously-skip-permissions "$@"
        rc=$?
    else
        NODE_OPTIONS="$node_opts" command claude --continue --dangerously-skip-permissions "$@"
        rc=$?
    fi
    __cca_unset_contexto
    return $rc
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
