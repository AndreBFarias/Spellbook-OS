#!/usr/bin/env bash
# aurora-zsh-ambiente.sh — guardiao do ambiente zsh que o git sozinho não guarda
# (2026-09-15, v3.73)
#
# POR QUE ESTE SCRIPT EXISTE
# O upgrade 22.04 -> 24.04 levou embora duas coisas que o repositorio não podia
# repor: o config.local.zsh (gitignored de proposito, e o único lugar onde as
# identidades git desta maquina moram) e dois plugins do oh-my-zsh (clonados
# pelo install.sh, nunca mais conferidos). Nenhuma das duas perdas deu erro
# visivel na hora. A primeira reapareceu horas depois como `[user]` VAZIO no
# .git/config de um repo, travando commit e push.
#
# Rodar como a USUARIA (o self-heal chama via runuser). Idempotente.
# Uso:
#   aurora-zsh-ambiente.sh            # confere, conserta o que e seguro
#   aurora-zsh-ambiente.sh --conferir # so confere, não escreve nada
#
# A FRONTEIRA DO QUE ELE CONSERTA, e o porque de cada lado:
#   CONSERTA plugin do oh-my-zsh faltando — artefato publico, clone idempotente,
#            nenhuma decisao envolvida.
#   CONSERTA chave user.name/user.email LOCAL com valor VAZIO — remover chave
#            vazia não escolhe identidade nenhuma: devolve o repo a herdar a
#            global, que e o estado correto de um repo sem override. E o reparo
#            do incidente de 15/09/2026.
#   SO AVISA config.local.zsh ausente — gerar identidade por adivinhacao e pior
#            que a ausencia. Quem preenche e um humano, a partir do template.

set -u

MODO_CONFERIR=0
[ "${1:-}" = "--conferir" ] && MODO_CONFERIR=1

ZDOTDIR_REAL="${ZDOTDIR:-$HOME/.config/zsh}"
CONFIG_LOCAL="$ZDOTDIR_REAL/config.local.zsh"
OMZ_PLUGINS="$ZDOTDIR_REAL/.oh-my-zsh/custom/plugins"

avisos=0
consertos=0

aviso()    { echo "  zsh-ambiente: AVISO — $*"; avisos=$((avisos + 1)); }
conserto() { echo "  zsh-ambiente: corrigido — $*"; consertos=$((consertos + 1)); }

# ---------------------------------------------------------------------------
# 1. config.local.zsh: existe e tem as variaveis que o resto do sistema assume
# ---------------------------------------------------------------------------
# A checagem não e so de existencia. Um arquivo presente mas com
# ZSH_GIT_NAME_PESSOAL vazio reproduz o mesmo incidente, e e um estado que o
# próprio template entrega (as linhas vem com valor de exemplo).
if [ ! -f "$CONFIG_LOCAL" ]; then
    aviso "config.local.zsh AUSENTE em $ZDOTDIR_REAL"
    echo "    Sem ele as identidades git ficam vazias e o santuario grava"
    echo "    user.name/user.email em branco no .git/config."
    echo "    Recrie a partir de: $ZDOTDIR_REAL/config.local.zsh.template"
else
    # Subshell: não queremos as variaveis dela vazando para o resto do script.
    faltando=$(
        # shellcheck source=/dev/null
        . "$CONFIG_LOCAL" 2>/dev/null
        for v in ZSH_GIT_NAME_PESSOAL ZSH_GIT_EMAIL_PESSOAL DEV_DIR; do
            eval "valor=\${$v:-}"
            [ -z "$valor" ] && printf '%s ' "$v"
        done
    )
    if [ -n "$faltando" ]; then
        aviso "config.local.zsh existe mas tem variavel vazia: $faltando"
    fi
    # Segredo em arquivo legivel por outros e o erro que ja custou caro aqui.
    modo=$(stat -c '%a' "$CONFIG_LOCAL" 2>/dev/null || echo "???")
    if [ "$modo" != "600" ]; then
        if [ "$MODO_CONFERIR" -eq 1 ]; then
            aviso "config.local.zsh com modo $modo (esperado 600)"
        else
            chmod 600 "$CONFIG_LOCAL" && conserto "config.local.zsh $modo -> 600"
        fi
    fi
fi

# ---------------------------------------------------------------------------
# 2. Plugins do oh-my-zsh declarados no env.zsh existem em disco
# ---------------------------------------------------------------------------
# A lista NÃO e hardcoded aqui. Ela sai do próprio `plugins=(...)` do env.zsh,
# que e a unica fonte de verdade; uma segunda lista neste arquivo seria a
# armadilha nº 3 do idempotencia-armadilhas.md (lista de nomes duplicada que
# envelhece sozinha). `git` e `fzf` sao built-in do oh-my-zsh e não tem pasta
# em custom/plugins — por isso a tabela de URLs abaixo so cobre os externos, e
# um plugin declarado que não esteja nem na tabela nem em disco vira AVISO.
declare -A PLUGIN_URL=(
    [zsh-autosuggestions]="https://github.com/zsh-users/zsh-autosuggestions"
    [zsh-syntax-highlighting]="https://github.com/zsh-users/zsh-syntax-highlighting"
    [zsh-history-substring-search]="https://github.com/zsh-users/zsh-history-substring-search"
    [fzf-tab]="https://github.com/Aloxaf/fzf-tab"
)

if [ -f "$ZDOTDIR_REAL/env.zsh" ]; then
    linha_plugins=$(grep -m1 '^plugins=(' "$ZDOTDIR_REAL/env.zsh" 2>/dev/null)
    declarados=$(echo "$linha_plugins" | sed -E 's/^plugins=\(//; s/\).*$//')
    for plug in $declarados; do
        # Built-in do oh-my-zsh: mora em plugins/, não em custom/plugins/.
        [ -d "$ZDOTDIR_REAL/.oh-my-zsh/plugins/$plug" ] && continue
        [ -d "$OMZ_PLUGINS/$plug" ] && continue

        url="${PLUGIN_URL[$plug]:-}"
        if [ -z "$url" ]; then
            aviso "plugin '$plug' declarado no env.zsh, ausente em disco e sem URL conhecida"
            continue
        fi
        if [ "$MODO_CONFERIR" -eq 1 ]; then
            aviso "plugin '$plug' ausente (seria clonado)"
            continue
        fi
        if git clone --depth=1 -q "$url" "$OMZ_PLUGINS/$plug" 2>/dev/null; then
            conserto "plugin '$plug' reinstalado"
        else
            aviso "plugin '$plug' ausente e o clone falhou (sem rede?)"
        fi
    done
fi

# ---------------------------------------------------------------------------
# 3. Repositorios com identidade LOCAL vazia
# ---------------------------------------------------------------------------
# A BARRA FINAL EM "$DEV_DIR/" NÃO E ENFEITE: DEV_DIR e symlink, e `find` sobre
# um symlink sem barra NÃO desce — devolve zero e o guardiao diria "tudo certo"
# sem ter olhado nada. Foi assim que as duas funções de sincronizacao ficaram
# mudas por meses.
#
# A deteção e pela PRESENCA da chave com valor vazio, nunca pelo rc:
# `git config --get user.name` devolve string vazia COM rc=0.
DEV_DIR_REAL=$(
    # shellcheck source=/dev/null
    . "$CONFIG_LOCAL" 2>/dev/null
    echo "${DEV_DIR:-$HOME/Desenvolvimento}"
)
[ -n "$DEV_DIR_REAL" ] || DEV_DIR_REAL="$HOME/Desenvolvimento"

repos_vazios=0
if [ -d "$DEV_DIR_REAL/" ]; then
    while IFS= read -r gitdir; do
        [ -n "$gitdir" ] || continue
        cfg="$gitdir/config"
        [ -f "$cfg" ] || continue
        sujo=0
        for chave in name email; do
            grep -qE "^[[:space:]]*${chave}[[:space:]]*=[[:space:]]*$" "$cfg" 2>/dev/null && sujo=1
        done
        [ "$sujo" -eq 1 ] || continue
        repos_vazios=$((repos_vazios + 1))
        repo="${gitdir%/.git}"
        if [ "$MODO_CONFERIR" -eq 1 ]; then
            aviso "identidade LOCAL vazia em $repo"
            continue
        fi
        for chave in user.name user.email; do
            if git -C "$repo" config --local --get "$chave" >/dev/null 2>&1 \
               && [ -z "$(git -C "$repo" config --local --get "$chave" 2>/dev/null)" ]; then
                git -C "$repo" config --local --unset-all "$chave" 2>/dev/null
            fi
        done
        conserto "identidade vazia removida em $repo (volta a herdar a global)"
    done <<EOF
$(find "$DEV_DIR_REAL/" -maxdepth 4 -name .git -type d -prune 2>/dev/null; find "$HOME/.config/zsh" -maxdepth 1 -name .git -type d -prune 2>/dev/null)
EOF
fi

# ---------------------------------------------------------------------------
# 4. O `claude` do PATH e o build nativo, e não um npm que voltou a sombrear
# ---------------------------------------------------------------------------
# Em 2026-09-15 esta maquina migrou do pacote npm para o build nativo. O detalhe
# que faz isto merecer vigilancia: o diretório do nvm vem ANTES do ~/.local/bin
# no PATH, entao basta um `npm install -g @anthropic-ai/claude-code` — feito a
# mao, ou por um `restaurar` a partir de manifesto antigo — para o npm voltar a
# ganhar sem ninguem perceber. O symlink do npm chegou a ser recriado as 10:15
# daquele mesmo dia, entao isso acontece.
# So AVISA: desinstalar pacote npm por conta própria e decisao, não reparo.
CLAUDE_BIN=$(command -v agente 2>/dev/null || true)
if [ -n "$CLAUDE_BIN" ]; then
    case "$CLAUDE_BIN" in
        *"/.nvm/"*|*"/node_modules/"*)
            aviso "o 'agente' do PATH e o do npm ($CLAUDE_BIN), sombreando o nativo"
            echo "    O build nativo vive em ~/.local/bin/claude. Para devolver a ele:"
            echo "      npm uninstall -g @anthropic-ai/claude-code"
            ;;
    esac
fi

# ---------------------------------------------------------------------------
# Resumo: UMA linha quando esta tudo certo. Este script roda de hora em hora.
# ---------------------------------------------------------------------------
if [ "$avisos" -eq 0 ] && [ "$consertos" -eq 0 ]; then
    echo "  zsh-ambiente: OK (config.local.zsh, plugins, identidades)"
fi

exit 0
