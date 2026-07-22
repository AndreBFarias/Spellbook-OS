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

# rc=1 quando não ha mudancas OU quando o guard de secrets bloqueou: nada a empurrar.
__spellbook_auto_commit || exit 0

# Autosync so cobre main: numa branch/worktree diferente o commit local ja rodou
# (rede de seguranca acima), mas não ha o que empurrar pra origin/main.
branch=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null)
[[ "$branch" != "main" ]] && exit 0

logf="${XDG_STATE_HOME:-$HOME/.local/state}/spellbook-sync.log"
mkdir -p "${logf:h}" 2>/dev/null
if ! timeout 30 git -C "$dir" push origin main --quiet 2>>"$logf"; then
    print -r -- "[$(date '+%F %T')] timer push falhou (commit local salvo)" >>"$logf"
fi
