#!/bin/zsh

# ============================================================================
# repatriar -- traz o histórico do vault de volta para casa, e só então
#              apaga a cópia que está na nuvem.
#
#   repatriar           mostra o estado. NÃO muda nada. É o padrão.
#   repatriar enviar    empurra os commits desta máquina para o repositório
#                       de casa, que vive no disco Mnemosyne da MeowSystem.
#   repatriar apagar    apaga o repositório privado do GitHub -- mas só
#                       depois de conferir, commit a commit, que tudo já
#                       está no repositório de casa.
#   repatriar soltar    remove o remoto "origin" morto, depois de apagado.
#
# Por que existe: o vault tinha uma única cópia fora desta casa, num
# repositório privado do GitHub. A decisão de 05/08/2026 foi trocá-la por um
# repositório de casa, entre as duas máquinas, pela rede local. Este arquivo
# faz a troca na ordem segura: primeiro o substituto de pé, depois a remoção.
#
# O que ele NUNCA faz: apagar antes de conferir, e apagar sem você digitar
# o nome do repositório com as próprias mãos.
#
# A conta que apaga precisa do escopo delete_repo. A função troca a conta ativa,
# apaga, e devolve a conta ativa ao que era antes. O nome da conta e o do
# repositório ficam em config.local.zsh, que não é versionado: este arquivo vai
# para um repositório público e identidade não mora nele.
# ============================================================================

REPATRIAR_VAULT="${BORDO_DIR:-$HOME/Controle de Bordo}"
REPATRIAR_HOST="maria"
REPATRIAR_CAMINHO="/mnt/Mnemosyne/git/controle-de-bordo.git"
REPATRIAR_REPO="${REPATRIAR_REPO:-}"
REPATRIAR_CONTA="${REPATRIAR_CONTA:-}"

# -- O remoto de casa, no formato que o git entende --
__repatriar_url() {
    echo "${REPATRIAR_HOST}:${REPATRIAR_CAMINHO}"
}

# -- A casa está acordada? A MeowSystem pode estar desligada. --
__repatriar_casa_no_ar() {
    ssh -o BatchMode=yes -o ConnectTimeout=6 "$REPATRIAR_HOST" \
        "test -d '$REPATRIAR_CAMINHO'" 2>/dev/null
}

# -- Garante que o remoto "casa" existe e aponta para o lugar certo --
__repatriar_garantir_remoto() {
    local url
    url=$(__repatriar_url)
    if git remote get-url casa &>/dev/null; then
        [[ "$(git remote get-url casa)" == "$url" ]] || git remote set-url casa "$url"
    else
        git remote add casa "$url"
    fi
}

# -- Quantos commits desta máquina ainda não chegaram em casa --
__repatriar_faltando() {
    git rev-list --count casa/main..HEAD 2>/dev/null || echo "?"
}

repatriar() {
    local verbo="${1:-estado}"

    if [[ -z "$REPATRIAR_REPO" || -z "$REPATRIAR_CONTA" ]]; then
        __err "Defina REPATRIAR_REPO e REPATRIAR_CONTA em config.local.zsh."
        __warn "A conta precisa do escopo delete_repo: gh auth status"
        return 1
    fi

    if [ ! -d "$REPATRIAR_VAULT/.git" ]; then
        __err "Não achei o vault em: $REPATRIAR_VAULT"
        __warn "Defina BORDO_DIR, ou corrija REPATRIAR_VAULT neste arquivo."
        return 1
    fi

    cd "$REPATRIAR_VAULT" || return 1

    case "$verbo" in

    # ------------------------------------------------------------------
    estado|"")
        __header "REPATRIAR: onde o histórico do vault está hoje" "$D_PURPLE"

        __item "Vault" "$REPATRIAR_VAULT"
        __item "Nesta máquina" "$(git log --oneline -1 2>/dev/null)"
        echo ""

        # A casa
        echo -e "  ${D_COMMENT}Repositório de casa${D_RESET}  ${D_FG}$(__repatriar_url)${D_RESET}"
        if __repatriar_casa_no_ar; then
            __repatriar_garantir_remoto
            git fetch casa --quiet 2>/dev/null
            local falta
            falta=$(__repatriar_faltando)
            if [[ "$falta" == "0" ]]; then
                __ok "em dia -- nada desta máquina está de fora"
            else
                __warn "$falta commit(s) desta máquina ainda não foram para casa"
                echo -e "  ${D_COMMENT}   Envie com:${D_RESET} ${D_GREEN}repatriar enviar${D_RESET}"
            fi
        else
            __err "a MeowSystem não respondeu (desligada, ou fora da rede)"
            echo -e "  ${D_COMMENT}   Ligue a outra máquina e rode de novo.${D_RESET}"
        fi
        echo ""

        # A nuvem
        echo -e "  ${D_COMMENT}Cópia no GitHub${D_RESET}      ${D_FG}$REPATRIAR_REPO${D_RESET}"
        local antes info
        antes=$(gh auth status 2>&1 | grep -B2 "Active account: true" | grep -oP '(?<=account )\S+' | head -1)
        gh auth switch -u "$REPATRIAR_CONTA" &>/dev/null
        info=$(gh repo view "$REPATRIAR_REPO" --json visibility,diskUsage,pushedAt 2>/dev/null)
        [[ -n "$antes" ]] && gh auth switch -u "$antes" &>/dev/null

        if [[ -z "$info" ]]; then
            __ok "não existe mais -- já foi apagado"
        else
            local mb
            mb=$(echo "$info" | python3 -c "import json,sys; print(round(json.load(sys.stdin)['diskUsage']/1024))" 2>/dev/null)
            __warn "ainda existe (${mb} MB, privado)"
            echo -e "  ${D_COMMENT}   Apague com:${D_RESET} ${D_GREEN}repatriar apagar${D_RESET}"
        fi
        echo ""
        ;;

    # ------------------------------------------------------------------
    enviar)
        __header "REPATRIAR: enviando para casa" "$D_CYAN"

        if ! __repatriar_casa_no_ar; then
            __err "a MeowSystem não respondeu."
            __warn "Ligue a outra máquina, confira que está na mesma rede, e tente de novo."
            return 1
        fi

        __repatriar_garantir_remoto
        __item "Destino" "$(__repatriar_url)"
        echo ""

        if git push casa main; then
            git fetch casa --quiet 2>/dev/null
            local falta
            falta=$(__repatriar_faltando)
            if [[ "$falta" == "0" ]]; then
                __ok "tudo desta máquina está em casa"
            else
                __warn "ainda faltam $falta commit(s). Veja o erro acima."
                return 1
            fi
        else
            __err "o envio falhou. Nada foi perdido -- o vault local está intacto."
            return 1
        fi
        echo ""
        ;;

    # ------------------------------------------------------------------
    apagar)
        __header "REPATRIAR: apagar a cópia do GitHub" "$D_RED"

        # [1/4] A casa existe e está no ar?
        if ! __repatriar_casa_no_ar; then
            __err "a MeowSystem não respondeu -- não dá para conferir se o histórico está a salvo."
            __warn "Nada foi apagado. Ligue a outra máquina e tente de novo."
            return 1
        fi
        __ok "repositório de casa alcançado"

        # [2/4] Tudo desta máquina já está lá?
        __repatriar_garantir_remoto
        git fetch casa --quiet 2>/dev/null
        local falta
        falta=$(__repatriar_faltando)
        if [[ "$falta" != "0" ]]; then
            __err "$falta commit(s) desta máquina ainda NÃO estão em casa."
            __warn "Rode primeiro:  repatriar enviar"
            __warn "Nada foi apagado."
            return 1
        fi
        __ok "todo commit desta máquina já está em casa"

        # [3/4] O que está no GitHub também está em casa?
        local antes
        antes=$(gh auth status 2>&1 | grep -B2 "Active account: true" | grep -oP '(?<=account )\S+' | head -1)
        gh auth switch -u "$REPATRIAR_CONTA" &>/dev/null

        if ! gh repo view "$REPATRIAR_REPO" &>/dev/null; then
            __ok "o repositório já não existe. Nada a fazer."
            [[ -n "$antes" ]] && gh auth switch -u "$antes" &>/dev/null
            return 0
        fi

        local topo_online
        topo_online=$(git ls-remote origin refs/heads/main 2>/dev/null | cut -f1)
        if [[ -z "$topo_online" ]]; then
            __warn "não consegui ler o topo do repositório online."
            __warn "Prossiga só se souber o que está fazendo."
        elif git --git-dir=.git merge-base --is-ancestor "$topo_online" HEAD 2>/dev/null; then
            __ok "o que está no GitHub já está contido no histórico local, e portanto em casa"
        else
            __err "o GitHub tem commit (${topo_online:0:7}) que esta máquina NÃO tem."
            __warn "Apagar agora perderia esse trabalho. Rode:  git fetch origin && git log HEAD..origin/main"
            [[ -n "$antes" ]] && gh auth switch -u "$antes" &>/dev/null
            return 1
        fi

        # [4/4] Confirmação escrita à mão
        echo ""
        echo -e "  ${D_YELLOW}Isto apaga o repositório do GitHub e não tem volta.${D_RESET}"
        echo -e "  ${D_COMMENT}O histórico continua aqui, no nitro-5, e em casa (Mnemosyne).${D_RESET}"
        echo ""
        echo -e "  Para confirmar, digite o nome do repositório:"
        echo -e "  ${D_COMMENT}$REPATRIAR_REPO${D_RESET}"
        echo -n "  > "
        local resposta
        read -r resposta

        if [[ "$resposta" != "$REPATRIAR_REPO" ]]; then
            __warn "não confere. Nada foi apagado."
            [[ -n "$antes" ]] && gh auth switch -u "$antes" &>/dev/null
            return 1
        fi

        if gh repo delete "$REPATRIAR_REPO" --yes; then
            __ok "apagado do GitHub"
            echo -e "  ${D_COMMENT}   Agora solte o remoto morto:${D_RESET} ${D_GREEN}repatriar soltar${D_RESET}"
        else
            __err "o GitHub recusou. A conta $REPATRIAR_CONTA tem o escopo delete_repo?"
            __warn "Se não tiver:  gh auth refresh -h github.com -s delete_repo"
        fi

        [[ -n "$antes" ]] && gh auth switch -u "$antes" &>/dev/null
        echo ""
        ;;

    # ------------------------------------------------------------------
    soltar)
        __header "REPATRIAR: soltando o remoto morto" "$D_YELLOW"

        if ! git remote get-url origin &>/dev/null; then
            __ok "não há remoto 'origin' nesta máquina"
        elif gh repo view "$REPATRIAR_REPO" &>/dev/null; then
            __err "o repositório ainda existe no GitHub. Não vou soltar o remoto ainda."
            return 1
        else
            git remote remove origin
            __ok "remoto 'origin' removido"
        fi

        __repatriar_garantir_remoto
        __item "Remotos" "$(git remote -v | head -1)"
        echo ""
        echo -e "  ${D_COMMENT}Falta fazer o mesmo na MeowSystem:${D_RESET}"
        echo -e "  ${D_GREEN}ssh maria 'cd \"/mnt/Apate/Controle de Bordo\" && git remote remove origin'${D_RESET}"
        echo ""
        ;;

    # ------------------------------------------------------------------
    -h|--help|ajuda)
        __header "REPATRIAR" "$D_PURPLE"
        echo -e "  ${D_COMMENT}Troca a cópia do vault que está na nuvem por uma que fica em casa.${D_RESET}"
        echo ""
        echo -e "    ${D_GREEN}repatriar${D_RESET}           onde o histórico está hoje (não muda nada)"
        echo -e "    ${D_GREEN}repatriar enviar${D_RESET}    manda os commits desta máquina para casa"
        echo -e "    ${D_GREEN}repatriar apagar${D_RESET}    apaga o repositório do GitHub, com conferência"
        echo -e "    ${D_GREEN}repatriar soltar${D_RESET}    tira o remoto morto, depois de apagado"
        echo ""
        echo -e "  ${D_COMMENT}A ordem segura é: enviar, apagar, soltar.${D_RESET}"
        echo ""
        ;;

    *)
        __err "não conheço o verbo: $verbo"
        repatriar --help
        return 1
        ;;
    esac
}
