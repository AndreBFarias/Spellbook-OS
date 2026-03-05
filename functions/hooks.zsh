#!/bin/zsh

# Proposito: Copiar hooks git (pre-commit + pre-push) para todos os repos
# Uso: aplicar_hooks_globais [diretorio_base]
aplicar_hooks_globais() {
    __verificar_dependencias "git" || return 1

    local base_dir="${1:-$DEV_DIR}"
    local hooks_source="$HOME/.config/git/hooks"

    if [ ! -d "$hooks_source" ]; then
        __err "Diretório de hooks nao encontrado em $hooks_source"
        return 1
    fi

    __header "HOOKS GLOBAIS" "$D_PINK"

    local repos=$(find "$base_dir" -maxdepth 4 -name ".git" -type d -prune | sed 's/\/\.git//' | sort)
    local total=$(echo "$repos" | wc -l | xargs)

    if [ -z "$repos" ]; then
        __warn "Nenhum repositório encontrado."
        return 0
    fi

    echo -e "  ${D_COMMENT}${total} repositórios encontrados.${D_RESET}"
    echo ""

    local count=0
    echo "$repos" | while read -r repo_path; do
        ((count++))
        local repo_name=$(basename "$repo_path")

        [ ! -d "$repo_path/.git/hooks" ] && mkdir -p "$repo_path/.git/hooks"

        cp "$hooks_source/pre-commit" "$repo_path/.git/hooks/pre-commit" 2>/dev/null
        cp "$hooks_source/pre-push" "$repo_path/.git/hooks/pre-push" 2>/dev/null
        cp "$hooks_source/commit-msg" "$repo_path/.git/hooks/commit-msg" 2>/dev/null
        chmod +x "$repo_path/.git/hooks/pre-commit" 2>/dev/null
        chmod +x "$repo_path/.git/hooks/pre-push" 2>/dev/null
        chmod +x "$repo_path/.git/hooks/commit-msg" 2>/dev/null

        printf "  ${D_GREEN}[%02d/%02d]${D_RESET} %s\n" "$count" "$total" "$repo_name"
    done

    echo ""
    __ok "Hooks aplicados: pre-commit (sanitizer + identidade) + commit-msg (anonimato) + pre-push (contexto + author)"
    echo ""
}
