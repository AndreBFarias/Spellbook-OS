#!/bin/zsh

# ============================================================================
# cca_features -- atalhos para as três ferramentas de terceiros que o Spellbook
#                 adota por padrão nas sessões de IA.
#
#   fazer_grafos      constrói o índice de código do repositório atual, que é
#                     o que faz o servidor de consulta subir na próxima sessão.
#   ativar_tdah       liga o formato de resposta direto (ação primeiro, sem
#                     preâmbulo). Vale a partir da próxima sessão.
#   desativar_tdah    desliga o mesmo formato.
#   design_humano     abre uma sessão já orientada a trabalho visual.
#
# Cada um tem um irmão de dentro da sessão: /fazer-grafos, /tdah e
# /design-humano. Os de fora servem para preparar o terreno antes de abrir a
# sessão; os de dentro servem para mudar de ideia no meio do caminho.
#
# Por que existem: as três ferramentas dependem de gatilho. O índice não é
# construído sozinho, o formato de resposta é lido de um arquivo-flag no início
# da sessão, e a skill de design não é acionada automaticamente no modo /design
# porque a descrição dela não menciona esse modo. Regra escrita não basta --
# precisa de comando.
#
# Ver: docs/superpowers/specs/2026-08-10-3-features-claude-default-design.md
# ============================================================================

# Raiz do repositório atual, ou o diretório corrente se não houver repositório.
__cf_raiz() {
    git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD"
}

# Arquivo-flag lido pelo hook de início de sessão do modo TDAH.
__cf_flag_tdah() {
    printf '%s' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.i-have-adhd-always"
}

# Embute a biblioteca de renderização dentro do HTML gerado.
#
# Por que existe: o HTML que a ferramenta gera carrega o D3 de um CDN. Sem
# internet ele abre em branco, não dá pra mandar pra alguém abrir offline, nem
# arquivar como registro de como o código estava naquele dia.
#
# O download é conferido contra o hash SRI que o próprio HTML declara na tag --
# não embutimos código remoto sem verificar. Falha de rede ou hash divergente
# deixa o arquivo como estava (dependendo do CDN), nunca corrompido.
# Idempotente: rodar de novo num arquivo já embutido não faz nada.
__cf_embutir_render() {
    local html="$1"
    local cache="${XDG_CACHE_HOME:-$HOME/.cache}/code-review-graph"
    mkdir -p "$cache"

    python3 - "$html" "$cache" <<'PY'
import base64, hashlib, pathlib, re, sys, urllib.request

html_path, cache_dir = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
texto = html_path.read_text(encoding="utf-8")

padrao = re.compile(
    r'<script\s+src="(?P<url>https://[^"]+\.js)"'
    r'(?:\s+integrity="(?P<sri>[^"]+)")?'
    r'[^>]*></script>'
)
achado = padrao.search(texto)
if not achado:
    sys.exit(2)  # ja embutido, ou formato mudou

url, sri = achado.group("url"), achado.group("sri")
destino = cache_dir / url.rsplit("/", 1)[-1]

if not destino.exists():
    # User-Agent explicito: d3js.org responde 403 ao padrão do urllib.
    req = urllib.request.Request(url, headers={"User-Agent": "curl/8.0"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            destino.write_bytes(r.read())
    except Exception as e:
        print(f"download falhou: {e}", file=sys.stderr)
        sys.exit(3)

conteudo = destino.read_bytes()

if sri:
    algo, _, esperado = sri.partition("-")
    try:
        calculado = base64.b64encode(hashlib.new(algo, conteudo).digest()).decode()
    except ValueError:
        print(f"algoritmo SRI desconhecido: {algo}", file=sys.stderr)
        sys.exit(4)
    if calculado != esperado:
        destino.unlink(missing_ok=True)
        print(f"hash {algo} divergente -- download descartado", file=sys.stderr)
        sys.exit(4)

texto = texto.replace(
    achado.group(0),
    "<script>" + conteudo.decode("utf-8") + "</script>",
)
html_path.write_text(texto, encoding="utf-8")
print(f"{len(conteudo) // 1024}KB embutidos ({algo if sri else 'sem SRI'} conferido)"
      if sri else f"{len(conteudo) // 1024}KB embutidos (sem SRI para conferir)")
PY
}

# Constrói ou atualiza o índice de código do repositório atual.
# Uso: fazer_grafos [--full]
fazer_grafos() {
    if ! command -v code-review-graph >/dev/null 2>&1; then
        __err "code-review-graph ausente. Instale com: pipx install code-review-graph"
        return 1
    fi

    local raiz; raiz="$(__cf_raiz)"

    __header "GRAFO DE CÓDIGO" "$D_CYAN"
    __item "Repositório" "${raiz:t}"
    __item "Caminho" "$raiz"

    local antes="novo"
    [ -d "$raiz/.code-review-graph" ] && antes="atualização"
    __item "Operação" "$antes"
    echo ""

    ( cd "$raiz" && code-review-graph build "$@" ) || {
        __err "Falha ao construir o grafo."
        return 1
    }

    echo ""
    if [ ! -d "$raiz/.code-review-graph" ]; then
        __warn "Build terminou sem erro, mas .code-review-graph/ não apareceu."
        return 1
    fi
    __ok "Índice pronto."

    # Visualização: gerada sempre, e com a biblioteca embutida para abrir offline.
    local html="$raiz/.code-review-graph/graph.html"
    if ( cd "$raiz" && code-review-graph visualize >/dev/null 2>&1 ) && [ -f "$html" ]; then
        local msg
        if msg="$(__cf_embutir_render "$html" 2>&1)"; then
            __ok "Visualização autocontida: $msg"
        else
            __warn "Visualização gerada, mas sem embutir (${msg:-sem detalhe}) — precisa de internet para abrir."
        fi
        __item "Abrir" "$html"
    else
        __warn "Índice construído, mas a visualização falhou."
    fi

    echo ""
    __ok "Total: $(du -sh "$raiz/.code-review-graph" 2>/dev/null | cut -f1)."
    __ok "A próxima sessão aberta aqui já sobe o servidor de consulta."
}

# Liga o formato de resposta direto.
ativar_tdah() {
    local flag; flag="$(__cf_flag_tdah)"

    __header "MODO TDAH" "$D_ORANGE"

    if [ -f "$flag" ]; then
        __ok "Já estava ligado."
        __item "Flag" "$flag"
        return 0
    fi

    mkdir -p "${flag:h}" && : > "$flag" || {
        __err "Não consegui criar o arquivo-flag em $flag"
        return 1
    }

    __ok "Ligado."
    __item "Flag" "$flag"
    echo ""
    __warn "Vale a partir da PRÓXIMA sessão — o hook lê no início dela."
    __warn "Para mudar a sessão que já está aberta, use /tdah lá dentro."
}

# Desliga o formato de resposta direto.
desativar_tdah() {
    local flag; flag="$(__cf_flag_tdah)"

    __header "MODO TDAH" "$D_ORANGE"

    if [ ! -f "$flag" ]; then
        __ok "Já estava desligado."
        return 0
    fi

    rm -f "$flag" || { __err "Não consegui remover $flag"; return 1; }

    __ok "Desligado."
    echo ""
    __warn "Vale a partir da PRÓXIMA sessão."
}

# Abre uma sessão já orientada a trabalho visual.
# Uso: design_humano [descrição do que construir]
design_humano() {
    local pedido="$*"
    local instrucao="Use a skill hallmark como direção de design principal nesta sessão, conforme a seção 6 do GUIDE.md. Trate frontend-design como apoio, só para o que hallmark não cobrir."

    [ -n "$pedido" ] && instrucao="$instrucao

Pedido: $pedido"

    __header "DESIGN HUMANO" "$D_PINK"
    __item "Skill" "hallmark (prioritária)"
    __item "Apoio" "frontend-design"
    [ -n "$pedido" ] && __item "Pedido" "$pedido"
    echo ""

    if ! typeset -f cca >/dev/null; then
        __err "Função cca não carregada neste shell."
        return 1
    fi

    cca "$instrucao"
}
