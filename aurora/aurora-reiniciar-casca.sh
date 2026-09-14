#!/usr/bin/env bash
# aurora-reiniciar-casca.sh — Alt+F2: recuperação da interface em TRÊS NÍVEIS,
# do inofensivo ao destrutivo, escalando por apertos repetidos. (leva-03)
#
#   1o aperto  -> reinicia a CASCA (painel, dock, applets, papel de parede,
#                 notificações, OSD, launcher, overview). ~0,9s, NENHUMA janela
#                 fecha. Resolve applet travado, ícone em cache, config nova.
#   2o aperto  -> CosmicSession.Restart. Reinicia a sessão pelo caminho oficial.
#                 FECHA AS JANELAS. Para quando a casca não bastou.
#   3o aperto  -> aurora-gpu-revive: MODE2 reset no amdgpu. Último recurso, para
#                 GPU genuinamente pendurada.
#
# POR QUE ISTO SUBSTITUI O Ctrl+Alt+0
#   O botão de pânico vivia no xbindkeys, e no X11 isso fazia sentido: o
#   xbindkeys fala com o X SERVER, um processo separado do gnome-shell, então a
#   tecla chegava mesmo com o shell travado. Sob Wayland essa separação não
#   existe — o cosmic-comp É o servidor e é ele quem registra os atalhos. Um
#   atalho só é entregue enquanto o compositor está vivo, e é por isso que ter
#   DUAS teclas não dava nenhuma garantia a mais: as duas morrem juntas.
#
#   Unificar troca duas teclas com o mesmo alcance por uma escalada explícita,
#   e tira o reset de GPU do primeiro toque — que foi o que derrubou a sessão do
#   dono três vezes em 14/09 (19:58:38, 20:00:43, 20:02:52), com a GPU saudável.
#
# ONDE A TECLA NÃO ALCANÇA, E QUAL É A SAÍDA
#   Compositor PENDURADO: nenhum atalho chega, nem este. A saída é Ctrl+Alt+F3,
#   que o kernel/logind trata sem passar pelo compositor, e de lá:
#       systemctl --user restart cosmic-session     (ou)
#       sudo /usr/local/sbin/aurora-gpu-revive
#   O caso que a escalada cobre é o INTERMEDIÁRIO — compositor vivo, render
#   quebrado — que é o que o journal de 14/09 mostra:
#       cosmic-comp: Failed to render texture ... import for wrong devices DrmNode
#
# POR QUE A JANELA É DE 30s, E NÃO 5s
#   O nível 2 reinicia a sessão e leva ~8s até o compositor voltar a aceitar
#   tecla. Com janela curta o nível 3 seria inalcançável na prática: o aperto
#   seguinte cairia fora da janela e voltaria ao nível 1. 30s cobre o restart e
#   ainda é curto o bastante para não acumular apertos avulsos do dia.
set -uo pipefail

JANELA=30
STATE="${XDG_RUNTIME_DIR:-/tmp}/aurora-casca-apertos"
# AURORA_CASCA_DRY=1 -> anuncia o nivel e sai, sem executar. Existe porque os
# niveis 2 e 3 não tem como ser testados ao vivo sem derrubar a sessão de quem
# testa; a LOGICA DE ESCALADA, que e a parte que erra, se verifica aqui.
DRY="${AURORA_CASCA_DRY:-0}"
log() { printf '[casca] %s\n' "$*"; }
aviso() { command -v notify-send >/dev/null 2>&1 && notify-send -a "Aurora" "$@" 2>/dev/null || true; }

agora=$(date +%s); ultimo=0; n=0
[ -f "$STATE" ] && read -r ultimo n < "$STATE" 2>/dev/null
# Sanear ANTES da aritmética: `$(( agora - ultimo ))` com último="lixo" faz o
# bash tratar a palavra como NOME DE VARIÁVEL, e sob `set -u` isso aborta o
# script — ou seja, um arquivo de estado corrompido tirava do ar a tecla de
# recuperação, justamente quando ela é necessária. Medido em 14/09.
case "${ultimo:-}" in (*[!0-9]*|"") ultimo=0 ;; esac
case "${n:-}"      in (*[!0-9]*|"") n=0 ;; esac
if [ $(( agora - ultimo )) -lt "$JANELA" ]; then n=$(( n + 1 )); else n=1; fi
printf '%s %s\n' "$agora" "$n" > "$STATE" 2>/dev/null

# --------------------------------------------------------------------------
# NÍVEL 3 — reset da GPU. Só com a GPU realmente pendurada.
# --------------------------------------------------------------------------
if [ "$n" -ge 3 ]; then
  log "3o aperto em ${JANELA}s: MODE2 reset no amdgpu (último recurso)"
  [ "$DRY" = "1" ] && { log "[dry] pararia aqui: exec aurora-gpu-revive-trigger"; exit 0; }
  aviso -i dialog-warning -u critical -t 6000 "Reset da GPU" \
        "Terceiro aperto: resetando a placa. A tela deve piscar."
  T="$HOME/.config/zsh/aurora/aurora-gpu-revive-trigger"
  if [ -x "$T" ]; then exec "$T"; fi
  log "ERRO: $T ausente ou sem permissao de execução"
  exit 1
fi

# --------------------------------------------------------------------------
# NÍVEL 2 — reinicia a sessão pelo caminho oficial do COSMIC.
# Deliberadamente NÃO é o restart do display-manager (que mata o greeter junto)
# nem o MODE2 reset (que derruba por baixo do compositor, sem ele saber).
# --------------------------------------------------------------------------
if [ "$n" -eq 2 ]; then
  log "2o aperto em ${JANELA}s: reiniciando a sessão COSMIC (as janelas fecham)"
  [ "$DRY" = "1" ] && { log "[dry] pararia aqui: CosmicSession.Restart"; exit 0; }
  aviso -i dialog-warning -u critical -t 5000 "Reiniciando a sessão" \
        "As janelas abertas vão fechar. Mais um aperto reseta a GPU."
  sleep 1   # dá tempo da notificação aparecer antes da sessão cair
  if busctl --user call com.system76.CosmicSession /com/system76/CosmicSession \
       com.system76.CosmicSession Restart >/dev/null 2>&1; then
    log "OK: CosmicSession.Restart aceito"
    exit 0
  fi
  log "AVISO: CosmicSession.Restart falhou — caindo para restart do cosmic-session"
  systemctl --user restart cosmic-session.service 2>/dev/null && exit 0
  log "ERRO: não foi possivel reiniciar a sessão"
  exit 1
fi

# --------------------------------------------------------------------------
# NÍVEL 1 — a casca. Nenhuma janela fecha. É o caso de 99% dos dias.
#
# `pkill -x` com nome TRUNCADO de propósito: o comm do kernel tem 15 caracteres,
# então `cosmic-notifications` aparece como `cosmic-notifica` e um pkill com o
# nome completo NÃO casa nada — falha silenciosa. Conferir com `ps -eo comm`
# antes de "corrigir" esta lista.
#
# O cosmic-comp fica fora: sob Wayland ele É o servidor, e matá-lo fecha toda
# janela aberta. Os sete abaixo são supervisionados pelo cosmic-session —
# medido um a um em 14/09, matando e conferindo o PID novo.
# --------------------------------------------------------------------------
EXTRAS=(cosmic-bg cosmic-osd cosmic-notifica cosmic-launcher
        cosmic-workspac cosmic-app-libr)

[ "$DRY" = "1" ] && { log "[dry] 1o aperto: reiniciaria a casca (${#EXTRAS[@]} extras + painel)"; exit 0; }

declare -A ANTES=()
for p in "${EXTRAS[@]}"; do ANTES[$p]="$(pgrep -x "$p" | head -1)"; done
for p in "${EXTRAS[@]}"; do [ -n "${ANTES[$p]}" ] && pkill -x "$p" 2>/dev/null; done

# O painel vai pelo script portado da meowsystem (hash de3416ca…, idêntico nas
# duas máquinas): ele tem a espera pelo PID novo, a captura de ambiente de um
# irmão e o fallback de subir na mão. Nada disso vale a pena duplicar aqui.
if [ -x /usr/local/bin/aurora-reiniciar-painel.sh ]; then
  /usr/local/bin/aurora-reiniciar-painel.sh 2>&1 | sed 's/^/[casca] /'
else
  log "AVISO: aurora-reiniciar-painel.sh ausente — so os extras reiniciaram"
fi

faltaram=()
for p in "${EXTRAS[@]}"; do
  [ -z "${ANTES[$p]}" ] && continue
  novo=""
  for _ in $(seq 1 50); do
    novo="$(pgrep -x "$p" | head -1)"
    [ -n "$novo" ] && [ "$novo" != "${ANTES[$p]}" ] && break
    novo=""; sleep 0.1
  done
  [ -z "$novo" ] && faltaram+=("$p")
done

if [ ${#faltaram[@]} -gt 0 ]; then
  log "AVISO: não voltaram em 5s: ${faltaram[*]}"
  aviso -i dialog-warning -t 4000 "Casca reiniciada com pendência" "Não voltaram: ${faltaram[*]}"
  exit 1
fi

log "OK: casca reiniciada (${#EXTRAS[@]} extras + painel); nenhuma janela fechada"
aviso -i view-refresh -t 3000 "Interface reiniciada" \
      "Nenhuma janela fechada. Outro aperto em ${JANELA}s reinicia a sessão."
exit 0
