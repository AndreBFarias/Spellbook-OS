#!/bin/zsh

# Propósito: garantir que cada repo em $DEV_DIR tenha CLAUDE.md como symlink
# para ~/.config/zsh/GUIDE.md (fonte canônica de diretrizes anti-erro de LLM)
# e que CLAUDE.md esteja no .gitignore (anonimato — nome não vai pro repo).
#
# Skipa:
#   - Spellbook-OS (symlink para o próprio zsh)
#   - Repos cujo CLAUDE.md já é arquivo real e não-symlink (regras locais)
#   - Repos listados em CLAUDE_SYMLINKS_SKIP (projetos com GUIDE.md committed
#     contendo regras próprias — o symlink CLAUDE.md → canônico sobrescreveria
#     o GUIDE.md local na leitura semântica do CC).
#
# Uso:
#   sync_claude_symlinks            # verboso, com header
#   sync_claude_symlinks --quiet    # silencioso (só erros), usado por cca/zshrc
sync_claude_symlinks() {
    local quiet=0
    [[ "$1" == "--quiet" || "$1" == "-q" ]] && quiet=1

    local base_dir="${DEV_DIR:-$HOME/Desenvolvimento}"
    local source_file="${ZDOTDIR:-$HOME/.config/zsh}/GUIDE.md"

    if [ ! -f "$source_file" ]; then
        [ "$quiet" -eq 0 ] && __err "Fonte canônica não existe: $source_file"
        return 1
    fi

    [ ! -d "$base_dir" ] && return 0

    # Lista de repos com regras próprias (GUIDE.md ou CLAUDE.md committed
    # com conteúdo específico do projeto). Esses NÃO recebem symlink — leitura
    # do CC pega o próprio GUIDE.md / CLAUDE.md local.
    local skip_list=(
        "Protocolo-Mob-Ouroboros"
        "protocolo-ouroboros"
    )

    [ "$quiet" -eq 0 ] && __header "SYNC CLAUDE.md SYMLINKS" "$D_CYAN"

    local total=0 created=0 ok=0 skipped=0 ignored_added=0

    for repo in "$base_dir"/*(N/); do
        local name="${repo:t}"

        # Skipar Spellbook-OS (symlink para o próprio zsh)
        [ -L "$repo" ] && continue
        [ "$name" = "Spellbook-OS" ] && continue

        # Skipar não-repos
        [ ! -d "$repo/.git" ] && continue

        ((total++))

        local target="$repo/CLAUDE.md"

        # Skipar projetos com regras próprias (lista explícita)
        if [[ " ${skip_list[*]} " == *" ${name} "* ]]; then
            ((skipped++))
            [ "$quiet" -eq 0 ] && printf "  ${D_COMMENT}[SKIP]${D_RESET} %-40s ${D_DIM}(regras próprias)${D_RESET}\n" "$name"
            continue
        fi

        # Se tem CLAUDE.md como arquivo real (não symlink), pular — regras locais
        if [ -f "$target" ] && [ ! -L "$target" ]; then
            ((skipped++))
            [ "$quiet" -eq 0 ] && printf "  ${D_COMMENT}[SKIP]${D_RESET} %-40s ${D_DIM}(CLAUDE.md real)${D_RESET}\n" "$name"
            continue
        fi

        # Criar/refazer symlink
        if [ -L "$target" ]; then
            local current="$(readlink "$target" 2>/dev/null)"
            if [ "$current" = "$source_file" ]; then
                ((ok++))
                [ "$quiet" -eq 0 ] && printf "  ${D_GREEN}[OK]${D_RESET}   %-40s\n" "$name"
            else
                ln -sfn "$source_file" "$target"
                ((created++))
                [ "$quiet" -eq 0 ] && printf "  ${D_ORANGE}[FIX]${D_RESET}  %-40s ${D_DIM}(target era %s)${D_RESET}\n" "$name" "$current"
            fi
        else
            ln -sfn "$source_file" "$target"
            ((created++))
            [ "$quiet" -eq 0 ] && printf "  ${D_PINK}[NEW]${D_RESET}  %-40s\n" "$name"
        fi

        # Garantir CLAUDE.md no .gitignore
        local gitignore="$repo/.gitignore"
        if [ ! -f "$gitignore" ]; then
            echo "CLAUDE.md" > "$gitignore"
            ((ignored_added++))
        elif ! grep -qxF "CLAUDE.md" "$gitignore" 2>/dev/null; then
            echo "" >> "$gitignore"
            echo "# Symlink local para diretrizes (não vai pro repo)" >> "$gitignore"
            echo "CLAUDE.md" >> "$gitignore"
            ((ignored_added++))
        fi
    done

    if [ "$quiet" -eq 0 ]; then
        echo ""
        echo -e "  ${D_COMMENT}Total: ${total} | OK: ${ok} | Novos/corrigidos: ${created} | Skip: ${skipped} | gitignore atualizado: ${ignored_added}${D_RESET}"
        echo ""
    fi

    return 0
}
