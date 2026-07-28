#!/bin/zsh

unalias ga 2>/dev/null

# Propósito: Git add com sanitizer automático e ruff (lint + format) para Python
# Uso: ga [arquivos]
ga() {
    local targets="${@:-.}"
    local sanitizer="${ZDOTDIR:-$HOME/.config/zsh}/scripts/universal-sanitizer.py"

    git add $targets

    local all_staged=(${(f)"$(git diff --name-only --cached --diff-filter=d | grep -vE 'venv|node_modules|env/|\.cfg')"})

    if [[ ${#all_staged[@]} -gt 0 ]]; then

        if [ -f "$sanitizer" ]; then
            python3 "$sanitizer" "${all_staged[@]}"
        fi

        # Acentuação PT-BR: aplica --fix e informa (corrigidos + revisão manual)
        # [2026-07-28] --somente-diff-staged: mesmo motivo do bloco [7] do
        # pre-commit. Este é o SEGUNDO ponto de entrada do mesmo corretor e
        # tinha o mesmo alcance de arquivo inteiro; sem a flag, um `ga` num
        # arquivo antigo reescreve linha que ninguém tocou.
        local validador="${ZDOTDIR:-$HOME/.config/zsh}/scripts/validar-acentuacao.py"
        local ptbr_files=(${(M)all_staged[@]:#*.(py|zsh|sh|md)})
        if [ -f "$validador" ] && [[ ${#ptbr_files[@]} -gt 0 ]]; then
            python3 "$validador" --fix --somente-diff-staged --paths "${ptbr_files[@]}"
        fi

        local python_files=(${(M)all_staged[@]:#*.py})

        if [[ ${#python_files[@]} -gt 0 ]] && command -v ruff &> /dev/null; then
            ruff check --fix "${python_files[@]}" --exit-zero --quiet
            ruff format "${python_files[@]}" --quiet
        fi

        git add "${all_staged[@]}"
    fi
}
