#!/bin/zsh

# Proposito: Investigar branch ou commit para recuperacao (log, diff, sugestoes)
# Uso: grecuperar [branch_ou_commit]
grecuperar() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        __err "Não e um repositorio git."
        return 1
    fi

    if [[ -z "$1" ]]; then
        __header "RECUPERACAO GIT" "$D_ORANGE"
        echo -e "  ${D_COMMENT}Uso: grecuperar <branch_ou_commit>${D_RESET}"
        echo ""
        echo -e "  ${D_PURPLE}Branches:${D_RESET}"
        git branch -v | sed 's/^/    /'
        echo ""
        echo -e "  ${D_PURPLE}Reflog (últimas 10):${D_RESET}"
        git reflog -10 --format="    %C(yellow)%h%Creset %C(blue)%gd%Creset %gs"
        echo ""
        return 1
    fi

    __header "VERIFICANDO: $1" "$D_ORANGE"

    git log --oneline -5 "$1" 2>/dev/null
    if [[ $? -eq 0 ]]; then
        echo ""
        echo -e "  ${D_COMMENT}Arquivos diferentes entre HEAD e $1:${D_RESET}"
        git diff --stat HEAD.."$1" | sed 's/^/    /'
        echo ""
        echo -e "  ${D_CYAN}merge:${D_RESET}    git merge $1"
        echo -e "  ${D_CYAN}checkout:${D_RESET} git checkout $1"
    else
        __err "Commit ou branch '$1' não encontrado."
    fi
    echo ""
}

# Proposito: Painel de emergencia git (status, branches, reflog, stashes)
# Uso: gsos
gsos() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        __err "Não e um repositorio git."
        return 1
    fi

    __header "SOS GIT" "$D_RED"

    echo -e "  ${D_PURPLE}Status${D_RESET}"
    git status -s | sed 's/^/    /'
    echo ""

    echo -e "  ${D_PURPLE}Branch${D_RESET}  $(git branch --show-current)"
    echo ""

    echo -e "  ${D_PURPLE}Branches Locais${D_RESET}"
    git branch -v | sed 's/^/    /'
    echo ""

    echo -e "  ${D_PURPLE}Reflog (últimas 15)${D_RESET}"
    git reflog -15 --format="    %C(yellow)%h%Creset %C(blue)%gd%Creset %C(green)%ar%Creset %gs"
    echo ""

    echo -e "  ${D_PURPLE}Stashes${D_RESET}"
    local stashes=$(git stash list)
    if [ -n "$stashes" ]; then
        echo "$stashes" | sed 's/^/    /'
    else
        echo -e "    ${D_COMMENT}(nenhum)${D_RESET}"
    fi
    echo ""

    echo -e "  ${D_COMMENT}Para recuperar: grecuperar <commit_ou_branch>${D_RESET}"
    echo ""
}

# Proposito: Reset hard para um ponto do reflog (com confirmacao e preview)
# Uso: grestore <ref>
grestore() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        __err "Não e um repositorio git."
        return 1
    fi

    if [[ -z "$1" ]]; then
        echo -e "  ${D_COMMENT}Uso: grestore HEAD@{N}${D_RESET}"
        echo ""
        echo -e "  ${D_PURPLE}Reflog:${D_RESET}"
        git reflog -15 --format="    %C(yellow)%h%Creset %C(blue)%gd%Creset %gs"
        echo ""
        return 1
    fi

    __header "RESTORE: $1" "$D_RED"

    echo -e "  ${D_YELLOW}Commits que serao perdidos do HEAD atual:${D_RESET}"
    git log --oneline "$1"..HEAD | sed 's/^/    /'
    echo ""

    read "resposta?  Confirmar reset para $1? (s/N): "
    if [[ "$resposta" =~ ^[Ss]$ ]]; then
        git reset --hard "$1"
        __ok "Reset concluido."
    else
        echo -e "  ${D_COMMENT}Cancelado.${D_RESET}"
    fi
    echo ""
}
