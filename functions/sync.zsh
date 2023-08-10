#!/bin/zsh

sincronizar_controle_de_bordo() {
    local auto=0 dry_run=0 show_stats=0 docs_only=0 cleanup=0 check_size=0
    for arg in "$@"; do
        case "$arg" in
            --auto) auto=1 ;;
            --dry-run) dry_run=1 ;;
            --stats) show_stats=1 ;;
            --docs-only) docs_only=1 ;;
            --cleanup) cleanup=1 ;;
            --check-size) check_size=1 ;;
            *) __err "Flag desconhecida: $arg"; return 1 ;;
        esac
    done

    __verificar_dependencias "rsync" || return 1

    local base_dir="${DEV_DIR:-$HOME/Desenvolvimento}"
    local bordo_dir="${BORDO_DIR:-$HOME/Controle de Bordo}"
    local doc_dir="$bordo_dir/Documentacao"
    local arquivo_dir="$bordo_dir/99_Arquivo"

    if [[ ! -d "$base_dir" ]]; then
        __err "Diretorio de desenvolvimento nao encontrado: $base_dir"
        return 1
    fi
    [[ ! -d "$doc_dir" ]] && mkdir -p "$doc_dir"

    # Verificar tamanho atual do vault
    if (( check_size )) || (( ! dry_run )); then
        local vault_size=$(du -sb "$bordo_dir" 2>/dev/null | cut -f1)
        local vault_size_mb=$((vault_size / 1024 / 1024))
        local limit_mb=1024
        local warning_threshold=800

        if (( vault_size_mb > limit_mb )); then
            __err "Vault excede 1GB ($vault_size_mb MB). Limpe antes de sincronizar."
            echo "  Dica: Use --docs-only ou limpe a pasta 99_Arquivo/"
            return 1
        elif (( vault_size_mb > warning_threshold )); then
            __warn "Vault proximo do limite: $vault_size_mb MB / $limit_mb MB"
            if (( ! auto )); then
                echo "  Continuar mesmo assim? (S/n)"
                read -k 1 reply
                echo ""
                [[ "$reply" == [Nn] ]] && return 0
            fi
        fi
    fi

    # Limpeza automatica se solicitada
    if (( cleanup )); then
        __header "LIMPEZA DO VAULT" "$D_CYAN"

        # Limpar caches Python
        find "$bordo_dir" -type d \( -name "__pycache__" -o -name ".pytest_cache" -o -name ".mypy_cache" -o -name ".ruff_cache" -o -name "htmlcov" \) -exec rm -rf {} + 2>/dev/null
        echo "  ${D_GREEN}Caches Python removidos${D_RESET}"

        # Limpar arquivos vazios na Inbox
        find "$bordo_dir/05_Diario/2026" -type f -size 0 -delete 2>/dev/null
        echo "  ${D_GREEN}Arquivos vazios removidos${D_RESET}"

        # Limpar backups antigos
        if [[ -d "$bordo_dir/_reorganizacao_backup" ]]; then
            local backup_age=$(( ($(date +%s) - $(stat -c %Y "$bordo_dir/_reorganizacao_backup" 2>/dev/null || echo 0)) / 86400 ))
            if (( backup_age > 7 )); then
                rm -rf "$bordo_dir/_reorganizacao_backup"
                echo "  ${D_GREEN}Backup antigo removido ($backup_age dias)${D_RESET}"
            fi
        fi

        echo ""
    fi

    local -a rsync_filters=()

    # Exclusoes padrao (diretorios)
    local -a exclude_dirs=(
        venv .venv env .env node_modules vendor
        site-packages .tox .nox .eggs
        __pycache__ .cache .pytest_cache .mypy_cache .ruff_cache
        htmlcov .coverage .hypothesis
        build dist target releases output outputs results
        .git .svn .hg
        .idea .vscode
        data datasets models checkpoints weights
        data_input data_output raw_data processed_data
        logs log tmp temp
        .ipynb_checkpoints .secrets
    )
    for d in "${exclude_dirs[@]}"; do
        rsync_filters+=(--exclude="$d/")
    done
    rsync_filters+=(--exclude='*.egg-info/')

    # Se --docs-only, excluir codigo fonte tambem
    if (( docs_only )); then
        rsync_filters+=(--exclude='src/')
        rsync_filters+=(--exclude='lib/')
        rsync_filters+=(--exclude='bin/')
        rsync_filters+=(--exclude='obj/')
        rsync_filters+=(--exclude='*.py' --exclude='*.js' --exclude='*.ts')
        rsync_filters+=(--exclude='*.rs' --exclude='*.go' --exclude='*.java')
        rsync_filters+=(--exclude='*.c' --exclude='*.cpp' --exclude='*.h')
    fi

    # Exclusoes de arquivos sensiveis
    rsync_filters+=(
        --exclude='.env'
        --exclude='.env.local'
        --exclude='.env.production'
        --exclude='.env.development'
        --exclude='.env.staging'
        --exclude='.git-credentials'
        --exclude='credentials.json'
        --exclude='secrets.json'
        --exclude='*.key'
        --exclude='*.pem'
        --exclude='*.p12'
        --exclude='*.pfx'
    )

    # Limitar tamanho de arquivo (evitar arquivos muito grandes)
    rsync_filters+=(--max-size=10M)

    rsync_filters+=(--include='*/')

    # Extensoes permitidas
    local -a include_exts=(
        md txt rst
        py sh zsh bash
        js ts jsx tsx
        json yaml yml toml
        ini cfg conf
        sql r R
        rs go java
        html css scss
        xml csv
        tf hcl
        ipynb
    )
    for ext in "${include_exts[@]}"; do
        rsync_filters+=(--include="*.$ext")
    done

    # Arquivos especiais permitidos
    rsync_filters+=(
        --include='Dockerfile'
        --include='Makefile'
        --include='Cargo.toml'
        --include='Cargo.lock'
        --include='package.json'
        --include='package-lock.json'
        --include='requirements*.txt'
        --include='setup.py'
        --include='pyproject.toml'
        --include='LICENSE'
        --include='CHANGELOG*'
        --include='README*'
        --include='CLAUDE*'
        --include='ROADMAP*'
        --include='CONTRIBUTING*'
        --include='SECURITY*'
        --include='CODE_OF_CONDUCT*'
    )

    rsync_filters+=(--exclude='*')

    local -a rsync_base=(-a --prune-empty-dirs)

    __header "SINCRONIZAR CONTROLE DE BORDO" "$D_CYAN"

    # Mostrar info do vault
    local current_size=$(du -sh "$bordo_dir" 2>/dev/null | cut -f1)
    echo -e "  ${D_COMMENT}Vault atual: ${D_FG}$current_size${D_RESET}"
    echo -e "  ${D_COMMENT}Origem:  ${D_FG}$base_dir${D_RESET}"
    echo -e "  ${D_COMMENT}Destino: ${D_FG}$doc_dir${D_RESET}"

    if (( docs_only )); then
        echo -e "  ${D_YELLOW}Modo: Apenas documentacao (sem codigo)${D_RESET}"
    fi
    echo ""
    echo -e "  ${D_COMMENT}Rastreando...${D_RESET}"

    local preview_output
    preview_output=$(rsync "${rsync_base[@]}" --dry-run --out-format=$'%l\t%n' \
        "${rsync_filters[@]}" "$base_dir/" "$doc_dir/" 2>/dev/null)

    local file_list
    file_list=$(echo "$preview_output" | grep -P '^\d+\t' | grep -v '/$')

    local file_count=0
    local total_bytes=0

    if [[ -n "$file_list" ]]; then
        file_count=$(echo "$file_list" | wc -l | tr -d ' ')
        total_bytes=$(echo "$file_list" | awk -F'\t' '{sum += $1} END {print sum+0}')
    fi

    local size_human
    if (( total_bytes >= 1073741824 )); then
        size_human=$(awk "BEGIN {printf \"%.1f GB\", $total_bytes/1073741824}")
    elif (( total_bytes >= 1048576 )); then
        size_human=$(awk "BEGIN {printf \"%.1f MB\", $total_bytes/1048576}")
    elif (( total_bytes >= 1024 )); then
        size_human=$(awk "BEGIN {printf \"%.1f KB\", $total_bytes/1024}")
    else
        size_human="${total_bytes} B"
    fi

    if [[ $file_count -eq 0 ]]; then
        __ok "Tudo sincronizado. Nenhum arquivo novo ou modificado."
        echo ""
        return 0
    fi

    # Verificar se sincronizacao excederia o limite
    local projected_size=$((vault_size + total_bytes))
    local projected_mb=$((projected_size / 1024 / 1024))

    if (( projected_mb > limit_mb )); then
        __err "Sincronizacao excederia 1GB (projecao: $projected_mb MB)"
        echo "  Arquivos pendentes: $file_count ($size_human)"
        echo "  Dica: Use --docs-only para sincronizar apenas documentacao"
        return 1
    fi

    echo -e "  ${D_CYAN}${file_count}${D_RESET} ${D_FG}arquivo(s) a sincronizar (${size_human})${D_RESET}"
    echo -e "  ${D_COMMENT}Projecao: ${vault_size_mb} MB -> $projected_mb MB${D_RESET}"
    echo ""

    echo -e "  ${D_PURPLE}Preview (10 maiores):${D_RESET}"
    echo "$file_list" | sort -t$'\t' -k1 -rn | head -10 | while IFS=$'\t' read -r fsize fname; do
        local size_fmt
        if (( fsize >= 1048576 )); then
            size_fmt=$(awk "BEGIN {printf \"%.1f MB\", $fsize/1048576}")
        elif (( fsize >= 1024 )); then
            size_fmt=$(awk "BEGIN {printf \"%.0f KB\", $fsize/1024}")
        else
            size_fmt="${fsize} B"
        fi
        printf "  ${D_COMMENT}|${D_RESET} ${D_GREEN}%-50s${D_RESET} ${D_FG}%8s${D_RESET}\n" "${fname:0:50}" "$size_fmt"
    done
    echo ""

    if (( dry_run )); then
        __ok "Dry-run concluido. Nenhum arquivo foi copiado."
        echo ""
        return 0
    fi

    if (( ! auto )); then
        echo -e "  ${D_FG}(S)incronizar  (P)review completo  (C)ancelar${D_RESET}"
        read -k 1 "reply?  > "
        echo ""

        case "$reply" in
            [Pp])
                echo ""
                echo -e "  ${D_PURPLE}Lista completa:${D_RESET}"
                echo "$file_list" | sort -t$'\t' -k2 | while IFS=$'\t' read -r _ fname; do
                    echo -e "  ${D_COMMENT}|${D_RESET} ${D_FG}${fname}${D_RESET}"
                done
                echo ""
                echo -e "  ${D_FG}(S)incronizar  (C)ancelar${D_RESET}"
                read -k 1 "reply?  > "
                echo ""
                if [[ "$reply" != [Ss] ]]; then
                    echo -e "  ${D_COMMENT}Cancelado.${D_RESET}"
                    echo ""
                    return 0
                fi
                ;;
            [Ss]|"") ;;
            *)
                echo -e "  ${D_COMMENT}Cancelado.${D_RESET}"
                echo ""
                return 0
                ;;
        esac
    fi

    echo ""
    local -a rsync_exec=("${rsync_base[@]}")
    (( show_stats )) && rsync_exec+=(--stats)

    local sync_output
    sync_output=$(rsync "${rsync_exec[@]}" "${rsync_filters[@]}" "$base_dir/" "$doc_dir/" 2>&1)
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        __err "rsync falhou (exit code: $exit_code)"
        echo "$sync_output" | tail -5
        return 1
    fi

    if (( show_stats )); then
        echo "$sync_output" | grep -E "^(Number|Total|Literal|Matched)" | while IFS= read -r stat_line; do
            echo -e "  ${D_COMMENT}${stat_line}${D_RESET}"
        done
        echo ""
    fi

    __ok "${file_count} arquivo(s) sincronizado(s) (${size_human})."

    # Mostrar tamanho final
    local final_size=$(du -sh "$bordo_dir" 2>/dev/null | cut -f1)
    echo -e "  ${D_COMMENT}Vault: $current_size -> $final_size${D_RESET}"
    echo ""

    # Verificar e limpar emojis nos arquivos sincronizados
    local emoji_guardian="$bordo_dir/.sistema/scripts/emoji_guardian.py"
    if [[ -f "$emoji_guardian" ]]; then
        echo -e "  ${D_COMMENT}Verificando emojis nos arquivos sincronizados...${D_RESET}"
        local emoji_check=$(python3 "$emoji_guardian" check "$doc_dir" 2>&1)
        local emoji_count
        emoji_count=$(echo "$emoji_check" | grep -c "ARQUIVO") || emoji_count=0

        if [[ "$emoji_count" -gt 0 ]]; then
            echo -e "  ${D_YELLOW}$emoji_count arquivo(s) com emojis encontrado(s)${D_RESET}"
            echo -e "  ${D_COMMENT}Limpando...${D_RESET}"
            python3 "$emoji_guardian" clean "$doc_dir" --apply > /dev/null 2>&1
            echo -e "  ${D_GREEN}Emojis removidos${D_RESET}"
        else
            echo -e "  ${D_GREEN}Nenhum emoji encontrado${D_RESET}"
        fi
        echo ""
    fi
}

# Alias para limpeza rapida
alias limpar_vault='sincronizar_controle_de_bordo --cleanup --check-size'
alias sync_docs='sincronizar_controle_de_bordo --docs-only --auto'
