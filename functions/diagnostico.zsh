#!/bin/zsh

# Proposito: Gerar dossie completo de um projeto (ambiente, git, arvore, conteudo)
# Uso: diagnostico_projeto <profundidade> [--max-linhas N]
diagnostico_projeto() {
    __verificar_dependencias "git" "tree" "fzf" "pv" "jq" || return 1

    local PYTHON_EXEC
    if [ -n "$VIRTUAL_ENV" ] && [ -x "$VIRTUAL_ENV/bin/python" ]; then
        PYTHON_EXEC="$VIRTUAL_ENV/bin/python"
        __verificar_dependencias_python "$PYTHON_EXEC" "pandas" "openpyxl" "tabulate" "pyarrow" || return 1
    else
        local DIAG_VENV_PATH="${XDG_DATA_HOME:-$HOME/.local/share}/diagnostico_venv"
        PYTHON_EXEC=$(__preparar_ambiente_python "$DIAG_VENV_PATH")
        if [ $? -ne 0 ]; then return 1; fi
    fi

    local profundidade=""
    local max_linhas=300

    for arg in "$@"; do
        case "$arg" in
            --max-linhas) ;;
            --max-linhas=*) max_linhas="${arg#*=}" ;;
            *)
                if [[ -z "$profundidade" && "$arg" =~ ^[0-9]+$ ]]; then
                    profundidade="$arg"
                elif [[ "$prev_arg" == "--max-linhas" && "$arg" =~ ^[0-9]+$ ]]; then
                    max_linhas="$arg"
                fi
                ;;
        esac
        local prev_arg="$arg"
    done

    if [[ -z "$profundidade" ]]; then
        echo -e "  ${D_COMMENT}Uso: diagnostico_projeto <profundidade> [--max-linhas N]${D_RESET}"
        echo -e "  ${D_COMMENT}  profundidade: 0 = infinita${D_RESET}"
        echo -e "  ${D_COMMENT}  --max-linhas: limite por arquivo texto (default: 300)${D_RESET}"
        return 1
    fi

    local timestamp=$(date +'%Y-%m-%d_%Hh%M')
    local nome_projeto=$(basename "$(pwd)")
    local output_file="diagnostico_projeto_${nome_projeto}_${timestamp}.md"

    local depth_label="$profundidade"
    [ "$profundidade" -eq 0 ] && depth_label="infinita"

    __header "DIAGNOSTICO: $nome_projeto" "$D_PURPLE"
    __item "Profundidade" "$depth_label" "$D_COMMENT" "$D_CYAN"
    __item "Max linhas" "$max_linhas" "$D_COMMENT" "$D_CYAN"
    __item "Saida" "$output_file" "$D_COMMENT" "$D_GREEN"
    echo ""

    __dossie_arquivos_avancado "$profundidade" "$PYTHON_EXEC" "$max_linhas" > "$output_file"

    local output_size=$(du -h "$output_file" | cut -f1)
    __ok "Dossie concluido: $output_file ($output_size)"
    echo ""
}

__dossie_capturar_ambiente() {
    local PYTHON_EXEC="$1"
    echo "Versao do Python:"
    if command -v "$PYTHON_EXEC" &>/dev/null; then
        "$PYTHON_EXEC" --version
        echo "  Caminho: $(which "$PYTHON_EXEC")"
    else
        echo "  Nao encontrado."
    fi

    echo "\nVersao do PIP:"
    if command -v "$PYTHON_EXEC" &>/dev/null; then
        "$PYTHON_EXEC" -m pip --version
    else
        echo "  Nao encontrado."
    fi

    echo "\nBibliotecas Instaladas (pip list):"
    if command -v "$PYTHON_EXEC" &>/dev/null; then
        "$PYTHON_EXEC" -m pip list
    else
        echo "  Nao foi possivel listar."
    fi
}

__git_diagnostico() {
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "Nao e um repositorio Git."
        return 1
    fi
    echo "Remotos:"
    git remote -v
    echo "\nBranch Atual:"
    git branch --show-current
    echo "\nUltimos 5 Commits:"
    git log --oneline --graph --decorate -n 5
    echo "\nStatus:"
    git status -s
}

__dossie_mostrar_progresso() {
    local current=$1
    local total=$2
    local etapa="$3"
    local arquivo="${4:-...}"
    local bar_width=30
    local percent=$((current * 100 / total))
    local filled=$((percent * bar_width / 100))
    local bar=""

    for ((i=0; i<filled; i++)); do bar+="\033[38;2;189;147;249m█\033[0m"; done
    for ((i=filled; i<bar_width; i++)); do bar+="\033[38;2;98;114;164m─\033[0m"; done

    printf "\r  \033[38;2;139;233;253m%-18s\033[0m [${bar}] \033[38;2;80;250;123m%3d%%\033[0m (%d/%d) \033[38;2;98;114;164m%s\033[0m\033[0K" \
        "$etapa" "$percent" "$current" "$total" "${arquivo:0:40}" >&2
}

# Exibe conteudo de um arquivo texto com limite de linhas
# .log mostra tail (ultimas linhas mais relevantes), demais mostra head
__dossie_exibir_texto() {
    local arquivo="$1"
    local limite="$2"

    if [ ! -s "$arquivo" ]; then
        echo "[ARQUIVO VAZIO]"
        return 0
    fi

    local total_linhas=$(wc -l < "$arquivo" 2>/dev/null | sed 's/ //g')
    local tamanho=$(du -h "$arquivo" 2>/dev/null | cut -f1)

    echo "[${total_linhas} linhas | ${tamanho}]"
    echo ""

    if [ "$total_linhas" -le "$limite" ]; then
        cat "$arquivo" 2>/dev/null
    elif [[ "$arquivo" == *.log ]]; then
        echo "... (mostrando ultimas ${limite} de ${total_linhas} linhas)"
        echo ""
        tail -n "$limite" "$arquivo" 2>/dev/null
    else
        head -n "$limite" "$arquivo" 2>/dev/null
        echo ""
        echo "... (truncado: ${limite}/${total_linhas} linhas)"
    fi
}

__dossie_arquivos_avancado() {
    local max_depth="$1"
    local PYTHON_EXEC="$2"
    local max_linhas="${3:-300}"
    local fast_timeout="15s"
    local intensive_timeout="90s"
    local nome_projeto=$(basename "$(pwd)")
    local analisador="${ZDOTDIR:-$HOME/.config/zsh}/scripts/analisador-dados.py"
    local failed_files_list=$(mktemp)
    trap 'rm -f "$failed_files_list"' EXIT

    local find_cmd=(find .)

    if [ "$max_depth" -ne 0 ]; then
        find_cmd+=(-maxdepth "$max_depth")
    fi

    find_cmd+=(-type d \(
        -name ".git" -o -name "venv" -o -name ".venv"
        -o -name "__pycache__" -o -name "node_modules"
        -o -name "*site-packages*" -o -name ".cache"
        -o -name ".idea" -o -name ".vscode"
        -o -name "target" -o -name "build" -o -name "dist"
    \) -prune
    -o -type f -not \(
        -name "*.png" -o -name "*.jpg" -o -name "*.jpeg"
        -o -name "*.gif" -o -name "*.svg"
        -o -name "*.mp3" -o -name "*.mp4" -o -name "*.avi" -o -name "*.mov"
        -o -name "*.zip" -o -name "*.tar" -o -name "*.gz" -o -name "*.rar"
        -o -name "*.o" -o -name "*.so" -o -name "*.a"
        -o -name "*.exe" -o -name "*.dll"
    \) -print)

    local all_files=$("${find_cmd[@]}")
    local total_files=$(echo "$all_files" | wc -l | sed 's/ //g')

    if [ "$total_files" -eq 0 ]; then
        echo "Nenhum arquivo relevante encontrado." >&2
        return 0
    fi

    echo "--- SUMARIO DO PROJETO: ${nome_projeto} ---"
    echo "Gerado em: $(date)"
    echo "Arquivos: ${total_files} | Max linhas/arquivo: ${max_linhas}"

    # Verificar e limpar emojis no projeto
    local emoji_guardian="${BORDO_DIR:-$HOME/Controle de Bordo}/.sistema/scripts/emoji_guardian.py"
    if [[ -f "$emoji_guardian" ]]; then
        echo -e "\n<details><summary><strong>VERIFICACAO DE EMOJIS</strong></summary>\n\n\`\`\`"
        local emoji_output=$(python3 "$emoji_guardian" check . 2>&1)
        local emoji_count
        emoji_count=$(echo "$emoji_output" | grep -c "ARQUIVO") || emoji_count=0
        if [[ "$emoji_count" -gt 0 ]]; then
            echo "[ALERTA] $emoji_count arquivo(s) com emojis encontrado(s)"
            echo "Limpando automaticamente..."
            python3 "$emoji_guardian" clean . --apply > /dev/null 2>&1
            echo "[OK] Emojis removidos"
        else
            echo "[OK] Nenhum emoji encontrado"
        fi
        echo -e "\n\`\`\`\n</details>"
    fi

    echo -e "\n<details><summary><strong>AMBIENTE</strong></summary>\n\n\`\`\`"
    __dossie_capturar_ambiente "$PYTHON_EXEC"
    echo -e "\n\`\`\`\n</details>"

    echo -e "\n<details><summary><strong>DIAGNOSTICO GIT</strong></summary>\n\n\`\`\`"
    __git_diagnostico
    echo -e "\n\`\`\`\n</details>"

    local ignore_pattern=".git|venv|.venv|__pycache__|node_modules|*site-packages*|.cache|target|build|dist"
    local depth_label="ILIMITADA"
    [ "$max_depth" -ne 0 ] && depth_label="$max_depth"

    echo -e "\n<details><summary><strong>ESTRUTURA (PROF. ${depth_label})</strong></summary>\n\n\`\`\`"
    local tree_cmd=(command tree -I "$ignore_pattern")
    [ "$max_depth" -ne 0 ] && tree_cmd+=(-L "$max_depth")
    "${tree_cmd[@]}"
    echo -e "\n\`\`\`\n</details>"

    if [ -f "README.md" ]; then
        if [ -s "README.md" ]; then
            echo -e "\n<details><summary><strong>README.MD</strong></summary>\n\n"
            head -n "$max_linhas" README.md
            local readme_lines=$(wc -l < README.md | sed 's/ //g')
            if [ "$readme_lines" -gt "$max_linhas" ]; then
                echo -e "\n... (truncado: ${max_linhas}/${readme_lines} linhas)"
            fi
            echo -e "\n</details>"
        else
            echo -e "\n<details><summary><strong>README.MD</strong></summary>\n\n[ARQUIVO VAZIO]\n</details>"
        fi
    fi

    echo -e "\n\n--- CONTEUDO DOS ARQUIVOS ---\n"

    echo "" >&2
    echo -e "  \033[38;2;189;147;249mETAPA 1/3:\033[0m Rastreio Rapido ($total_files arquivos, max ${max_linhas} linhas/arquivo)" >&2
    local current_file=0
    local total_linhas_output=0

    while read -r file; do
        ((current_file++))
        __dossie_mostrar_progresso $current_file $total_files "Rastreio Rapido" "$file"

        echo -e "\n<details><summary><code>$file</code></summary>\n\n\`\`\`"
        local exit_code=0

        case "$file" in
            *.csv|*.xlsx|*.xls|*.parquet|*.json)
                if [ -f "$analisador" ]; then
                    timeout "$fast_timeout" "$PYTHON_EXEC" "$analisador" "$file"
                else
                    head -n "$max_linhas" "$file" 2>/dev/null
                    local data_lines=$(wc -l < "$file" 2>/dev/null | sed 's/ //g')
                    if [ "$data_lines" -gt "$max_linhas" ]; then
                        echo -e "\n... (truncado: ${max_linhas}/${data_lines} linhas)"
                    fi
                fi
                exit_code=$?
                ;;
            *.md|*.txt|*.sh|*.py|*.zsh|*.toml|*.yaml|*.yml|*.ini|*.cfg|*.env|*.sql|*.log|*.gitignore|*.rst|*.conf)
                __dossie_exibir_texto "$file" "$max_linhas"
                exit_code=$?
                ;;
            *)
                if ! [ -s "$file" ]; then
                    echo "[ARQUIVO VAZIO]"
                elif grep -Iq . "$file"; then
                    head -n "$max_linhas" "$file"
                    local unk_lines=$(wc -l < "$file" 2>/dev/null | sed 's/ //g')
                    if [ "$unk_lines" -gt "$max_linhas" ]; then
                        echo -e "\n... (truncado: ${max_linhas}/${unk_lines} linhas)"
                    fi
                else
                    echo "[ARQUIVO BINARIO]"
                fi
                exit_code=$?
                ;;
        esac

        if [ $exit_code -eq 124 ]; then
            echo -e "\n[TIMEOUT] Analise rapida excedeu ${fast_timeout}."
            echo "$file" >> "$failed_files_list"
        fi
        echo -e "\n\`\`\`\n</details>"
    done <<< "$all_files"

    echo "" >&2
    echo -e "  \033[38;2;80;250;123m[OK]\033[0m Etapa 1 concluida." >&2

    if [ -s "$failed_files_list" ]; then
        local failed_count=$(wc -l < "$failed_files_list" | sed 's/ //g')
        local current_file=0
        echo -e "  \033[38;2;255;184;108mETAPA 2/3:\033[0m Reprocessando $failed_count arquivo(s)..." >&2

        while read -r file; do
            ((current_file++))
            __dossie_mostrar_progresso $current_file $failed_count "Reprocessamento" "$file"
            echo -e "\n<details open><summary><code>$file</code> (REPROCESSAMENTO)</summary>\n\n\`\`\`"

            if [ -f "$analisador" ]; then
                timeout "$intensive_timeout" "$PYTHON_EXEC" "$analisador" "$file"
            fi

            if [ $? -eq 124 ]; then
                echo -e "\n[IRRECUPERAVEL] Excedeu ${intensive_timeout}."
            fi
            echo -e "\n\`\`\`\n</details>"
        done < "$failed_files_list"

        echo "" >&2
        echo -e "  \033[38;2;80;250;123m[OK]\033[0m Etapa 2 concluida." >&2
    else
        echo -e "  \033[38;2;98;114;164mETAPA 2/3:\033[0m Nenhum reprocessamento necessario." >&2
    fi

    echo -e "  \033[38;2;98;114;164mETAPA 3/3:\033[0m Finalizando dossie..." >&2

    local output_total_linhas=$(wc -l < /dev/stdin 2>/dev/null || echo "?")

    echo ""
    read -k 1 "reply?  Abrir no Antigravity? (s/N) "
    echo ""
    if [[ "$reply" == "s" || "$reply" == "S" ]]; then
        levitar .
    fi
}

# Proposito: Reconstruir arquivos a partir de um diagnostico .md
# Uso: reconstruir_diagnostico <arquivo.md>
reconstruir_diagnostico() {
    local arquivo_entrada="$1"

    if [ -z "$arquivo_entrada" ]; then
        echo -e "  ${D_COMMENT}Uso: reconstruir_diagnostico <arquivo_diagnostico.md>${D_RESET}"
        return 1
    fi

    if [ ! -f "$arquivo_entrada" ]; then
        __err "'$arquivo_entrada' nao existe."
        return 1
    fi

    local nome_base=$(basename "$arquivo_entrada" .md)
    local dir_pai=$(dirname "$arquivo_entrada")
    local dir_destino="${dir_pai}/${nome_base}"
    local script_helper="${ZDOTDIR:-$HOME/.config/zsh}/scripts/reconstrutor-helper.py"

    __header "RECONSTRUIR DIAGNOSTICO" "$D_ORANGE"
    __item "Entrada" "$arquivo_entrada" "$D_COMMENT" "$D_FG"
    __item "Destino" "$dir_destino" "$D_COMMENT" "$D_CYAN"
    echo ""

    if [ -d "$dir_destino" ]; then
        __warn "Pasta ja existe. Arquivos podem ser sobrescritos."
    else
        mkdir -p "$dir_destino"
    fi

    if [ ! -f "$script_helper" ]; then
        __err "Script auxiliar nao encontrado: $script_helper"
        return 1
    fi

    python3 "$script_helper" "$arquivo_entrada" "$dir_destino"

    __ok "Reconstrucao concluida."
    echo ""
}
