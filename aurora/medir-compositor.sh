#!/usr/bin/env bash
# medir-compositor.sh — a mesma medida, antes e depois, para a comparação valer.
#
# POR QUE ISTO EXISTE
#   Em 17/09/2026 a sessão COSMIC caiu e a investigação levou a duas mudanças
#   independentes: a variável COSMIC_RENDER_DEVICE (qual GPU conduz o
#   compositor) e um patch no cosmic-comp (o crash do blur). Sem uma medida
#   igual dos dois lados, "melhorou" vira impressão — e impressão não decide
#   se vale manter uma mudança que custa VRAM de um trabalho com LLM local.
#
#   Toda métrica aqui é acumulada ou contada desde o boot, NUNCA instantânea:
#   %CPU de um `top` sobe e desce com o que mais estiver rodando na hora, e foi
#   exatamente assim que a primeira medição desta máquina se contaminou (dois
#   agentes varrendo o disco durante a amostra).
#
# COMO USAR
#   ~/.config/zsh/aurora/medir-compositor.sh                    # imprime na tela
#   ~/.config/zsh/aurora/medir-compositor.sh > compositor-DEPOIS.txt
#
#   (veio do Migração-OS/scripts em 23/10/2026, P94 do MeowSystem: é a medida
#   do compositor por GPU DESTE PC, e mora ao lado da guarda da GPU, a
#   aurora-gpu-compositor. Só lê; não mexe nela nem em nada do sistema.)
#
#   Compare sempre sessões de duração parecida: a CPU acumulada do compositor
#   cresce com o tempo de vida, então 20% em 30 min não se compara com 20% em
#   3 h. O script imprime o tempo de vida junto, para isso ficar visível.
#
# NÃO PRECISA DE SUDO. Só lê /proc, /sys e o journal do próprio usuário.

set -uo pipefail

printf '===== medição do compositor — %s =====\n\n' "$(date '+%F %T %Z')"

# --- 1. Quem é o compositor, e há quanto tempo vive -------------------------
pid=$(pgrep -x cosmic-comp | head -1)
if [ -z "$pid" ]; then
    echo "cosmic-comp não está rodando. Nada a medir."
    exit 1
fi

vida=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ')
tick=$(getconf CLK_TCK)
read -r utime stime < <(awk '{print $14, $15}' "/proc/$pid/stat")
cpu_s=$(awk -v u="$utime" -v s="$stime" -v t="$tick" 'BEGIN{printf "%.2f", (u+s)/t}')
pct=$(awk -v c="$cpu_s" -v v="$vida" 'BEGIN{ if (v>0) printf "%.2f", c/v*100; else print "0" }')

echo "-- compositor --"
echo "   pid            : $pid"
echo "   vida           : ${vida}s"
echo "   CPU acumulada  : ${cpu_s}s"
echo "   = % de um core : ${pct}%          <- a métrica principal"
echo

# --- 2. Qual GPU ele elegeu como primária -----------------------------------
# O cosmic-comp abre TODOS os nós DRM; o primário é aquele em que ele mantém
# mais descritores de render abertos. `determine_primary_gpu` (kms/mod.rs:241)
# decide por COSMIC_RENDER_DEVICE e, sem ela, pela GPU que tiver o painel eDP.
echo "-- GPU --"
echo "   COSMIC_RENDER_DEVICE: $(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | sed -n 's/^COSMIC_RENDER_DEVICE=//p' | head -1 || true)${_:+}"
[ -z "$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep -c '^COSMIC_RENDER_DEVICE=' | grep -v '^0$')" ] \
    && echo "   (a variável NÃO está no ambiente do compositor)"
for n in renderD128 renderD129; do
    q=$(ls -l "/proc/$pid/fd" 2>/dev/null | grep -c "$n" || true)
    drv=$(basename "$(readlink -f "/sys/class/drm/$n/device/driver" 2>/dev/null)" 2>/dev/null)
    echo "   fds em $n ($drv): $q"
done
echo "   system76-power  : $(system76-power graphics 2>/dev/null | head -1)"
echo

# --- 3. Os erros que este trabalho quer zerar --------------------------------
# Conta ocorrências no journal sem deixar o `grep -c` sujar a saída.
#
# [2026-09-17] O jeito ingênuo — `$(... | grep -c X || echo 0)` — tem um defeito
# que só aparece quando dá tudo certo: `grep -c` sai com rc=1 quando encontra
# ZERO ocorrências, o `|| echo 0` dispara, e o resultado vira DUAS linhas ("0"
# do grep e "0" do echo). O printf então imprime a primeira e joga a segunda na
# linha de baixo, e o relatório sai quebrado justamente no caso bom.
_contar() {
    local n
    n=$(eval "$1" 2>/dev/null | grep -c "$2")
    printf '%s' "${n:-0}"
}

echo "-- erros no journal deste boot --"
printf '   import for wrong devices    : %s\n' \
    "$(_contar 'journalctl --user -b 0' 'import for wrong devices')"
printf '   Duplicated FramebufferEffect: %s   (o smithay só avisa UMA vez por processo)\n' \
    "$(_contar 'journalctl --user -b 0' 'Duplicated FramebufferEffect')"
printf '   quedas do cosmic-comp       : %s\n' \
    "$(_contar 'journalctl --user -b 0' 'cosmic-comp.*exited\|cosmic-comp.*signal')"
printf '   page faults do amdgpu       : %s\n' \
    "$(_contar 'journalctl -b 0' 'amdgpu.*page fault')"

# O boot pode conter VÁRIAS sessões (logout/login não troca de boot), e os erros
# da sessão anterior continuam no journal. Estas contagens são só do compositor
# que está de pé AGORA — é o número honesto para comparar com o "antes".
if [ -n "${pid:-}" ]; then
    echo "   -- só do compositor atual (pid $pid) --"
    printf '   import for wrong devices    : %s\n' \
        "$(_contar "journalctl --user -b 0 _PID=$pid" 'import for wrong devices')"
    printf '   Duplicated FramebufferEffect: %s\n' \
        "$(_contar "journalctl --user -b 0 _PID=$pid" 'Duplicated FramebufferEffect')"
    printf '   Failed to parse device entry: %s   (se >0, COSMIC_RENDER_DEVICE foi recusada)\n' \
        "$(_contar "journalctl --user -b 0 _PID=$pid" 'Failed to parse device entry')"
fi
echo

# --- 4. VRAM: o recurso disputado entre o desktop e os modelos locais --------
echo "-- VRAM da RTX 3050 (4 GiB, disputada com o Ollama) --"
nvidia-smi --query-gpu=memory.total,memory.used,memory.free --format=csv,noheader 2>/dev/null \
    | sed 's/^/   total,usada,livre: /'
echo "   processos na dGPU:"
nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader 2>/dev/null \
    | sed 's/^/     /' || true
# O compositor entra como cliente gráfico, não como compute — sai noutra lista.
nvidia-smi 2>/dev/null | grep -E '^\|\s+[0-9]+\s+N/A\s+N/A' | sed 's/^/     /' || true
echo

# --- 5. Pressão de I/O, que é o que não mente --------------------------------
echo "-- PSI (pressão desde o boot) --"
sed 's/^/   io  /'     /proc/pressure/io
sed 's/^/   cpu /'     /proc/pressure/cpu
sed 's/^/   mem /'     /proc/pressure/memory
echo
echo "   uptime: $(cut -d. -f1 /proc/uptime)s"
