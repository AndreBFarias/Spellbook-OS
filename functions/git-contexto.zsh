#!/bin/zsh

# --- Resolução de identidade por path (lê de config.local.zsh) ---

__resolver_identidade() {
    local repo_path="${1:-$(pwd)}"

    for tag in ${(s: :)ZSH_IDENTITY_TAGS}; do
        local path_var="ZSH_IDENTITY_${tag}_PATH"
        local path_pattern="${(P)path_var}"

        if [[ -n "$path_pattern" && ("$repo_path" == *"/${path_pattern}/"* || "$repo_path" == *"/${path_pattern}") ]]; then
            local name_var="ZSH_IDENTITY_${tag}_NAME"
            local email_var="ZSH_IDENTITY_${tag}_EMAIL"
            local ssh_var="ZSH_IDENTITY_${tag}_SSH"

            REPLY_NAME="${(P)name_var}"
            REPLY_EMAIL="${(P)email_var}"
            REPLY_SSH="${(P)ssh_var}"
            REPLY_CONTEXT="$tag"
            return 0
        fi
    done

    # REDE DE SEGURANÇA (2026-09-15, mediação vinda do Andromeda-OS). Estas duas
    # linhas não tinham valor padrão enquanto a do SSH, logo abaixo, sempre teve.
    # No MeowSystem o config.local.zsh sumiu num upgrade e o fallback passou a
    # devolver string vazia: o __definir_contexto_git gravou `name =` / `email =`
    # em branco no .git/config de um repositório, e a chave vazia sobrescreve a
    # global — commit e push mortos ali. O git ACEITA a chave vazia:
    # `git config --get user.name` volta vazio com rc=0, então nem quem testa o
    # rc percebe. Aqui o arquivo existe, então isto é prevenção, não conserto.
    REPLY_NAME="${ZSH_GIT_NAME_PESSOAL:-$(git config --global user.name 2>/dev/null)}"
    REPLY_EMAIL="${ZSH_GIT_EMAIL_PESSOAL:-$(git config --global user.email 2>/dev/null)}"
    REPLY_SSH="${ZSH_SSH_ALIAS_PESSOAL:-github.com-personal}"
    REPLY_CONTEXT="Pessoal"
    return 0
}

# --- Funções de contexto git ---

# AUTO-REPARO (2026-09-15): remove a marca deixada por uma gravação de
# identidade vazia. A detecção tem de ser pela PRESENÇA da chave com valor
# vazio, nunca pelo rc: `git config --get` devolve string vazia com rc=0.
# Sem a chave, o repositório volta a herdar a identidade global, que é o estado
# correto de um repositório sem override.
__limpar_identidade_vazia() {
    local achou=0 chave
    for chave in user.name user.email; do
        if git config --local --get "$chave" >/dev/null 2>&1 \
           && [ -z "$(git config --local --get "$chave" 2>/dev/null)" ]; then
            git config --local --unset-all "$chave" 2>/dev/null && achou=1
        fi
    done
    if [ "$achou" -eq 1 ]; then
        __warn "Identidade local VAZIA encontrada no .git/config e removida."
        return 1
    fi
    return 0
}

__definir_contexto_git() {
    local user_name="$1"
    local user_email="$2"

    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        __warn "Sem repositório git. Execute 'git init' e reabra o santuário."
        return 1
    fi

    # Roda ANTES da guarda: mesmo sem identidade para escrever, o repositório
    # tem de sair daqui sem a chave vazia.
    __limpar_identidade_vazia

    # GUARDA (2026-09-15): escrever vazio nunca é a intenção de quem chamou, é
    # sempre um defeito. Sem isto o `git config --local user.name ""` grava a
    # chave vazia, que sobrescreve a global e trava commit e push naquele
    # repositório até alguém rodar `--unset-all` à mão.
    if [ -z "$user_name" ] || [ -z "$user_email" ]; then
        __err "Identidade vazia — nada gravado no .git/config deste repositório."
        echo -e "  ${D_COMMENT}Falta ${D_YELLOW}config.local.zsh${D_RESET}${D_COMMENT} (ZSH_GIT_NAME_PESSOAL / ZSH_GIT_EMAIL_PESSOAL)${D_RESET}"
        echo -e "  ${D_COMMENT}ou a tag de path correspondente em ZSH_IDENTITY_TAGS.${D_RESET}"
        return 1
    fi

    git config --local user.name "$user_name"
    git config --local user.email "$user_email"

    echo -e "  ${D_COMMENT}Contexto git:${D_RESET} ${D_CYAN}$user_name${D_RESET}"
}

__resolver_alias_ssh() {
    local repo_path="${1:-$(pwd)}"
    __resolver_identidade "$repo_path"
    echo "$REPLY_SSH"
}

__fixar_remote_ssh() {
    local remote_url
    remote_url=$(git remote get-url origin 2>/dev/null)
    [[ -z "$remote_url" ]] && return 0

    # OPT-OUT POR REPOSITÓRIO (2026-09-15). Reescrever o `origin` é ação visível
    # e, no limite, manda push para o lugar errado. Quando o repositório quiser
    # decidir sozinho:
    #     git config --local andromeda.remote-fixo true
    # Ligada, esta função não toca no remote. `--unset` devolve o automático.
    if [[ "$(git config --local --get andromeda.remote-fixo 2>/dev/null)" == "true" ]]; then
        return 0
    fi

    local alias_correto
    alias_correto=$(__resolver_alias_ssh)

    if [[ "$remote_url" == git@${alias_correto}:* ]]; then
        return 0
    fi

    local owner_repo=""

    if [[ "$remote_url" == https://* ]]; then
        owner_repo=$(echo "$remote_url" | sed -E 's|https://([^@]+@)?github\.com/||')
    elif [[ "$remote_url" == git@* ]]; then
        owner_repo=$(echo "$remote_url" | sed -E 's|git@[^:]+:||')
    fi

    [[ -z "$owner_repo" ]] && return 0

    owner_repo="${owner_repo%.git}.git"
    owner_repo=$(echo "$owner_repo" | sed 's|\.git\.git|.git|')

    local novo_url="git@${alias_correto}:${owner_repo}"
    git remote set-url origin "$novo_url"
    __item "Remote" "${remote_url} -> ${novo_url}" "$D_COMMENT" "$D_GREEN"
}

__aplicar_contexto_git_automatico() {
    __resolver_identidade "$(pwd)"
    # Identidade que falhou não dá autoridade para reescrever o remote. Antes, o
    # __definir_contexto_git falhava e o __fixar_remote_ssh mexia no origin
    # assim mesmo — agravado por o alias SSH ter valor padrão e as identidades
    # não terem.
    __definir_contexto_git "$REPLY_NAME" "$REPLY_EMAIL" || return 1
    __fixar_remote_ssh
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
    local alias_esperado
    alias_esperado=$(__resolver_alias_ssh)
    if [[ "$remote_url" == git@${alias_esperado}:* ]]; then
        remote_proto="SSH ($alias_esperado)"
    elif [[ "$remote_url" == git@* || "$remote_url" == ssh://* ]]; then
        remote_proto="SSH (alias incorreto, esperado: $alias_esperado)"
    elif [[ "$remote_url" == https://* ]]; then
        remote_proto="HTTPS (credential.helper global)"
    fi
    __item "Auth" "$remote_proto" "$D_COMMENT" "$D_GREEN"

    echo ""
}

alias git_status='git_info'

__aplicar_contexto_gh_automatico() {
    if ! command -v gh &>/dev/null; then
        return 0
    fi

    __resolver_identidade "$(pwd)"
    local conta_alvo="$REPLY_NAME"

    local conta_ativa
    conta_ativa=$(gh api user --jq '.login' 2>/dev/null)

    if [[ "$conta_ativa" == "$conta_alvo" ]]; then
        echo -e "  ${D_COMMENT}gh:${D_RESET} ${D_CYAN}${conta_alvo}${D_RESET}"
        return 0
    fi

    if gh auth switch --user "$conta_alvo" >/dev/null 2>&1; then
        echo -e "  ${D_COMMENT}gh:${D_RESET} ${D_CYAN}${conta_alvo}${D_RESET}"
    else
        __warn "gh: conta '${conta_alvo}' não cadastrada. Ativa: ${conta_ativa:-desconhecida}"
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

    local commits_locais=$(git rev-list --count "${upstream}..HEAD" 2>/dev/null)
    if [ -n "$(git status --porcelain)" ] || [ "${commits_locais:-0}" -gt 0 ]; then
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

    local repos=$(find "$DEV_DIR/" -maxdepth 4 -name ".git" -type d -prune | sed 's/\/\.git//' | sort)

    local seleção=$(echo "$repos" | fzf --multi --height=60% \
        --prompt="  Sincronizar > " \
        --header="  TAB para selecionar multiplos" \
        --color="bg+:#44475a,fg+:#f8f8f2,hl:#bd93f9,hl+:#ff79c6,pointer:#50fa7b,marker:#50fa7b,prompt:#bd93f9,header:#6272a4,border:#6272a4" \
        --preview 'git -C {} status -s')

    if [ -z "$seleção" ]; then echo -e "  ${D_COMMENT}Cancelado.${D_RESET}"; return 0; fi

    __header "SINCRONIZACAO" "$D_ORANGE"

    while read -r repo_path; do
        __cd "$repo_path" || continue
        __aplicar_contexto_git_automatico > /dev/null 2>&1
        __sinc_preservadora
    done <<< "$seleção"
    echo ""
}

# Proposito: Sincronizar TODOS os repositorios com o remoto (com backup)
# Uso: sincronizar_todos_os_repositorios
sincronizar_todos_os_repositorios() {
    __verificar_dependencias "git" "rsync" || return 1

    __header "SINCRONIZACAO EM MASSA" "$D_RED"
    echo -e "  ${D_YELLOW}Arquivos locais não versionados serao backupeados em '_VERSAO_ANTIGA/'.${D_RESET}"
    read -k 1 "reply?  Confirmar? (y/N) "
    echo ""

    if [[ "$reply" != "y" ]]; then echo -e "  ${D_COMMENT}Cancelado.${D_RESET}"; return 0; fi

    local repos=$(find "$DEV_DIR/" -maxdepth 4 -name ".git" -type d -prune | sed 's/\/\.git//' | sort)

    while read -r repo_path; do
        __cd "$repo_path" || continue
        __aplicar_contexto_git_automatico > /dev/null 2>&1
        __sinc_preservadora
    done <<< "$repos"

    echo ""
    __ok "Todos os repositorios processados."
    echo ""
}

# "Não e a consciencia que determina a vida, mas a vida que determina a consciencia." -- Karl Marx
