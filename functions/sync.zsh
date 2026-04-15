#!/bin/zsh

sincronizar_controle_de_bordo() {
    local auto=0 dry_run=0 show_stats=0 cleanup=0 check_size=0
    for arg in "$@"; do
        case "$arg" in
            --auto) auto=1 ;;
            --dry-run) dry_run=1 ;;
            --stats) show_stats=1 ;;
            --cleanup) cleanup=1 ;;
            --check-size) check_size=1 ;;
            *) __err "Flag desconhecida: $arg"; return 1 ;;
        esac
    done

    # Modo dry-run ativo por padrão quando chamado sem flags de execução
    if (( ! auto )) && (( ! dry_run )); then
        dry_run=1
        echo -e "  ${D_YELLOW}Modo dry-run ativo por padrão. Use --auto para executar.${D_RESET}"
    fi

    __verificar_dependencias "rsync" || return 1

    local base_dir="${DEV_DIR:-$HOME/Desenvolvimento}"
    local bordo_dir="${BORDO_DIR:-$HOME/Controle de Bordo}"

    if [[ ! -d "$base_dir" ]]; then
        __err "Diretório de desenvolvimento não encontrado: $base_dir"
        return 1
    fi

    # Mapeamento repo -> destino no vault (apenas documentação)
    typeset -A REPO_MAP=(
        [Luna]="Projetos/Luna"
        [Financas]="Pessoal/Casal/Financeiro/Código"
        [Controle_de_Bordo_OS]="Projetos/Controle de Bordo OS"
    )

    # Repos para ignorar
    local -a REPO_SKIP=(Spellbook-OS)

    # Variáveis de tamanho (inicializadas antes do bloco condicional)
    local vault_size=0 vault_size_mb=0 limit_mb=1024 warning_threshold=800

    # Verificar tamanho atual do vault
    if (( check_size )) || (( ! dry_run )); then
        vault_size=$(du -sb "$bordo_dir" 2>/dev/null | cut -f1)
        vault_size_mb=$((vault_size / 1024 / 1024))

        if (( vault_size_mb > limit_mb )); then
            __err "Vault excede 1GB ($vault_size_mb MB). Limpe antes de sincronizar."
            echo "  Dica: Limpe a pasta Arquivo/ ou remova arquivos desnecessários."
            return 1
        elif (( vault_size_mb > warning_threshold )); then
            __warn "Vault próximo do limite: $vault_size_mb MB / $limit_mb MB"
            if (( ! auto )); then
                echo "  Continuar mesmo assim? (S/n)"
                read -k 1 reply
                echo ""
                [[ "$reply" == [Nn] ]] && return 0
            fi
        fi
    fi

    # Limpeza automática se solicitada
    if (( cleanup )); then
        __header "LIMPEZA DO VAULT" "$D_CYAN"

        # Limpar caches Python
        find "$bordo_dir" -type d \( -name "__pycache__" -o -name ".pytest_cache" -o -name ".mypy_cache" -o -name ".ruff_cache" -o -name "htmlcov" \) -exec rm -rf {} + 2>/dev/null
        echo "  ${D_GREEN}Caches Python removidos${D_RESET}"

        # Limpar arquivos vazios no Diário
        find "$bordo_dir/Diario/2026" -type f -size 0 -delete 2>/dev/null
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

    # Exclusões padrão (diretórios)
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

    # Exclusões de arquivos sensíveis
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

    # Limitar tamanho de arquivo
    rsync_filters+=(--max-size=10M)

    rsync_filters+=(--include='*/')

    # Extensões permitidas (apenas documentação)
    local -a include_exts=(
        md txt rst
        yaml yml toml
        ini cfg conf
    )
    for ext in "${include_exts[@]}"; do
        rsync_filters+=(--include="*.$ext")
    done

    # Arquivos especiais permitidos
    rsync_filters+=(
        --include='Dockerfile'
        --include='Makefile'
        --include='requirements*.txt'
        --include='pyproject.toml'
        --include='LICENSE'
        --include='CHANGELOG*'
        --include='README*'
        --include='ROADMAP*'
        --include='CONTRIBUTING*'
        --include='SECURITY*'
        --include='CODE_OF_CONDUCT*'
    )

    rsync_filters+=(--exclude='*')

    local -a rsync_base=(-a --prune-empty-dirs)

    __header "SINCRONIZAR CONTROLE DE BORDO" "$D_CYAN"

    # Mostrar informações do vault
    local current_size=$(du -sh "$bordo_dir" 2>/dev/null | cut -f1)
    echo -e "  ${D_COMMENT}Vault atual: ${D_FG}$current_size${D_RESET}"
    echo -e "  ${D_COMMENT}Origem:  ${D_FG}$base_dir${D_RESET}"
    echo -e "  ${D_YELLOW}Modo: Apenas documentação${D_RESET}"
    echo ""
    echo -e "  ${D_COMMENT}Rastreando...${D_RESET}"

    # Resolver origem e destino de cada repo
    __resolve_repo_sync() {
        local repo_name="$1"
        local repo_path="$base_dir/$repo_name"

        # Ignorar se não é diretório
        [[ ! -d "$repo_path" ]] && return 1

        # Ignorar repos em REPO_SKIP
        for skip in "${REPO_SKIP[@]}"; do
            [[ "$repo_name" == "$skip" ]] && return 1
        done

        local src dest

        if [[ -n "${REPO_MAP[$repo_name]}" ]]; then
            src="$repo_path"
            dest="$bordo_dir/${REPO_MAP[$repo_name]}"
        else
            src="$repo_path"
            dest="$bordo_dir/Projetos/Outros/$repo_name"
        fi

        echo "${src}|${dest}"
    }

    # Coletar todos os pares origem:destino
    local -a sync_pairs=()
    for entry in "$base_dir"/*(N/); do
        local repo_name="${entry:t}"
        local pair
        pair=$(__resolve_repo_sync "$repo_name") || continue
        sync_pairs+=("$pair")
    done

    unfunction __resolve_repo_sync 2>/dev/null

    if [[ ${#sync_pairs[@]} -eq 0 ]]; then
        __ok "Nenhum repositório encontrado para sincronizar."
        echo ""
        return 0
    fi

    # Dry-run agregado: coletar preview de todos os repos
    local all_file_list=""

    for pair in "${sync_pairs[@]}"; do
        local src="${pair%%|*}"
        local dest="${pair#*|}"

        local repo_preview
        repo_preview=$(rsync "${rsync_base[@]}" --dry-run --out-format=$'%l\t%n' \
            "${rsync_filters[@]}" "$src/" "$dest/" 2>/dev/null)

        local repo_files
        repo_files=$(echo "$repo_preview" | grep -P '^\d+\t' | grep -v '/$')

        if [[ -n "$repo_files" ]]; then
            # Prefixar com nome legível do destino relativo ao vault
            local rel_dest="${dest#$bordo_dir/}"
            while IFS=$'\t' read -r fsize fname; do
                all_file_list+="${fsize}\t${rel_dest}/${fname}\n"
            done <<< "$repo_files"
        fi
    done

    # Remover trailing newline e linhas vazias
    all_file_list=$(echo -e "$all_file_list" | grep -P '^\d+\t')

    local file_count=0
    local total_bytes=0

    if [[ -n "$all_file_list" ]]; then
        file_count=$(echo "$all_file_list" | wc -l | tr -d ' ')
        total_bytes=$(echo "$all_file_list" | awk -F'\t' '{sum += $1} END {print sum+0}')
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

    # Verificar se sincronização excederia o limite
    local projected_size=$((vault_size + total_bytes))
    local projected_mb=$((projected_size / 1024 / 1024))

    if (( projected_mb > limit_mb )); then
        __err "Sincronização excederia 1GB (projeção: $projected_mb MB)"
        echo "  Arquivos pendentes: $file_count ($size_human)"
        return 1
    fi

    echo -e "  ${D_CYAN}${file_count}${D_RESET} ${D_FG}arquivo(s) a sincronizar (${size_human})${D_RESET}"
    echo -e "  ${D_COMMENT}Projeção: ${vault_size_mb} MB -> $projected_mb MB${D_RESET}"
    echo ""

    echo -e "  ${D_PURPLE}Preview (10 maiores):${D_RESET}"
    echo "$all_file_list" | sort -t$'\t' -k1 -rn | head -10 | while IFS=$'\t' read -r fsize fname; do
        local size_fmt
        if (( fsize >= 1048576 )); then
            size_fmt=$(awk "BEGIN {printf \"%.1f MB\", $fsize/1048576}")
        elif (( fsize >= 1024 )); then
            size_fmt=$(awk "BEGIN {printf \"%.0f KB\", $fsize/1024}")
        else
            size_fmt="${fsize} B"
        fi
        printf "  ${D_COMMENT}|${D_RESET} ${D_GREEN}%-60s${D_RESET} ${D_FG}%8s${D_RESET}\n" "${fname:0:60}" "$size_fmt"
    done
    echo ""

    if (( dry_run )); then
        __ok "Dry-run concluído. Nenhum arquivo foi copiado."
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
                echo "$all_file_list" | sort -t$'\t' -k2 | while IFS=$'\t' read -r _ fname; do
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

    # Sincronizar cada repo individualmente
    local sync_errors=0
    for pair in "${sync_pairs[@]}"; do
        local src="${pair%%|*}"
        local dest="${pair#*|}"

        [[ ! -d "$dest" ]] && mkdir -p "$dest"

        local sync_output
        sync_output=$(rsync "${rsync_exec[@]}" "${rsync_filters[@]}" "$src/" "$dest/" 2>&1)
        local exit_code=$?

        if [[ $exit_code -ne 0 ]]; then
            __err "rsync falhou para ${src:t} (exit code: $exit_code)"
            echo "$sync_output" | tail -3
            (( sync_errors++ ))
            continue
        fi

        if (( show_stats )); then
            local rel_dest="${dest#$bordo_dir/}"
            echo -e "  ${D_PURPLE}${rel_dest}:${D_RESET}"
            echo "$sync_output" | grep -E "^(Number|Total|Literal|Matched)" | while IFS= read -r stat_line; do
                echo -e "    ${D_COMMENT}${stat_line}${D_RESET}"
            done
        fi
    done

    if (( sync_errors > 0 )); then
        __warn "$sync_errors repo(s) com erro durante sincronização"
    fi

    __ok "${file_count} arquivo(s) sincronizado(s) (${size_human})."

    # Mostrar tamanho final
    local final_size=$(du -sh "$bordo_dir" 2>/dev/null | cut -f1)
    echo -e "  ${D_COMMENT}Vault: $current_size -> $final_size${D_RESET}"
    echo ""
}

alias sync_docs='sincronizar_controle_de_bordo --auto'

# "A simplicidade e a sofisticacao suprema." -- Leonardo da Vinci
