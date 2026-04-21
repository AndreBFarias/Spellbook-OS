#!/bin/zsh

# Propósito: Abrir diretório no Antigravity (file manager)
# Uso: levitar [caminho]
# Completa:
#   [caminho]=_path_files -/
levitar() {
    local alvo="${1:-.}"

    if ! command -v antigravity &> /dev/null; then
        __err "'antigravity' não encontrado no PATH."
        return 1
    fi

    echo -e "  ${D_COMMENT}Abrindo no Antigravity...${D_RESET}"
    nohup antigravity "$alvo" > /dev/null 2>&1 &
}

# Propósito: Setup completo de projeto (cd, branch, venv, deps, git context)
# Uso: santuario <Projeto> [Branch] [--sync] [--vit]
# Flags: --sync=Sincroniza dependências via pip install -r
#        --vit=Usa subdiretório VitoriaMariaDB/
# Completa:
#   <Projeto>=__santuario_pastas_dev
#   [Branch]=__santuario_branches_git
santuario() {
    local projeto_raiz="$1"

    if [ -z "$projeto_raiz" ]; then
        __header "SANTUARIO" "$D_PURPLE"
        echo -e "  ${D_COMMENT}Uso: santuario <Projeto> [Sub/Branch] [--sync] [--vit]${D_RESET}"
        echo ""
        echo -e "  ${D_FG}Exemplos:${D_RESET}"
        echo -e "    ${D_GREEN}santuario Luna${D_RESET}             Abre projeto Luna"
        echo -e "    ${D_GREEN}santuario Luna dev${D_RESET}         Abre e muda para branch dev"
        echo -e "    ${D_GREEN}santuario Luna --sync${D_RESET}      Abre e sincroniza deps"
        echo -e "    ${D_GREEN}santuario repo --vit${D_RESET}       Abre projeto em VitoriaMariaDB/"
        echo ""
        return 1
    fi
    shift

    local sync_dependencias=false
    local perfil_vit=false
    local alvo_primario=""
    local alvo_secundario=""

    while (( $# > 0 )); do
        case "$1" in
            --sync|-s) sync_dependencias=true ;;
            --vit|-v) perfil_vit=true ;;
            --*) local limpo="${1#--}";
                 if [ -z "$alvo_primario" ]; then alvo_primario="$limpo"; else alvo_secundario="$limpo"; fi ;;
            *)   if [ -z "$alvo_primario" ]; then alvo_primario="$1"; else alvo_secundario="$1"; fi ;;
        esac
        shift
    done

    local base_dir="${DEV_DIR:-$HOME/Desenvolvimento}"
    if [ "$perfil_vit" = true ]; then
        base_dir="$base_dir/VitoriaMariaDB"
    fi
    local dir_alvo="$base_dir/$projeto_raiz"
    local branch_alvo=""

    if [ -n "$alvo_primario" ]; then
        if [ -d "$dir_alvo/$alvo_primario" ]; then
            dir_alvo="$dir_alvo/$alvo_primario"
            [ -n "$alvo_secundario" ] && branch_alvo="$alvo_secundario"
        else
            branch_alvo="$alvo_primario"
        fi
    fi

    if [ ! -d "$dir_alvo" ]; then
        __err "Caminho não existe: $dir_alvo"
        return 1
    fi

    cd "$dir_alvo" || return

    __header "SANTUARIO: $(basename "$dir_alvo")" "$D_PURPLE"
    __item "Path" "$(pwd)" "$D_COMMENT" "$D_FG"

    if [ -n "$branch_alvo" ]; then
        if [ -d ".git" ] || [ -d "../.git" ]; then
            echo ""
            echo -e "  ${D_COMMENT}Trocando para branch:${D_RESET} ${D_YELLOW}$branch_alvo${D_RESET}"

            if git show-ref --verify --quiet "refs/heads/$branch_alvo"; then
                git checkout "$branch_alvo"
            else
                git fetch origin "$branch_alvo" >/dev/null 2>&1
                if git show-ref --verify --quiet "refs/remotes/origin/$branch_alvo"; then
                    git checkout "$branch_alvo"
                else
                    __warn "Branch '$branch_alvo' não encontrada."
                    echo -e -n "  ${D_FG}Criar nova branch? (s/N)${D_RESET} "
                    read -k 1 reply
                    echo ""
                    if [[ "$reply" == "s" || "$reply" == "S" ]]; then
                        git checkout -b "$branch_alvo"
                    else
                        echo -e "  ${D_COMMENT}Mantendo branch atual.${D_RESET}"
                    fi
                fi
            fi
        fi
    fi

    echo ""

    if [[ "$(pwd)" == *"/MEC/pipelines-main"* ]]; then
        echo -e "  ${D_ORANGE}Protocolo MEC${D_RESET}"
        __aplicar_contexto_git_automatico
    elif [[ "$(pwd)" == *"/VitoriaMariaDB/"* ]]; then
        echo -e "  ${D_PURPLE}Protocolo VitoriaMariaDB${D_RESET}"
        __aplicar_contexto_git_automatico
    else
        if [ -f "Cargo.toml" ]; then
            echo -e "  ${D_COMMENT}Projeto Rust detectado. Compilando...${D_RESET}"
            cargo build
        else
            # Delegação para install.sh do projeto (respeita configuração de venv do projeto)
            if [ -f "install.sh" ]; then
                local venv_base="venv"
                if [ ! -d "$venv_base" ] || [ "$sync_dependencias" = true ]; then
                    echo -e "  ${D_GREEN}[SETUP]${D_RESET} Delegando para install.sh do projeto..."
                    bash install.sh || __warn "Falha ao executar install.sh"
                fi
            fi

            local req_files=($(find . -maxdepth 1 -name "requirements*.txt"))

            if [ ${#req_files[@]} -eq 0 ]; then
                echo -e "  ${D_COMMENT}Nenhum requirements.txt encontrado.${D_RESET}"
            else
                echo -e "  ${D_CYAN}${#req_files[@]} requirements detectado(s)${D_RESET}"

                local -a sufixos_delegados=()

                for req in "${req_files[@]}"; do
                    local req_nome=$(basename "$req")
                    local venv_target=""
                    local sufixo=""

                    # Skip requirements de CI
                    if [[ "$req_nome" == *"-ci"* || "$req_nome" == *"_ci"* ]]; then
                        echo -e "  ${D_COMMENT}[SKIP]${D_RESET} $req_nome (CI-only)"
                        continue
                    fi

                    if [[ "$req_nome" == "requirements.txt" ]]; then
                        venv_target="venv"
                    else
                        sufixo=${req_nome#requirements[_-]}
                        sufixo=${sufixo%.txt}
                        venv_target="venv_${sufixo}"
                    fi

                    # Remover symlinks quebrados
                    if [ -L "$venv_target" ] && [ ! -e "$venv_target" ]; then
                        __warn "Symlink quebrado '$venv_target' removido."
                        rm -f "$venv_target"
                    fi

                    # Delegar para setup script se existir
                    local setup_script="scripts/${sufixo}_setup.sh"
                    if [[ -n "$sufixo" && -f "$setup_script" ]]; then
                        if [ ! -d "$venv_target" ] || [ "$sync_dependencias" = true ]; then
                            echo -e "  ${D_GREEN}[SETUP]${D_RESET} Delegando '$venv_target' para $setup_script..."
                            bash "$setup_script" || { __warn "Falha ao executar '$setup_script'"; continue; }
                        fi
                        sufixos_delegados+=("$sufixo")
                        continue
                    fi

                    # Skip sub-requirements de um setup script já delegado
                    # Ex: tts_coqui e tts_chatterbox são consumidos por tts_setup.sh
                    if [[ -n "$sufixo" && ${#sufixos_delegados[@]} -gt 0 ]]; then
                        local skip_sub=false
                        for delegado in "${sufixos_delegados[@]}"; do
                            if [[ "$sufixo" == "${delegado}_"* ]]; then
                                echo -e "  ${D_COMMENT}[SKIP]${D_RESET} $req_nome (consumido por ${delegado}_setup.sh)"
                                skip_sub=true
                                break
                            fi
                        done
                        if [ "$skip_sub" = true ]; then continue; fi
                    fi

                    if [ ! -d "$venv_target" ]; then
                        local py_cmd=$(__resolver_python_projeto)
                        local venv_flags=""
                        if [ -f "install.sh" ] && grep -q "system-site-packages" install.sh 2>/dev/null; then
                            venv_flags="--system-site-packages"
                        fi
                        echo -e "  ${D_GREEN}[NOVO]${D_RESET} Criando '$venv_target' ($req_nome) [${py_cmd}]..."
                        "$py_cmd" -m venv $venv_flags "$venv_target" || { __warn "Falha ao criar venv '$venv_target'"; continue; }
                        [[ -f "$venv_target/bin/activate" ]] || { __warn "activate não encontrado em '$venv_target'"; continue; }
                        source "$venv_target/bin/activate"
                        pip install -r "$req_nome"
                        typeset -f deactivate > /dev/null 2>&1 && deactivate
                    elif [ "$sync_dependencias" = true ]; then
                        echo -e "  ${D_ORANGE}[SYNC]${D_RESET} Atualizando '$venv_target' ($req_nome)..."
                        [[ -f "$venv_target/bin/activate" ]] || { __warn "activate não encontrado em '$venv_target'"; continue; }
                        source "$venv_target/bin/activate"
                        pip install -r "$req_nome"
                        typeset -f deactivate > /dev/null 2>&1 && deactivate
                    fi
                done
            fi

            local venvs=($(find . -maxdepth 1 -type d \( -name "venv*" -o -name ".venv*" \) -printf "%f\n" | sort))
            local venv_escolhido=""

            if [ ${#venvs[@]} -eq 1 ]; then
                venv_escolhido="${venvs[1]}"
            elif [ ${#venvs[@]} -gt 1 ]; then
                __verificar_dependencias "fzf" || return 1
                local FZF_DRACULA="--color=bg+:#44475a,fg+:#f8f8f2,hl:#bd93f9,hl+:#ff79c6,pointer:#50fa7b,marker:#50fa7b,prompt:#bd93f9,header:#6272a4,border:#6272a4"
                echo ""
                venv_escolhido=$(printf "%s\n" "${venvs[@]}" | \
                    fzf --height=20% --layout=reverse --border \
                    --prompt="  Ambiente > " $FZF_DRACULA)
            fi

            if [ -n "$venv_escolhido" ]; then
                if [ -f "$venv_escolhido/bin/activate" ]; then
                    source "$venv_escolhido/bin/activate"
                    __item "Venv" "$venv_escolhido" "$D_COMMENT" "$D_GREEN"
                else
                    __err "Ambiente '$venv_escolhido' corrompido."
                fi
            fi
        fi
    fi

    if [ -f ".santuario_setup.sh" ]; then
        echo -e "  ${D_COMMENT}Executando .santuario_setup.sh...${D_RESET}"
        source ./.santuario_setup.sh
    fi

    __aplicar_contexto_git_automatico
    __aplicar_contexto_gh_automatico

    # Verificação e limpeza automática de emojis
    echo ""
    local emoji_guardian="${BORDO_DIR:-$HOME/Controle de Bordo}/.sistema/scripts/emoji_guardian.py"
    if [ -f "$emoji_guardian" ]; then
        echo -e "  ${D_COMMENT}Verificando emojis...${D_RESET}"
        local check_output=$(python3 "$emoji_guardian" check . 2>&1)
        local emoji_files
        emoji_files=$(echo "$check_output" | grep -c "ARQUIVO") || emoji_files=0

        if [ "$emoji_files" -gt 0 ] && [[ -z "$SANTUARIO_SKIP_EMOJI" ]]; then
            echo -e "  ${D_YELLOW}[ALERTA] $emoji_files arquivo(s) com emojis${D_RESET}"
            echo -e "  ${D_COMMENT}Limpando automaticamente...${D_RESET}"
            python3 "$emoji_guardian" clean . --apply > /dev/null 2>&1
            echo -e "  ${D_GREEN}[OK] Emojis removidos${D_RESET}"
        else
            echo -e "  ${D_GREEN}[OK] Projeto livre de emojis${D_RESET}"
        fi
    fi

    # Sistema de validação de sprints (Claude Code v2 - subagente validador-sprint)
    if [ -d ".git" ]; then
        # Doctor silencioso: avisa apenas se detectar issues
        if typeset -f __sprint_doctor_quick > /dev/null 2>&1; then
            __sprint_doctor_quick
        fi

        echo ""
        if [ -f "VALIDATOR_BRIEF.md" ]; then
            local brief_age=$(( ($(date +%s) - $(stat -c %Y VALIDATOR_BRIEF.md)) / 86400 ))
            local brief_lines=$(wc -l < VALIDATOR_BRIEF.md)
            echo -e "  ${D_CYAN}[VALIDADOR]${D_RESET} BRIEF ativo (${brief_lines}L, atualizado há ${brief_age}d)"
        else
            echo -e "  ${D_YELLOW}[VALIDADOR]${D_RESET} sem VALIDATOR_BRIEF.md (hook SessionStart do cca cria automaticamente na próxima sessão)"
        fi
    fi

    echo ""
    __ok "Santuario pronto."

    if command -v git_info &> /dev/null; then git_info; fi

    read -k 1 "reply?  Abrir no Antigravity? (s/N) "
    echo ""
    if [[ "$reply" == "s" || "$reply" == "S" ]]; then
        levitar .
    fi

    # Nota v2: prompt de abrir Claude Code removido - rodar `cca` diretamente já carrega
    # VALIDATOR_BRIEF.md, capacidades visuais e ciclo automatico via hook SessionStart.
    # Para validar sprint: `cca "/validar-sprint"` ou `sval`.
    # Para ciclo completo: `cca "/sprint-ciclo <ideia>"` ou `sciclo <ideia>`.

    if [[ "$(pwd)" == *"/MEC/pipelines-main"* ]]; then
        echo -e -n "  ${D_ORANGE}Abrir menu MEC? (s/N)${D_RESET} "
        local mec_reply=""
        read -k 1 mec_reply
        echo ""
        if [[ "$mec_reply" == "s" || "$mec_reply" == "S" ]]; then
            conjurar_mec
        fi
    fi
}
