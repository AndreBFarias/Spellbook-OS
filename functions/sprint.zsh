#!/bin/zsh
# Função sprint: integracao unificada com o sistema de sprints Claude Code
# (planejador-sprint + executor-sprint + validador-sprint)
# Requer: cca (wrapper claude com quota guard) em cca/aliases_cca.zsh

# Proposito: Wrapper unificado para o ciclo de sprint Claude Code
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
        brief|status)
            __sprint_brief_status
            ;;
        brief-edit|edit)
            __sprint_brief_edit
            ;;
        bootstrap|boot)
            __sprint_bootstrap_clipboard
            ;;
        doctor|check)
            __sprint_doctor
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
    echo -e "    ${D_GREEN}sprint plan${D_RESET} <ideia>        Planeja sprint (gera spec)"
    echo -e "    ${D_GREEN}sprint exec${D_RESET} [spec]         Executa sprint (implementa)"
    echo -e "    ${D_GREEN}sprint val${D_RESET} [plano]         Valida sprint (proof-of-work)"
    echo -e "    ${D_GREEN}sprint ciclo${D_RESET} <ideia>       Ciclo completo com checkpoints"
    echo ""
    echo -e "  ${D_FG}Memoria (VALIDATOR_BRIEF.md):${D_RESET}"
    echo -e "    ${D_GREEN}sprint brief${D_RESET}               Status do BRIEF do projeto"
    echo -e "    ${D_GREEN}sprint brief-edit${D_RESET}          Abre BRIEF no editor"
    echo -e "    ${D_GREEN}sprint bootstrap${D_RESET}           Copia template bootstrap-rico pro clipboard"
    echo ""
    echo -e "  ${D_FG}Diagnostico:${D_RESET}"
    echo -e "    ${D_GREEN}sprint doctor${D_RESET}              Health check do setup Claude"
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
        __warn "Não esta em repo git. Recomendado rodar sprint dentro de um projeto."
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
        __err "Não esta em repo git"
        return 1
    fi

    local brief="$root/VALIDATOR_BRIEF.md"
    if [ ! -f "$brief" ]; then
        __header "VALIDADOR_BRIEF" "$D_YELLOW"
        __warn "BRIEF ausente em $(basename "$root")"
        echo -e "  ${D_COMMENT}Sera criado automaticamente no 1o ${D_GREEN}sprint val${D_COMMENT} ou ${D_GREEN}sprint ciclo${D_RESET}"
        echo -e "  ${D_COMMENT}Ou use ${D_GREEN}sprint bootstrap${D_COMMENT} para dump-rico em sessão viva${D_RESET}"
        return 0
    fi

    local lines sections age_days
    lines=$(wc -l < "$brief")
    sections=$(grep -c '^## ' "$brief" 2>/dev/null)
    age_days=$(( ($(date +%s) - $(stat -c %Y "$brief")) / 86400 ))

    __header "VALIDADOR_BRIEF: $(basename "$root")" "$D_CYAN"
    __item "Linhas" "$lines" "$D_COMMENT" "$D_FG"
    __item "Secoes" "$sections" "$D_COMMENT" "$D_FG"
    __item "Idade" "${age_days}d" "$D_COMMENT" "$D_FG"
    __item "Path" "$brief" "$D_COMMENT" "$D_GREEN"
    echo ""
    __item "Secoes detectadas:" "" "$D_COMMENT" "$D_FG"
    grep '^## ' "$brief" 2>/dev/null | sed 's/^## /    - /'
}

__sprint_brief_edit() {
    local root
    root=$(git rev-parse --show-toplevel 2>/dev/null)
    if [ -z "$root" ]; then
        __err "Não esta em repo git"
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
        __err "Não esta em repo git"
        return 1
    fi

    local projeto
    projeto=$(basename "$root" | tr '[:upper:]' '[:lower:]')
    local template="$HOME/.claude/templates/bootstrap-${projeto}.md"

    if [ ! -f "$template" ]; then
        template="$HOME/.claude/templates/bootstrap-generico.md"
        __warn "Template especifico não encontrado, usando generico"
        echo -e "  ${D_COMMENT}Para customizar: crie ${D_GREEN}~/.claude/templates/bootstrap-${projeto}.md${D_RESET}"
    fi

    if [ ! -f "$template" ]; then
        __err "Nenhum template disponivel em ~/.claude/templates/"
        return 1
    fi

    if ! command -v xclip > /dev/null 2>&1; then
        __warn "xclip não instalado"
        echo -e "  ${D_COMMENT}Conteudo do template em: ${D_GREEN}$template${D_RESET}"
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
        echo -e "    ${D_GREEN}[OK]${D_RESET} guardian.py (bloqueia emojis e atribuicoes a IA)"
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

    if typeset -f santuario > /dev/null 2>&1; then
        echo -e "    ${D_GREEN}[OK]${D_RESET} santuario carregado"
    else
        echo -e "    ${D_ORANGE}[FALTA]${D_RESET} santuario não carregado"
        ((issues++))
    fi

    echo ""
    __item "Settings" "" "$D_COMMENT" "$D_FG"
    if command -v jq > /dev/null 2>&1 && jq empty "$HOME/.claude/settings.json" 2>/dev/null; then
        local plugins perms has_hook
        plugins=$(jq -r '.enabledPlugins | length' "$HOME/.claude/settings.json")
        perms=$(jq -r '.permissions.allow | length' "$HOME/.claude/settings.json")
        has_hook=$(jq -r '.hooks.PreToolUse | length' "$HOME/.claude/settings.json" 2>/dev/null)
        echo -e "    ${D_GREEN}[OK]${D_RESET} settings.json valido (${plugins} plugins, ${perms} perms, ${has_hook:-0} pre-tool hooks)"
    else
        echo -e "    ${D_ORANGE}[FALTA]${D_RESET} settings.json invalido ou ausente"
        ((issues++))
    fi

    echo ""
    __item "Templates" "" "$D_COMMENT" "$D_FG"
    local templates_count
    templates_count=$(ls "$HOME/.claude/templates/"*.md 2>/dev/null | wc -l)
    echo -e "    ${D_GREEN}[OK]${D_RESET} $templates_count template(s) em ~/.claude/templates/"

    echo ""
    if [ "$issues" -eq 0 ]; then
        __ok "Setup Claude saudavel (tudo integrado)"
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
        'ciclo:Ciclo completo plan->exec->val'
        'brief:Status do VALIDATOR_BRIEF.md'
        'brief-edit:Abre BRIEF no editor'
        'bootstrap:Copia template bootstrap pro clipboard'
        'doctor:Health check do setup'
        'help:Mostra ajuda'
    )
    _describe 'subcomando' subcomandos
}
