#!/bin/zsh

# Propósito: Gerar dossiê completo de um projeto (ambiente, git, árvore, conteúdo)
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

    __header "DIAGNÓSTICO: $nome_projeto" "$D_PURPLE"
    __item "Profundidade" "$depth_label" "$D_COMMENT" "$D_CYAN"
    __item "Max linhas" "$max_linhas" "$D_COMMENT" "$D_CYAN"
    __item "Saída" "$output_file" "$D_COMMENT" "$D_GREEN"
    echo ""

    __dossie_arquivos_avancado "$profundidade" "$PYTHON_EXEC" "$max_linhas" > "$output_file"

    local output_size=$(du -h "$output_file" | cut -f1)
    __ok "Dossiê concluído: $output_file ($output_size)"
    echo ""

    local reply
    read -k 1 "reply?  Abrir no Antigravity? (s/N) "
    echo ""
    if [[ "$reply" == "s" || "$reply" == "S" ]]; then
        levitar .
    fi
}

__dossie_capturar_ambiente() {
    local PYTHON_EXEC="$1"
    echo "Versão do Python:"
    if command -v "$PYTHON_EXEC" &>/dev/null; then
        "$PYTHON_EXEC" --version
        echo "  Caminho: $(which "$PYTHON_EXEC")"
    else
        echo "  Não encontrado."
    fi

    echo "\nVersão do PIP:"
    if command -v "$PYTHON_EXEC" &>/dev/null; then
        "$PYTHON_EXEC" -m pip --version
    else
        echo "  Não encontrado."
    fi

    echo "\nBibliotecas Instaladas (pip list):"
    if command -v "$PYTHON_EXEC" &>/dev/null; then
        "$PYTHON_EXEC" -m pip list
    else
        echo "  Não foi possível listar."
    fi
}

__git_diagnostico() {
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "Não é um repositório Git."
        return 1
    fi
    echo "Remotos:"
    git remote -v
    echo "\nBranch Atual:"
    git branch --show-current
    echo "\nÚltimos 5 Commits:"
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

# Exibe conteúdo de um arquivo texto com limite de linhas
# .log mostra tail (últimas linhas mais relevantes), demais mostra head
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
        echo "... (mostrando últimas ${limite} de ${total_linhas} linhas)"
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
    local passwords_file=$(mktemp)
    trap 'rm -f "$failed_files_list" "$passwords_file"' EXIT

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
        -name "*.mp3" -o -name "*.mp4" -o -name "*.avi" -o -name "*.mov"
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

    echo "# Diagnóstico — ${nome_projeto}"
    echo ""
    echo "**Gerado em:** $(date) · **Arquivos:** ${total_files} · **Max linhas/arquivo:** ${max_linhas}"
    echo ""
    echo "---"

    # Verificar e limpar emojis no projeto
    local emoji_guardian="${BORDO_DIR:-$HOME/Controle de Bordo}/.sistema/scripts/emoji_guardian.py"
    if [[ -f "$emoji_guardian" ]]; then
        echo ""
        echo "## Verificação de Emojis"
        echo ""
        echo "<details>"
        echo "<summary>Resultado da verificação automática</summary>"
        echo ""
        echo '```'
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
        echo '```'
        echo ""
        echo "</details>"
        echo ""
        echo "---"
    fi

    echo ""
    echo "## Ambiente Python"
    echo ""
    echo "<details>"
    echo "<summary>Dependências e versões</summary>"
    echo ""
    echo '```'
    __dossie_capturar_ambiente "$PYTHON_EXEC"
    echo '```'
    echo ""
    echo "</details>"
    echo ""
    echo "---"

    echo ""
    echo "## Git"
    echo ""
    echo "<details>"
    echo "<summary>Status do repositório</summary>"
    echo ""
    echo '```'
    __git_diagnostico
    echo '```'
    echo ""
    echo "</details>"
    echo ""
    echo "---"

    local ignore_pattern=".git|venv|.venv|__pycache__|node_modules|*site-packages*|.cache|target|build|dist"
    local depth_label="ilimitada"
    [ "$max_depth" -ne 0 ] && depth_label="$max_depth"

    echo ""
    echo "## Estrutura (profundidade: ${depth_label})"
    echo ""
    echo '```'
    local tree_cmd=(command tree -I "$ignore_pattern")
    [ "$max_depth" -ne 0 ] && tree_cmd+=(-L "$max_depth")
    "${tree_cmd[@]}"
    echo '```'
    echo ""
    echo "---"

    if [ -f "README.md" ]; then
        echo ""
        echo "## README"
        echo ""
        if [ -s "README.md" ]; then
            head -n "$max_linhas" README.md
            local readme_lines=$(wc -l < README.md | sed 's/ //g')
            if [ "$readme_lines" -gt "$max_linhas" ]; then
                echo ""
                echo "... (truncado: ${max_linhas}/${readme_lines} linhas)"
            fi
        else
            echo "*Arquivo vazio.*"
        fi
        echo ""
        echo "---"
    fi

    echo ""
    echo "## Conteúdo dos Arquivos"
    echo ""
    echo "> ${total_files} arquivos mapeados"
    echo ""

    echo "" >&2
    echo -e "  \033[38;2;189;147;249mETAPA 1/3:\033[0m Rastreio Rápido ($total_files arquivos, max ${max_linhas} linhas/arquivo)" >&2
    local current_file=0

    while read -r file; do
        ((current_file++))
        __dossie_mostrar_progresso $current_file $total_files "Rastreio Rápido" "$file"

        local exit_code=0
        local tipo

        case "$file" in
            *.pdf)   tipo="PDF"    ;;
            *.csv)   tipo="CSV"    ;;
            *.xlsx)  tipo="Excel"  ;;
            *.xls)   tipo="Excel"  ;;
            *.parquet) tipo="Parquet" ;;
            *.json)  tipo="JSON"   ;;
            *.jpg|*.jpeg|*.png|*.gif|*.svg|*.webp|*.bmp|*.tiff|*.tif|*.heic|*.avif)
                     tipo="Imagem" ;;
            *.md)    tipo="Markdown" ;;
            *.py)    tipo="Python" ;;
            *.sh|*.zsh) tipo="Script" ;;
            *.sql)   tipo="SQL"    ;;
            *.yaml|*.yml) tipo="YAML" ;;
            *.toml)  tipo="TOML"   ;;
            *.txt)   tipo="Texto"  ;;
            *.log)   tipo="Log"    ;;
            *.env)   tipo="Env"    ;;
            *)       tipo="Arquivo" ;;
        esac

        case "$file" in
            *.pdf|*.csv|*.xlsx|*.xls|*.parquet|*.json)
                echo ""
                echo "<details>"
                echo "<summary><b>[${tipo}]</b> <code>${file}</code></summary>"
                echo ""
                if [ -f "$analisador" ]; then
                    timeout "$fast_timeout" "$PYTHON_EXEC" "$analisador" "$file" --passwords-file "$passwords_file"
                    exit_code=$?
                    if [ $exit_code -eq 125 ]; then
                        echo "" >&2
                        local new_senha
                        print -n "  Senha para '${file:t}': " >&2
                        read -rs new_senha < /dev/tty
                        echo "" >&2
                        echo "$new_senha" >> "$passwords_file"
                        timeout "$fast_timeout" "$PYTHON_EXEC" "$analisador" "$file" --passwords-file "$passwords_file"
                        exit_code=$?
                        if [ $exit_code -eq 125 ]; then
                            echo ""
                            echo "[SENHA INCORRETA] Nenhuma senha do pool abriu este arquivo."
                            exit_code=0
                        fi
                    fi
                else
                    echo '```'
                    head -n "$max_linhas" "$file" 2>/dev/null
                    local data_lines=$(wc -l < "$file" 2>/dev/null | sed 's/ //g')
                    if [ "$data_lines" -gt "$max_linhas" ]; then
                        echo ""
                        echo "... (truncado: ${max_linhas}/${data_lines} linhas)"
                    fi
                    echo '```'
                    exit_code=$?
                fi
                ;;
            *.jpg|*.jpeg|*.png|*.gif|*.svg|*.webp|*.bmp|*.tiff|*.tif|*.heic|*.avif)
                echo ""
                echo "<details>"
                echo "<summary><b>[${tipo}]</b> <code>${file}</code></summary>"
                echo ""
                if [ -f "$analisador" ]; then
                    timeout "$fast_timeout" "$PYTHON_EXEC" "$analisador" "$file" --passwords-file "$passwords_file"
                fi
                exit_code=$?
                ;;
            *.md|*.txt|*.sh|*.py|*.zsh|*.toml|*.yaml|*.yml|*.ini|*.cfg|*.env|*.sql|*.log|*.gitignore|*.rst|*.conf)
                echo ""
                echo "<details>"
                echo "<summary><b>[${tipo}]</b> <code>${file}</code></summary>"
                echo ""
                echo '```'
                __dossie_exibir_texto "$file" "$max_linhas"
                exit_code=$?
                echo '```'
                ;;
            *)
                echo ""
                echo "<details>"
                echo "<summary><b>[${tipo}]</b> <code>${file}</code></summary>"
                echo ""
                echo '```'
                if ! [ -s "$file" ]; then
                    echo "[ARQUIVO VAZIO]"
                elif grep -Iq . "$file"; then
                    head -n "$max_linhas" "$file"
                    local unk_lines=$(wc -l < "$file" 2>/dev/null | sed 's/ //g')
                    if [ "$unk_lines" -gt "$max_linhas" ]; then
                        echo ""
                        echo "... (truncado: ${max_linhas}/${unk_lines} linhas)"
                    fi
                else
                    echo "[ARQUIVO BINÁRIO]"
                fi
                exit_code=$?
                echo '```'
                ;;
        esac

        if [ $exit_code -eq 124 ]; then
            echo ""
            echo "[TIMEOUT] Análise rápida excedeu ${fast_timeout}."
            echo "$file" >> "$failed_files_list"
        fi
        echo ""
        echo "</details>"
    done <<< "$all_files"

    echo "" >&2
    echo -e "  \033[38;2;80;250;123m[OK]\033[0m Etapa 1 concluída." >&2

    if [ -s "$failed_files_list" ]; then
        local failed_count=$(wc -l < "$failed_files_list" | sed 's/ //g')
        local current_file=0
        echo -e "  \033[38;2;255;184;108mETAPA 2/3:\033[0m Reprocessando $failed_count arquivo(s)..." >&2

        while read -r file; do
            ((current_file++))
            __dossie_mostrar_progresso $current_file $failed_count "Reprocessamento" "$file"

            echo ""
            echo "<details open>"
            echo "<summary><b>[Reprocessamento]</b> <code>${file}</code></summary>"
            echo ""

            if [ -f "$analisador" ]; then
                timeout "$intensive_timeout" "$PYTHON_EXEC" "$analisador" "$file" --passwords-file "$passwords_file"
                local reprocess_code=$?
                if [ $reprocess_code -eq 125 ]; then
                    echo "" >&2
                    local new_senha
                    print -n "  Senha para '${file:t}': " >&2
                    read -rs new_senha < /dev/tty
                    echo "" >&2
                    echo "$new_senha" >> "$passwords_file"
                    timeout "$intensive_timeout" "$PYTHON_EXEC" "$analisador" "$file" --passwords-file "$passwords_file"
                    reprocess_code=$?
                    if [ $reprocess_code -eq 125 ]; then
                        echo ""
                        echo "[SENHA INCORRETA] Nenhuma senha do pool abriu este arquivo."
                    elif [ $reprocess_code -eq 124 ]; then
                        echo ""
                        echo "[IRRECUPERÁVEL] Excedeu ${intensive_timeout}."
                    fi
                elif [ $reprocess_code -eq 124 ]; then
                    echo ""
                    echo "[IRRECUPERÁVEL] Excedeu ${intensive_timeout}."
                fi
            fi
            echo ""
            echo "</details>"
        done < "$failed_files_list"

        echo "" >&2
        echo -e "  \033[38;2;80;250;123m[OK]\033[0m Etapa 2 concluída." >&2
    else
        echo -e "  \033[38;2;98;114;164mETAPA 2/3:\033[0m Nenhum reprocessamento necessário." >&2
    fi

    echo -e "  \033[38;2;98;114;164mETAPA 3/3:\033[0m Finalizando dossiê..." >&2
}

# Propósito: Reconstruir arquivos a partir de um diagnóstico .md
# Uso: reconstruir_diagnostico <arquivo.md>
reconstruir_diagnostico() {
    local arquivo_entrada="$1"

    if [ -z "$arquivo_entrada" ]; then
        echo -e "  ${D_COMMENT}Uso: reconstruir_diagnostico <arquivo_diagnostico.md>${D_RESET}"
        return 1
    fi

    if [ ! -f "$arquivo_entrada" ]; then
        __err "'$arquivo_entrada' não existe."
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
        __warn "Pasta já existe. Arquivos podem ser sobrescritos."
    else
        mkdir -p "$dir_destino"
    fi

    if [ ! -f "$script_helper" ]; then
        __err "Script auxiliar não encontrado: $script_helper"
        return 1
    fi

    python3 "$script_helper" "$arquivo_entrada" "$dir_destino"

    __ok "Reconstrução concluída."
    echo ""
}
