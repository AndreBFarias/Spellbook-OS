#!/bin/bash
#
# Proposito: Parte do Ritual da Aurora que roda como usuario (sem sudo).
#            Configura GPU Nvidia no modo performance via nvidia-settings.
#            A parte com sudo (earlyoom, system76-power) roda via systemd:
#            ritual-aurora-root.service
#

# Esperar display estar pronto
sleep 3

if command -v nvidia-settings &> /dev/null; then
    nvidia-settings -a '[gpu:0]/GpuPowerMizerMode=1' > /dev/null 2>&1
fi

# "A excelencia não e um ato, mas um habito." -- Aristoteles
