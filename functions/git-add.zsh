#!/bin/zsh

unalias ga 2>/dev/null

# Proposito: Git add com sanitizer automatico e ruff (lint + format) para Python
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

        local python_files=(${(M)all_staged[@]:#*.py})

        if [[ ${#python_files[@]} -gt 0 ]] && command -v ruff &> /dev/null; then
            ruff check --fix "${python_files[@]}" --exit-zero --quiet
            ruff format "${python_files[@]}" --quiet
        fi

        git add "${all_staged[@]}"
    fi
}
