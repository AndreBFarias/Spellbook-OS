#!/bin/zsh
# Completers dinâmicos referenciados em `# Completa:` nos metadados das funções.
# Carregado em env.zsh após compinit.

# -------------------------------------------------------------------
# Projeto / santuario
# -------------------------------------------------------------------

# Lista pastas em $DEV_DIR (e opcionalmente VitoriaMariaDB) — usado pelo
# primeiro argumento de `santuario`.
__santuario_pastas_dev() {
    local base="${DEV_DIR:-$HOME/Desenvolvimento}"
    local -a pastas
    if [[ -d "$base" ]]; then
        pastas=("$base"/*(/N:t))
    fi
    if [[ -d "$base/VitoriaMariaDB" ]]; then
        local -a pastas_vit
        pastas_vit=("$base/VitoriaMariaDB"/*(/N:t))
        for p in $pastas_vit; do pastas+=("$p (VitoriaMariaDB)"); done
    fi
    _describe 'projeto' pastas
}

# Lista branches locais do repo git cujo path é $DEV_DIR/$words[2].
__santuario_branches_git() {
    local projeto="${words[2]:-}"
    local base="${DEV_DIR:-$HOME/Desenvolvimento}"
    local repo="$base/$projeto"
    [[ -d "$repo/.git" ]] || return 0
    local -a branches
    branches=(${(f)"$(git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null)"})
    _describe 'branch' branches
}

# -------------------------------------------------------------------
# Git genérico
# -------------------------------------------------------------------

__git_branches_locais() {
    [[ -d ".git" ]] || return 0
    local -a branches
    branches=(${(f)"$(git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null)"})
    _describe 'branch' branches
}

__git_reflog() {
    [[ -d ".git" ]] || return 0
    local -a entries
    entries=(${(f)"$(git reflog --format='%h:%s' -20 2>/dev/null)"})
    _describe 'ref' entries
}

# -------------------------------------------------------------------
# Vault / Controle de Bordo
# -------------------------------------------------------------------

__vnova_tipos() {
    local -a tipos
    tipos=(
        'daily:Nota diária'
        'projeto:Projeto de código'
        'trabalho:Nota de trabalho'
        'conceito:Referência/conhecimento'
        'pessoal:Nota pessoal'
        'saude:Registro de saúde'
        'habito:Hábito'
        'meta:Meta pessoal'
        'estudo:Anotação de estudo'
        'evento:Evento/agenda'
        'conta:Conta/financeiro'
    )
    _describe 'tipo' tipos
}

__vtask_clientes() {
    local -a clientes
    clientes=(
        'mec:MEC direto (Vitória)'
        'g4f:G4F contractor (André)'
        'energisa:Energisa (André)'
        'mulher:Projeto Mulher (Vitória)'
        'pessoal:Tarefas pessoais (Casal)'
    )
    _describe 'cliente' clientes
}

__vault_arquivos_md() {
    _files -W "${BORDO_DIR:-$HOME/Controle de Bordo}" -g "*.md"
}

# -------------------------------------------------------------------
# Encoding
# -------------------------------------------------------------------

__enc_encodings() {
    local -a encs
    encs=('utf-8:UTF-8 (recomendado)' 'latin1:ISO-8859-1' 'cp1252:Windows-1252' 'ascii:ASCII puro')
    _describe 'encoding' encs
}

# -------------------------------------------------------------------
# Conjurar
# -------------------------------------------------------------------

__conjurar_modos() {
    local -a modos
    modos=(
        '--help:Exibe ajuda'
        '--list:Lista sem fzf'
        '--search:Busca com termo inicial'
        '--recent:Últimos 5 executados'
    )
    _describe 'modo' modos
}
