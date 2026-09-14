#!/usr/bin/env bash
# aurora-reiniciar-painel.sh — Alt+F2: reinicia o painel do COSMIC (topbar + dock)
# sem derrubar a sessão nem fechar janela nenhuma. (v3.66)
#
# POR QUE ISSO EXISTE, E POR QUE NÃO É UM "RESTART DA SESSÃO"
#   No GNOME sob X11, Alt+F2 → `r` reinicia o gnome-shell no lugar: o compositor
#   se recarrega e as janelas sobrevivem porque quem as segura é o X server.
#   No COSMIC (Wayland) isso é IMPOSSÍVEL por construção — o `cosmic-comp` É o
#   servidor: as superfícies das janelas vivem na conexão com ele, e matá-lo
#   fecha tudo o que está aberto. Não existe reload in-place upstream.
#
#   O que dá pra reiniciar de graça é a CASCA: o `cosmic-panel`, que desenha a
#   topbar E a dock (são o mesmo processo — ele lê "Panel" e "Dock" das entries
#   de `CosmicPanel/v1/entries`) e é o pai de todos os applets. Na prática é o
#   que o `r` do GNOME resolvia no dia a dia: applet travado, ícone que ficou no
#   cache, config nova que o painel só relê ao carregar.
#
#   Existe SIM um restart de sessão de verdade — o método D-Bus `Restart` em
#   com.system76.CosmicSession — e ele está deliberadamente FORA daqui: fecha
#   todos os apps, e uma tecla que a pessoa pode encostar sem querer não pode
#   ter esse poder.
#
# QUEM RESSUSCITA O PAINEL
#   O `cosmic-session` supervisiona o `cosmic-panel` e o reinicia sozinho — medido
#   em 25/08/2026: "sleeping for 9ms before restarting process cosmic-panel".
#   Não há teto de tentativas no binário (só backoff que cresce), então a tecla
#   não "queima" a sessão se ela apertar várias vezes; o custo é a tela piscar.
#   O fallback abaixo só entra se o supervisor falhar, e é caminho raro.
#
# POR QUE SIGTERM E NÃO SIGKILL
#   O painel precisa desmontar as layer surfaces antes de sair; com SIGKILL o
#   compositor às vezes segura a superfície órfã e o painel novo nasce por cima
#   do fantasma do velho. `pkill -x` casa o nome exato, para não pegar junto os
#   `cosmic-panel-button` e os `cosmic-applet-*` (que morrem com o pai de todo
#   jeito, por serem filhos dele).
#
# RELAÇÃO COM O VIGIA DO PAINEL FANTASMA
#   O `aurora-painel-fantasma.sh` faz outra coisa: ele JULGA se o painel está
#   vivo-porém-sem-desenhar (erro de protocolo Wayland derrubou o cliente) e só
#   então mata, com carência de 600s pra não virar loop de kills. Este aqui é o
#   comando MANUAL e incondicional: ela apertou, reinicia. Um não substitui o
#   outro, e este não mexe no contador de tentativas daquele.
#
# ============================================================================
# O QUE A AUDITORIA DE 25/08/2026 MEDIU, E CONSERTOU, NESTE ARQUIVO
# ============================================================================
#
# (1) O FALLBACK NUNCA FUNCIONOU — e mentia dizendo que sim.
#     Ele montava o ambiente a partir de `/proc/<cosmic-session>/environ`,
#     confiando em que "WAYLAND_DISPLAY e afins vivem no environ dele". Não
#     vivem. O `cosmic-session` nasce ANTES de existir socket Wayland: quem cria
#     o `wayland-1` é o `cosmic-comp`, que o session sobe depois — e o session
#     ACRESCENTA a variável ao ambiente que passa aos FILHOS, sem nunca mexer no
#     próprio environ, que é congelado no exec. Medido, com a sessão dela viva:
#
#       cosmic-session (pid 4142)   → SEM WAYLAND_DISPLAY   · 0 *NOTIFICATIONS_FD
#       cosmic-panel   (pid 1430322) → WAYLAND_DISPLAY=wayland-1 · PANEL_NOTIFICATIONS_FD=18
#       cosmic-bg, cosmic-launcher, cosmic-osd, cosmic-idle → WAYLAND_DISPLAY=wayland-1
#       cosmic-comp                  → SEM WAYLAND_DISPLAY (é ele que cria o socket)
#
#     E o teste direto, rodando exatamente a linha que o fallback rodava:
#         $ env -i "${ENVS[@]}" cosmic-panel
#         Error: Could not find wayland compositor
#     Sem `WAYLAND_DISPLAY` o cliente tenta `wayland-0`, que nem existe nesta
#     máquina (só há `wayland-1`), e morre em milissegundos.
#
#     Pior: o `pgrep` de conferência logo depois não olhava QUEM tinha subido,
#     só "existe algum cosmic-panel?". Como o backoff do supervisor cresce a
#     cada morte, o painel dele volta às vezes DEPOIS dos 5 s de espera — e a
#     conferência creditava esse painel ao fallback. As seis linhas
#     "OK (fallback): painel subiu fora do supervisor" no log de hoje são todas
#     falso-positivo: o painel vivo agora tem `PANEL_NOTIFICATIONS_FD` no
#     environ, carimbo que só o supervisor põe.
#
#     Conserto: o ambiente sai do PRÓPRIO PAINEL, lido ANTES do SIGTERM (é, por
#     construção, o ambiente exato em que ele estava rodando); se ele já estava
#     morto, sai de um IRMÃO vivo que o session tenha spawnado. E o sucesso do
#     fallback agora é conferido pelo PID que NÓS criamos, não por "existe
#     algum".
#
# (2) O FILTRO DOS *_NOTIFICATIONS_FD ESTAVA CERTO NA IDEIA E NO LUGAR ERRADO.
#     A variável não existe no environ do session (contagem: 0), só no dos
#     filhos — então, do jeito antigo, o filtro nunca filtrava nada. Agora que a
#     fonte é o painel/irmão, ele passa a fazer trabalho de verdade: o fd 18
#     herdado do supervisor não existe fora dele, e passá-lo aborta o painel.
#
# (3) NÃO HAVIA TRANCA, E O LOG DE HOJE MOSTRA O ESTRAGO.
#     Duas invocações se intercalaram várias vezes (12:26:35→12:28:13,
#     12:42:50→12:42:58): uma mata o painel que a outra acabou de conseguir, e o
#     log fica ilegível porque as linhas se misturam. Alt+F2 é tecla de encostar
#     sem querer. Agora há um `flock -n`: a segunda invocação avisa e sai.
#
# (4) O LOG: NÃO cresce sem limite entre sessões — ele mora em
#     `$XDG_RUNTIME_DIR`, que é tmpfs e some no logout. Mas tmpfs é RAM, e
#     dentro de UMA sessão nada o segurava: o teste de hoje deixou 47 linhas em
#     poucos minutos. O corte para as últimas 400 linhas custa um `tail` por
#     execução e fecha a pergunta.

set -uo pipefail

LOG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/aurora-reiniciar-painel.log"
log() { printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }

aviso() {
  # A notificação é o único retorno visível: o script roda por Spawn do
  # compositor, sem terminal onde imprimir. Se o painel morreu, o
  # cosmic-notifications continua desenhando (é outro processo, outra layer).
  notify-send -a "MeowSystem" -i "preferences-desktop" "$1" "${2:-}" 2>/dev/null || true
}

# TRANCA — ver o achado (3) do cabeçalho. `-n` e não espera: se já há um reinício
# em curso, a segunda tecla não tem nada a acrescentar, e enfileirá-la só faria a
# tela piscar de novo. O lock mora no tmpfs da sessão, junto do log.
TRAVA="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/aurora-reiniciar-painel.lock"
if command -v flock >/dev/null 2>&1; then
  # As chaves e NÃO um `exec 9>… 2>/dev/null` solto: naquela forma o
  # `2>/dev/null` também é do `exec`, e o stderr do script inteiro morreria ali.
  { exec 9>"$TRAVA"; } 2>/dev/null
  if [ -e /proc/self/fd/9 ] && ! flock -n 9; then
    log "já há um reinício em curso — esta invocação sai sem fazer nada"
    exit 0
  fi
fi

# Corte do log — ver o achado (4). Feito ANTES de escrever, para que as linhas
# desta execução nunca sejam as cortadas.
if [ -f "$LOG" ] && [ "$(wc -l < "$LOG" 2>/dev/null || echo 0)" -gt 400 ]; then
  tail -n 200 "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG" 2>/dev/null
fi

# TETO DE REINÍCIOS — PORQUE FOI APERTAR DEMAIS QUE QUEBROU A TARDE DE 25/08
#   O `cosmic-session` reinicia o painel com BACKOFF CRESCENTE: começa em 9ms e
#   cresce a cada morte. Depois de eu testar este atalho dezenas de vezes o
#   contador chegou a "now at 20 restarts" e o intervalo virou ~87 MINUTOS —
#   quer dizer: o supervisor parou de socorrer, e sobrou ela sem topbar e sem
#   dock esperando, com um painel de emergência capenga no lugar. O estrago não
#   foi de um reinício, foi da SEQUÊNCIA deles.
#
#   O teto não protege o painel; protege o SUPERVISOR, que é quem devolve a
#   barra completa. Passar dele não é erro da usuária — é sinal de que a barra
#   está morrendo sozinha e o problema é outro (raio de canto, applet em pânico,
#   erro de protocolo). Por isso aqui a saída é AVISAR e mandar olhar o log, em
#   vez de reiniciar mais uma vez e afundar o backoff.
#
#   Contagem no tmpfs do XDG_RUNTIME_DIR: morre no logout, que é exatamente a
#   vida do contador do cosmic-session.
TETO_REINICIOS="${AURORA_PAINEL_TETO:-6}"
JANELA_REINICIOS=1800          # 30 min
MARCAS="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/aurora-reiniciar-painel.marcas"
_agora=$(date +%s)
_recentes=""
if [ -r "$MARCAS" ]; then
  while IFS= read -r _t; do
    case "$_t" in ''|*[!0-9]*) continue ;; esac
    [ $((_agora - _t)) -lt "$JANELA_REINICIOS" ] && _recentes="$_recentes$_t
"
  done < "$MARCAS"
fi
_n=$(printf '%s' "$_recentes" | grep -c . || true)
if [ "$_n" -ge "$TETO_REINICIOS" ]; then
  log "RECUSADO: $_n reinícios em 30 min — o backoff do cosmic-session já deve estar longo"
  aviso "Não vou reiniciar o painel de novo" \
        "Foram $_n vezes em 30 minutos. Reiniciar mais afunda o backoff do cosmic-session e você fica SEM barra por dezenas de minutos. Se a barra está morrendo sozinha, o motivo está no journal: 'corner radius too large' é o suspeito nº 1."
  exit 3
fi
printf '%s%s\n' "$_recentes" "$_agora" > "$MARCAS"

ANTES="$(pgrep -x cosmic-panel | head -1)"

# O AMBIENTE SAI DAQUI, E TEM DE SER LIDO ANTES DO SIGTERM — achado (1).
# `/proc/PID/environ` é NUL-delimitado, e o `read -r -d ''` do bash lê isso
# certo: conferido nesta máquina, 36 pares vindos do session e 41 do cosmic-bg,
# sem truncar valor com espaço. O redirecionamento de ARQUIVO (não de pipe) é o
# que permite o `read` andar sobre ele.
ENV_PAINEL=()
ler_environ() {   # $1 = pid; enche ENV_PAINEL, já sem os *_NOTIFICATIONS_FD
  local pid="$1" kv
  [ -n "$pid" ] && [ -r "/proc/$pid/environ" ] || return 1
  ENV_PAINEL=()
  while IFS= read -r -d '' kv; do
    case "$kv" in
      *_NOTIFICATIONS_FD=*) continue ;;   # fd herdado do supervisor: aborta fora dele
    esac
    ENV_PAINEL+=("$kv")
  done < "/proc/$pid/environ"
  # Um ambiente sem WAYLAND_DISPLAY não serve para NADA aqui: é exatamente o
  # modo de falha que o fallback teve desde que nasceu.
  printf '%s\n' "${ENV_PAINEL[@]}" | grep -q '^WAYLAND_DISPLAY=' || { ENV_PAINEL=(); return 1; }
  return 0
}

ler_environ "$ANTES" || {
  # O painel já estava morto (ou ilegível): pega o ambiente de um IRMÃO que o
  # cosmic-session tenha spawnado. Todos eles carregam o WAYLAND_DISPLAY certo —
  # medido. O cosmic-comp fica FORA da lista de propósito: é ele que cria o
  # socket, e por isso é o único que não tem a variável.
  for _irmao in cosmic-bg cosmic-launcher cosmic-osd cosmic-idle \
                cosmic-notifications cosmic-app-library cosmic-workspaces; do
    ler_environ "$(pgrep -x "$_irmao" | head -1)" && { log "ambiente herdado de $_irmao"; break; }
  done
}

if [ -z "$ANTES" ]; then
  log "painel não estava rodando; tentando subir direto"
else
  log "SIGTERM em cosmic-panel (pid $ANTES)"
  pkill -x cosmic-panel
fi

# Espera o supervisor devolver um PID DIFERENTE. Comparar com o PID antigo (e
# não só "existe algum cosmic-panel?") evita declarar sucesso ao ver o processo
# velho ainda agonizando.
DEPOIS=""
for _ in $(seq 1 50); do          # 50 x 0,1s = 5s de teto
  sleep 0.1
  DEPOIS="$(pgrep -x cosmic-panel | head -1)"
  [ -n "$DEPOIS" ] && [ "$DEPOIS" != "$ANTES" ] && break
  DEPOIS=""
done

if [ -n "$DEPOIS" ]; then
  APPLETS="$(pgrep -c -f 'cosmic-applet|cosmic-app-list' 2>/dev/null || echo 0)"
  log "OK: painel $ANTES -> $DEPOIS ($APPLETS applets)"
  exit 0
fi

# FALLBACK: o cosmic-session não devolveu o painel em 5s. Sobe na mão com o
# ambiente que o `ler_environ` já capturou lá em cima — ver o achado (1) do
# cabeçalho para por que ele NÃO pode sair do cosmic-session.
log "AVISO: supervisor não devolveu o painel em 5s — subindo na mão"
if [ "${#ENV_PAINEL[@]}" -gt 0 ]; then
  # `9>&-` FECHA A TRAVA NO FILHO, E ISSO NÃO É ZELO — É CONSERTO DE BUG MEDIDO
  #   Sem ele, o `exec 9>` lá de cima vaza para o `cosmic-panel` que subimos, e
  #   o painel PASSA o descritor a todos os applets que spawna. Medido em
  #   25/08/2026, com `lsof` na trava: o painel e SETE applets segurando o fd 9.
  #   O `flock` só solta quando o último descritor fecha — ou seja, a tecla
  #   Alt+F2 virava no-op ("já há um reinício em curso") até o logout, que é o
  #   oposto exato do que a trava existe para fazer.
  # `env -i` E NÃO `env` — UM CARACTERE, E FOI ELE QUE MATOU A BANDEJA
  #   Sem o `-i`, o `env` ACRESCENTA ao ambiente de quem chamou em vez de
  #   substituir. Rodado de um terminal aberto pela dock, o painel nascia
  #   herdando `PANEL_NOTIFICATIONS_FD=21` e `X_PRIVILEGED_WAYLAND_SOCKET=121`
  #   do terminal — descritores que NÃO existem no processo novo. O resultado,
  #   medido em 25/08/2026, é `Io error: Bad file descriptor (os error 9)` e
  #   panic em `libcosmic/src/applet/token/wayland_handler.rs:110` para
  #   StatusArea, Power, Audio e Network: a barra sobe SEM a bandeja e SEM o
  #   botão de desligar, e nada na tela diz por quê. O `ler_environ` já tirava
  #   essas variáveis da lista que montamos; o que faltava era impedir que
  #   voltassem pela porta dos fundos. Com `-i` os quatro applets sobem.
  setsid env -i "${ENV_PAINEL[@]}" cosmic-panel 9>&- >/dev/null 2>&1 &
else
  # Sem ambiente utilizável, subir "na mão" é subir para morrer: o painel não
  # acha o compositor. Dizer isso é melhor que fingir que tentou.
  log "ERRO: nenhum processo do COSMIC com WAYLAND_DISPLAY para herdar ambiente"
  aviso "O painel não voltou" \
        "Não achei o ambiente Wayland da sessão. Abra um terminal e rode 'cosmic-panel &', ou faça logout/login."
  exit 1
fi

# DE QUEM É O PAINEL QUE FICOU DE PÉ? — achado (1).
#   Perguntar "existe algum cosmic-panel?" foi o que produziu as seis linhas
#   "OK (fallback)" falsas de hoje: o backoff do supervisor cresce a cada morte,
#   o painel dele às vezes chega DEPOIS dos 5 s, e o fallback levava o crédito.
#   O `$!` também não serve de prova: o `setsid` forka quando já é líder de
#   grupo, e aí o PID que o shell guarda é o do wrapper, não o do painel.
#   O carimbo que separa os dois é o environ: o painel do supervisor carrega
#   `PANEL_NOTIFICATIONS_FD` (medido: fd 18); o nosso nunca, porque o
#   `ler_environ` tira exatamente essa variável antes de passar o ambiente.
#   E a classificação NÃO pode sair de um `| head -1`: o menor PID é o nosso
#   sempre que o supervisor chega atrasado (nós spawnamos aos 5 s, ele aos 6 s),
#   e aí o crédito se inverteria. É a mesma armadilha do `head -1` que o
#   ritual-aurora-self-heal.sh pagou com o cosmic-settings-daemon. Aqui a gente
#   classifica TODOS e decide pelo carimbo.
#   CORREÇÃO DE 25/08/2026: o carimbo do environ NÃO servia. `PANEL_NOTIFICATIONS_FD`
#   é herança, e herança desce por toda a árvore — sete linhas do log de hoje
#   dizem "é o do supervisor" numa janela em que o supervisor comprovadamente
#   ainda dormia. O discriminador honesto é o PARENTESCO: o painel do supervisor
#   é filho do `cosmic-session`; o nosso nasce de `setsid` e é adotado pelo init.
#   Isso o `/proc` responde sem ambiguidade e sem depender de variável nenhuma.
sleep 2
SESSAO_PID="$(pgrep -x cosmic-session | head -1)"
SUPERVISOR=""; NOSSO=""
for _p in $(pgrep -x cosmic-panel); do
  _pai="$(ps -o ppid= -p "$_p" 2>/dev/null | tr -d ' ')"
  if [ -n "$SESSAO_PID" ] && [ "$_pai" = "$SESSAO_PID" ]; then
    [ -z "$SUPERVISOR" ] && SUPERVISOR="$_p"
  else
    [ -z "$NOSSO" ] && NOSSO="$_p"
  fi
done

if [ -n "$SUPERVISOR" ]; then
  # O supervisor chegou atrasado. Se o NOSSO também tiver vingado, sobram dois
  # painéis disputando as mesmas layer surfaces — e quem tem de sair é o nosso,
  # porque o do supervisor é o que será ressuscitado da próxima vez. Sem esta
  # limpeza, a corrida deixa lixo que só o logout resolve.
  if [ -n "$NOSSO" ]; then
    log "limpando o painel do fallback (pid $NOSSO): o do supervisor (pid $SUPERVISOR) venceu a corrida"
    kill -TERM "$NOSSO" 2>/dev/null || true
  fi
  log "OK: o painel de pé (pid $SUPERVISOR) é o do supervisor, chegou atrasado — o fallback não foi preciso"
  exit 0
fi

if [ -n "$NOSSO" ]; then
  log "OK (fallback): painel subiu fora do supervisor (pid $NOSSO)"
  aviso "Painel reiniciado (modo manual)" \
        "O cosmic-session não respondeu; o painel subiu fora dele. Se algum applet ficar estranho, faça logout/login."
  exit 0
fi

log "ERRO: painel não voltou"
aviso "O painel não voltou" "Rode 'cosmic-panel &' num terminal, ou faça logout/login."
exit 1
