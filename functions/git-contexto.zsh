#!/bin/zsh

__definir_contexto_git() {
    local user_name="$1"
    local user_email="$2"

    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        __warn "Sem repositorio git. Execute 'git init' e reabra o santuario."
        return 1
    fi

    git config --local user.name "$user_name"
    git config --local user.email "$user_email"

    echo -e "  ${D_COMMENT}Contexto git:${D_RESET} ${D_CYAN}$user_name${D_RESET}"
}

__aplicar_contexto_git_automatico() {
    local user_pessoal="${ZSH_GIT_NAME_PESSOAL:-AndreBFarias}"
    local email_pessoal="${ZSH_GIT_EMAIL_PESSOAL:-andre.dsbf@gmail.com}"

    local user_mec="${ZSH_GIT_NAME_MEC:-andrefariasmec}"
    local email_mec="${ZSH_GIT_EMAIL_MEC:-andrefarias@mec.gov.br}"

    local user_alt="${ZSH_GIT_NAME_ALT:-vitoriamariadb}"
    local email_alt="${ZSH_GIT_EMAIL_ALT:-vitoriamaria.sds@gmail.com}"

    if [[ "$(pwd)" == *"/MEC/pipelines-main"* ]]; then
        __definir_contexto_git "$user_mec" "$email_mec"
    elif [[ "$(pwd)" == *"/VitoriaMariaDB/"* ]]; then
        __definir_contexto_git "$user_alt" "$email_alt"
    else
        __definir_contexto_git "$user_pessoal" "$email_pessoal"
    fi
}

# Proposito: Exibir identidade git do repositorio atual (nome, email, branch, remote)
# Uso: git_info
git_info() {
    __header "IDENTIDADE GIT" "$D_PURPLE"

    __item "Nome" "$(git config --local user.name 2>/dev/null || echo '(global)')" "$D_COMMENT" "$D_FG"
    __item "Email" "$(git config --local user.email 2>/dev/null || echo '(global)')" "$D_COMMENT" "$D_FG"
    __item "Branch" "$(git branch --show-current 2>/dev/null)" "$D_COMMENT" "$D_CYAN"

    local remote_url=$(git remote get-url origin 2>/dev/null)
    __item "Remote" "${remote_url:-(nenhum)}" "$D_COMMENT" "$D_GREEN"

    local remote_proto="desconhecido"
    if [[ "$remote_url" == git@* || "$remote_url" == ssh://* ]]; then
        remote_proto="SSH"
    elif [[ "$remote_url" == https://* ]]; then
        remote_proto="HTTPS (credential.helper global)"
    fi
    __item "Auth" "$remote_proto" "$D_COMMENT" "$D_GREEN"

    echo ""
}

# Proposito: Alias para git_info (exibir identidade git)
# Uso: git_status
alias git_status='git_info'

__aplicar_contexto_gh_automatico() {
    if ! command -v gh &>/dev/null; then
        return 0
    fi

    local conta_alvo=""
    if [[ "$(pwd)" == *"/MEC/pipelines-main"* ]]; then
        conta_alvo="${ZSH_GIT_NAME_MEC:-andrefariasmec}"
    elif [[ "$(pwd)" == *"/VitoriaMariaDB/"* ]]; then
        conta_alvo="${ZSH_GIT_NAME_ALT:-vitoriamariadb}"
    else
        conta_alvo="${ZSH_GIT_NAME_PESSOAL:-AndreBFarias}"
    fi

    local conta_ativa
    conta_ativa=$(gh api user --jq '.login' 2>/dev/null)

    if [[ "$conta_ativa" == "$conta_alvo" ]]; then
        echo -e "  ${D_COMMENT}gh:${D_RESET} ${D_CYAN}${conta_alvo}${D_RESET}"
        return 0
    fi

    if gh auth switch --user "$conta_alvo" >/dev/null 2>&1; then
        echo -e "  ${D_COMMENT}gh:${D_RESET} ${D_CYAN}${conta_alvo}${D_RESET}"
    else
        __warn "gh: conta '${conta_alvo}' nao cadastrada. Ativa: ${conta_ativa:-desconhecida}"
    fi
}

__sinc_preservadora() {
    local nome_repo=$(basename "$(pwd)")
    local timestamp=$(date +'%Y-%m-%d_%Hh%M%S')
    local backup_root="_VERSAO_ANTIGA"
    local backup_dir="$backup_root/Backup_$timestamp"

    echo -e "  ${D_COMMENT}Sincronizando '${nome_repo}'...${D_RESET}"

    if ! git fetch --all -p -q; then
        __err "Falha ao buscar dados do remoto."
        return 1
    fi

    local upstream=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)
    if [ -z "$upstream" ]; then
        __warn "Branch sem upstream. Nada a fazer."
        return 1
    fi

    if [ -n "$(git status --porcelain)" ]; then
        mkdir -p "$backup_dir"
        rsync -ax --exclude '.git' --exclude "$backup_root" . "$backup_dir"
        echo -e "  ${D_COMMENT}Backup:${D_RESET} ${D_CYAN}${backup_dir}${D_RESET}"
    fi

    git reset --hard "$upstream" -q
    git clean -fd -e "$backup_root" -q

    __ok "$nome_repo sincronizado."
}

# Proposito: Sincronizar repositorios selecionados via FZF (com backup de alteracoes)
# Uso: sincronizar_repositorio
sincronizar_repositorio() {
    __verificar_dependencias "git" "fzf" "rsync" || return 1

    local repos=$(find "$DEV_DIR" -maxdepth 4 -name ".git" -type d -prune | sed 's/\/\.git//' | sort)

    local selecao=$(echo "$repos" | fzf --multi --height=60% \
        --prompt="  Sincronizar > " \
        --header="  TAB para selecionar multiplos" \
        --color="bg+:#44475a,fg+:#f8f8f2,hl:#bd93f9,hl+:#ff79c6,pointer:#50fa7b,marker:#50fa7b,prompt:#bd93f9,header:#6272a4,border:#6272a4" \
        --preview 'git -C {} status -s')

    if [ -z "$selecao" ]; then echo -e "  ${D_COMMENT}Cancelado.${D_RESET}"; return 0; fi

    __header "SINCRONIZACAO" "$D_ORANGE"

    echo "$selecao" | while read -r repo_path; do
        cd "$repo_path" || continue
        __aplicar_contexto_git_automatico > /dev/null 2>&1
        __sinc_preservadora
    done
    echo ""
}

# Proposito: Sincronizar TODOS os repositorios com o remoto (com backup)
# Uso: sincronizar_todos_os_repositorios
sincronizar_todos_os_repositorios() {
    __verificar_dependencias "git" "rsync" || return 1

    __header "SINCRONIZACAO EM MASSA" "$D_RED"
    echo -e "  ${D_YELLOW}Arquivos locais nao versionados serao backupeados em '_VERSAO_ANTIGA/'.${D_RESET}"
    read -k 1 "reply?  Confirmar? (y/N) "
    echo ""

    if [[ "$reply" != "y" ]]; then echo -e "  ${D_COMMENT}Cancelado.${D_RESET}"; return 0; fi

    local repos=$(find "$DEV_DIR" -maxdepth 4 -name ".git" -type d -prune | sed 's/\/\.git//' | sort)

    echo "$repos" | while read -r repo_path; do
        cd "$repo_path" || continue
        __aplicar_contexto_git_automatico > /dev/null 2>&1
        __sinc_preservadora
    done

    echo ""
    __ok "Todos os repositorios processados."
    echo ""
}
