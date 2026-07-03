#!/bin/zsh

# -- Relatório de Serviço MEC/G4F: pipeline universal --
# Fluxo mensal: relatorio novo -> editar no OnlyOffice -> exportar PDF ->
#               relatorio pdf <arquivo.pdf> -> assinar no gov.br
# Payload canônico (scripts/fontes/aliases): Dracula_OS-Theme, módulo relatorio-mec
# (instalar_relatorio_mec.sh é idempotente e autocurativo — `relatorio check` reaplica).

__RELATORIO_VAULT="${RELATORIO_VAULT:-${HOME}/Controle de Bordo/Trabalho/Andre/G4F/Relatorios}"
__RELATORIO_TEMPLATE="${__RELATORIO_VAULT}/template_relatorio_servico_universal.docx"
__RELATORIO_MENSAIS="${__RELATORIO_VAULT}/Mensais"
__RELATORIO_DRACULA="${DRACULA_OS_ROOT:-${HOME}/Desenvolvimento/Dracula_OS-Theme}"
__RELATORIO_NOME_BASE="Relatório MEC - G4F - André da Silva Analista de BI"

__relatorio_ajuda() {
    echo -e "  ${D_PURPLE}${D_BOLD}relatorio${D_RESET} — Relatório de Serviço MEC/G4F"
    echo -e "  ${D_COMMENT}$(printf '%.0s─' {1..50})${D_RESET}"
    echo -e "  ${D_CYAN}relatorio novo${D_RESET} [MM-YYYY]   cria o docx do mês a partir do template universal"
    echo -e "  ${D_CYAN}relatorio doctor${D_RESET} <docx>    diagnostica fontes/logos/placeholders (--aplicar --logos trata)"
    echo -e "  ${D_CYAN}relatorio pdf${D_RESET} <pdf>        lava o PDF exportado do OnlyOffice p/ o assinador gov.br"
    echo -e "  ${D_CYAN}relatorio check${D_RESET}            verifica e AUTOCURA o pipeline (fontes, aliases, scripts)"
    echo -e "  ${D_CYAN}relatorio instalar${D_RESET}         idem + instala dependências apt que faltarem (sudo -n)"
}

__relatorio_check() {
    local instalador="${__RELATORIO_DRACULA}/scripts/instalar_relatorio_mec.sh"
    if [[ ! -x "$instalador" ]]; then
        echo -e "  ${D_RED}!!${D_RESET} Dracula_OS-Theme não encontrado em ${__RELATORIO_DRACULA}" >&2
        echo -e "  ${D_COMMENT}   clone o repo ou exporte DRACULA_OS_ROOT${D_RESET}" >&2
        return 1
    fi
    "$instalador" "$@"
}

__relatorio_novo() {
    local mes="${1:-$(date +%m-%Y)}"
    if [[ ! "$mes" =~ ^[0-1][0-9]-20[0-9][0-9]$ ]]; then
        echo -e "  ${D_RED}!!${D_RESET} mês inválido: '$mes' (esperado MM-YYYY, ex.: 07-2026)" >&2
        return 1
    fi
    local destino="${__RELATORIO_MENSAIS}/${mes} - ${__RELATORIO_NOME_BASE}.docx"
    if [[ ! -f "$__RELATORIO_TEMPLATE" ]]; then
        echo -e "  ${D_RED}!!${D_RESET} template não encontrado: $__RELATORIO_TEMPLATE" >&2
        return 1
    fi
    if [[ -f "$destino" ]]; then
        echo -e "  ${D_YELLOW}!!${D_RESET} já existe (não sobrescrevo): $destino"
    else
        mkdir -p "$__RELATORIO_MENSAIS"
        cp "$__RELATORIO_TEMPLATE" "$destino"
        echo -e "  ${D_GREEN}OK${D_RESET} criado: $destino"
        echo -e "  ${D_YELLOW}!!${D_RESET} ATENÇÃO: o template carrega o CONTEÚDO do mês anterior"
        echo -e "  ${D_COMMENT}   revise TODAS as seções (narrativa, Encarte B, prints do Encarte C)${D_RESET}"
    fi
    command -v xdg-open >/dev/null && xdg-open "$destino" >/dev/null 2>&1 &
}

relatorio() {
    local cmd="${1:-ajuda}"
    [[ $# -gt 0 ]] && shift
    case "$cmd" in
        novo)      __relatorio_novo "$@" ;;
        doctor)    docx_doctor "$@" ;;
        pdf)       relatorio_pdf "$@" ;;
        check)     __relatorio_check ;;
        instalar)  __relatorio_check --apt ;;
        ajuda|-h|--help|*) __relatorio_ajuda ;;
    esac
}
