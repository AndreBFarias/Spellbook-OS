#!/usr/bin/env bash
# Corrige a origem dos travamentos de tela no Pop!_OS COSMIC deste Nitro AN515-47.
#
# Sintoma: ao acordar de uma suspensão, o cosmic-comp falha o page flip na RTX 3050
#     Page flip commit failed on device /dev/dri/card1 (Invalid argument, os error 22)
# e logo em seguida derruba TODOS os clientes Wayland com
#     Protocol error 1 on object wp_linux_drm_syncobj_manager_v1
# matando terminais e qualquer sessão em andamento. Visto em 2026-09-11 e 2026-09-14.
#
# Causa: o notebook é muxless (não existe /sys/kernel/debug/vgaswitcheroo). O painel
# interno (eDP-1) está cabeado na Radeon 680M e o HDMI externo na RTX 3050. Toda
# suspensão obriga a NVIDIA a salvar e restaurar as superfícies de scanout, e o driver
# 580.173.02 falha ao revalidá-las no resume:
#     nvidia-modeset: Invalid request parameters, planePitch or rmObjectSizeInBytes
#
# Correção, nos dois vetores comprovados no journal:
#   1. idle  -> cosmic-idle deixa de suspender sozinho (era 30 min na tomada, 15 na bateria)
#   2. tampa -> a dGPU não cai mais em D3cold, então o resume não precisa reconstruir a GPU
#
# NÃO mexe no logind (IdleAction já é "ignore") nem desabilita a suspensão por tampa:
# fechar a tampa continua suspendendo, só que agora sobrevive ao resume.
#
# Idempotente: rodar N vezes converge para o mesmo estado e só toca no que está fora dele.
#
# Uso:
#   ./corrigir-suspend-nvidia.sh           aplica
#   ./corrigir-suspend-nvidia.sh --check   só relata o estado, não altera nada
#   ./corrigir-suspend-nvidia.sh --revert  desfaz e devolve os valores originais
set -euo pipefail

IDLE=$HOME/.config/cosmic/com.system76.CosmicIdle/v1
ESTADO=$HOME/.local/state/corrigir-suspend-nvidia
MODPROBE=/etc/modprobe.d/99-nvidia-no-d3cold.conf
CONTEUDO='# Gerado por corrigir-suspend-nvidia.sh
# Impede que a RTX 3050 entre em D3cold. Ela dirige o HDMI externo, e reconstruir
# a GPU no resume é o que quebra o page flip do cosmic-comp.
options nvidia NVreg_DynamicPowerManagement=0'

modo=${1:-aplicar}
mudou=0
mudou_modprobe=0

# Os arquivos do cosmic-config são RON puro, sem newline final. "None" desliga o timer.
ler()    { cat "$IDLE/$1" 2>/dev/null || echo AUSENTE; }
gravar() { printf '%s' "$2" > "$IDLE/$1"; }

case $modo in
  --check)
    echo "== cosmic-idle =="
    for k in suspend_on_ac_time suspend_on_battery_time; do
        v=$(ler "$k")
        [[ $v == None ]] && echo "  OK       $k = None" || echo "  PENDENTE $k = $v"
    done
    echo "== NVIDIA D3cold =="
    if [[ -f $MODPROBE ]] && diff -q <(printf '%s\n' "$CONTEUDO") "$MODPROBE" >/dev/null 2>&1; then
        echo "  OK       $MODPROBE aplicado"
    else
        echo "  PENDENTE $MODPROBE ausente ou divergente"
    fi
    echo "  em uso:  DynamicPowerManagement = $(sed -n 's/^DynamicPowerManagement: //p' /proc/driver/nvidia/params)"
    exit 0
    ;;

  --revert)
    if [[ -f $ESTADO/suspend_on_ac_time ]]; then
        for k in suspend_on_ac_time suspend_on_battery_time; do
            gravar "$k" "$(cat "$ESTADO/$k")"
            echo "restaurado  $k = $(ler "$k")"
        done
    else
        echo "sem backup dos timers; deixando o cosmic-idle como está"
    fi
    if [[ -f $MODPROBE ]]; then
        sudo rm -v "$MODPROBE"
        mudou_modprobe=1
    fi
    ;;

  aplicar)
    mkdir -p "$ESTADO"
    for k in suspend_on_ac_time suspend_on_battery_time; do
        atual=$(ler "$k")
        if [[ $atual == None ]]; then
            echo "já ok       $k = None"
            continue
        fi
        # guarda o original uma única vez, para o --revert não perder o valor de fábrica
        [[ -f $ESTADO/$k ]] || printf '%s' "$atual" > "$ESTADO/$k"
        gravar "$k" None
        echo "alterado    $k: $atual -> None"
        mudou=1
    done

    if [[ -f $MODPROBE ]] && diff -q <(printf '%s\n' "$CONTEUDO") "$MODPROBE" >/dev/null 2>&1; then
        echo "já ok       $MODPROBE"
    else
        printf '%s\n' "$CONTEUDO" | sudo tee "$MODPROBE" >/dev/null
        echo "escrito     $MODPROBE"
        mudou_modprobe=1
    fi
    ;;

  *) echo "uso: $0 [--check|--revert]" >&2; exit 2 ;;
esac

if [[ $mudou_modprobe -eq 1 ]]; then
    echo
    echo "Regerando o initramfs (demora ~30s)..."
    sudo update-initramfs -u
fi

echo
if [[ $mudou -eq 0 && $mudou_modprobe -eq 0 ]]; then
    echo "Nada a fazer: o sistema já estava no estado desejado."
else
    echo "Reinicie para aplicar. O parâmetro do módulo nvidia só entra em vigor no boot."
    echo "Depois do boot, confirme com: $0 --check"
fi
