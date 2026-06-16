#!/bin/zsh
# Spellbook-OS: Sync bidirecional via git
# ~/.config/zsh/ e um clone do Spellbook-OS com auto-sync ao abrir/fechar terminal

__spellbook_sync_dir() {
    echo "${ZDOTDIR:-$HOME/.config/zsh}"
}

# Status curto p/ o módulo `command` Spellbook-OS do fastfetch lê na próxima abertura.
__spellbook_status_cache_write() {
    local msg="$1"
    local cache_dir="${XDG_RUNTIME_DIR:-/tmp}"
    local cache="$cache_dir/spellbook_status_$(id -u)"
    print -r -- "$msg" > "$cache" 2>/dev/null
    chmod 600 "$cache" 2>/dev/null
}

__spellbook_is_git_repo() {
    local dir="$(__spellbook_sync_dir)"
    [[ -d "$dir/.git" ]] || return 1
    git -C "$dir" remote get-url origin &>/dev/null || return 1
    return 0
}

# Guard de secrets: nunca permitir autocommit se arquivos sensíveis estiverem versionados.
# Defense-in-depth contra .gitignore quebrado/editado por engano.
#
# Exceção: .zsh_secrets virou SHIM versionado de propósito (decifra vault/secrets.gpg em
# runtime; passphrase fora do repo). Versioná-lo é correto — só vaza se ALGUÉM colar um
# export com valor literal (plaintext) dentro dele. Por isso ele é checado por CONTEÚDO,
# não por presença no index (senão bloqueava todo autocommit, como ocorreu 20/05 -> 16/06).
# Os demais arquivos nunca devem ser versionados: bloqueio por presença, como antes.
__spellbook_secrets_leaked() {
    local dir="$1"
    local -a sensitive=(segape-andre.json profiles.yml meua-ambiente.json novo_login_de_acesso.json)
    local -a leaked=()
    local p
    for p in "${sensitive[@]}"; do
        git -C "$dir" ls-files --error-unmatch "$p" >/dev/null 2>&1 && leaked+=("$p")
    done
    # .zsh_secrets: tracked é esperado (shim); só conta como leak se tiver plaintext de fato.
    if git -C "$dir" ls-files --error-unmatch .zsh_secrets >/dev/null 2>&1; then
        local plaintext_re="^[[:space:]]*export[[:space:]]+[A-Za-z_][A-Za-z0-9_]*=['\"]?[A-Za-z0-9/_+.:-]"
        if git -C "$dir" show :.zsh_secrets 2>/dev/null | grep -qE "$plaintext_re"; then
            leaked+=(.zsh_secrets)
        fi
    fi
    if (( ${#leaked[@]} > 0 )); then
        __err "[autosync] BLOQUEADO: secrets detectados no index:"
        local f
        for f in "${leaked[@]}"; do __err "    - $f"; done
        __err "  Corrija manualmente:"
        __err "    git rm --cached ${leaked[*]}"
        __err "    git commit -m 'fix: remove tracked secrets'"
        return 0
    fi
    return 1
}

__spellbook_auto_commit() {
    local dir="$(__spellbook_sync_dir)"
    local changes
    changes=$(git -C "$dir" status --porcelain 2>/dev/null)

    [[ -z "$changes" ]] && return 1

    # Defense-in-depth: bloqueia autocommit se gitignore foi furado
    __spellbook_secrets_leaked "$dir" && return 1

    git -C "$dir" add -A 2>/dev/null
    git -C "$dir" commit -m "auto: sync $(hostname) $(date '+%Y-%m-%d %H:%M')" --quiet 2>/dev/null
    return 0
}

__spellbook_resolve_conflict() {
    local dir="$(__spellbook_sync_dir)"
    local conflitos
    conflitos=$(git -C "$dir" diff --name-only --diff-filter=U 2>/dev/null)

    if [[ -z "$conflitos" ]]; then
        git -C "$dir" commit --no-edit --quiet 2>/dev/null
        return 0
    fi

    echo ""
    echo -e "  ${D_YELLOW}${D_BOLD}Conflitos detectados:${D_RESET}"
    echo -e "  ${D_COMMENT}$(printf '%.0s─' {1..48})${D_RESET}"

    local arquivo
    while IFS= read -r arquivo; do
        [[ -z "$arquivo" ]] && continue
        echo ""
        echo -e "  ${D_PINK}$arquivo${D_RESET}"
        echo -e "  ${D_COMMENT}$(printf '%.0s─' {1..36})${D_RESET}"
        git -C "$dir" diff "$arquivo" 2>/dev/null | head -30
        echo ""

        local reply=""
        if [[ -t 0 ]]; then
            echo -e "  ${D_FG}(L)ocal  (R)emoto  (M)erge manual  (A)diar${D_RESET}"
            read -k 1 "reply?  > "
            echo ""
        else
            # Non-interactive (cron/systemd): adia conflito, não bloqueia
            reply="A"
            __warn "Conflito em $arquivo — non-interactive, sync adiado"
        fi

        case "$reply" in
            [Ll])
                git -C "$dir" checkout --ours -- "$arquivo"
                git -C "$dir" add "$arquivo"
                __ok "Mantido versão local: $arquivo"
                ;;
            [Rr])
                git -C "$dir" checkout --theirs -- "$arquivo"
                git -C "$dir" add "$arquivo"
                __ok "Aceito versão remota: $arquivo"
                ;;
            [Mm])
                echo -e "  ${D_COMMENT}Abrindo ${EDITOR:-vim}...${D_RESET}"
                ${EDITOR:-vim} "$dir/$arquivo"
                git -C "$dir" add "$arquivo"
                __ok "Merge manual concluído: $arquivo"
                ;;
            [Aa]|*)
                echo -e "  ${D_YELLOW}Sync adiado. Resolva manualmente com:${D_RESET}"
                echo -e "  ${D_COMMENT}  cd $dir && git status${D_RESET}"
                git -C "$dir" merge --abort 2>/dev/null
                return 1
                ;;
        esac
    done <<< "$conflitos"

    git -C "$dir" commit --no-edit --quiet 2>/dev/null
    __ok "Conflitos resolvidos"
    return 0
}

# Propósito: Pull sincronizado do Spellbook-OS (commit local + fetch + merge com tratamento de conflito)
# Uso: spellbook_sync_pull
spellbook_sync_pull() {
    __spellbook_is_git_repo || return 0

    local dir="$(__spellbook_sync_dir)"
    local start_time=$SECONDS

    # Commit mudanças locais pendentes
    local had_local=false
    if __spellbook_auto_commit; then
        had_local=true
    fi

    # Verificar conectividade (timeout 2s)
    if ! timeout 2 git -C "$dir" ls-remote --exit-code origin HEAD &>/dev/null 2>&1; then
        if [[ "$had_local" == true ]]; then
            echo -e "  ${D_COMMENT}Spellbook: commit local salvo (sem rede)${D_RESET}"
            __spellbook_status_cache_write "Commit local salvo (sem rede)"
        else
            __spellbook_status_cache_write "Offline"
        fi
        return 0
    fi

    # Fetch
    git -C "$dir" fetch origin --quiet 2>/dev/null

    # Verificar divergência
    local behind
    behind=$(git -C "$dir" rev-list --count HEAD..origin/main 2>/dev/null)
    local ahead
    ahead=$(git -C "$dir" rev-list --count origin/main..HEAD 2>/dev/null)

    if [[ "${behind:-0}" -eq 0 && "${ahead:-0}" -eq 0 ]]; then
        echo -e "  ${D_GREEN}Spellbook sincronizado${D_RESET}"
        __spellbook_status_cache_write "Sincronizado"
        return 0
    fi

    if [[ "${behind:-0}" -eq 0 && "${ahead:-0}" -gt 0 ]]; then
        echo -e "  ${D_GREEN}Spellbook:${D_RESET} ${D_COMMENT}$ahead commit(s) local(is) pendente(s) de push${D_RESET}"
        __spellbook_status_cache_write "Pendente: $ahead commit(s) de push"
        return 0
    fi

    # Tentar fast-forward
    if git -C "$dir" merge origin/main --ff-only --quiet 2>/dev/null; then
        local elapsed=$(( SECONDS - start_time ))
        echo -e "  ${D_GREEN}Spellbook atualizado:${D_RESET} ${D_FG}$behind commit(s) (${elapsed}s)${D_RESET}"
        __spellbook_status_cache_write "Atualizado: $behind commit(s)"
        return 0
    fi

    # Fast-forward falhou — tentar merge real
    echo -e "  ${D_YELLOW}Spellbook: divergência detectada (local: $ahead, remoto: $behind)${D_RESET}"
    if git -C "$dir" merge origin/main --no-edit --quiet 2>/dev/null; then
        local elapsed=$(( SECONDS - start_time ))
        echo -e "  ${D_GREEN}Spellbook merged:${D_RESET} ${D_FG}$behind commit(s) integrado(s) (${elapsed}s)${D_RESET}"
        __spellbook_status_cache_write "Merged: $behind commit(s)"
        return 0
    fi

    # Merge com conflito
    __spellbook_resolve_conflict
    local rc=$?
    if (( rc == 0 )); then
        __spellbook_status_cache_write "Conflitos resolvidos"
    else
        __spellbook_status_cache_write "Conflito (resolva manualmente)"
    fi
    return $rc
}

# Propósito: Push em background do Spellbook-OS (auto-commit local + push não-bloqueante)
# Uso: spellbook_sync_push
spellbook_sync_push() {
    __spellbook_is_git_repo || return 0

    local dir="$(__spellbook_sync_dir)"

    __spellbook_auto_commit

    # Push em background com log de erro (nunca bloqueia fechamento do terminal)
    local log="${XDG_STATE_HOME:-$HOME/.local/state}/spellbook-sync.log"
    mkdir -p "${log:h}" 2>/dev/null
    {
        if ! git -C "$dir" push origin main --quiet 2>>"$log"; then
            print -r -- "[$(date '+%F %T')] push failed (rc=$?)" >>"$log"
        fi
    } &!
}

# Propósito: Exibir status do sync do Spellbook-OS (branch, ahead/behind, pendentes)
# Uso: spellbook_sync_status
spellbook_sync_status() {
    __spellbook_is_git_repo || {
        __err "ZDOTDIR não é um repositório git com remote configurado"
        return 1
    }

    local dir="$(__spellbook_sync_dir)"

    __header "SPELLBOOK SYNC" "$D_PURPLE"

    local branch
    branch=$(git -C "$dir" branch --show-current 2>/dev/null)
    local last_commit
    last_commit=$(git -C "$dir" log -1 --format="%h %s (%ar)" 2>/dev/null)
    local remote
    remote=$(git -C "$dir" remote get-url origin 2>/dev/null)
    local changes
    changes=$(git -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')

    __item "Diretório" "$dir"
    __item "Branch" "${branch:-desconhecida}" "$D_COMMENT" "$D_CYAN"
    __item "Último" "$last_commit" "$D_COMMENT" "$D_FG"
    __item "Remote" "$remote" "$D_COMMENT" "$D_COMMENT"
    __item "Pendentes" "$changes arquivo(s)" "$D_COMMENT" "$D_FG"

    # Verificar sync com remote
    if timeout 2 git -C "$dir" ls-remote --exit-code origin HEAD &>/dev/null 2>&1; then
        git -C "$dir" fetch origin --quiet 2>/dev/null
        local behind
        behind=$(git -C "$dir" rev-list --count HEAD..origin/main 2>/dev/null)
        local ahead
        ahead=$(git -C "$dir" rev-list --count origin/main..HEAD 2>/dev/null)

        if [[ "${behind:-0}" -eq 0 && "${ahead:-0}" -eq 0 ]]; then
            __item "Status" "sincronizado" "$D_COMMENT" "$D_GREEN"
        else
            __item "Status" "ahead: $ahead, behind: $behind" "$D_COMMENT" "$D_YELLOW"
        fi
    else
        __item "Status" "offline" "$D_COMMENT" "$D_YELLOW"
    fi

    echo ""
}

# Propósito: Forçar sync do Spellbook-OS sobrescrevendo local ou remoto
# Uso: spellbook_sync_force [--local|--remote]
# Flags: --local=Push força (sobrescreve remoto com local)
#        --remote=Pull força (sobrescreve local com remoto)
spellbook_sync_force() {
    __spellbook_is_git_repo || {
        __err "ZDOTDIR não é um repositório git com remote configurado"
        return 1
    }

    local dir="$(__spellbook_sync_dir)"
    local modo="$1"

    case "$modo" in
        --local)
            echo -e "  ${D_YELLOW}Forçando versão local para o remote...${D_RESET}"
            __spellbook_auto_commit
            git -C "$dir" push origin main --force-with-lease
            __ok "Push forçado concluído"
            ;;
        --remote)
            echo -e "  ${D_YELLOW}Forçando versão remota para local...${D_RESET}"
            git -C "$dir" fetch origin
            git -C "$dir" reset --hard origin/main
            __ok "Reset para versão remota concluído"
            ;;
        *)
            echo -e "  ${D_FG}Uso: spellbook_sync_force [--local|--remote]${D_RESET}"
            echo ""
            echo -e "  ${D_COMMENT}--local   Força push (sobrescreve remote com local)${D_RESET}"
            echo -e "  ${D_COMMENT}--remote  Força pull (sobrescreve local com remote)${D_RESET}"
            ;;
    esac
}

# "O que não se pode medir, não se pode melhorar." -- Lord Kelvin
