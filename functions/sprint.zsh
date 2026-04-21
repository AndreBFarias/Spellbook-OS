#!/bin/zsh
# Função sprint: integração unificada com o sistema de sprints Claude Code
# (planejador-sprint + executor-sprint + validador-sprint)
# Requer: cca (wrapper claude com quota guard) em cca/aliases_cca.zsh

# Propósito: Wrapper unificado para o ciclo de sprint Claude Code
# Uso: sprint <subcomando> [args]
# Subcomandos:
#   plan <ideia>        Dispatcha planejador-sprint (gera spec de sprint)
#   exec [spec]         Dispatcha executor-sprint (implementa spec)
#   val [plano]         Dispatcha validador-sprint (valida proof-of-work)
#   ciclo <ideia>       Fluxo completo plan -> exec -> val com checkpoints
#   brief               Status do VALIDATOR_BRIEF.md do projeto atual
#   brief-edit          Abre VALIDATOR_BRIEF.md no editor
#   bootstrap           Copia template de bootstrap-rico pro clipboard
#   doctor              Health check completo do setup Claude
# Completa:
#   <subcomando>=__sprint_subcomandos
sprint() {
    local cmd="${1:-}"
    shift 2>/dev/null

    case "$cmd" in
        plan|planejar)
            __sprint_exec_slash "planejar-sprint" "$@"
            ;;
        exec|executar)
            __sprint_exec_slash "executar-sprint" "$@"
            ;;
        val|validar)
            __sprint_exec_slash "validar-sprint" "$@"
            ;;
        ciclo|cycle)
            if [ -z "$1" ]; then
                __err "Uso: sprint ciclo <ideia-da-sprint>"
                return 1
            fi
            __sprint_exec_slash "sprint-ciclo" "$@"
            ;;
        ciclo-manual|cycle-manual)
            if [ -z "$1" ]; then
                __err "Uso: sprint ciclo-manual <ideia-da-sprint>"
                return 1
            fi
            __sprint_exec_slash "sprint-ciclo-manual" "$@"
            ;;
        brief|status)
            __sprint_brief_status
            ;;
        brief-edit|edit)
            __sprint_brief_edit
            ;;
        bootstrap|boot)
            if [ "${1:-}" = "--rich" ] || [ "${1:-}" = "rich" ]; then
                shift
                __sprint_bootstrap_rico "$@"
            else
                __sprint_bootstrap_clipboard
            fi
            ;;
        doctor|check)
            __sprint_doctor
            ;;
        doctor-quick|check-quick)
            __sprint_doctor_quick
            ;;
        ""|help|-h|--help)
            __sprint_help
            ;;
        *)
            __err "Subcomando desconhecido: $cmd"
            echo ""
            __sprint_help
            return 1
            ;;
    esac
}

__sprint_help() {
    __header "SPRINT" "$D_PURPLE"
    echo -e "  ${D_COMMENT}Sistema unificado de sprints Claude Code${D_RESET}"
    echo ""
    echo -e "  ${D_FG}Ciclo:${D_RESET}"
    echo -e "    ${D_GREEN}sprint plan${D_RESET} <ideia>          Planeja sprint (gera spec)"
    echo -e "    ${D_GREEN}sprint exec${D_RESET} [spec]           Executa sprint (implementa)"
    echo -e "    ${D_GREEN}sprint val${D_RESET} [plano]           Valida sprint (proof-of-work)"
    echo -e "    ${D_GREEN}sprint ciclo${D_RESET} <ideia>         Ciclo automático plan->exec->val (3-retry)"
    echo -e "    ${D_GREEN}sprint ciclo-manual${D_RESET} <ideia>  Ciclo com checkpoints (opt-in)"
    echo ""
    echo -e "  ${D_FG}Memória (VALIDATOR_BRIEF.md):${D_RESET}"
    echo -e "    ${D_GREEN}sprint brief${D_RESET}                 Status do BRIEF do projeto"
    echo -e "    ${D_GREEN}sprint brief-edit${D_RESET}            Abre BRIEF no editor"
    echo -e "    ${D_GREEN}sprint bootstrap${D_RESET}             Copia template pro clipboard"
    echo -e "    ${D_GREEN}sprint bootstrap --rich${D_RESET}      Gera BRIEF rico via script (Luna/Nyx/ouroboros)"
    echo ""
    echo -e "  ${D_FG}Diagnóstico:${D_RESET}"
    echo -e "    ${D_GREEN}sprint doctor${D_RESET}                Health check completo (14 lições + setup)"
    echo -e "    ${D_GREEN}sprint doctor-quick${D_RESET}          Health check silencioso (chamado por santuário)"
}

__sprint_exec_slash() {
    local slash="$1"
    shift
    local args="$*"

    if ! typeset -f cca > /dev/null 2>&1; then
        __err "cca não carregado. Verifique ${ZDOTDIR:-$HOME/.config/zsh}/cca/aliases_cca.zsh"
        return 1
    fi

    if [ ! -d ".git" ] && ! git rev-parse --show-toplevel > /dev/null 2>&1; then
        __warn "Não está em repo git. Recomendado rodar sprint dentro de um projeto."
    fi

    if [ -n "$args" ]; then
        cca "/$slash $args"
    else
        cca "/$slash"
    fi
}

__sprint_brief_status() {
    local root
    root=$(git rev-parse --show-toplevel 2>/dev/null)
    if [ -z "$root" ]; then
        __err "Não está em repo git"
        return 1
    fi

    local brief="$root/VALIDATOR_BRIEF.md"
    if [ ! -f "$brief" ]; then
        __header "VALIDADOR_BRIEF" "$D_YELLOW"
        __warn "BRIEF ausente em $(basename "$root")"
        echo -e "  ${D_COMMENT}Será criado automaticamente no 1º ${D_GREEN}sprint val${D_COMMENT} ou ${D_GREEN}sprint ciclo${D_RESET}"
        echo -e "  ${D_COMMENT}Ou use ${D_GREEN}sprint bootstrap${D_COMMENT} para dump-rico em sessão viva${D_RESET}"
        return 0
    fi

    local lines sections age_days
    lines=$(wc -l < "$brief")
    sections=$(grep -c '^## ' "$brief" 2>/dev/null)
    age_days=$(( ($(date +%s) - $(stat -c %Y "$brief")) / 86400 ))

    __header "VALIDADOR_BRIEF: $(basename "$root")" "$D_CYAN"
    __item "Linhas" "$lines" "$D_COMMENT" "$D_FG"
    __item "Seções" "$sections" "$D_COMMENT" "$D_FG"
    __item "Idade" "${age_days}d" "$D_COMMENT" "$D_FG"
    __item "Path" "$brief" "$D_COMMENT" "$D_GREEN"
    echo ""
    __item "Seções detectadas:" "" "$D_COMMENT" "$D_FG"
    grep '^## ' "$brief" 2>/dev/null | sed 's/^## /    - /'
}

__sprint_brief_edit() {
    local root
    root=$(git rev-parse --show-toplevel 2>/dev/null)
    if [ -z "$root" ]; then
        __err "Não está em repo git"
        return 1
    fi

    local brief="$root/VALIDATOR_BRIEF.md"
    if [ ! -f "$brief" ]; then
        __err "BRIEF ausente. Use ${D_GREEN}sprint val${D_RESET} pra criar automaticamente."
        return 1
    fi

    ${EDITOR:-vi} "$brief"
}

__sprint_bootstrap_clipboard() {
    local root
    root=$(git rev-parse --show-toplevel 2>/dev/null)
    if [ -z "$root" ]; then
        __err "Não está em repo git"
        return 1
    fi

    local projeto
    projeto=$(basename "$root" | tr '[:upper:]' '[:lower:]')
    local template="$HOME/.claude/templates/bootstrap-${projeto}.md"

    if [ ! -f "$template" ]; then
        template="$HOME/.claude/templates/bootstrap-genérico.md"
        __warn "Template específico não encontrado, usando genérico"
        echo -e "  ${D_COMMENT}Para customizar: crie ${D_GREEN}~/.claude/templates/bootstrap-${projeto}.md${D_RESET}"
    fi

    if [ ! -f "$template" ]; then
        __err "Nenhum template disponível em ~/.claude/templates/"
        return 1
    fi

    if ! command -v xclip > /dev/null 2>&1; then
        __warn "xclip não instalado"
        echo -e "  ${D_COMMENT}Conteúdo do template em: ${D_GREEN}$template${D_RESET}"
        echo -e "  ${D_COMMENT}Instale: ${D_GREEN}sudo apt install xclip${D_RESET}"
        return 1
    fi

    awk '/^---$/ && !seen++ {next} seen {print}' "$template" | xclip -selection clipboard
    __ok "Template copiado pro clipboard"
    echo -e "  ${D_COMMENT}Cole na sessão Claude viva do projeto (Ctrl+Shift+V)${D_RESET}"
    echo -e "  ${D_COMMENT}Template usado: ${D_GREEN}$(basename "$template")${D_RESET}"
}

__sprint_doctor() {
    __header "CLAUDE SETUP DOCTOR" "$D_PURPLE"
    local issues=0

    __item "Agentes" "" "$D_COMMENT" "$D_FG"
    local agent
    for agent in planejador-sprint executor-sprint validador-sprint; do
        if [ -f "$HOME/.claude/agents/$agent.md" ]; then
            echo -e "    ${D_GREEN}[OK]${D_RESET} $agent"
        else
            echo -e "    ${D_ORANGE}[FALTA]${D_RESET} $agent"
            ((issues++))
        fi
    done

    echo ""
    __item "Commands" "" "$D_COMMENT" "$D_FG"
    local cmd
    for cmd in planejar-sprint executar-sprint validar-sprint sprint-ciclo; do
        if [ -f "$HOME/.claude/commands/$cmd.md" ]; then
            echo -e "    ${D_GREEN}[OK]${D_RESET} /$cmd"
        else
            echo -e "    ${D_ORANGE}[FALTA]${D_RESET} /$cmd"
            ((issues++))
        fi
    done

    echo ""
    __item "Hooks" "" "$D_COMMENT" "$D_FG"
    if [ -f "$HOME/.claude/hooks/guardian.py" ]; then
        echo -e "    ${D_GREEN}[OK]${D_RESET} guardian.py (bloqueia emojis e atribuições a IA)"
    else
        echo -e "    ${D_ORANGE}[FALTA]${D_RESET} guardian.py"
        ((issues++))
    fi

    local emoji_path="$HOME/Controle de Bordo/.sistema/scripts/emoji_guardian.py"
    if [ -f "$emoji_path" ]; then
        echo -e "    ${D_GREEN}[OK]${D_RESET} emoji_guardian.py ativo"
    else
        echo -e "    ${D_ORANGE}[FALTA]${D_RESET} emoji_guardian.py fora do path"
        ((issues++))
    fi

    echo ""
    __item "Shell" "" "$D_COMMENT" "$D_FG"
    if typeset -f cca > /dev/null 2>&1; then
        echo -e "    ${D_GREEN}[OK]${D_RESET} cca carregado"
    else
        echo -e "    ${D_ORANGE}[FALTA]${D_RESET} cca não carregado"
        ((issues++))
    fi

    if typeset -f santuário > /dev/null 2>&1; then
        echo -e "    ${D_GREEN}[OK]${D_RESET} santuário carregado"
    else
        echo -e "    ${D_ORANGE}[FALTA]${D_RESET} santuário não carregado"
        ((issues++))
    fi

    echo ""
    __item "Settings" "" "$D_COMMENT" "$D_FG"
    if command -v jq > /dev/null 2>&1 && jq empty "$HOME/.claude/settings.json" 2>/dev/null; then
        local plugins perms has_hook
        plugins=$(jq -r '.enabledPlugins | length' "$HOME/.claude/settings.json")
        perms=$(jq -r '.permissions.allow | length' "$HOME/.claude/settings.json")
        has_hook=$(jq -r '.hooks.PreToolUse | length' "$HOME/.claude/settings.json" 2>/dev/null)
        echo -e "    ${D_GREEN}[OK]${D_RESET} settings.json válido (${plugins} plugins, ${perms} perms, ${has_hook:-0} pre-tool hooks)"
    else
        echo -e "    ${D_ORANGE}[FALTA]${D_RESET} settings.json inválido ou ausente"
        ((issues++))
    fi

    echo ""
    __item "Templates" "" "$D_COMMENT" "$D_FG"
    local templates_count
    templates_count=$(ls "$HOME/.claude/templates/"*.md 2>/dev/null | wc -l)
    echo -e "    ${D_GREEN}[OK]${D_RESET} $templates_count template(s) em ~/.claude/templates/"

    echo ""
    __item "Hooks v2" "" "$D_COMMENT" "$D_FG"
    for f in session-start-briefing.py post-plan-clear.py; do
        if [ -e "$HOME/.claude/hooks/$f" ]; then
            echo -e "    ${D_GREEN}[OK]${D_RESET} $f"
        else
            echo -e "    ${D_ORANGE}[FALTA]${D_RESET} $f"
            ((issues++))
        fi
    done

    echo ""
    __item "Skill validação-visual" "" "$D_COMMENT" "$D_FG"
    if [ -e "$HOME/.claude/skills/validacao-visual/SKILL.md" ]; then
        echo -e "    ${D_GREEN}[OK]${D_RESET} skill registrada"
    else
        echo -e "    ${D_ORANGE}[FALTA]${D_RESET} skill validação-visual"
        ((issues++))
    fi

    echo ""
    __item "Docs versionados (docs/claude/)" "" "$D_COMMENT" "$D_FG"
    local docs_count
    docs_count=$(ls "$HOME/.config/zsh/docs/claude/"*.md 2>/dev/null | wc -l)
    if [ "$docs_count" -ge 10 ]; then
        echo -e "    ${D_GREEN}[OK]${D_RESET} $docs_count docs em ~/.config/zsh/docs/claude/"
    else
        echo -e "    ${D_ORANGE}[FALTA]${D_RESET} apenas $docs_count docs (esperado >=10)"
        ((issues++))
    fi

    echo ""
    __item "Bootstrap-rico" "" "$D_COMMENT" "$D_FG"
    if [ -e "$HOME/.config/zsh/scripts/bootstrap-rico-brief.py" ]; then
        echo -e "    ${D_GREEN}[OK]${D_RESET} bootstrap-rico-brief.py"
    else
        echo -e "    ${D_ORANGE}[FALTA]${D_RESET} bootstrap-rico-brief.py"
        ((issues++))
    fi

    echo ""
    __item "14 lições ativas no agents v2" "" "$D_COMMENT" "$D_FG"
    local validador="$HOME/.claude/agents/validador-sprint.md"
    local executor="$HOME/.claude/agents/executor-sprint.md"
    local checks_ok=0
    grep -q "14 checks universais" "$validador" 2>/dev/null && ((checks_ok++))
    grep -q "PONTO-CEGO" "$validador" 2>/dev/null && ((checks_ok++))
    grep -q "anti-débito" "$validador" 2>/dev/null && ((checks_ok++))
    grep -q "Verificar hipótese" "$executor" 2>/dev/null && ((checks_ok++))
    grep -q "Aritmética" "$executor" 2>/dev/null && ((checks_ok++))
    echo -e "    ${D_GREEN}[OK]${D_RESET} $checks_ok/5 heurísticas v2 detectadas"

    echo ""
    if [ "$issues" -eq 0 ]; then
        __ok "Setup Claude v2 saudável (tudo integrado)"
    else
        __warn "$issues issue(s) detectado(s)"
    fi
}

__sprint_subcomandos() {
    local -a subcomandos
    subcomandos=(
        'plan:Planeja sprint (gera spec)'
        'exec:Executa sprint (implementa spec aprovado)'
        'val:Valida sprint (proof-of-work)'
        'ciclo:Ciclo completo plan->exec->val (automatico)'
        'ciclo-manual:Ciclo com checkpoints entre fases (opt-in)'
        'brief:Status do VALIDATOR_BRIEF.md'
        'brief-edit:Abre BRIEF no editor'
        'bootstrap:Copia template bootstrap pro clipboard'
        'bootstrap --rich:Gera BRIEF rico via script (projetos conhecidos)'
        'doctor:Health check completo (14 licoes + setup)'
        'doctor-quick:Health check silencioso (chamado por santuario)'
        'help:Mostra ajuda'
    )
    _describe 'subcomando' subcomandos
}

# Propósito: Gera VALIDATOR_BRIEF.md rico a partir de memórias históricas
# Uso: sprint bootstrap --rich [projeto]
__sprint_bootstrap_rico() {
    local root projeto kind
    root=$(git rev-parse --show-toplevel 2>/dev/null)
    if [ -z "$root" ]; then
        __err "Não está em repo git"
        return 1
    fi

    if [ -n "${1:-}" ]; then
        kind="$1"
    else
        projeto=$(basename "$root" | tr '[:upper:]' '[:lower:]')
        case "$projeto" in
            luna)                kind="luna" ;;
            nyx-code)            kind="nyx-code" ;;
            protocolo-ouroboros) kind="protocolo-ouroboros" ;;
            *)
                __err "Projeto genérico: use 'sprint val' (dispatcha BOOTSTRAP do validador)"
                return 1
                ;;
        esac
    fi

    local script="$HOME/.config/zsh/scripts/bootstrap-rico-brief.py"
    if [ ! -x "$script" ] && [ ! -f "$script" ]; then
        __err "Script ausente: $script"
        return 1
    fi

    python3 "$script" --projeto "$kind" --saida "$root/VALIDATOR_BRIEF.md"
}

# Propósito: Health check silencioso do setup Claude (chamado por santuário)
# Uso: __sprint_doctor_quick
# Imprime 1 linha com issues se detectados, ou fica em silêncio se tudo OK.
__sprint_doctor_quick() {
    local issues=0
    local -a faltando

    local f
    for f in \
        "$HOME/.claude/agents/planejador-sprint.md" \
        "$HOME/.claude/agents/executor-sprint.md" \
        "$HOME/.claude/agents/validador-sprint.md" \
        "$HOME/.claude/commands/planejar-sprint.md" \
        "$HOME/.claude/commands/executar-sprint.md" \
        "$HOME/.claude/commands/validar-sprint.md" \
        "$HOME/.claude/commands/sprint-ciclo.md" \
        "$HOME/.claude/hooks/guardian.py" \
        "$HOME/.claude/hooks/session-start-briefing.py" \
        "$HOME/.claude/hooks/post-plan-clear.py"; do
        if [ ! -e "$f" ]; then
            faltando+=("$(basename "$f")")
            ((issues++))
        fi
    done

    if ! typeset -f cca > /dev/null 2>&1; then
        faltando+=("cca")
        ((issues++))
    fi

    if [ "${SANTUARIO_DOCTOR_VERBOSE:-0}" = "1" ] && [ "$issues" -eq 0 ]; then
        __ok "sprint doctor-quick: setup OK"
        return 0
    fi

    if [ "$issues" -gt 0 ]; then
        __warn "sprint doctor: ${issues} issue(s): ${faltando[*]}"
    fi
    return 0
}
