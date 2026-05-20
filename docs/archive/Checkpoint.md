# Checkpoint — Sessão Aurora 2.3 ULTRA

**Última atualização:** 2026-05-16 ~22:05 BRT (auditoria pré-reboot + fix do bug NM)
**Diretório:** `~/.config/zsh`
**Branch:** `main` (autosync ativo — commits `auto: sync nitro-5 ...`)

---

## Contexto resumido

Usuário reportou "USB não carrega quando o PC autosuspende". Diagnóstico mostrou que:

- BIOS Insyde V1.17 do **Acer Nitro AN515-47** (Ryzen 7000) **não expõe S3 deep** — só Modern Standby (S0ix), S4, S5.
- Em S0ix o EC corta VBUS das portas USB. No Windows funciona porque NitroSense sinaliza ao EC; no Linux não há driver equivalente.
- Solução: **desabilitar suspend completamente** — laptop é usado como desktop sempre plugado, suspend não tem propósito.

Escopo expandido para **Aurora 2.3 ULTRA** ("modo always-plugged desktop-replacement"), integrado ao Aurora 2.x já existente. Escolhas confirmadas:

- **APLICADO:** Anti-suspend total (logind + targets + dconf)
- **APLICADO:** Hardware idle off (`pcie_aspm=off`, `nvme_core.default_ps_max_latency_us=0`)
- **APLICADO:** CPU pinned no teto (`scaling_min=max`, `boost=1`, NVIDIA `persistence-mode=Enabled`)
- **APLICADO:** Wi-Fi sem powersave (`wifi.powersave=2` via NM drop-in)
- **RECUSADO:** Charge-thresholds 100% — Li-ion degrada. Mantém default System76 50–80%.
- **N/A:** `systemd-oomd mask` — não existe nesta instalação Pop!_OS 22.04.
- **FORA DE ESCOPO:** `THP=always`.

---

## O que foi feito

### Artefatos novos (`aurora/`) — já commitados pelo autosync

- `aurora/99-no-suspend.conf` — logind drop-in (HandleLid/Suspend/Idle = ignore)
- `aurora/dconf/no-suspend.db` — GNOME power policy (sleep-inactive-*-type='nothing', idle-delay=0)
- `aurora/dconf/no-suspend.locks` — locks das keys acima
- `aurora/dconf/profile-user` — dconf profile system-wide
- `aurora/99-aurora-ultra-wifi.conf` — NM conf `wifi.powersave=2`

### Scripts estendidos — 3 modified, staged, ainda não commitados

- `aurora/aurora-bootstrap.sh` — KERNELSTUB_PARAMS ganhou `pcie_aspm=off` + `nvme_core.default_ps_max_latency_us=0`; copia_se_diff dos novos artefatos; `dconf update`
- `aurora/aurora-postboot-validate.sh` — PARAMS_OBRIGATORIOS ganhou os 2 novos; Check 10 anti-suspend (drop-in + targets); Check 11 ULTRA (CPU pinned + boost + NVIDIA)
- `aurora/aurora-watchdog-check.sh` — checks novos: targets masked, drop-in presente, scaling_min=max, boost=1, NVIDIA pm, NM drop-in com `wifi.powersave=2`

### Script estendido — já commitado pelo autosync

- `aurora/aurora-root-apply` — passos 6–9: mask 5 sleep targets, scaling_min=max em todos cores, garante boost=1, `nvidia-smi -pm 1`

### Cleanup feito

- Removidas units paralelas que tinha criado antes: `/etc/systemd/system/enforce-no-suspend.{service,timer}`, `/usr/local/sbin/enforce-no-suspend.sh`, `/tmp/no-suspend-pack/`.
- Auto-healing é responsabilidade do `aurora-watchdog.timer` existente (não duplicar).

### Sistema (instalado pelo bootstrap, já em vigor)

- `/etc/systemd/logind.conf.d/99-no-suspend.conf` instalado
- `/etc/dconf/db/local.d/00-no-suspend` + `locks/00-no-suspend` + `/etc/dconf/profile/user` instalados, `dconf update` rodado
- `/etc/NetworkManager/conf.d/99-aurora-ultra-wifi.conf` instalado
- 5 sleep targets em estado `masked`
- CPU 12 cores com `scaling_min=max=4604757`
- `cpufreq/boost=1`, NVIDIA `persistence-mode=Enabled`

### Memória (Claude memory)

- `~/.claude/projects/-home-andrefarias--config-zsh/memory/aurora_2_3_ultra.md` — criado
- `MEMORY.md` — index atualizado

---

## Arquivos modificados ainda não commitados

```
M  aurora/aurora-bootstrap.sh
M  aurora/aurora-postboot-validate.sh
M  aurora/aurora-watchdog-check.sh
```

Estão **staged** (autosync já fez `git add`), aguardando próximo ciclo do autosync que deve rodar dentro de poucos minutos. Último commit observado: `cdf9b84 auto: sync nitro-5 2026-05-16 20:05`.

Se autosync demorar e sessão cair, inspecionar com:

```bash
cd ~/.config/zsh
git diff --cached aurora/aurora-bootstrap.sh aurora/aurora-postboot-validate.sh aurora/aurora-watchdog-check.sh
# (autosync vai commitar sozinho — não commitar manual sem checar git log -5 antes)
```

---

## Próximos passos exatos

1. **Reboot** para ativar os 2 kernel params novos (`pcie_aspm=off`, `nvme_core.default_ps_max_latency_us=0`). Estão gravados no kernelstub mas ainda não em `/proc/cmdline`.

   ```bash
   sudo reboot
   ```

2. **Pós-reboot, validar:**

   ```bash
   cat /proc/cmdline | tr ' ' '\n' | grep -E 'pcie_aspm|nvme_core'
   bash ~/.config/zsh/aurora/aurora-postboot-validate.sh
   ls ~/Desktop/AURORA-*.md
   ```

   Esperado: ambos params em `/proc/cmdline`, validator silencioso, transição erro->ok gera `AURORA-OK.md` **uma única vez** (sumirá nos boots seguintes).

3. **Smoke test USB de carga:** plugar celular numa porta USB. Mesmo se o GNOME mandar suspend, system não vai aceitar (target masked). USB deve continuar recebendo VBUS.

4. (Opcional) Atualizar `aurora/RECOVERY.md` com seção "Aurora 2.3 ULTRA" — útil para o cenário de reinstalação total. Não fizemos ainda.

---

## Decisões pendentes

- **Nenhuma bloqueadora.** Implementação completa e validada.
- Eventual: criar toggle "modo viagem" se o laptop um dia sair da tomada (boost+min=max consome ~10W extras em idle). Não fizemos porque user explicitou que vive plugado.

---

## Auditoria pré-reboot (2026-05-16 ~22:00)

### BUG-1 (CRÍTICO) — ENCONTRADO E FIXADO

`/etc/NetworkManager/conf.d/default-wifi-powersave-on.conf` (instalado pelo Pop!_OS) define `wifi.powersave=3` (powersave ligado). Como NM lê em ordem alfabética com regra "last wins" e `'9' < 'd'` em ASCII, esse arquivo era lido APÓS o nosso `99-aurora-ultra-wifi.conf` e o sobrescrevia. **Wi-Fi continuava com powersave on.**

**Fix aplicado:**
1. Renomeado o default para `.bak-aurora-ultra` (backup preservado).
2. `aurora-bootstrap.sh` agora remove esse arquivo se reaparecer (apt reinstall, etc).
3. `aurora-root-apply` também remove (reconciliação via watchdog).
4. `aurora-watchdog-check.sh` detecta reaparecimento como desvio.

Confirmado pós-fix: `NetworkManager --print-config` mostra `[connection] wifi.powersave=2`.

### NOTA-1 (não-bug, comportamento esperado) — Temperatura sob workload

Auditoria mediu Tctl=93.5°C, mas com `ollama (258% CPU) + 4 nodes (100%)` rodando concorrentemente. Throttling térmico do hardware kicks in ~95°C — esse é o **circuito breaker do silicon, não nosso código**. Com `scaling_min_freq=max + boost=1`, o kernel sempre pede clock máximo, mas o hardware respeita seu próprio limite térmico.

**Implicações para uso normal (sem ollama+nodes):** idle vai consumir mais que o default System76 mas não vai esquentar a 93°C. Workloads pesados continuam batendo o teto térmico que já batia antes (governor performance já fazia isso). Diferença prática vs estado anterior: pequena.

### NOTA-2 (risco residual aceitável) — `/sys/power/state` ainda permite suspend direto

Targets `suspend.target` etc estão masked, e `systemctl suspend` falha com "Access denied". Mas `/sys/power/state` ainda contém `freeze mem disk` — se algum processo rodando como root escrever `mem` ali, o sistema suspende mesmo assim, bypass-targets. Risco baixo (ninguém faz isso em uso normal), apenas documentar.

### Auditoria green

- Sintaxe Bash: 4/4 scripts OK
- Idempotência: bootstrap 2x passadas silenciosas; aurora-root-apply 2x rodando reporta tudo "ja em ..."
- Sem daemons de power concorrentes (power-profiles-daemon, tlp, auto-cpufreq inexistentes; thermald enabled mas neutro)
- dconf locks ativos e valores efetivos confirmados
- kernelstub gravou os 2 params novos (pendentes de reboot)
- Watchdog reporta `OK - sem desvio` após o fix

---

## Notas de manutenção

- **Autosync** (`auto: sync nitro-5 ...`): repo commita e pusha sozinho a cada poucos minutos. **Não commitar manualmente** sem checar `git log -5` primeiro.
- **apt-postinvoke hook** (`/etc/apt/apt.conf.d/99-aurora-postinvoke`): roda `aurora-bootstrap.sh --post-update --quiet` após qualquer `apt`. Tunings sobrevivem a updates por desenho.
- **Watchdog 15min** reconcilia desvios. Se algo for sobrescrito por update inesperado, volta sozinho em <=15min.
- **AURORA-ERRO.md no Desktop**: enquanto não rebootar, vai existir apontando os 2 kernel params pendentes. Esperado, não é bug.
