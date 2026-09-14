#!/usr/bin/zsh
# Aurora - runner do autosync periodico (disparado por spellbook-autosync.timer).
#
# Por que existe: o autosync histórico depende do hook zshexit (so dispara ao fechar
# terminal). Em 20/05 o guard de secrets travou e isso ficou MASCARADO por ~1 mes porque
# ninguem reparou que não havia commit. Este timer commita periodicamente, independente de
# abrir/fechar terminal -> zero perda de trabalho.
#
# Estrategia: commit local SEMPRE (com o guard de secrets de spellbook-sync.zsh) + push
# best-effort (a chave SSH personal não tem passphrase). Se o push falhar (offline), o
# commit fica salvo e o próximo sync (timer ou zshexit) empurra.

export ZDOTDIR="${ZDOTDIR:-$HOME/.config/zsh}"
dir="$ZDOTDIR"

source "$ZDOTDIR/functions/_helpers.zsh" 2>/dev/null
source "$ZDOTDIR/functions/spellbook-sync.zsh" 2>/dev/null || exit 0

logf="${XDG_STATE_HOME:-$HOME/.local/state}/spellbook-sync.log"
mkdir -p "${logf:h}" 2>/dev/null

# ---------------------------------------------------------------------------
# SANIDADE DO CHAMADOR — este bloco existe por causa de 45 dias de silencio.
#
# Ate 2026-09-14 a linha abaixo era:
#
#     __spellbook_auto_commit || exit 0
#
# e o comentario dizia "rc=1 quando não ha mudancas OU quando o guard bloqueou".
# Faltava a terceira possibilidade, que foi a que aconteceu: em 31/07/2026 a
# função foi RENOMEADA (virou o par _original/_guardado, para parar o commit cego
# e exigir mensagem descritiva) e o nome curto deixou de existir. `rc=127`,
# comando não encontrado — e o `|| exit 0` tratou isso como "nada a fazer".
#
# O servico rodou a cada 10 minutos por 45 DIAS, saindo com SUCCESS, sem
# commitar nada e sem uma linha de log. Dezenove arquivos ficaram parados. E o
# cabecalho deste mesmo arquivo ja narra o episodio de 20/05, quando o guard
# travou e ficou "MASCARADO por ~1 mes porque ninguem reparou". A mesma classe
# de falha, duas vezes, pelo mesmo motivo: sair calado.
#
# Agora função ausente e ERRO, com exit 1. O systemd marca a unit como failed,
# e `systemctl --user --failed` passa a denunciar.
# ---------------------------------------------------------------------------
if ! typeset -f __spellbook_auto_commit_guardado >/dev/null 2>&1; then
    msg="ERRO: __spellbook_auto_commit_guardado ausente em $ZDOTDIR/functions/spellbook-sync.zsh"
    print -r -- "[$(date '+%F %T')] $msg" >>"$logf"
    logger -t spellbook-autosync -p user.err "$msg" 2>/dev/null
    exit 1
fi

# A guarda de 31/07 e deliberada: sem SPELLBOOK_AUTOCOMMIT=1 o autosync NÃO
# commita, so aponta que ha pendencia. Isso e decisao, não defeito — commit cego
# com mensagem "auto: sync" não diz o que mudou. O que se conserta aqui e o
# SILENCIO, não a guarda.
__spellbook_auto_commit_guardado

# Pendencia parada: avisa no log, com represa de 24h para não virar ruido a cada
# 10 minutos. Sem represa o aviso vira paisagem e para de ser lido — que e outra
# forma de ficar mascarado.
if ! git -C "$dir" diff --quiet 2>/dev/null \
   || [[ -n "$(git -C "$dir" ls-files -o --exclude-standard 2>/dev/null)" ]]; then
    marca="${XDG_RUNTIME_DIR:-/tmp}/spellbook-autosync-avisado"
    agora=$(date +%s)
    ultimo=0
    [[ -f "$marca" ]] && ultimo=$(<"$marca") 2>/dev/null
    [[ "$ultimo" != <-> ]] && ultimo=0
    if (( agora - ultimo > 86400 )); then
        n=$(git -C "$dir" status --porcelain 2>/dev/null | wc -l)
        msg="$n arquivo(s) sem commit ha mais de 24h. Commite com mensagem própria, ou rode com SPELLBOOK_AUTOCOMMIT=1."
        print -r -- "[$(date '+%F %T')] $msg" >>"$logf"
        logger -t spellbook-autosync -p user.warning "$msg" 2>/dev/null
        print -r -- "$agora" >"$marca" 2>/dev/null
    fi
fi

# Sem commit novo para empurrar, encerra aqui. (`| read -q` NAO serve para isto:
# em zsh ele le UM caractere e so devolve 0 se for 'y' — o resultado dependeria
# da primeira letra do hash do commit.)
[[ -z "$(git -C "$dir" log origin/main..HEAD --oneline 2>/dev/null)" ]] && exit 0

# Autosync so cobre main: numa branch/worktree diferente o commit local ja rodou
# (rede de seguranca acima), mas não ha o que empurrar pra origin/main.
branch=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null)
[[ "$branch" != "main" ]] && exit 0

if ! timeout 30 git -C "$dir" push origin main --quiet 2>>"$logf"; then
    print -r -- "[$(date '+%F %T')] timer push falhou (commit local salvo)" >>"$logf"
fi
