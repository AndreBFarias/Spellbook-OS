#!/usr/bin/env bash
# aurora-reiniciar-casca.sh — Alt+F2: reinicia a CASCA inteira do COSMIC
# (painel, dock, applets, papel de parede, notificações, OSD, launcher, overview
# e biblioteca de apps) sem fechar uma única janela. (leva-03, 2026-09-14)
#
# POR QUE ESTE ARQUIVO EXISTE, EM VEZ DE UM PATCH NO OUTRO
#   O aurora-reiniciar-painel.sh veio da meowsystem por scp e tem hash idêntico
#   nas duas máquinas (de3416ca…). Isso é o que permite dizer "é o mesmo script
#   dos dois lados" quando um comportamento diverge — foi assim que se provou, em
#   14/09, que o Alt+F2 fazia a MESMA coisa lá e aqui, e que a diferença era de
#   percepção, não de código. Editá-lo aqui queimaria essa referência. Este script
#   CHAMA aquele e só acrescenta o que é decisão local.
#
# O QUE MORRE E O QUE SOBREVIVE
#   Morre e volta: cosmic-panel (topbar + dock + todos os applets, que são filhos
#   dele), cosmic-bg, cosmic-notifications, cosmic-osd, cosmic-launcher,
#   cosmic-workspaces, cosmic-app-library.
#   Sobrevive: o cosmic-comp e, com ele, TODAS as janelas abertas.
#
#   O cosmic-comp fica fora de propósito, e não por excesso de zelo: sob Wayland
#   ele É o servidor — as superfícies das janelas vivem na conexão com ele, e
#   matá-lo fecha todo aplicativo aberto. O restart de sessão de verdade existe
#   (método D-Bus `Restart` em com.system76.CosmicSession) e continua fora daqui:
#   é poder demais para uma tecla em que se encosta sem querer.
#
# POR QUE `pkill -x` COM NOMES TRUNCADOS
#   O `comm` do kernel tem 15 caracteres. `cosmic-notifications` (20) aparece como
#   `cosmic-notifica`, e um `pkill -x cosmic-notifications` NÃO casa nada — falha
#   silenciosa, que é o pior modo de falha possível aqui. Medido em 14/09; por isso
#   a lista abaixo usa o nome TRUNCADO de propósito. Não "corrija" para o nome
#   completo sem antes conferir com `ps -eo comm`.
#
#   `-x` (nome exato) também evita pegar junto os `cosmic-panel-button` e os
#   `cosmic-applet-*`, que morrem de qualquer jeito por serem filhos do painel.
#
# QUEM RESSUSCITA
#   O cosmic-session supervisiona todos os sete. Conferido um a um em 14/09,
#   matando e medindo o PID novo:
#       cosmic-bg        3614 -> 12167     cosmic-workspac  3609 -> 13512
#       cosmic-osd       3613 -> 12438     cosmic-app-libr  3599 -> 13743
#       cosmic-notifica  3596 -> 12588     cosmic-panel     (via o outro script)
#       cosmic-launcher  3607 -> 13418
#   Nenhum precisa ser subido na mão. Se algum dia um deixar de voltar, este
#   script AVISA e segue — nunca deixa a casca pela metade em silêncio.
set -uo pipefail

log() { printf '[casca] %s\n' "$*"; }

# Nomes como o kernel os expõe em /proc/<pid>/comm (15 chars). Ver cabeçalho.
EXTRAS=(cosmic-bg cosmic-osd cosmic-notifica cosmic-launcher
        cosmic-workspac cosmic-app-libr)

declare -A ANTES=()
for p in "${EXTRAS[@]}"; do
  ANTES[$p]="$(pgrep -x "$p" | head -1)"
done

# Derruba os extras primeiro; o supervisor já começa a devolvê-los enquanto o
# painel (mais lento, tem espera e validação própria) ainda está reiniciando.
for p in "${EXTRAS[@]}"; do
  [ -n "${ANTES[$p]}" ] && pkill -x "$p" 2>/dev/null
done

# O painel vai pelo script portado: ele tem a espera pelo PID novo, a captura de
# ambiente do irmão e o fallback de subir na mão. Nada disso vale a pena duplicar.
if [ -x /usr/local/bin/aurora-reiniciar-painel.sh ]; then
  /usr/local/bin/aurora-reiniciar-painel.sh 2>&1 | sed 's/^/[casca] /'
else
  log "AVISO: aurora-reiniciar-painel.sh ausente — só os extras foram reiniciados"
fi

# Confere quem voltou. Teto de 5s, no mesmo espírito do script do painel.
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
  command -v notify-send >/dev/null 2>&1 && \
    notify-send -a "Aurora" -i dialog-warning -t 4000 \
      "Casca reiniciada com pendência" "Não voltaram: ${faltaram[*]}" 2>/dev/null
  exit 1
fi

log "OK: casca reiniciada (${#EXTRAS[@]} extras + painel); nenhuma janela fechada"
exit 0
