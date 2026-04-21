#!/bin/zsh

# -- Constantes do projeto MEC --
__MEC_ROOT="${MEC_ROOT:-${HOME}/Desenvolvimento/MEC/pipelines-main}"
__MEC_DBT_BIN="${__MEC_ROOT}/.pipelines/bin/dbt"
__MEC_DBT_DIR="${__MEC_ROOT}/queries"
__MEC_PROFILES_DIR="${__MEC_ROOT}/dev"
__MEC_RESULTS_SCRIPT="${ZDOTDIR:-$HOME/.config/zsh}/scripts/mec-dbt-results.py"
__MEC_RESULTS_JSON="${__MEC_DBT_DIR}/target/run_results.json"
__MEC_PYTHON="${__MEC_ROOT}/.pipelines/bin/python"
__MEC_MIGRAR_BIN="${ZDOTDIR:-$HOME/.config/zsh}/scripts/mec-migrar-censo.py"
__MEC_FZF_COLOR="--color=bg+:#44475a,fg+:#f8f8f2,hl:#bd93f9,hl+:#ff79c6,pointer:#50fa7b,marker:#50fa7b,prompt:#bd93f9,header:#6272a4,border:#6272a4"

# -- Exibe painel de contexto antes do FZF --
__mec_mostrar_contexto() {
    local proj_root="${1:-$__MEC_ROOT}"

    local identidade email branch
    identidade=$(git -C "$proj_root" config --local user.name 2>/dev/null || echo "(global)")
    email=$(git -C "$proj_root" config --local user.email 2>/dev/null || echo "(global)")
    branch=$(git -C "$proj_root" branch --show-current 2>/dev/null || echo "?")

    local behind
    behind=$(git -C "$proj_root" rev-list --count HEAD..@{u} 2>/dev/null || echo "0")

    local sql_count yml_count py_count
    local porcelain
    porcelain=$(git -C "$proj_root" status --porcelain 2>/dev/null)
    sql_count=$(echo "$porcelain" | grep -c '\.sql$' 2>/dev/null) || sql_count=0
    yml_count=$(echo "$porcelain" | grep -cE '\.(yml|yaml)$' 2>/dev/null) || yml_count=0
    py_count=$(echo "$porcelain" | grep -c '\.py$' 2>/dev/null) || py_count=0

    echo ""
    echo -e "  ${D_PURPLE}${D_BOLD}CONTEXTO MEC${D_RESET}"
    echo -e "  ${D_COMMENT}$(printf '%.0s─' {1..50})${D_RESET}"
    printf "  ${D_COMMENT}%-12s${D_RESET} ${D_FG}%s${D_RESET}\n" "Identidade" "$identidade"
    printf "  ${D_COMMENT}%-12s${D_RESET} ${D_FG}%s${D_RESET}\n" "Email" "$email"
    printf "  ${D_COMMENT}%-12s${D_RESET} ${D_CYAN}%s${D_RESET}\n" "Branch" "$branch"

    local sync_color="$D_GREEN"
    local sync_label="${behind} commit(s) atrás do remoto"
    [[ "$behind" -gt 0 ]] && sync_color="$D_RED"
    printf "  ${D_COMMENT}%-12s${D_RESET} ${sync_color}%s${D_RESET}\n" "Sync" "$sync_label"

    if [[ "$sql_count" -gt 0 || "$yml_count" -gt 0 || "$py_count" -gt 0 ]]; then
        echo ""
        echo -e "  ${D_COMMENT}Alterações detectadas:${D_RESET}"
        [[ "$sql_count" -gt 0 ]] && printf "    ${D_YELLOW}%-8s${D_RESET} ${D_FG}%s modelo(s)${D_RESET}\n" "SQL" "$sql_count"
        [[ "$yml_count" -gt 0 ]] && printf "    ${D_YELLOW}%-8s${D_RESET} ${D_FG}%s schema(s)${D_RESET}\n" "YAML" "$yml_count"
        [[ "$py_count" -gt 0 ]]  && printf "    ${D_YELLOW}%-8s${D_RESET} ${D_FG}%s script(s)${D_RESET}\n" "Python" "$py_count"
    fi

    local tem_sugestao=false
    echo ""
    echo -e "  ${D_COMMENT}Sugestões:${D_RESET}"

    if [[ "$behind" -gt 0 ]]; then
        echo -e "  ${D_ORANGE}->  [SYNC] git pull --rebase  (${behind} commits pendentes)${D_RESET}"
        tem_sugestao=true
    fi
    if [[ "$sql_count" -gt 0 ]]; then
        echo -e "  ${D_ORANGE}->  [DBT] dbt compile         (validar SQL antes de rodar)${D_RESET}"
        echo -e "  ${D_ORANGE}->  [DBT] dbt run --select    (modelos alterados)${D_RESET}"
        tem_sugestao=true
    fi
    if [[ "$tem_sugestao" == false ]]; then
        echo -e "  ${D_COMMENT}(nenhuma sugestão no momento)${D_RESET}"
    fi

    echo -e "  ${D_COMMENT}$(printf '%.0s─' {1..50})${D_RESET}"
    echo ""
}

# -- Pull seguro com stash automatico --
__mec_git_pull_seguro() {
    local proj_root="${1:-$__MEC_ROOT}"
    local stashed=false

    if [[ -n "$(git -C "$proj_root" status --porcelain 2>/dev/null)" ]]; then
        local stash_label="mec-auto-stash-$(date +%Y%m%d-%H%M%S)"
        echo -e "  ${D_COMMENT}WIP detectado. Guardando stash: ${stash_label}${D_RESET}"
        git -C "$proj_root" stash push -u -m "$stash_label"
        stashed=true
    fi

    echo -e "  ${D_COMMENT}Executando git pull --rebase...${D_RESET}"
    if git -C "$proj_root" pull --rebase; then
        if [[ "$stashed" == true ]]; then
            echo -e "  ${D_COMMENT}Restaurando stash...${D_RESET}"
            git -C "$proj_root" stash pop
        fi
        echo ""
        echo -e "  ${D_GREEN}Últimos 3 commits:${D_RESET}"
        git -C "$proj_root" log --oneline -3 HEAD
    else
        __err "git pull --rebase falhou."
        if [[ "$stashed" == true ]]; then
            __warn "Stash preservado. Use: git stash pop"
        fi
        return 1
    fi
}

# -- Executa comando dbt com profiles correto --
__mec_exec_dbt() {
    local subcmd="$1"
    shift
    local extra_args="$*"

    if [[ ! -x "$__MEC_DBT_BIN" ]]; then
        __err "dbt não encontrado em: ${__MEC_DBT_BIN}"
        return 1
    fi

    local original_dir="$(pwd)"
    __cd "$__MEC_DBT_DIR" || return 1

    echo -e "  ${D_COMMENT}Rodando: dbt ${subcmd} ${extra_args}${D_RESET}"
    $__MEC_DBT_BIN "$subcmd" --profiles-dir ../dev $extra_args
    local dbt_exit=$?

    __cd "$original_dir" || return $dbt_exit

    if [[ "$subcmd" == "run" || "$subcmd" == "build" || "$subcmd" == "test" ]]; then
        if [[ -f "$__MEC_RESULTS_JSON" ]]; then
            echo ""
            "$__MEC_PYTHON" "$__MEC_RESULTS_SCRIPT" "$__MEC_RESULTS_JSON" 2>/dev/null \
                || python3 "$__MEC_RESULTS_SCRIPT" "$__MEC_RESULTS_JSON" 2>/dev/null \
                || __warn "Não foi possível renderizar run_results.json"
        fi
    fi

    return $dbt_exit
}

# -- Seleção FZF de modelos e executa dbt --
__mec_exec_dbt_select() {
    local subcmd="$1"
    local models_dir="${__MEC_DBT_DIR}/models"

    if [[ ! -d "$models_dir" ]]; then
        __warn "Diretório de modelos não encontrado: ${models_dir}"
        __mec_exec_dbt "$subcmd"
        return
    fi

    local fzf_select_color="bg+:#44475a,fg+:#f8f8f2,hl:#bd93f9,hl+:#ff79c6,pointer:#50fa7b,marker:#50fa7b,prompt:#bd93f9,header:#6272a4,border:#6272a4"
    local selecao
    selecao=$(find "$models_dir" -name "*.sql" \
        | sed "s|${models_dir}/||; s|\.sql$||" \
        | sort \
        | fzf --multi \
              --height=50% \
              --layout=reverse \
              --border \
              --prompt="  Modelo > " \
              --header="  TAB múltiplos | ESC = todos" \
              --color="$fzf_select_color")

    if [[ -z "$selecao" ]]; then
        echo -e "  ${D_COMMENT}Nenhum modelo selecionado. Rodando todos...${D_RESET}"
        __mec_exec_dbt "$subcmd"
    else
        local modelos_args=""
        while IFS= read -r m; do
            local base
            base=$(basename "$m")
            modelos_args+="$base "
        done <<< "$selecao"
        modelos_args="${modelos_args%% }"
        __mec_exec_dbt "$subcmd" "--select $modelos_args"
    fi
}

# -- Checklist pre-push com 4 verificações --
__mec_checklist_push() {
    local proj_root="${1:-$__MEC_ROOT}"
    local passou=true

    echo ""
    echo -e "  ${D_COMMENT}Checklist pre-push:${D_RESET}"
    echo ""

    # [1/4] Identidade
    local email_local
    email_local=$(git -C "$proj_root" config --local user.email 2>/dev/null)
    local email_esperado="${ZSH_IDENTITY_MEC_EMAIL:-andrefarias@mec.gov.br}"
    if [[ "$email_local" == "$email_esperado" ]]; then
        echo -e "  ${D_GREEN}[1/4]${D_RESET} Identidade: ${D_FG}${email_local}${D_RESET}"
    else
        echo -e "  ${D_RED}[1/4]${D_RESET} Identidade incorreta: ${D_FG}${email_local:-"(não configurada)"}${D_RESET}"
        passou=false
    fi

    # [2/4] Branch não e main/master
    local branch_atual
    branch_atual=$(git -C "$proj_root" branch --show-current 2>/dev/null)
    if [[ "$branch_atual" =~ ^(main|master)$ ]]; then
        echo -e "  ${D_RED}[2/4]${D_RESET} Branch protegida: ${D_YELLOW}${branch_atual}${D_RESET}"
        passou=false
    else
        echo -e "  ${D_GREEN}[2/4]${D_RESET} Branch: ${D_CYAN}${branch_atual}${D_RESET}"
    fi

    # [3/4] dbt compile
    if [[ -x "$__MEC_DBT_BIN" ]]; then
        local orig="$(pwd)"
        if __cd "$__MEC_DBT_DIR"; then
            if $__MEC_DBT_BIN compile --profiles-dir ../dev --quiet >/dev/null 2>&1; then
                echo -e "  ${D_GREEN}[3/4]${D_RESET} dbt compile: ${D_FG}OK${D_RESET}"
            else
                echo -e "  ${D_RED}[3/4]${D_RESET} dbt compile falhou"
                passou=false
            fi
            __cd "$orig" || true
        else
            echo -e "  ${D_YELLOW}[3/4]${D_RESET} dbt dir não encontrado — pulando compile"
        fi
    else
        echo -e "  ${D_YELLOW}[3/4]${D_RESET} dbt não encontrado — pulando compile"
    fi

    # [4/4] pre-commit
    if command -v pre-commit &>/dev/null; then
        local orig="$(pwd)"
        if __cd "$proj_root"; then
            if pre-commit run --all-files >/dev/null 2>&1; then
                echo -e "  ${D_GREEN}[4/4]${D_RESET} pre-commit: ${D_FG}OK${D_RESET}"
            else
                echo -e "  ${D_RED}[4/4]${D_RESET} pre-commit encontrou problemas"
                passou=false
            fi
            __cd "$orig" || true
        else
            echo -e "  ${D_YELLOW}[4/4]${D_RESET} proj_root não encontrado — pulando pre-commit"
        fi
    else
        echo -e "  ${D_COMMENT}[4/4]${D_RESET} pre-commit não instalado — pulando"
    fi

    echo ""

    if [[ "$passou" == false ]]; then
        __err "Checklist falhou. Push abortado."
        return 1
    fi

    echo -e -n "  ${D_ORANGE}Confirmar push? (s/N)${D_RESET} "
    local push_reply=""
    read -k 1 push_reply
    echo ""

    if [[ "$push_reply" == "s" || "$push_reply" == "S" ]]; then
        git -C "$proj_root" push
    else
        echo -e "  ${D_COMMENT}Push cancelado.${D_RESET}"
    fi
}

# -- Menu FZF principal: conjurar_mec --
# Proposito: Interface CLI completa para o projeto MEC (dbt, git, push, ambiente)
# Uso: conjurar_mec
conjurar_mec() {
    __verificar_dependencias "fzf" "git" || return 1

    if [[ ! -d "$__MEC_ROOT" ]]; then
        __err "Projeto MEC não encontrado: ${__MEC_ROOT}"
        return 1
    fi

    if ! git -C "$__MEC_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        __err "Diretório não é um repositório git: ${__MEC_ROOT}"
        return 1
    fi

    echo -e "  ${D_COMMENT}Atualizando informações do remoto...${D_RESET}"
    git -C "$__MEC_ROOT" fetch --quiet 2>/dev/null \
        && echo -e "  ${D_GREEN}fetch OK${D_RESET}" \
        || echo -e "  ${D_YELLOW}fetch falhou (offline?)${D_RESET}"

    __mec_mostrar_contexto "$__MEC_ROOT"

    local -a opcoes=(
        "[SYNC]  git pull --rebase	SYNC	Atualizar branch (seguro, stash auto, sem reset --hard)"
        "[SYNC]  git fetch	SYNC	Buscar info do remoto sem alterar local"
        "[SYNC]  git status	SYNC	Status atual do repositório"
        "[SYNC]  git log recente	SYNC	Últimos 10 commits com grafo"
        "[DBT]   dbt run (todos)	DBT	Rodar todos os modelos no dataset dev"
        "[DBT]   dbt run (selecionar)	DBT	FZF de modelos + dbt run no dev"
        "[DBT]   dbt build (todos)	DBT	Build completo: run + test no dev"
        "[DBT]   dbt build (selecionar)	DBT	FZF de modelos + dbt build no dev"
        "[DBT]   dbt test	DBT	Rodar testes de qualidade no dev"
        "[DBT]   dbt compile	DBT	Compilar SQL sem executar (validação)"
        "[DBT]   dbt ls	DBT	Listar todos os modelos do projeto"
        "[GIT]   git add + commit	GIT	Stagear arquivos e commitar"
        "[GIT]   git diff staged	GIT	Ver diff dos arquivos em staging"
        "[GIT]   git stash	GIT	Guardar WIP com label automático"
        "[GIT]   git stash pop	GIT	Restaurar último stash"
        "[PUSH]  push com checklist	PUSH	4 checks + confirmar + git push"
        "[PUSH]  push direto	PUSH	Git push sem checklist (pede confirmação)"
        "[AMB]   abrir santuario	AMB	santuario MEC pipelines-main"
        "[AMB]   pre-commit run	AMB	Rodar black/isort/flake8 em todos os arquivos"
        "[AMB]   verificar rastros IA	AMB	Scaneia arquivos staged por comentários, emojis ou menções a IA"
        "[AMB]   ver identidade git	AMB	git_info (nome, email, branch, remote)"
        "[INFO]  ver run_results	INFO	Tabela do último dbt run/build/test"
        "[INFO]  ver contexto	INFO	Reexibir painel de contexto"
        "[INFO]  ver PR status	INFO	gh pr view: status, checks e target branch do PR atual"
        "[MIG]   scan do projeto	MIG	Listar todos os SQLs com source censo pendente de migração"
        "[MIG]   validar coluna	MIG	Comparar old_col vs new_col no BQ (tipos + distinct + sum)"
        "[MIG]   migrar source_only	MIG	Trocar apenas source ID em um SQL (sem aliases)"
        "[MIG]   migrar aliases (auto)	MIG	Apply yes-all: aceitar todos aliases inferidos automaticamente"
        "[MIG]   migrar modelo	MIG	Apply interativo: analisar + aplicar aliases em SQL file"
    )

    local preview_cmd='linha="{}"
label=$(printf "%s" "$linha" | cut -d'"'"'	'"'"' -f1)
grupo=$(printf "%s" "$linha" | cut -d'"'"'	'"'"' -f2)
desc=$(printf "%s" "$linha" | cut -d'"'"'	'"'"' -f3)
printf "\033[38;2;189;147;249m\033[1m%s\033[0m\n" "$label"
printf "\033[38;2;98;114;164m%s\033[0m\n" "────────────────────────────────────────"
printf "\033[38;2;241;250;140mGrupo:\033[0m %s\n\n" "$grupo"
printf "\033[38;2;248;248;242m%s\033[0m\n" "$desc"'

    local selecao
    selecao=$(printf '%s\n' "${opcoes[@]}" | fzf \
        --height=70% \
        --layout=reverse \
        --border=rounded \
        --margin=1 \
        --padding=1 \
        --prompt="  MEC > " \
        --header="  ENTER executar | ESC sair | 29 operações" \
        --preview-window="right:45%:wrap" \
        --delimiter=$'\t' \
        --with-nth=1 \
        --preview="$preview_cmd" \
        $__MEC_FZF_COLOR)

    local exit_code=$?

    if [[ $exit_code -eq 130 || -z "$selecao" ]]; then
        echo -e "  ${D_COMMENT}Cancelado.${D_RESET}"
        return 0
    fi

    local label
    label=$(printf '%s' "$selecao" | cut -d$'\t' -f1 | sed 's/[[:space:]]*$//')

    echo ""
    echo -e "  ${D_PURPLE}>>>${D_RESET} ${D_FG}${label}${D_RESET}"
    echo ""

    case "$label" in
        "[SYNC]  git pull --rebase")
            __mec_git_pull_seguro "$__MEC_ROOT"
            ;;
        "[SYNC]  git fetch")
            git -C "$__MEC_ROOT" fetch --all --prune
            ;;
        "[SYNC]  git status")
            git -C "$__MEC_ROOT" status
            ;;
        "[SYNC]  git log recente")
            git -C "$__MEC_ROOT" log --oneline --graph --decorate -10
            ;;
        "[DBT]   dbt run (todos)")
            __mec_exec_dbt run
            ;;
        "[DBT]   dbt run (selecionar)")
            __mec_exec_dbt_select run
            ;;
        "[DBT]   dbt build (todos)")
            __mec_exec_dbt build
            ;;
        "[DBT]   dbt build (selecionar)")
            __mec_exec_dbt_select build
            ;;
        "[DBT]   dbt test")
            __mec_exec_dbt test
            ;;
        "[DBT]   dbt compile")
            __mec_exec_dbt compile
            ;;
        "[DBT]   dbt ls")
            __mec_exec_dbt ls
            ;;
        "[GIT]   git add + commit")
            git -C "$__MEC_ROOT" add -p
            echo -e -n "  ${D_ORANGE}Mensagem do commit: ${D_RESET}"
            local commit_msg=""
            read commit_msg
            if [[ -n "$commit_msg" ]]; then
                git -C "$__MEC_ROOT" commit -m "$commit_msg"
            else
                echo -e "  ${D_COMMENT}Commit cancelado.${D_RESET}"
            fi
            ;;
        "[GIT]   git diff staged")
            git -C "$__MEC_ROOT" diff --cached
            ;;
        "[GIT]   git stash")
            local stash_label="mec-wip-$(date +%Y%m%d-%H%M%S)"
            git -C "$__MEC_ROOT" stash push -u -m "$stash_label"
            ;;
        "[GIT]   git stash pop")
            git -C "$__MEC_ROOT" stash pop
            ;;
        "[PUSH]  push com checklist")
            __mec_checklist_push "$__MEC_ROOT"
            ;;
        "[PUSH]  push direto")
            echo -e -n "  ${D_ORANGE}Confirmar git push? (s/N)${D_RESET} "
            local push_direct=""
            read -k 1 push_direct
            echo ""
            if [[ "$push_direct" == "s" || "$push_direct" == "S" ]]; then
                git -C "$__MEC_ROOT" push
            else
                echo -e "  ${D_COMMENT}Push cancelado.${D_RESET}"
            fi
            ;;
        "[AMB]   abrir santuario")
            santuario MEC pipelines-main
            ;;
        "[AMB]   pre-commit run")
            if command -v pre-commit &>/dev/null; then
                local orig="$(pwd)"
                __cd "$__MEC_ROOT" && pre-commit run --all-files
                __cd "$orig" || true
            else
                __err "pre-commit não instalado."
            fi
            ;;
        "[AMB]   verificar rastros IA")
            local sanitizer="${ZDOTDIR:-$HOME/.config/zsh}/scripts/universal-sanitizer.py"
            if [[ -f "$sanitizer" ]]; then
                local staged
                staged=$(git -C "$__MEC_ROOT" diff --cached --name-only 2>/dev/null)
                if [[ -z "$staged" ]]; then
                    echo -e "  ${D_COMMENT}Nenhum arquivo em staging.${D_RESET}"
                else
                    local orig="$(pwd)"
                    __cd "$__MEC_ROOT" || break
                    echo "$staged" | xargs python3 "$sanitizer" --check 2>/dev/null \
                        && echo -e "  ${D_GREEN}Nenhum rastro detectado.${D_RESET}" \
                        || __warn "Rastros detectados. Revisar antes de commitar."
                    __cd "$orig" || true
                fi
            else
                __err "universal-sanitizer.py não encontrado."
            fi
            ;;
        "[AMB]   ver identidade git")
            local orig="$(pwd)"
            __cd "$__MEC_ROOT" && git_info
            __cd "$orig" || true
            ;;
        "[INFO]  ver run_results")
            if [[ -f "$__MEC_RESULTS_JSON" ]]; then
                "$__MEC_PYTHON" "$__MEC_RESULTS_SCRIPT" "$__MEC_RESULTS_JSON" 2>/dev/null \
                    || python3 "$__MEC_RESULTS_SCRIPT" "$__MEC_RESULTS_JSON"
            else
                __warn "run_results.json não encontrado em: ${__MEC_RESULTS_JSON}"
            fi
            ;;
        "[INFO]  ver contexto")
            __mec_mostrar_contexto "$__MEC_ROOT"
            ;;
        "[INFO]  ver PR status")
            if command -v gh &>/dev/null; then
                gh -R SEGAPE/pipelines pr view \
                    --json number,title,baseRefName,headRefName,state,statusCheckRollup \
                    --jq '"PR #\(.number): \(.title)\nDe: \(.headRefName) → Para: \(.baseRefName)\nStatus: \(.state)"' \
                    2>/dev/null || gh pr view 2>/dev/null || __warn "Nenhum PR encontrado para a branch atual."
            else
                __err "gh CLI não instalado."
            fi
            ;;
        "[MIG]   scan do projeto")
            python3 "$__MEC_MIGRAR_BIN" --no-sync
            ;;
        "[MIG]   validar coluna")
            echo -e -n "  ${D_COMMENT}Coluna antiga: ${D_RESET}"; read old_col
            echo -e -n "  ${D_COMMENT}Coluna nova: ${D_RESET}"; read new_col
            "$__MEC_PYTHON" "$__MEC_MIGRAR_BIN" \
                validate --old-col "$old_col" --new-col "$new_col"
            ;;
        "[MIG]   migrar source_only")
            local model_path
            model_path=$(find "$__MEC_DBT_DIR/models" -name "*.sql" \
                | fzf --height=50% --prompt="  Modelo (source-only) > " $__MEC_FZF_COLOR)
            [[ -n "$model_path" ]] && \
                python3 "$__MEC_MIGRAR_BIN" apply \
                    --sql-file "$model_path" --source-only --no-sync
            ;;
        "[MIG]   migrar aliases (auto)")
            local model_path
            model_path=$(find "$__MEC_DBT_DIR/models" -name "*.sql" \
                | fzf --height=50% --prompt="  Modelo (yes-all) > " $__MEC_FZF_COLOR)
            [[ -n "$model_path" ]] && \
                python3 "$__MEC_MIGRAR_BIN" apply \
                    --sql-file "$model_path" --yes-all --mock --no-sync
            ;;
        "[MIG]   migrar modelo")
            local model_path
            model_path=$(find "$__MEC_DBT_DIR/models" -name "*.sql" \
                | fzf --height=50% --prompt="  Modelo > " $__MEC_FZF_COLOR)
            [[ -n "$model_path" ]] && \
                "$__MEC_PYTHON" "$__MEC_MIGRAR_BIN" \
                    apply --sql-file "$model_path"
            ;;
        *)
            __warn "Ação não mapeada: ${label}"
            ;;
    esac
}

# Propósito: Alias curto para conjurar_mec
# Uso: mec
alias mec='conjurar_mec'

# "A ordem é o dom natural da mente que age com propósito." — Marco Aurélio
