#!/bin/bash
# _lib.sh — Biblioteca compartilhada para hooks git
# Regexes centralizados + funções de logging
# Identidades lidas de config.local.zsh (variáveis ZSH_IDENTITY_*)
# Fonte: source "$HOME/.config/git/hooks/_lib.sh" 2>/dev/null || true

# Auto-carrega o config.local.zsh: sem isto, hooks em contexto NAO-interativo
# (git de GUI, ssh remoto, cron) rodavam com as variaveis vazias e o pre-push
# falhava mudo exigindo alias github.com. [mediacao Andromeda 2026-07-21]
# shellcheck source=/dev/null
source "${ZDOTDIR:-$HOME/.config/zsh}/config.local.zsh" 2>/dev/null || true

# --- Diretorio de logs ---
HOOK_LOG_DIR="$HOME/.local/share/spellbook"
HOOK_LOG_FILE="$HOOK_LOG_DIR/hooks.log"

# --- Regexes centralizados ---

# Emojis (para grep -P / perl)
EMOJI_RE='[\x{1F600}-\x{1F64F}\x{1F300}-\x{1F5FF}\x{1F680}-\x{1F6FF}\x{2600}-\x{26FF}\x{2700}-\x{27BF}\x{1F900}-\x{1F9FF}\x{1FA00}-\x{1FA6F}\x{1FA70}-\x{1FAFF}]'

# Co-autoria e atribuicao (case-insensitive via grep -iE)
COAUTHOR_RE='[Cc]o-[Aa]uthored-[Bb]y|[Pp]aired-[Ww]ith|[Aa]ssisted-[Bb]y'

# Mencoes a ferramentas de IA em MENSAGEM de commit (commit-msg, pre-push).
#
# [2026-07-30, sprint INFRA-HOOK-COMMIT-MSG-MODELO-IA] O gate continua
# bloqueando mencao a ferramenta de IA na mensagem -- a ideia original vale.
# Mudou a FRONTEIRA, em dois pontos, cada um com dano medido:
#
#   (1) fronteira de palavra (\< \>): o nome do fornecedor colado dentro de um
#       identificador ou de um path (a_b_c, dir/a_b_c) e vocabulario tecnico do
#       projeto, não atribuicao de autoria. Sem isso, "restaura o path do
#       <x>_ocr_cache" saiu do hook como "<agente>_ocr_cache" na mensagem do
#       commit bfac3d78 -- a mensagem passou a afirmar um diretorio que não
#       existe -- e o mesmo texto no ASSUNTO era impossivel de commitar.
#       Como "_" e caractere de palavra para o grep/sed do GNU, \< \> ja
#       isolam o caso; e a mesma semantica de STANDALONE_MODEL_RE em
#       hooks/check_anonymity.py:93 do protocolo-ouroboros.
#
#   (2) "cursor" saiu desta lista e ganhou variavel propria com filtro de
#       contexto (AI_MENTION_CURSOR_RE + AI_CURSOR_EXCLUDE_RE), do mesmo jeito
#       que AI_WORD_CODE_RE ja fazia para conteudo de arquivo: e propriedade
#       CSS (cursor: pointer), cursor de banco (cursor.execute) e cursor de
#       texto. Como estava, comeu uma linha inteira de mensagem em 0b2798b2.
#
# O que NÃO mudou: "gerado por <modelo>" continua bloqueado. Prosa de autoria
# não tem underscore nem marcador de cursor -- casa a fronteira de palavra e
# cai no gate, que e exatamente a razao de o hook existir.
AI_MENTION_RE='\<([Cc]laude|[Aa]nthropic|[Oo]pen[Aa][Ii]|[Cc]hat[Gg][Pp][Tt]|[Cc]opilot|[Gg]emini|[Gg][Pp][Tt]-[34]|[Dd]eep[Ss]eek|[Aa]ider|[Ww]indsurf|[Cc]odeium|[Tt]abnine|[Oo]pus|[Ss]onnet|[Hh]aiku|[Ff]able|noreply@anthropic)\>'

# "Cursor" em mensagem: so conta quando a mensagem NÃO tem nenhum marcador de
# cursor real (ver AI_CURSOR_EXCLUDE_RE abaixo).
AI_MENTION_CURSOR_RE='\<[Cc]ursor\>'

# Mesma lista, com fronteira de palavra (\b) e SEM "Cursor" -- usada para
# substituicao palavra-a-palavra em CONTEUDO de arquivo (comentario,
# docstring, prosa, config), onde "cursor" colide demais com cursor de
# banco/UI real (`cursor = conn.cursor()`). "Cursor" ganha checagem propria
# com filtro de contexto via AI_CURSOR_EXCLUDE_RE (ver pre-commit).
AI_WORD_CODE_RE='\b([Cc]laude|[Aa]nthropic|[Oo]pen[Aa][Ii]|[Cc]hat[Gg][Pp][Tt]|[Gg]emini|[Gg][Pp][Tt]-[34]|[Dd]eep[Ss]eek|[Aa]ider|[Ww]indsurf|[Cc]odeium|[Tt]abnine|[Oo]pus|[Ss]onnet|[Hh]aiku|[Ff]able)\b'

# Marcadores de contexto que indicam "cursor" real (banco de dados/UI), nao
# o editor Cursor. Mesmo filtro usado em scripts/auditoria-repos.sh.
# [2026-07-30] Acrescentado `cursor\.<letra>`: acesso a atributo so acontece
# num objeto cursor de banco/UI (cursor.execute, cursor.fetchall). O nome da
# ferramenta em prosa nunca aparece seguido de ponto e letra minuscula.
AI_CURSOR_EXCLUDE_RE='(api_key|api-key|provider|model|client|_MODEL|_API|endpoint|baseurl|base_url|\.cursor\(\)|cursor\s*=\s*conn|cursor\s*=\s*db|cursor\s*=\s*self|getcursor|set_cursor|cursor_factory|CursorKind|cursor\s*:|:\s*cursor\b|cursorPointer|cursor\.[a-z_])'

# Secrets (para grep -P)
SECRET_RE='(sk-[a-zA-Z0-9]{20,}|sk-ant-[a-zA-Z0-9]{20,}|AIza[0-9A-Za-z_-]{35}|ghp_[a-zA-Z0-9]{36}|gho_[a-zA-Z0-9]{36}|github_pat_[a-zA-Z0-9]{22}_[a-zA-Z0-9]{59}|AKIA[0-9A-Z]{16})'

# --- Mencao a IA em mensagem de commit ---
#
# Um unico par de funcoes para commit-msg e pre-push. Antes cada hook montava
# o proprio `grep -qiE "$AI_MENTION_RE"`; com o filtro de contexto do cursor
# isso viraria a mesma logica escrita duas vezes -- e divergir aqui produz o
# pior defeito possivel: o commit-msg aceita a mensagem e o pre-push barra o
# push da mesma mensagem, sem saida.

_AI_KEEP_TOKEN='(`[^`\n]*`|\S*/\S*|[A-Za-z0-9]+(?:[-._][A-Za-z0-9]+)+)'

# No ASSUNTO o hifen NAO protege. Corpo e assunto tem contratos diferentes por
# desenho -- o corpo e reescrito (scrub), o assunto e BLOQUEADO -- entao a lista
# de tokens preservados tambem difere: no corpo, preservar `<x>-desktop` evita
# que a frase "reescreveu <x>-desktop como agente-desktop" saia do hook dizendo
# "agente-desktop como agente-desktop"; no assunto, preservar o mesmo token
# desligaria o gate para qualquer nome de ferramenta escrito em kebab, que e
# justamente a forma como esses produtos se chamam. O underscore continua
# protegido nos dois: `\<`/`\>` do GNU tratam `_` como letra e `-` como
# fronteira, entao identificador snake_case e nome de variavel de ambiente
# seguem passando no assunto.
_AI_KEEP_TOKEN_ASSUNTO='(`[^`\n]*`|\S*/\S*|[A-Za-z0-9]+(?:[._][A-Za-z0-9]+)+)'

# Verdadeiro (0) quando o TEXTO menciona ferramenta de IA de um jeito que o
# projeto proibe. Uso: `if _ai_mention_in_text "$MSG"; then ...`
_ai_mention_in_text() {
    local texto="$1"
    local keep="${2:-$_AI_KEEP_TOKEN}"
    # Mesma guarda da substituicao: o que _ai_mention_scrub_text preserva nao
    # pode BLOQUEAR aqui, senao "corrige claude-desktop" no assunto vira commit
    # impossivel enquanto o mesmo texto no corpo passa intacto -- o pior defeito
    # possivel, gate e scrub discordando sobre o mesmo texto.
    texto=$(printf '%s\n' "$texto" | perl -CSD -pe "s{$keep}{ }g" 2>/dev/null)
    if printf '%s\n' "$texto" | grep -qiE "$AI_MENTION_RE" 2>/dev/null; then
        return 0
    fi
    if printf '%s\n' "$texto" | grep -qiP "$AI_CURSOR_EXCLUDE_RE" 2>/dev/null; then
        return 1
    fi
    printf '%s\n' "$texto" | grep -qiE "$AI_MENTION_CURSOR_RE" 2>/dev/null
}

# Verdadeiro (0) quando o ASSUNTO menciona ferramenta de IA. Mesma logica, so
# muda o conjunto protegido -- ver _AI_KEEP_TOKEN_ASSUNTO.
_ai_mention_in_subject() {
    _ai_mention_in_text "$1" "$_AI_KEEP_TOKEN_ASSUNTO"
}

# Devolve o TEXTO com as mencoes substituidas por "agente", preservando o
# resto da frase (nunca apaga a linha). O filtro de contexto do cursor e por
# TEXTO INTEIRO, não por linha: numa mensagem de commit a declaracao CSS
# aparece num paragrafo e a explicacao noutro.
# Mesma guarda do _PERL_KEEP_TOKEN do pre-commit: code span, token com barra
# (URL/caminho) e identificador tecnico (separador com alfanumerico dos dois
# lados) sao constante externa, nao mencao. Sem isto a mensagem "reescreveu
# claude-desktop como agente-desktop" saia do hook como "reescreveu
# agente-desktop como agente-desktop", perdendo o sentido.

# \< \> e fronteira do GNU e o perl NAO entende: passaria a exigir "<" literal
# e a substituicao pararia de casar qualquer coisa, desligando o gate inteiro
# sem avisar. Converte para \b antes de entregar ao perl.
_ai_re_para_perl() { printf '%s' "${1//\\</\\b}" | sed 's/\\>/\\b/g'; }

_ai_mention_scrub_text() {
    local texto="$1"
    local re_men re_cur
    re_men=$(_ai_re_para_perl "$AI_MENTION_RE")
    re_cur=$(_ai_re_para_perl "$AI_MENTION_CURSOR_RE")
    texto=$(printf '%s\n' "$texto" | perl -CSD -pe "s{$_AI_KEEP_TOKEN|$re_men}{ defined \$1 ? \$1 : q(agente) }gei")
    if ! printf '%s\n' "$texto" | grep -qiP "$AI_CURSOR_EXCLUDE_RE" 2>/dev/null; then
        texto=$(printf '%s\n' "$texto" | perl -CSD -pe "s{$_AI_KEEP_TOKEN|$re_cur}{ defined \$1 ? \$1 : q(agente) }gei")
    fi
    # Colapsa repeticao gerada pela propria substituicao ("agente agente").
    printf '%s\n' "$texto" | sed -E 's/\bagente([[:space:]-]+agente\b)+/agente/g'
}

# --- Funcoes utilitarias ---

_hook_log() {
    local hook_name="$1"
    local message="$2"
    local repo_name
    repo_name=$(_hook_repo_name)

    mkdir -p "$HOOK_LOG_DIR" 2>/dev/null
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$hook_name] [$repo_name] $message" >> "$HOOK_LOG_FILE" 2>/dev/null
}

_hook_repo_name() {
    local root
    root=$(git rev-parse --show-toplevel 2>/dev/null)
    if [[ -n "$root" ]]; then
        basename "$root"
    else
        echo "unknown"
    fi
}

_hook_detect_context() {
    local repo_path="$1"

    # Iterar sobre identidades configuradas em config.local.zsh
    for tag in $ZSH_IDENTITY_TAGS; do
        local path_var="ZSH_IDENTITY_${tag}_PATH"
        local name_var="ZSH_IDENTITY_${tag}_NAME"
        local email_var="ZSH_IDENTITY_${tag}_EMAIL"
        local ssh_var="ZSH_IDENTITY_${tag}_SSH"

        local path_pattern="${!path_var}"

        if [[ -n "$path_pattern" && ("$repo_path" == *"/${path_pattern}/"* || "$repo_path" == *"/${path_pattern}") ]]; then
            EXPECTED_NAME="${!name_var}"
            EXPECTED_EMAIL="${!email_var}"
            EXPECTED_SSH_ALIAS="${!ssh_var}"
            CONTEXT="$tag"
            return
        fi
    done

    # Fallback: identidade padrão
    EXPECTED_NAME="${ZSH_GIT_NAME_PESSOAL:-$(git config --global user.name)}"
    EXPECTED_EMAIL="${ZSH_GIT_EMAIL_PESSOAL:-$(git config --global user.email)}"
    EXPECTED_SSH_ALIAS="${ZSH_SSH_ALIAS_PESSOAL:-github.com}"
    CONTEXT="Pessoal"
}

_hook_validate_identity() {
    local current_name current_email
    current_name=$(git config --get user.name)
    current_email=$(git config --get user.email)

    if [[ "$current_name" != "$EXPECTED_NAME" || "$current_email" != "$EXPECTED_EMAIL" ]]; then
        echo "  [BLOQUEIO] Identidade incorreta para contexto $CONTEXT"
        echo "    Esperado: $EXPECTED_NAME <$EXPECTED_EMAIL>"
        echo "    Atual:    $current_name <$current_email>"
        echo "    Corrija com: santuario <projeto>"
        return 1
    fi
    return 0
}

# "A desconfianca e mae da seguranca." — Aristofanes
