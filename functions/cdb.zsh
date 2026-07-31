# cdb -- um comando so para o Controle de Bordo.
#
# Substitui as ~39 funções espalhadas em controle-de-bordo.zsh, das quais 6
# chamavam scripts que ja não existem. O problema não era o numero de funções:
# era não haver forma de descobrir o que existe, e nada garantir que o que a
# função chama ainda esta la.
#
# Por isso `cdb` NAO tem lista de comandos escrita a mao. Ele le a pasta de
# scripts e monta o menu a partir do que de fato existe. Um script apagado
# some do menu sozinho; um script novo aparece sem ninguem editar este arquivo.
# E a mesma licao da auditoria: não duplique a informação, aponte para a fonte.
#
# Sem argumento abre um menu fzf. Com o verbo direto, executa.

export CDB_DIR="${CDB_DIR:-$HOME/Controle de Bordo}"
export BORDO_DIR="$CDB_DIR"

_cdb_scripts_dir() { echo "$CDB_DIR/.sistema/scripts"; }

# Uma linha por script: nome e a primeira frase do docstring.
_cdb_listar() {
  local d="$(_cdb_scripts_dir)" f nome desc
  for f in "$d"/*.py(N); do
    nome="${f:t:r}"
    case "$nome" in (_*|lib|vault_logger|acoes) continue ;; esac
    # A descrição sai do próprio script: nunca fica velha em relacao a ele.
    desc=$(python3 - "$f" <<'PY' 2>/dev/null
import ast, sys
try:
    doc = ast.get_docstring(ast.parse(open(sys.argv[1], encoding="utf-8").read())) or ""
except Exception:
    doc = ""
linhas = [l.strip() for l in doc.splitlines() if l.strip()]
print(linhas[0] if linhas else "")
PY
)
    printf '%-14s %s\n' "$nome" "${desc:-(sem descrição)}"
  done
}

_cdb_ajuda() {
  print -P "%F{cyan}cdb%f -- Controle de Bordo em $CDB_DIR"
  print ""
  print -P "%F{yellow}Comandos%f (lidos de .sistema/scripts, entao nunca apontam para o vazio):"
  _cdb_listar | sed 's/^/  /'
  print ""
  print -P "%F{yellow}Atalhos%f"
  print "  cdb              menu interativo (fzf)"
  print "  cdb hoje         abre a nota de hoje no editor"
  print "  cdb caixa        abre a Caixa de Entrada"
  print "  cdb captura TXT  joga uma linha na caixa, sem abrir nada"
  print "  cdb status       doutor + grafo + segredos, de uma vez"
  print "  cdb desfazer     reverte a última rodada da automacao"
  print ""
  print -P "%F{240}Todo script aceita --fix; sem ele, so le.%f"
}

# --- atalhos que não sao script Python ------------------------------------- #

_cdb_hoje() {
  local alvo="$CDB_DIR/Diário/$(date +%Y)/$(date +%Y-%m-%d).md"
  if [[ ! -f "$alvo" ]]; then
    python3 "$(_cdb_scripts_dir)/captura.py" --fix >/dev/null 2>&1
  fi
  ${EDITOR:-nvim} "$alvo"
}

_cdb_caixa() { ${EDITOR:-nvim} "$CDB_DIR/Caixa de Entrada/Captura Rápida.md" }

# Capturar do terminal tambem não pode pedir decisao: uma linha, e acabou.
_cdb_captura() {
  local alvo="$CDB_DIR/Caixa de Entrada/Captura Rápida.md"
  [[ -f "$alvo" ]] || python3 "$(_cdb_scripts_dir)/captura.py" --fix >/dev/null 2>&1
  printf -- '- [ ] %s  <!-- %s -->\n' "$*" "$(date +%Y-%m-%d\ %H:%M)" >> "$alvo"
  print -P "%F{green}capturado%f em Caixa de Entrada"
}

_cdb_status() {
  local d="$(_cdb_scripts_dir)"
  python3 "$d/doutor.py"
  [[ -f "$d/grafo.py" ]]    && python3 "$d/grafo.py" verificar
  [[ -f "$d/segredos.py" ]] && python3 "$d/segredos.py" verificar
}

_cdb_desfazer() {
  local ultima
  ultima=$(command ls -1t "$CDB_DIR/.sistema/organizacao/rodadas" 2>/dev/null | head -1)
  if [[ -z "$ultima" ]]; then
    print -P "%F{red}nenhuma rodada registrada%f"; return 1
  fi
  print -P "Última rodada: %F{cyan}$ultima%f"
  python3 "$(_cdb_scripts_dir)/undo.py" \
    "$CDB_DIR/.sistema/organizacao/rodadas/$ultima" "$@"
}

# --- o comando ------------------------------------------------------------- #

cdb() {
  local verbo="$1"; shift 2>/dev/null

  if [[ -z "$verbo" ]]; then
    if (( $+commands[fzf] )); then
      verbo=$(_cdb_listar | fzf --height=60% --reverse --prompt='cdb > ' \
                --header='Enter executa em modo leitura. Nada e alterado sem --fix.' \
              | awk '{print $1}')
      [[ -z "$verbo" ]] && return 0
    else
      _cdb_ajuda; return 0
    fi
  fi

  case "$verbo" in
    -h|--help|ajuda|help) _cdb_ajuda; return 0 ;;
    hoje)      _cdb_hoje "$@"; return $? ;;
    caixa)     _cdb_caixa "$@"; return $? ;;
    captura)   _cdb_captura "$@"; return $? ;;
    status)    _cdb_status "$@"; return $? ;;
    desfazer)  _cdb_desfazer "$@"; return $? ;;
    cd)        cd "$CDB_DIR"; return 0 ;;
  esac

  local alvo="$(_cdb_scripts_dir)/$verbo.py"
  if [[ ! -f "$alvo" ]]; then
    print -P "%F{red}não existe:%f $verbo"
    print -P "%F{240}rode 'cdb' sem argumento para ver o que existe%f"
    return 127
  fi
  python3 "$alvo" "$@"
}

# --- completion ------------------------------------------------------------ #

_cdb_completar() {
  local -a verbos
  verbos=(${(f)"$(_cdb_listar 2>/dev/null | awk '{print $1}')"})
  verbos+=(hoje caixa captura status desfazer cd ajuda)
  _describe 'comando' verbos
}
compdef _cdb_completar cdb 2>/dev/null

# vim: ft=zsh
