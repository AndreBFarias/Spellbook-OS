#!/usr/bin/env bash
# aurora-cosmic-comp-ws.sh — mantém o cosmic-comp SEM o workspace vazio extra.
#
# O PORQUÊ
#   A MeowSystem tem workspaces FIXOS, todos alfinetados: "Meow" (o dela) e "OS"
#   (o do assistente).
#   ERRATA de 30/08/2026: este parágrafo dizia TRÊS, com um "III" nomeado em
#   24/08. O III saiu em 25/08 e o texto ficou. Medido hoje, no
#   ~/.config/cosmic/com.system76.CosmicComp/v1/pinned_workspaces: os
#   `name: Some(...)` são exatamente `['Meow', 'OS']`. Fica registrado porque o
#   número importa para o parágrafo do CUSTO ACEITO, mais abaixo.
#   O upstream, em `Workspaces::ensure_last_empty`
#   (src/shell/mod.rs), acrescenta um workspace vazio sempre que o último da lista
#   está ocupado OU é alfinetado:
#       .is_none_or(|last| !last.is_empty() || last.pinned)
#   Como o último dela é SEMPRE alfinetado, o compositor criava eternamente um
#   terceiro workspace que não é de ninguém — um botão a mais no applet do painel,
#   que ela via o tempo todo. O patch troca essa condição por `is_empty()`: só
#   cria se a lista estiver sem NENHUM workspace.
#
#   O GUARDA `is_empty()` NÃO É ENFEITE: em 04/08/2026 um clique errado no
#   overview zerou o `pinned_workspaces`. Sem esse guarda, o mesmo acidente
#   deixaria o compositor sem nenhum workspace — sem chão.
#
# O QUE ACONTECE QUANDO ESTE PATCH CAI (visto em 24/08/2026)
#   O `apt upgrade` trocou o cosmic-comp e levou o build patchado junto. O vazio
#   voltou, e no painel dela ele apareceu como um "3" seco -- que é como um
#   workspace SEM alfinete se apresenta, porque o nome dele é a posição na lista.
#   O sintoma NÃO é "o COSMIC criou um workspace estranho": é este patch ausente.
#   `--ensure` diz isso em uma linha, sem compilar nada.
#
# CUSTO ACEITO (decidido com a Vitória em 04/08/2026)
#   Sem o vazio no fim não há para onde arrastar uma janela no overview para
#   criar um workspace novo. Os workspaces passam a nascer só pelo
#   `pinned_workspaces` (via aurora-cosmic-workspaces.py), valendo no login
#   seguinte. Com dois workspaces fixos, é exatamente o desejado.
#
# POR QUE ISTO NÃO É UM PATCH DE BINÁRIO COMO O NIGHT LIGHT
#   O aurora-night-light.py reescreve TEXTO (o shader GLSL embutido) preservando
#   o tamanho byte a byte — barato e sem recompilar. Aqui a mudança é de lógica
#   Rust compilada: não há texto a reescrever, só instruções. Então o caminho é
#   recompilar a MESMA versão do pacote, com o patch, e trocar o binário.
#
# COMO O SELF-HEAL SABE SE O BINÁRIO INSTALADO É O NOSSO
#   Por um MARCADOR de texto embutido no build (`AURORA-COSMIC-WS-PATCH`), não
#   por hash. Hash não serve: o aurora-night-light.py reescreve bytes do shader
#   DEPOIS, e a partir daí nenhum hash bate. O marcador sobrevive a isso.
#
# A ORDEM IMPORTA (e o self-heal respeita)
#   Este script roda ANTES da etapa do night light. Instalar o nosso build joga
#   fora o patch do shader (o binário é novo em folha); é o night light, logo em
#   seguida no mesmo ciclo, que o reaplica. Invertida, a ordem perderia a luz
#   noturna até o ciclo seguinte.
#
# O `--ensure` NÃO COMPILA — ELE DISPARA QUEM COMPILA (mudou em 28/08/2026)
#   Até aqui, quando o apt trocava a versão do cosmic-comp o script só AVISAVA, e
#   rebuildar era decisão humana. Na prática o humano nunca era avisado (o Não
#   Perturbe comia o notify-send) e o patch ficava dias caído — ver o bloco
#   AUTO-BUILD, mais abaixo, com os números medidos.
#   Agora o `--ensure` continua sem compilar coisa alguma DENTRO do ciclo do
#   self-heal — ele delega a uma unit transitória (`systemd-run`) que compila em
#   segundo plano, com Nice 19, e instala sozinha. O timer de hora em hora
#   continua saindo em segundos. Quatro guardas impedem que isso vire build em
#   laço; `--build` à mão continua existindo e é o caminho quando se quer olhar.
#   Degradação suave segue valendo: sem o patch, o desktop continua perfeito —
#   só volta o workspace vazio.
#
# NUNCA INSTALA BINÁRIO DE OUTRA VERSÃO: o artefato guardado carrega a versão do
#   pacote no nome, e o `--ensure` só instala o que casa com a versão instalada
#   AGORA. Um cosmic-comp de uma versão com o resto do COSMIC de outra é receita
#   de sessão que não sobe.
#
# ---------------------------------------------------------------------------
# DE UM PATCH PARA UMA SÉRIE (30/08/2026, Sprint U do MeowSystem)
# ---------------------------------------------------------------------------
#   Este script aplicava UM `.patch` só, num caminho literal. O
#   `cosmic-comp-raio-clampado.patch` — o que impede o raio de canto de MATAR o
#   painel dela — existia desde 26/08, aplicava limpo num dry-run, o README dizia
#   que estava em produção, e NUNCA entrou em binário nenhum: não havia onde
#   declará-lo. Falha completamente muda, e por três semanas.
#
#   Agora a lista de patches é um arquivo, `patches.d/series`, com três campos
#   por linha: classe (`req`/`opt`), arquivo, marcador-base. Procurado nesta
#   ordem: /usr/local/share/aurora/patches.d/, $HOME/.config/zsh/patches/patches.d/
#   e o mesmo caminho dentro do home da usuária (o self-heal roda como unit de
#   SISTEMA, e o $HOME dele é /root). Sem nenhuma delas, o script cai no
#   comportamento antigo e DIZ que caiu.
#
#   TRÊS COISAS QUE MUDARAM JUNTO, e nenhuma é enfeite:
#
#   1. DRY-RUN DE TODOS ANTES DE APLICAR QUALQUER UM. Um `req` que não aplica
#      mais aborta antes de a árvore ser tocada. Melhor o binário do pacote
#      (desktop feio, mas de pé) do que um compositor meio-patchado — e o
#      greeter é o MESMO binário, então "meio-patchado" é a tela de login junto.
#
#   2. IDEMPOTÊNCIA POR MARCADOR, NÃO POR CÓDIGO DE SAÍDA. `patch --forward`
#      devolve **1** para "já aplicado". MEDIDO de novo em 30/08/2026, no fonte
#      0.1~1787767625~24.04~5c93094 desta máquina:
#          workspace-vazio (já no fonte) -> rc=1, "Reversed (or previously
#                                           applied) patch detected!"
#          raio-clampado   (não no fonte) -> rc=0
#      Um script que trate 1 como erro aborta para sempre; um que trate 1 como
#      sucesso não distingue "já estava" de "quebrou". O teste é
#      `grep -q <marcador-base> <arquivo-fonte>`, e o ARQUIVO-FONTE é descoberto
#      a partir do próprio `.patch` (qual hunk ACRESCENTA o marcador), em vez de
#      `src/shell/mod.rs` chumbado — que já não serviria para o raio, que mora em
#      src/wayland/protocols/corner_radius.rs.
#
#   3. `marcador_de()` DEVOLVE TODOS OS MARCADORES, ordenados e colados com `+`.
#      Devolvendo só o primeiro, acrescentar um patch à série não mudava a string
#      e o `--ensure` não reinstalava nada: quatro minutos de compilação parados
#      no disco e a tela igual. É a mesma forma do bug de 25/08/2026, um degrau
#      acima — lá era a VERSÃO do patch, aqui é a SÉRIE.
#
#   E quem escreve /usr/bin/cosmic-comp grava /var/lib/aurora/cosmic-comp-patches.estado,
#   MEDIDO com `strings` no binário recém-instalado — nunca deduzido da série. É
#   o que o `meow doctor` lê. Deduzir seria escrever no arquivo de diagnóstico a
#   intenção em vez do fato, e o fato é justamente o que se quer conferir: o
#   `#[used]` pode ter sido descartado pelo linker, e aí o efeito não está no
#   binário mesmo que a série o declare.
#
# Fonte canônica: ~/.config/zsh/scripts/. Destino: /usr/local/sbin/. Aurora v3.54.
set -u

# QUEM CHAMA ESTE SCRIPT PELO systemd NÃO TEM `HOME` NO AMBIENTE
#   O self-heal roda numa unit de SISTEMA (sem `User=`), e o systemd só define
#   HOME quando há usuário. Com `set -u`, a primeira expansão de `$HOME` abortava
#   o script inteiro na linha do BUILD_DIR — antes de fazer qualquer coisa.
#   MEDIDO: 27 execuções seguidas entre 04/08/2026 15:15 e 05/08/2026 15:51
#   terminaram em `HOME: variável não associada` + `ERRO: cosmic-comp-ws falhou`,
#   deixando o `ritual-aurora-self-heal.service` em estado `failed`.
#   O sintoma era traiçoeiro porque nada aqui é urgente: o `--ensure` só CONFERE
#   o patch, então o desktop continuava perfeito enquanto a unit gritava.
#   O chamador agora passa `HOME=`; esta linha é a rede para quem esquecer.
HOME="${HOME:-$(getent passwd "${AURORA_USER:-$(id -un)}" 2>/dev/null | cut -d: -f6)}"
HOME="${HOME:-/root}"
export HOME

MARCA="AURORA-COSMIC-WS-PATCH"
ALVO="${AURORA_WS_ALVO:-/usr/bin/cosmic-comp}"
LIB=/var/lib/aurora
PATCH_INSTALADO=/usr/local/share/aurora/cosmic-comp-sem-workspace-vazio.patch
BUILD_DIR="${AURORA_WS_BUILD_DIR:-$HOME/Desenvolvimento/cosmic-comp-patch}"

# A SÉRIE (30/08/2026). O `series` dentro de um destes diretórios manda; ver o
# bloco "DE UM PATCH PARA UMA SÉRIE" no cabeçalho.
SERIE_SISTEMA=/usr/local/share/aurora/patches.d

# O arquivo que o `meow doctor` lê. Gravado por quem escreve /usr/bin/cosmic-comp,
# 644 e de root, a partir do `strings` do binário RECÉM-INSTALADO.
ESTADO="$LIB/cosmic-comp-patches.estado"

log() { echo "  cosmic-comp-ws: $*"; }

versao_pacote() {
  dpkg-query -W -f='${Version}' cosmic-comp 2>/dev/null
}

# Nome do artefato: um por versão do pacote, para nunca misturar.
artefato_de() { echo "$LIB/cosmic-comp-${1//\//_}.aurora-ws"; }

# O binário do PACOTE, guardado antes de qualquer patch nosso. Serve ao
# --restore e é a rede de segurança se um build sair ruim.
pkg_orig_de() { echo "$LIB/cosmic-comp-${1//\//_}.pkg-orig"; }

# --- AUTO-BUILD: o que faltava para a idempotência valer ---------------------
#
# O QUE ESTAVA QUEBRADO (diagnosticado em 28/08/2026)
#   O artefato é guardado POR VERSÃO do pacote, e o `--ensure` só instala o que
#   casa com a versão de agora. Isso está CERTO e fica: cosmic-comp de uma versão
#   com o resto do COSMIC de outra é sessão que não sobe. O que envelheceu foi o
#   pressuposto de que o artefato dura. Não dura: o cosmic-comp do Pop subiu TRÊS
#   versões em três dias (314fc67 -> 31827ed -> 5c93094). Cada `apt` deixa o
#   artefato obsoleto e, como o `--ensure` nunca compila, o patch fica caído até
#   um humano rebuildar. Contados no log do self-heal: 177 avisos "não tem build
#   patchado", 22 só da versão instalada em 27/08 às 22:43.
#
#   E O AVISO NÃO CHEGAVA NELA. O `avisar_usuaria` manda notify-send e o
#   `~/.config/cosmic/com.system76.CosmicNotifications/v1/do_not_disturb: true`
#   engoliu as 22. O `|| true` da função faz o script nem saber. Ela descobriu
#   pelo "3" no painel, dois dias depois. Uma idempotência que depende de um
#   humano acordado por um canal silenciado não é idempotência.
#
# O QUE MUDA
#   O `--ensure` passa a DISPARAR o build sozinho quando falta artefato para a
#   versão instalada — nunca dentro do próprio ciclo do self-heal: o
#   `systemd-run` desacopla numa unit transitória com o mesmo Nice/IOWeight da
#   unit do self-heal. O timer de hora em hora continua saindo em segundos.
#
# AS QUATRO GUARDAS — sem elas isto vira desastre por timer
#   1. JOGO ABERTO adia. Mesmo sinal do `ExecCondition` do self-heal
#      (`reaper SteamLaunch AppId=`): compilar come CPU por minutos.
#   2. UNIT DE NOME FIXO não empilha: o systemd-run recusa criar a segunda
#      enquanto a primeira roda. Sem isso, um build de 10 min pegaria dois
#      disparos do timer e teria duas compilações no mesmo diretório.
#   3. CARIMBO POR VERSÃO limita a MAX_TENTATIVAS. Se o upstream mexer no
#      `ensure_last_empty`, o patch para de aplicar e o build falha SEMPRE —
#      sem o carimbo isso vira uma compilação por hora, para sempre.
#   4. FREIO MANUAL: `sudo touch /var/lib/aurora/cosmic-comp-ws-autobuild-off`
#      volta ao comportamento antigo (só avisar), sem editar script.
AUTOBUILD_OFF="$LIB/cosmic-comp-ws-autobuild-off"
MAX_TENTATIVAS=3
USUARIA="${AURORA_USER:-vitoriamaria}"

# Carimbo de tentativa: uma linha por disparo, para o log contar sozinho.
tentativa_de() { echo "$LIB/cosmic-comp-${1//\//_}.build-tentado"; }
tentativas_feitas() { local f; f="$(tentativa_de "$1")"; [ -f "$f" ] && wc -l < "$f" || echo 0; }

# O `[ ]` é o idioma do `ps aux | grep [p]attern`: impede que a regex case a
# cmdline do próprio pgrep. Mesma linha que vive no ExecCondition da unit do
# self-heal — se um dia mudar lá, muda aqui.
jogo_aberto() { pgrep -f "SteamLaunch[ ]AppId=[0-9]" >/dev/null 2>&1; }

# INSTALAR NOSSO BINÁRIO APAGA A LUZ NOTURNA, e quem a devolvia era a ORDEM: no
# self-heal a etapa do night light vem dez linhas depois da chamada do `--ensure`,
# de propósito. O auto-build rompe essa ordem — ele instala minutos DEPOIS, numa
# unit que o self-heal já não está olhando, e a tela dela ficaria em 6500K até o
# ciclo seguinte (até uma hora). Então quem instala fora do ciclo reaplica aqui.
# Exit 3 do patcher = o shader mudou upstream: ele não tocou no binário, e isso
# não é motivo para dizer que o build falhou.
reaplicar_night_light() {
  [ -x /usr/local/bin/aurora-night-light.py ] || return 0
  local rc=0
  /usr/local/bin/aurora-night-light.py 2>&1 | sed 's/^/  night-light: /' || rc=$?
  [ "$rc" = 0 ] || log "night-light: patcher voltou rc=$rc (a luz noturna volta no próximo self-heal)"
  return 0
}

# Dispara o build numa unit transitória e VOLTA na hora. Chamado de dentro do
# `--ensure`, que roda no meio do self-heal: bloquear aqui seria segurar a
# auto-cura inteira por minutos.
disparar_autobuild() {
  local ver="$1" n

  [ -f "$AUTOBUILD_OFF" ] && { log "auto-build desligado ($AUTOBUILD_OFF)"; return 1; }
  [ "$(id -u)" = "0" ] || return 1   # só o self-heal (root) dispara; à mão é --build
  command -v systemd-run >/dev/null 2>&1 || return 1

  if jogo_aberto; then
    log "auto-build adiado: jogo aberto (o próximo ciclo tenta de novo)"
    return 1
  fi

  n="$(tentativas_feitas "$ver")"
  if [ "$n" -ge "$MAX_TENTATIVAS" ]; then
    log "auto-build esgotado: $n tentativas para $ver falharam — precisa de olho humano"
    log "       o log de cada uma: journalctl -u aurora-cosmic-comp-ws-build"
    return 1
  fi

  # O carimbo é gravado ANTES de compilar, de propósito: um build que trava e
  # leva a máquina junto não pode voltar a ser tentado no boot seguinte como se
  # fosse a primeira vez.
  mkdir -p "$LIB"
  echo "$(date -Is) tentativa $((n + 1))/$MAX_TENTATIVAS" >> "$(tentativa_de "$ver")"

  if systemd-run --unit=aurora-cosmic-comp-ws-build --collect \
       --description="build do cosmic-comp patchado (versão $ver)" \
       --property=Nice=19 --property=CPUWeight=10 \
       --property=IOWeight=10 --property=IOSchedulingClass=idle \
       --setenv=AURORA_USER="$USUARIA" \
       "$0" --build-auto >/dev/null 2>&1; then
    log "auto-build DISPARADO em background (tentativa $((n + 1))/$MAX_TENTATIVAS)"
    log "       acompanhar: journalctl -fu aurora-cosmic-comp-ws-build"
    return 0
  fi

  # Falha aqui é quase sempre "a unit já existe" = build anterior ainda rodando.
  log "auto-build já em andamento (unit aurora-cosmic-comp-ws-build ativa)"
  return 1
}

# --- a SÉRIE de patches -----------------------------------------------------
#
# Três arrays paralelos, um índice por patch. Arrays e não um "classe:arquivo"
# concatenado porque nome de arquivo com espaço existe, e porque o marcador
# entra em regex — dividir na hora de usar seria pedir para errar.
SERIE_CARREGADA=0
SERIE_CLASSE=()
SERIE_ARQ=()
SERIE_MARCA=()
SERIE_ERROS=()
SERIE_ORIGEM=""

# Carrega uma vez por processo. NÃO registra nada sozinha: quem chama decide se
# a origem interessa ao humano — o `--ensure` roda de hora em hora e uma linha
# por ciclo dizendo "achei a série" só faria o journal crescer.
carregar_serie() {
  [ "$SERIE_CARREGADA" = 1 ] && return 0
  SERIE_CARREGADA=1

  local d classe arq marca home_dela p
  home_dela="$(getent passwd "$USUARIA" 2>/dev/null | cut -d: -f6)"

  # A TERCEIRA CANDIDATA NÃO É REDUNDANTE. O self-heal roda numa unit de SISTEMA,
  # sem `User=`: o `$HOME` que a linha 81 deriva vira /root, e /root/.config/zsh
  # não existe. Sem esta terceira tentativa, um auto-build disparado antes de o
  # `install_if_diff` do self-heal ter copiado para $SERIE_SISTEMA cairia no modo
  # antigo e sairia sem o patch do raio, calado.
  for d in "$SERIE_SISTEMA" \
           "$HOME/.config/zsh/patches/patches.d" \
           ${home_dela:+"$home_dela/.config/zsh/patches/patches.d"}; do
    [ -f "$d/series" ] || continue
    SERIE_ORIGEM="$d"
    break
  done

  if [ -n "$SERIE_ORIGEM" ]; then
    while read -r classe arq marca _; do
      case "$classe" in ''|'#'*) continue ;; esac
      if [ -z "$arq" ] || [ -z "$marca" ]; then
        SERIE_ERROS+=("linha com menos de 3 campos: '$classe $arq'"); continue
      fi
      case "$classe" in
        req|opt) ;;
        *) SERIE_ERROS+=("classe desconhecida '$classe' (só req/opt) em '$arq'"); continue ;;
      esac
      if [ ! -f "$SERIE_ORIGEM/$arq" ]; then
        SERIE_ERROS+=("declarado na série mas ausente no disco: $SERIE_ORIGEM/$arq"); continue
      fi
      SERIE_CLASSE+=("$classe"); SERIE_ARQ+=("$SERIE_ORIGEM/$arq"); SERIE_MARCA+=("$marca")
    done < "$SERIE_ORIGEM/series"
  fi

  [ "${#SERIE_CLASSE[@]}" -gt 0 ] && return 0

  # DEGRADAÇÃO SUAVE: sem série utilizável, volta a ser o que era antes de
  # 30/08/2026 — o patch único de workspace, obrigatório. Perde-se o raio
  # clampado, e só; o desktop continua de pé. Quem chama diz isso na tela.
  SERIE_ORIGEM="legado"
  p="$PATCH_INSTALADO"
  [ -f "$p" ] || p="$HOME/.config/zsh/patches/cosmic-comp-sem-workspace-vazio.patch"
  [ -f "$p" ] || [ -z "$home_dela" ] || p="$home_dela/.config/zsh/patches/cosmic-comp-sem-workspace-vazio.patch"
  if [ -f "$p" ]; then
    SERIE_CLASSE+=("req"); SERIE_ARQ+=("$p"); SERIE_MARCA+=("$MARCA")
  fi
  return 0
}

# A regex que casa QUALQUER marcador da série, com a versão colada.
#
# O SUFIXO É SÓ DÍGITO E PONTO, DE PROPÓSITO. Com `[0-9A-Za-z._-]*` o grep colava
# o símbolo seguinte da tabela de strings do binário e devolvia
# "AURORA-COSMIC-WS-PATCH-3.67assertion" — conferido de novo em 30/08/2026 no
# /usr/bin/cosmic-comp em execução. Dois binários com a MESMA versão do patch
# podem ter vizinhos diferentes ali, e a comparação passaria a acusar diferença
# onde não há: reinstalação em laço, uma por ciclo do self-heal.
marcas_regex() {
  local i partes=""
  carregar_serie
  for i in "${!SERIE_MARCA[@]}"; do
    partes="${partes:+$partes|}${SERIE_MARCA[$i]}"
  done
  echo "(${partes:-$MARCA})-[0-9][0-9.]*"
}

# O ARQUIVO-FONTE de um patch, descoberto no próprio `.patch`: qual hunk
# ACRESCENTA o marcador. Chumbar `src/shell/mod.rs` já não serviria — o patch do
# raio mora em src/wayland/protocols/corner_radius.rs, e o do modo de leitura vai
# morar noutro lugar ainda. Se nenhum `+` carregar o marcador (patch sem marcador
# declarado, ou marcador só em comentário de contexto), devolve o PRIMEIRO alvo
# do patch, que é o melhor palpite disponível.
arquivo_fonte_do_patch() {
  awk -v m="$2" '
    /^\+\+\+ / { alvo = $2; sub(/^b\//, "", alvo); if (primeiro == "") primeiro = alvo; next }
    /^\+/      { if (alvo != "" && index($0, m) > 0) { print alvo; achou = 1; exit } }
    END        { if (!achou && primeiro != "") print primeiro }
  ' "$1"
}

# "Patchado" passa a ser TODOS OS `req` PRESENTES, não "existe um marcador
# qualquer" (30/08/2026). Com a série de dois, o teste antigo respondia "sim"
# para um binário que tinha o workspace e não tinha o raio — e o `--ensure`
# voltava sem instalar o artefato que tinha os dois.
esta_patchado() {
  # grep -a: o binário é "arquivo binário" para o grep, que senão só diz
  # "Binary file matches" e some com o texto.
  local alvo="${1:-$ALVO}" i n=0
  carregar_serie
  for i in "${!SERIE_CLASSE[@]}"; do
    [ "${SERIE_CLASSE[$i]}" = req ] || continue
    n=$((n + 1))
    grep -aqs "${SERIE_MARCA[$i]}" "$alvo" || return 1
  done
  [ "$n" -gt 0 ] && return 0
  # Série sem nenhum `req` (só opcionais, ou série vazia): não há o que exigir,
  # então cai no marcador histórico para não responder "patchado" a um binário
  # de fábrica.
  grep -aqs "$MARCA" "$alvo"
}

# TODOS os marcadores COM a versão, ordenados e colados com `+`. Ex.:
#   AURORA-COSMIC-RADIUS-PATCH-1+AURORA-COSMIC-WS-PATCH-3.67
#
# O BURACO QUE ISTO TAPA, MEDIDO EM 25/08/2026
#   O patch ganhou um segundo assunto (as animações 1,75x e o fade do overview).
#   O build saiu com AURORA-COSMIC-WS-PATCH-3.67, o binário instalado tinha
#   3.54 — e o `esta_patchado` respondia "sim" para os dois. Resultado: o
#   `--ensure` dizia "OK (patch de workspace ativo)" e voltava sem instalar
#   nada. Quatro minutos de compilação parados no disco, e a tela igual.
#   Um booleano não serve para responder "qual patch?".
#
# O MESMO BURACO, UM DEGRAU ACIMA (30/08/2026)
#   Devolvendo só o PRIMEIRO marcador (`head -1`), a string do binário com
#   workspace+raio era idêntica à do binário só com workspace: a comparação do
#   `--ensure` não via diferença e não reinstalava. Acrescentar um patch à série
#   não chegava na tela dela. Agora entram todos.
#   `sort -u` e não a ordem do `strings`: a ordem em que o linker deixa os
#   símbolos não é estável entre builds, e uma string instável faria o `--ensure`
#   reinstalar o mesmo binário todo ciclo.
marcador_de() {
  strings -a "${1:-$ALVO}" 2>/dev/null \
    | grep -oE "$(marcas_regex)" | sort -u | paste -sd+ -
}

# --- o arquivo que o `meow doctor` lê ---------------------------------------
#
# MEDIDO, NUNCA DEDUZIDO. A tentação é gravar aqui a lista de marcadores que a
# série DECLARA — é mais barato e sempre "bate". Mas o que se quer conferir é
# exatamente o que pode divergir: o `#[used]` pode ter sido descartado pelo
# linker, um `opt` pode ter sido pulado no dry-run, e nos dois casos o efeito não
# está no binário mesmo com o patch na série. Um arquivo de diagnóstico que
# grava a intenção em vez do fato é pior que arquivo nenhum: ele faz o doctor
# dizer "conforme" para um desktop que não está.
#
# Formato, quatro campos por linha de patch, um espaço entre eles:
#   <classe> <marcador-completo> <arquivo> <presente|ausente>
# Quando o marcador não está no binário, o campo 2 fica com o marcador-BASE (sem
# versão) — não há versão a informar — e o campo 4 é `ausente`.
gravar_estado() {
  local bin="${1:-$ALVO}" ver="${2:-}" i base achado tmp achados
  [ -f "$bin" ] || return 0
  [ -n "$ver" ] || ver="$(versao_pacote)"
  carregar_serie

  # Só quem pode escrever em /var/lib/aurora grava. O `--build` à mão roda como
  # ela e instala via `sudo "$0" --ensure`: é esse --ensure, já root, que grava.
  [ "$(id -u)" = "0" ] || return 0
  mkdir -p "$LIB" 2>/dev/null || return 0

  # Um `strings` só no binário de 33 MB, não um por patch.
  achados="$(strings -a "$bin" 2>/dev/null | grep -oE "$(marcas_regex)" | sort -u)"

  tmp="$ESTADO.tmp$$"
  {
    echo "# gerado por aurora-cosmic-comp-ws.sh — NÃO EDITAR A MAO"
    echo "versao=$ver"
    echo "gravado=$(date -Is)"
    for i in "${!SERIE_CLASSE[@]}"; do
      base="${SERIE_MARCA[$i]}"
      achado="$(printf '%s\n' "$achados" | grep -m1 "^$base-" || true)"
      if [ -n "$achado" ]; then
        echo "${SERIE_CLASSE[$i]} $achado $(basename "${SERIE_ARQ[$i]}") presente"
      else
        echo "${SERIE_CLASSE[$i]} $base $(basename "${SERIE_ARQ[$i]}") ausente"
      fi
    done
  } > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 0; }
  chmod 644 "$tmp" && mv -f "$tmp" "$ESTADO"
}

# O estado envelhece sozinho: um `apt` troca a versão do pacote e o arquivo passa
# a descrever um binário que já não está no disco. Isto regrava quando falta ou
# quando a versão gravada não é a de agora — barato (um `strings`) e mantém o
# doctor honesto sem esperar a próxima instalação.
estado_em_dia() {
  local ver="$1"
  [ -f "$ESTADO" ] || return 1
  grep -qx "versao=$ver" "$ESTADO" 2>/dev/null || return 1
  return 0
}

# O TERCEIRO ARGUMENTO É A URGÊNCIA — e ela NÃO é a cura do Não Perturbe.
#   MEDIDO em 28/08/2026, nesta máquina: com `do_not_disturb: true` no
#   cosmic-notifications, um `notify-send -u critical` NÃO aparece na tela.
#   Testado com screenshot logo depois do envio: nada. O COSMIC engole as três
#   urgências igual — diferente do GNOME, onde critical fura.
#   Então `critical` aqui vale por duas coisas menores, não pela entrega: fica no
#   histórico da central e passa a funcionar no dia em que ela desligar o DND.
#   QUEM PRECISA MESMO SER VISTO não pode depender disto — é por isso que o
#   auto-build existe: conserta sem precisar avisar ninguém.
avisar_usuaria() {
  # notify-send precisa do barramento DELA; o self-heal roda como root.
  local titulo="$1" corpo="$2" urg="${3:-normal}"
  if [ "$(id -u)" = "0" ] && id vitoriamaria >/dev/null 2>&1; then
    runuser -u vitoriamaria -- env \
      XDG_RUNTIME_DIR=/run/user/1000 \
      DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus" \
      notify-send -u "$urg" -i dialog-information "$titulo" "$corpo" >/dev/null 2>&1 || true
  else
    command -v notify-send >/dev/null 2>&1 && \
      notify-send -u "$urg" -i dialog-information "$titulo" "$corpo" >/dev/null 2>&1 || true
  fi
}

cmd_status() {
  local ver art i pid exe m_disco m_sessao
  ver="$(versao_pacote)"
  art="$(artefato_de "$ver")"
  carregar_serie
  echo "versão do pacote : ${ver:-desconhecida}"
  echo "binário instalado: $ALVO"
  if esta_patchado; then
    echo "estado           : PATCHADO (todos os req da série presentes)"
  else
    echo "estado           : INCOMPLETO — falta req da série (o workspace vazio volta)"
  fi

  if [ "$SERIE_ORIGEM" = legado ]; then
    echo "série            : AUSENTE — modo antigo, só o patch de workspace"
  else
    echo "série            : $SERIE_ORIGEM (${#SERIE_CLASSE[@]} patches)"
  fi
  for i in "${!SERIE_ERROS[@]}"; do
    echo "  ! ${SERIE_ERROS[$i]}"
  done
  for i in "${!SERIE_CLASSE[@]}"; do
    if grep -aqs "${SERIE_MARCA[$i]}" "$ALVO"; then
      printf '  %-4s %-38s no binário\n' "${SERIE_CLASSE[$i]}" "$(basename "${SERIE_ARQ[$i]}")"
    else
      printf '  %-4s %-38s AUSENTE do binário\n' "${SERIE_CLASSE[$i]}" "$(basename "${SERIE_ARQ[$i]}")"
    fi
  done

  m_disco="$(marcador_de "$ALVO")"
  echo "marcadores (disco): ${m_disco:-<nenhum>}"

  # A PERGUNTA DO DOCTOR É SOBRE O PROCESSO, NÃO SOBRE O ARQUIVO: instalar
  # binário novo não troca o compositor em execução — vale no próximo login. Ler
  # /proc/<pid>/exe pede ser o dono do processo (ela) ou root.
  pid="$(pgrep -x cosmic-comp 2>/dev/null | head -1)"
  if [ -n "$pid" ]; then
    exe="/proc/$pid/exe"
    if [ -r "$exe" ]; then
      m_sessao="$(marcador_de "$exe")"
      echo "marcadores (sessão): ${m_sessao:-<nenhum>}  [pid $pid]"
      [ "$m_sessao" = "$m_disco" ] || \
        echo "  ~~ disco e sessão divergem: o que está no disco vale no próximo login"
    else
      echo "marcadores (sessão): sem permissão de ler /proc/$pid/exe (rode como ela ou root)"
    fi
  else
    echo "marcadores (sessão): cosmic-comp não está em execução"
  fi

  if [ -f "$ESTADO" ]; then
    echo "estado gravado   : $ESTADO"
    sed 's/^/  /' "$ESTADO"
  else
    echo "estado gravado   : AUSENTE ($ESTADO) — nasce na próxima instalação"
  fi

  if [ -f "$art" ]; then
    echo "artefato         : $art"
  else
    echo "artefato         : AUSENTE para esta versão — precisa de --build"
  fi
}

# --- modo do self-heal: reconcilia sem nunca compilar -----------------------
cmd_ensure() {
  [ -f "$ALVO" ] || { log "cosmic-comp não instalado — nada a fazer"; return 0; }

  local ver art orig
  ver="$(versao_pacote)"
  if [ -z "$ver" ]; then
    log "AVISO: não consegui descobrir a versão do pacote — não vou tocar no binário"
    return 0
  fi
  art="$(artefato_de "$ver")"
  orig="$(pkg_orig_de "$ver")"

  # Uma linha por ciclo, e SÓ quando há degradação a relatar. "Achei a série" não
  # é notícia; "caí no modo antigo" é — foi o silêncio que deixou o patch do raio
  # três semanas fora de produção sem ninguém saber.
  carregar_serie
  local e
  [ "$SERIE_ORIGEM" = legado ] && \
    log "AVISO: sem patches.d — modo antigo (só o patch de workspace, sem o raio clampado)"
  for e in "${!SERIE_ERROS[@]}"; do log "AVISO na série: ${SERIE_ERROS[$e]}"; done

  if esta_patchado; then
    # Já está do nosso jeito. Se o artefato sumiu (limpeza de disco), regrava a
    # partir do próprio binário instalado — mas só se ele ainda estiver LIMPO,
    # isto é, sem o patch do shader por cima. Um artefato com night light dentro
    # envenenaria a próxima instalação com a temperatura de hoje.
    # A STRING AQUI ERA 'aurora-night-light' E NUNCA CASAVA COM NADA.
    #   `grep -ac 'aurora-night-light' /usr/bin/cosmic-comp` -> 0, mesmo com a luz
    #   noturna aplicada. O marcador que o patcher escreve é outro:
    #   `MARK = "NIGHT LIGHT (Aurora)"` (aurora-night-light.py:69). Com o nome
    #   errado a guarda passava sempre, e um binário JÁ com a temperatura de hoje
    #   podia virar o artefato — que é o molde de toda instalação futura. Guarda
    #   que nunca dispara é pior que guarda nenhuma: ela dá a impressão de que o
    #   caso está coberto. Achado pela auditoria de 25/08/2026.
    if [ ! -f "$art" ] && ! grep -aqs 'NIGHT LIGHT (Aurora)' "$ALVO"; then
      mkdir -p "$LIB" && cp -a "$ALVO" "$art" 2>/dev/null \
        && log "artefato regravado a partir do binário instalado"
    fi

    # O ARTEFATO PODE SER MAIS NOVO QUE O INSTALADO — ver `marcador_de`. Um
    # `--build` novo troca o artefato; sem esta comparação o binário só mudaria
    # no dia em que o apt subisse a versão do pacote, que é quando o
    # `esta_patchado` finalmente responde "não".
    #
    # PERDER O NIGHT LIGHT AQUI É ESPERADO E ESTÁ COBERTO: o artefato sai do
    # build, limpo, e o shader quente do `aurora-night-light.py` vive só no
    # binário instalado. O self-heal reaplica logo depois — a chamada dele
    # (ritual-aurora-self-heal.sh:2636) vem DEZ linhas abaixo da chamada deste
    # `--ensure` (:2626), nessa ordem de propósito.
    local m_alvo m_art
    m_alvo="$(marcador_de "$ALVO")"; m_art=""
    if [ -f "$art" ]; then
      m_art="$(marcador_de "$art")"
      if [ -n "$m_art" ] && [ "$m_alvo" != "$m_art" ]; then
        mkdir -p "$LIB"
        [ -f "$orig" ] || cp -a "$ALVO" "$orig"
        cp -a "$art" "$ALVO.aurora-tmp" && mv -f "$ALVO.aurora-tmp" "$ALVO" \
          && chmod 755 "$ALVO" \
          && log "ATUALIZADO o build patchado: ${m_alvo:-<sem marcador>} -> $m_art (vale no próximo login)"
        gravar_estado "$ALVO" "$ver"
        return 0
      fi
    fi

    # Nada mudou no binário — mas o arquivo de estado pode ter envelhecido (um
    # `apt` que trocou a versão, ou este script rodando pela primeira vez depois
    # da mudança de 30/08/2026). Regravar aqui é um `strings` e mantém o doctor
    # falando do binário que está no disco AGORA.
    estado_em_dia "$ver" || gravar_estado "$ALVO" "$ver"
    log "OK (patch ativo: ${m_alvo:-<sem marcador>}, versão $ver)"
    return 0
  fi

  if [ -f "$art" ]; then
    mkdir -p "$LIB"
    [ -f "$orig" ] || cp -a "$ALVO" "$orig"
    # Escrita atômica: nunca deixar /usr/bin/cosmic-comp truncado. Um cosmic-comp
    # pela metade é tela preta no próximo login.
    cp -a "$art" "$ALVO.aurora-tmp" && mv -f "$ALVO.aurora-tmp" "$ALVO" \
      && chmod 755 "$ALVO" \
      && log "REINSTALADO o build patchado (versão $ver) — vale no próximo login"
    gravar_estado "$ALVO" "$ver"
    return 0
  fi

  # Sem artefato: o binário no disco é o do pacote. O estado tem de dizer isso —
  # é o caso em que o doctor precisa gritar, e um arquivo velho o faria calar.
  estado_em_dia "$ver" || gravar_estado "$ALVO" "$ver"

  log "AVISO: cosmic-comp $ver não tem build patchado — o workspace vazio volta"

  # Antes de 28/08/2026 esta função parava aqui, no aviso. Agora ela tenta
  # consertar: o `disparar_autobuild` sai em silêncio (return 1) sempre que
  # alguma das quatro guardas segura, e aí o aviso ao humano continua valendo.
  if disparar_autobuild "$ver"; then
    avisar_usuaria "COSMIC atualizou" \
      "Estou recompilando o patch dos workspaces em segundo plano. O número extra some no próximo login."
    return 0
  fi

  log "       para consertar à mão: aurora-cosmic-comp-ws.sh --build"
  # URGÊNCIA CRITICAL DE PROPÓSITO: a `normal` morre no Não Perturbe, que vive
  # ligado nesta máquina — foi assim que 22 avisos seguidos não chegaram nela.
  avisar_usuaria "COSMIC atualizou" \
    "O patch que esconde o workspace vazio não vale para a versão nova, e o auto-build não pôde rodar. Peça ao agente: 'rebuilda o patch do cosmic-comp'." \
    critical
  return 0
}

# O diretório de fonte DESTA versão, dentro do BUILD_DIR de quem for dono dele.
# Existe para o auto-build: ele roda como root, mas o fonte e o `target/` são
# dela — derivar o caminho é mais honesto que adivinhar pelo $HOME de quem chama.
src_dir_de() {
  local ver="$1" base="${2:-$BUILD_DIR}"
  echo "$base/cosmic-comp-$ver"
}

# --- a compilação, sem instalar nada ----------------------------------------
# SEPARADA DO `cmd_build` EM 28/08/2026, por causa do auto-build: a unit
# transitória já é root, e o `sudo` do final do cmd_build pediria senha num
# lugar onde ninguém pode digitar. Agora quem instala é o chamador — com sudo
# (build à mão) ou direto (auto-build, já root).
compilar() {
  command -v cargo >/dev/null 2>&1 || { echo "ERRO: cargo não encontrado." >&2; return 2; }

  local ver src i j fonte rc seco_saida
  ver="$(versao_pacote)"
  [ -n "$ver" ] || { echo "ERRO: cosmic-comp não instalado." >&2; return 2; }

  carregar_serie
  if [ "${#SERIE_CLASSE[@]}" = 0 ]; then
    echo "ERRO: nenhuma série de patches encontrada, e nem o patch único de" >&2
    echo "      reserva ($PATCH_INSTALADO). Nada foi instalado." >&2
    return 2
  fi
  if [ "$SERIE_ORIGEM" = legado ]; then
    echo ">> AVISO: sem patches.d — modo antigo, só o patch de workspace"
  else
    echo ">> série: $SERIE_ORIGEM (${#SERIE_CLASSE[@]} patches)"
  fi
  for i in "${!SERIE_ERROS[@]}"; do echo ">> AVISO na série: ${SERIE_ERROS[$i]}"; done

  mkdir -p "$BUILD_DIR" || return 2
  cd "$BUILD_DIR" || return 2

  echo ">> baixando o fonte da versão instalada ($ver)"
  apt-get source cosmic-comp >/dev/null 2>&1 || {
    echo "ERRO: apt-get source falhou (deb-src habilitado?)." >&2; return 2; }

  # ANTES ISTO ERA `find ... | sort | tail -1`, e acertava por sorte: os
  # timestamps epoch do nome ainda têm o mesmo número de dígitos, então a ordem
  # alfabética coincide com a cronológica. Basta um fonte de versão MAIOR ficar
  # no diretório (um downgrade do apt, um `apt-get source` manual) para o build
  # sair da versão errada — e um cosmic-comp de outra versão é a sessão que não
  # sobe que este script inteiro existe para evitar. Agora casa a versão exata.
  src="$(src_dir_de "$ver")"
  [ -d "$src" ] || {
    echo "ERRO: fonte da versão $ver não apareceu em $BUILD_DIR." >&2; return 2; }
  cd "$src" || return 2

  # --- FASE 1: DRY-RUN DE TODOS ANTES DE APLICAR QUALQUER UM -----------------
  #
  # A ordem importa mais do que parece. Aplicando um por um, um `opt` que falhe
  # depois de um `req` já aplicado deixa a árvore num estado que ninguém
  # declarou, e o build seguinte parte dela. Conferindo tudo primeiro, um `req`
  # que morreu aborta com a árvore intocada.
  #
  # E O TESTE DE "JÁ APLICADO" VEM ANTES DO DRY-RUN, NÃO DEPOIS: `patch
  # --forward` devolve 1 para "Reversed (or previously applied) patch detected"
  # — indistinguível de erro pelo código de saída. Medido em 30/08/2026 neste
  # fonte: workspace-vazio (já aplicado) rc=1, raio-clampado (ausente) rc=0. Sem
  # este grep, um build repetido veria o `req` "falhando" e abortaria para sempre.
  local plano=()
  for i in "${!SERIE_ARQ[@]}"; do
    fonte="$(arquivo_fonte_do_patch "${SERIE_ARQ[$i]}" "${SERIE_MARCA[$i]}")"
    if [ -n "$fonte" ] && [ -f "$fonte" ] && grep -q "${SERIE_MARCA[$i]}" "$fonte" 2>/dev/null; then
      plano+=("ja")
      echo ">> [${SERIE_CLASSE[$i]}] $(basename "${SERIE_ARQ[$i]}"): já no fonte ($fonte)"
      continue
    fi
    rc=0
    seco_saida="$(patch -p1 --dry-run --forward --batch < "${SERIE_ARQ[$i]}" 2>&1)" || rc=$?
    if [ "$rc" = 0 ]; then
      plano+=("aplicar")
      echo ">> [${SERIE_CLASSE[$i]}] $(basename "${SERIE_ARQ[$i]}"): dry-run OK -> ${fonte:-?}"
      # "APLICOU" E "APLICOU NO LUGAR CERTO" SÃO PERGUNTAS DIFERENTES — descoberto
      # do jeito caro em 30/08/2026. Um `.patch` de teste com contexto INVENTADO
      # ("esta linha não existe no fonte") passou no dry-run com rc=0 e foi
      # aplicado: o `patch` do GNU tem fator de fuzz 2 por padrão, ignora até
      # duas linhas de contexto e casa pelo número da linha. O `strings` do fim
      # não pega isso — o marcador ESTÁ no binário, só que pregado num lugar que
      # ninguém pediu. Num compositor que é também a tela de login, isso é o
      # tipo de coisa que só aparece no reboot.
      # NÃO ABORTA, avisa: fuzz também é como um patch sobrevive a upstream
      # empurrando o código algumas linhas, que é o caso comum e legítimo. Mas
      # sai no registro, com nome e número, para o humano poder olhar.
      if printf '%s\n' "$seco_saida" | grep -q 'with fuzz'; then
        echo "   ~~ ATENÇÃO: casou com FUZZ — o contexto do patch já não bate com o fonte."
        printf '%s\n' "$seco_saida" | grep 'with fuzz' | sed 's/^/      /'
        echo "      O patch vai entrar assim mesmo. Se o efeito sumir sem erro, é aqui."
      fi
    elif [ "${SERIE_CLASSE[$i]}" = req ]; then
      echo "ERRO: o patch OBRIGATÓRIO $(basename "${SERIE_ARQ[$i]}") não aplica (rc=$rc)." >&2
      echo "      Provável: o upstream mexeu no trecho que ele edita." >&2
      echo "      A árvore NÃO foi tocada e NADA será instalado — o desktop" >&2
      echo "      continua no binário do pacote, que é o certo aqui." >&2
      return 3
    else
      plano+=("pular")
      echo ">> [opt] $(basename "${SERIE_ARQ[$i]}"): NÃO aplica (rc=$rc) — o build segue SEM esse efeito"
    fi
  done

  # Válvula para conferir a série e os dry-runs sem queimar 4 minutos de CPU.
  # Não existe caminho daqui para o `make`: quem exercita isto nunca compila.
  if [ "${AURORA_WS_SO_DRYRUN:-0}" = "1" ]; then
    echo ">> AURORA_WS_SO_DRYRUN=1: parei depois dos dry-runs. A árvore não foi tocada."
    for i in "${!SERIE_ARQ[@]}"; do
      printf '   %-4s %-38s %s\n' "${SERIE_CLASSE[$i]}" "$(basename "${SERIE_ARQ[$i]}")" "${plano[$i]}"
    done
    return 0
  fi

  # --- FASE 2: aplicar, com desfazer se algo escapar do dry-run --------------
  local aplicados=()
  for i in "${!SERIE_ARQ[@]}"; do
    [ "${plano[$i]}" = "aplicar" ] || continue
    echo ">> aplicando $(basename "${SERIE_ARQ[$i]}")"
    if patch -p1 --forward --batch < "${SERIE_ARQ[$i]}"; then
      aplicados+=("$i")
      continue
    fi
    echo "ERRO: $(basename "${SERIE_ARQ[$i]}") passou no dry-run e falhou ao aplicar." >&2
    echo "      Desfazendo o que ESTE build já tinha aplicado — uma árvore" >&2
    echo "      meio-patchada faz o build seguinte sair torto em silêncio." >&2
    for j in "${aplicados[@]}"; do
      patch -p1 --reverse --batch < "${SERIE_ARQ[$j]}" >/dev/null 2>&1 \
        && echo "      desfeito: $(basename "${SERIE_ARQ[$j]}")"
    done
    echo "      Se sobrar algum .rej, o conserto é apagar a árvore e deixar o" >&2
    echo "      apt-get source reextrair:  rm -rf '$src'" >&2
    return 3
  done

  echo ">> compilando (LTO fat; ~4min com o vendor quente, ~30min do zero)"
  make VENDOR=1 || { echo "ERRO: build falhou." >&2; return 4; }

  local bin="$src/target/release/cosmic-comp"
  [ -f "$bin" ] || { echo "ERRO: binário não saiu do build." >&2; return 4; }

  # --- FASE 3: o marcador tem de ter SOBREVIVIDO ao linker -------------------
  # O marcador é um `#[used] static &str`. Sem o `#[used]` o linker o descarta, e
  # um marcador ausente faz o `--ensure` não reconhecer o próprio build: ele
  # reinstalaria o artefato a cada ciclo, para sempre. A guarda já existia para
  # um patch; aqui ela vale para cada um que deveria estar dentro.
  local faltou_req=0
  for i in "${!SERIE_ARQ[@]}"; do
    case "${plano[$i]}" in ja|aplicar) ;; *) continue ;; esac
    if grep -aqs "${SERIE_MARCA[$i]}" "$bin"; then
      echo ">> marcador no binário: $(strings -a "$bin" | grep -om1 "${SERIE_MARCA[$i]}-[0-9][0-9.]*" || echo "${SERIE_MARCA[$i]}")"
    elif [ "${SERIE_CLASSE[$i]}" = req ]; then
      echo "ERRO: o binário buildado NÃO tem ${SERIE_MARCA[$i]}, e o patch foi" >&2
      echo "      aplicado. Falta o \`#[used]\` no static, ou o linker o comeu." >&2
      faltou_req=1
    else
      echo ">> AVISO: ${SERIE_MARCA[$i]} não está no binário (opcional). O efeito"
      echo "          pode estar lá, mas o self-heal não tem como saber."
    fi
  done
  [ "$faltou_req" = 0 ] || {
    echo "      Abortado sem instalar; o desktop continua no binário atual." >&2; return 4; }

  echo "ARTEFATO-PRONTO: $bin"
}

# Cada árvore de fonte compilada pesa ~3,2 GB, e as versões do cosmic-comp saem
# quase diárias — sem poda o auto-build enche o /home dela sozinho. Só roda
# depois de um build BEM-SUCEDIDO, e só apaga o que prova ser árvore de fonte de
# OUTRA versão. Os `.tar.xz` (94 MB) ficam: são o que evita re-baixar.
podar_fontes() {
  local ver_atual="$1" base="${2:-$BUILD_DIR}" d
  [ -d "$base" ] || return 0
  for d in "$base"/cosmic-comp-*; do
    [ -d "$d" ] || continue
    [ "$d" = "$(src_dir_de "$ver_atual" "$base")" ] && continue
    [ -f "$d/Cargo.toml" ] || continue    # sem isto não é árvore de fonte: não toco
    rm -rf -- "$d" && echo ">> podado o fonte antigo: $(basename "$d")"
  done
}

# --- poda do /var/lib/aurora (30/08/2026, Sprint U item 7) -------------------
#
# O QUE FOI MEDIDO HOJE, e o que ele contradiz
#   /var/lib/aurora tem 8 `.orig`, 4 `.pkg-orig` e 4 `.aurora-ws` — 460 MB, e o
#   cosmic-comp trocou SEIS vezes entre 13/07 e 26/08. Nada aqui nunca limpou
#   nada: o `podar_fontes` cuida do /home dela (as árvores de 3,2 GB), e o
#   /var/lib ficou sem dono.
#
# AS REGRAS, e por que cada uma
#   * os 3 `.orig` mais novos por mtime ficam. O `.orig` é o binário do PACOTE, e
#     é ele — não o `.pkg-orig` — que o cartão de recuperação manda usar quando o
#     compositor não sobe (o md5 do `.pkg-orig` não bate com o do dpkg, porque
#     ele já vem com o night light dentro). Três é a folga para um downgrade.
#   * o `.orig` E o `.pkg-orig` da versão instalada AGORA ficam sempre, mesmo que
#     o mtime os jogue para fora dos três — é a rede de segurança de hoje.
#   * `.pkg-orig` acompanha o `.orig` da mesma versão: um `.pkg-orig` órfão, sem
#     o `.orig` irmão, é 28 MB que nenhum procedimento de volta menciona.
#   * todo `.aurora-ws` de versão que NÃO é a corrente vai embora. Ele é o nosso
#     build, e o `--ensure` se recusa (com razão) a instalar artefato de outra
#     versão: guardar é guardar o que já não pode ser usado.
#   * o artefato da versão corrente NUNCA é apagado — é ele que o `--ensure`
#     reinstala depois de um `apt` reescrever /usr/bin/cosmic-comp.
#
# O QUE ELA NÃO TOCA: os globs são estreitos de propósito. `night-light-temp`,
# `efi-pop-backup/`, os carimbos `.build-tentado`, o freio
# `cosmic-comp-ws-autobuild-off`, o `.estado` e — importante — um
# `.QUARENTENA` criado no passo 4 do cartão de recuperação não casam com
# nenhum deles.
QUANTOS_ORIG=3

# `cosmic-comp-<versão>.<ext>` -> `<versão>`. O `%.<ext>` explícito, e não
# `${b%.*}`: a versão TEM pontos (0.1~…~24.04~…) e um corte genérico é o tipo de
# coisa que só erra no dia em que o formato da versão mudar.
ver_do_arquivo() { local b; b="$(basename "$1")"; b="${b#cosmic-comp-}"; echo "${b%".$2"}"; }

podar_lib() {
  local seco="${1:-}" ver_atual f v n=0 manter=" "
  ver_atual="$(versao_pacote)"
  ver_atual="${ver_atual//\//_}"
  [ -d "$LIB" ] || { echo ">> $LIB não existe — nada a podar"; return 0; }

  # SEM VERSÃO NÃO SE PODA. Com `ver_atual` vazio, a regra do `.aurora-ws`
  # ("apaga todo o que não é o corrente") apagaria TODOS — inclusive o único
  # artefato que o `--ensure` tem para reinstalar depois de um apt. É o mesmo
  # cuidado que o `cmd_ensure` já toma antes de tocar no binário.
  if [ -z "$ver_atual" ]; then
    echo ">> não consegui descobrir a versão do pacote — não vou podar nada"
    return 0
  fi

  # Quem fica: a versão corrente + as versões dos N `.orig` mais novos.
  [ -n "$ver_atual" ] && manter=" $ver_atual "
  # `ls -1t` e não `find`: o find não ordena por mtime sem um sort extra, e os
  # nomes aqui são nossos (cosmic-comp-<versão>.orig) — a versão do pacote nunca
  # teve espaço, quebra de linha ou aspa.
  # shellcheck disable=SC2012
  while read -r f; do
    [ -n "$f" ] || continue
    v="$(ver_do_arquivo "$f" orig)"
    case "$manter" in *" $v "*) ;; *) manter="$manter$v " ;; esac
  done < <(ls -1t "$LIB"/cosmic-comp-*.orig 2>/dev/null | head -n "$QUANTOS_ORIG")

  echo ">> poda de $LIB${seco:+  (SECO: só lista, não apaga)}"
  echo "   versão instalada: ${ver_atual:-<desconhecida>}"
  echo "   versões mantidas:$manter"

  for f in "$LIB"/cosmic-comp-*.orig "$LIB"/cosmic-comp-*.pkg-orig "$LIB"/cosmic-comp-*.aurora-ws; do
    [ -f "$f" ] || continue
    case "$f" in
      *.pkg-orig)  v="$(ver_do_arquivo "$f" pkg-orig)" ;;
      *.aurora-ws) v="$(ver_do_arquivo "$f" aurora-ws)" ;;
      *)           v="$(ver_do_arquivo "$f" orig)" ;;
    esac

    # O nosso build só serve à versão corrente; os backups do pacote seguem a
    # lista de mantidos.
    case "$f" in
      *.aurora-ws) [ "$v" = "$ver_atual" ] && { echo "   fica   $(basename "$f")"; continue; } ;;
      *)           case "$manter" in *" $v "*) echo "   fica   $(basename "$f")"; continue ;; esac ;;
    esac

    n=$((n + 1))
    if [ -n "$seco" ]; then
      echo "   APAGARIA $(basename "$f")  ($(du -h "$f" 2>/dev/null | cut -f1))"
    else
      rm -f -- "$f" && echo "   apagado  $(basename "$f")"
    fi
  done

  [ "$n" = 0 ] && echo "   nada a podar"
  return 0
}

cmd_podar() {
  local seco=""
  case "${1:-}" in
    --seco|-n|seco) seco=1 ;;
    "") ;;
    *) echo "uso: $0 --podar [--seco]" >&2; return 2 ;;
  esac
  # Sem root não dá para apagar de /var/lib/aurora (root:root). Em vez de falhar
  # arquivo por arquivo, degrada para seco e diz por quê.
  if [ -z "$seco" ] && [ "$(id -u)" != "0" ]; then
    echo ">> sem root: rodando em modo SECO (para apagar de verdade: sudo $0 --podar)"
    seco=1
  fi
  podar_lib "$seco"
}

# --- build à mão: compila como ela, instala com sudo -------------------------
cmd_build() {
  if [ "$(id -u)" = "0" ]; then
    echo "ERRO: rode o --build como usuária normal (o cargo é do rustup dela)." >&2
    echo "      O script pede sudo sozinho na hora de instalar." >&2
    return 2
  fi

  local saida bin ver rc
  ver="$(versao_pacote)"
  # O `tee` mantém o progresso na tela — um build de minutos em silêncio parece
  # travado. A captura serve só para achar a linha ARTEFATO-PRONTO no fim.
  # `/dev/stderr` e não `/dev/tty`: assim isto também funciona com a saída
  # redirecionada para arquivo, que é como um agente roda o build.
  saida="$(compilar 2>&1 | tee /dev/stderr)"; rc=${PIPESTATUS[0]}
  [ "$rc" = 0 ] || return "$rc"
  bin="$(echo "$saida" | sed -n 's/^ARTEFATO-PRONTO: //p' | tail -1)"
  [ -n "$bin" ] && [ -f "$bin" ] || { echo "ERRO: build não produziu binário." >&2; return 4; }

  echo ">> guardando o artefato e instalando (pede sudo)"
  sudo mkdir -p "$LIB" \
    && sudo cp -a "$bin" "$(artefato_de "$ver")" \
    && sudo "$0" --ensure || return 4

  # Mesma razão do auto-build: o binário recém-instalado é limpo, sem o shader da
  # luz noturna. Um rc≠0 aqui não inválida o build — daí não estar no `&&`.
  [ -x /usr/local/bin/aurora-night-light.py ] && \
    sudo /usr/local/bin/aurora-night-light.py 2>&1 | sed 's/^/  night-light: /'

  # O `.estado` já foi gravado pelo `sudo "$0" --ensure` acima, que é quem
  # escreveu /usr/bin/cosmic-comp — e é root, que é quem pode escrever em $LIB.
  podar_fontes "$ver"
  # A poda do /var/lib precisa de root e este caminho roda como ela. Falhar aqui
  # não inválida um build que já está instalado: `|| true`.
  sudo "$0" --podar || true
}

# --- build automático: chamado pela unit transitória, já como root -----------
# NÃO CHAMAR À MÃO — para isso existe o `--build`. Este modo assume que quem o
# invocou é o `disparar_autobuild`, que já gravou o carimbo da tentativa.
cmd_build_auto() {
  [ "$(id -u)" = "0" ] || { echo "ERRO: --build-auto é chamado como root pela unit." >&2; return 2; }

  local ver home_dela build_dela bin
  ver="$(versao_pacote)"
  [ -n "$ver" ] || { echo "ERRO: cosmic-comp não instalado." >&2; return 2; }

  # Já pode ter chegado artefato entre o disparo e agora (um `--build` à mão da
  # usuária, por exemplo). Compilar de novo seria só queimar CPU.
  [ -f "$(artefato_de "$ver")" ] && { log "artefato já existe para $ver — nada a compilar"; exec "$0" --ensure; }

  home_dela="$(getent passwd "$USUARIA" 2>/dev/null | cut -d: -f6)"
  [ -n "$home_dela" ] || { echo "ERRO: não achei o home de $USUARIA." >&2; return 2; }
  build_dela="${AURORA_WS_BUILD_DIR:-$home_dela/Desenvolvimento/cosmic-comp-patch}"

  # O CARGO É DO RUSTUP DELA, e vive em ~/.cargo/bin — que não está no PATH de
  # uma unit do systemd. Sem esta linha o `command -v cargo` do `compilar`
  # falharia com "cargo não encontrado" depois de baixar 94 MB de fonte.
  echo ">> compilando como $USUARIA (versão $ver)"
  runuser -u "$USUARIA" -- env \
    HOME="$home_dela" \
    PATH="$home_dela/.cargo/bin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin" \
    AURORA_WS_BUILD_DIR="$build_dela" \
    "$0" --compile-only || {
      echo "ERRO: a compilação falhou — o binário do pacote continua no lugar." >&2
      avisar_usuaria "Patch dos workspaces falhou" \
        "A recompilação automática do cosmic-comp não deu certo. O número extra continua no painel até alguém olhar." \
        critical
      return 4; }

  # `esta_patchado` e não `grep "$MARCA"`: com a série, "tem marcador" deixou de
  # ser a pergunta — a pergunta é se TODOS os `req` estão no binário. Um build que
  # perdeu um obrigatório não pode virar artefato: o artefato é o molde de toda
  # instalação futura desta versão.
  bin="$(src_dir_de "$ver" "$build_dela")/target/release/cosmic-comp"
  [ -f "$bin" ] && esta_patchado "$bin" || {
    echo "ERRO: binário compilado ausente ou sem os marcadores obrigatórios ($bin)." >&2; return 4; }

  # Sem sudo: esta unit já é root. Era exatamente o `sudo` do `cmd_build` que
  # impedia o build de ser automatizado — ele pede senha e aqui não há tty.
  mkdir -p "$LIB" && cp -a "$bin" "$(artefato_de "$ver")" || return 4
  "$0" --ensure
  reaplicar_night_light
  # Regravado DEPOIS do night light, de propósito: o `.estado` tem de descrever o
  # binário que ficou no disco, e o patcher reescreve bytes dele. Os nossos
  # marcadores sobrevivem a isso (o patcher só troca texto do shader, preservando
  # o tamanho), e é justamente por isso que o arquivo é medido e não deduzido.
  gravar_estado "$ALVO" "$ver"
  podar_fontes "$ver" "$build_dela"
  podar_lib

  # O carimbo some no sucesso: se esta MESMA versão perder o patch de novo (uma
  # reinstalação do pacote), o contador não pode começar já gasto.
  rm -f "$(tentativa_de "$ver")"
  avisar_usuaria "Workspaces de volta ao normal" \
    "Recompilei o cosmic-comp com o patch (versão $ver). O número extra some no próximo login."
}

cmd_restore() {
  local ver orig
  ver="$(versao_pacote)"
  orig="$(pkg_orig_de "$ver")"
  if [ ! -f "$orig" ]; then
    echo "ERRO: não há backup do binário do pacote para a versão $ver." >&2
    echo "      Recupere com: sudo apt-get install --reinstall cosmic-comp" >&2
    return 2
  fi
  cp -a "$orig" "$ALVO.aurora-tmp" && mv -f "$ALVO.aurora-tmp" "$ALVO" && chmod 755 "$ALVO" \
    && echo "restaurado o cosmic-comp do pacote — o workspace vazio volta no próximo login"
}

case "${1:---ensure}" in
  --ensure|ensure) cmd_ensure ;;
  --build|build)   cmd_build ;;
  --restore|restore) cmd_restore ;;
  --status|status) cmd_status ;;
  --podar|podar)   cmd_podar "${2:-}" ;;
  # Os dois abaixo são internos: quem os chama é a unit transitória do
  # auto-build (--build-auto, como root) e o runuser que ela abre para compilar
  # como a usuária (--compile-only). Ficam fora do texto de uso de propósito.
  --build-auto)    cmd_build_auto ;;
  --compile-only)  compilar ;;
  *) echo "uso: $0 [--ensure|--build|--restore|--status|--podar [--seco]]" >&2; exit 2 ;;
esac
