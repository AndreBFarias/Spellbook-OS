#!/bin/zsh

# Propósito: Reaplicar os git hooks versionados (.githooks/) no diretório do
#            core.hooksPath global (~/.config/git/hooks) -- o único que roda em
#            TODOS os repos. NÃO espalha mais para o .git/hooks/ de cada repo:
#            com core.hooksPath global setado (via install.sh), esses hooks
#            locais são ignorados pelo git (era trabalho morto que só gerava
#            cópias divergentes). O hooksPath em si é configurado pelo install.sh.
# Uso: aplicar_hooks_globais
aplicar_hooks_globais() {
    __verificar_dependencias "git" || return 1

    # Fonte canônica versionada
    local source_dir="${ZDOTDIR:-$HOME/.config/zsh}/.githooks"
    local dest_dir="$HOME/.config/git/hooks"

    if [ ! -d "$source_dir" ]; then
        __err "Fonte de hooks não encontrada em $source_dir"
        return 1
    fi

    __header "HOOKS GLOBAIS" "$D_PINK"
    mkdir -p "$dest_dir"

    local -a hook_files=(_lib.sh pre-commit commit-msg pre-push post-commit)
    local count=0
    for hook in "${hook_files[@]}"; do
        if [ -f "$source_dir/$hook" ]; then
            cp "$source_dir/$hook" "$dest_dir/$hook"
            chmod +x "$dest_dir/$hook"
            ((count++))
            __item "$hook"
        fi
    done

    # Commit template (fora do dir de hooks, apontado por commit.template)
    [ -f "$source_dir/commit-template" ] && \
        cp "$source_dir/commit-template" "$HOME/.config/git/commit-template"

    echo ""
    __ok "$count hook(s) reaplicado(s) em $dest_dir (core.hooksPath global)"
    echo ""
}
