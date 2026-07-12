# Aurora 2.9 — Térmico inteligente (fan sempre agressiva + auto-switcher de CPU)

**Data:** 2026-07-11 · **Host:** nitro-5 (Acer Nitro AN515-47, Ryzen 5 7535HS, Radeon 660M + RTX 3050, BIOS V1.17)

## Contexto / problema

O Nitro ventila mal: sob carga total de 12 cores o **Tctl vai a 97°C em ~3 segundos** e throttla na hora, porque o APU (STAPM stock 71.5W) despeja calor mais rápido do que o dissipador + a curva reativa do EC conseguem tirar. Objetivo do dono: **fan SEMPRE no perfil agressivo pra prevenir calor** (não liga para ruído — "real mesmo") + **CPU inteligente** (balanceada no idle, escala só sob carga real, nada de trabalho burro). Tudo idempotente, no `install.sh` + self-heal, por default.

## Descobertas da investigação (medidas, não presumidas)

- `platform_profile=performance` é **rejeitado pelo EC** (readback fica em `balanced-performance`); e **não há canal PWM** em nenhum hwmon → o controle de fan nativo é só a `platform_profile`, e o EC rampa por temperatura, reativo e lento (daí o 97°C-em-3s).
- **Secure Boot OFF** → módulos (`ec_sys`, NBFC) carregam a quente, sem reboot.
- **ryzenadj**: Curve Optimizer (`--set-coall`) é **rejeitado pelo SMU** (`set_coall is rejected by SMU`) → undervolt por software impossível. MAS `--tctl-temp` e limites PPT (STAPM/fast/slow) **funcionam** via /dev/mem (provado: tctl 100→95→100, STAPM 71.5→60).
- Limites stock capturados: STAPM 71.5W · PPT 80/70W · tctl 100°C · TDC 65A · EDC 140A.
- **NBFC-Linux** tem config stock pro AN515-47 exato (autor Josesk Volpe), mas com curva preguiçosa (5%@70°C, 100% só @90°C). Em modo manual empurra a fan a **7692 RPM** (vs ~5555 do EC auto) — mais frio, comprovado.
- `system76-power` é dono do D-Bus `net.hadess.PowerProfiles` → o slider de Energia do GNOME reprograma governor/EPP por baixo da Aurora.

## Arquitetura (4 componentes ortogonais)

**① NBFC-Linux — fan sempre agressiva.** Config própria `Acer Nitro AN515-47 Aurora` (piso 40%, 100% aos 78°C, crítico 88°C) assume o EC. `nbfc_service.service` enabled+active. Resolve o lag: rampa **antes** do spike, não depois dos 90°C.

**② ryzenadj — levers de potência.** PPT dinâmico + cap térmico `tctl-temp`. CO indisponível (SMU), mas PPT/tctl seguram o calor no lugar do undervolt.

**③ aurora-switcher — a CPU inteligente.** `aurora-switcher.timer` (oneshot, 10s, `flock`, crash-safe). Governor SEMPRE `powersave` (sob `performance` o amd-pstate TRAVA o EPP). Posturas decididas por **carga** (busy% via delta de `/proc/stat`, não loadavg), com histerese anti-flap:
- **BASE** (idle): EPP `balance_performance`, PPT 45W.
- **PERF** (busy ≥ 70% por ~20s): EPP `performance`, PPT 68W.
- **Teto térmico**: acima de 85°C degrada o PPT em passos; `tctl-temp=90` é o cap do AMD → banda-alvo **~85-90°C**.
- Escalada = **SÓ carga**. Temperatura NÃO escala (a fan já cuida do calor); temp só REDUZ o PPT — assim "quente mas ocioso" não gasta potência à toa.
- Fonte-de-verdade em `/run/aurora/target` (lido por `aurora-root-apply` e watchdog → **sem guerra de escrita**).
- CSV de tuning em `/var/log/aurora-switcher.log` (uptime,postura,busy%,tctl,ppt,transição).

**④ Higiene.** `thermald` mascarado (no-op em AMD), timers de 30s de-alinhados (`RandomizedDelaySec`), `vm.page-cluster=0` persistido.

## O que mudou

| Item | Antes | Agora (2.9) | Vale quando |
|---|---|---|---|
| Fan | curva preguiçosa do EC (100% só @90°C, teto ~5555 RPM) | **NBFC agressiva** (100% @78°C, teto 7692 RPM) | imediato |
| Postura de CPU | estática (cool/perf manual, sticky) | **auto-switcher** dinâmico por carga | imediato |
| EPP sob carga | fixo | **dinâmico** (balance_performance ↔ performance) | imediato |
| Potência | STAPM stock 71.5W (cozinha) | **ryzenadj** 45W base / 68W perf, tctl-cap 90°C | imediato |
| governor | performance / powersave (cool) | **powersave fixo** no modo auto | imediato |
| thermald | enabled (no-op) | **masked** | imediato |
| `vm.page-cluster` | só via pop-zram-config (volátil) | **persistido no 99-aurora.conf** | imediato |
| `loglevel` | `0` (cega throttle) | **`3`** | após reboot |
| Guerra watchdog×switcher | — | **eliminada** (root-apply lê /run/aurora/target) | imediato |

## Arquivos (fonte versionada em `~/.config/zsh/aurora/`)

**Novos:**
- `nbfc/Acer Nitro AN515-47 Aurora.json` — curva de fan agressiva.
- `aurora-thermal-apply.sh` — applier idempotente: build-if-missing de ryzenadj/NBFC (do source), deploy da curva, `ec_sys` (write_support persistente), seleção da config, enable do nbfc_service, mask do thermald, install do switcher+units. Chamado pelo bootstrap (§6g, **default**) e pelo self-heal.
- `aurora-switcher` + `units/aurora-switcher.{service,timer}` — o auto-switcher.

**Editados:**
- `aurora-root-apply` — lê `/run/aurora/target` e adota o EPP do switcher (fim da guerra).
- `aurora-watchdog-check.sh` — ressuscita `nbfc_service`/`aurora-switcher.timer` se caírem.
- `aurora-bootstrap.sh` — §1 migra `loglevel` 0→3; §6g chama o `aurora-thermal-apply.sh`.
- `functions/aurora-self-heal.zsh` — checks de ryzenadj/nbfc/switcher/thermald (fix = thermal-apply).
- `functions/termico.zsh` — `temp`/`cool`/`perf` refletem o switcher + NBFC + ryzenadj.
- `99-aurora.conf` — `+vm.page-cluster=0`.
- `units/amdgpu-dmcub-watchdog.timer` — `+RandomizedDelaySec=8s`.

## Comandos (zsh)

- `temp` — readout: modo/postura do switcher, governor/EPP, temps (CPU/chassi/iGPU/dGPU/NVMe), fans, NBFC, ryzenadj PPT/tctl.
- `cool` — modo **AUTO** dinâmico (switcher on; cria `/etc/aurora/allow-powersave`). **É o default recomendado.**
- `perf` — modo estático (switcher off, governor performance pinado; fan segue agressiva).
- `travou` — fallback do Ctrl+Alt+0 (display AMD travado).

## Calibração (knobs no topo do `aurora-switcher`)

`BUSY_UP/DOWN` (70/40%) · `N_UP/N_DOWN` (2/6 amostras ≈ 20s/60s) · `MIN_HOLD` (30s) · `CAP_TEMP` (85°C, degrade do PPT) · `TCTL_CAP` (90°C, throttle do AMD) · `PPT_BASE/PPT_PERF` (45/68W). **Mais quente/rápido:** subir CAP_TEMP/TCTL_CAP e PPT_PERF. **Mais frio:** baixar. Após editar: `sudo install -m0755 aurora/aurora-switcher /usr/local/sbin/` (ou rodar o bootstrap).

## Validação (medida 2026-07-11)

- **Idle**: 59°C, posture BASE, fan no talo (7692). Eficiente e frio.
- **Carga 12-core full**: banda **90-95°C capada e estável** (vs stock **97°C runaway + throttle caótico**). Escala/desescala sozinho.
- **Self-heal**: derrubar `nbfc_service` → detectado (`fan agressiva anti-calor caiu`) + ressuscitado automaticamente.
- **Install path**: `aurora-bootstrap.sh --post-update` monta o stack inteiro idempotente; `install.sh:958-974` já o chama por default.
- Verdade física: sob stress sintético máximo o chassi é **heat-limited** (cooler ~45W vs APU 60-71W); o ganho não é o pico e sim **fan no talo + controle + idle eficiente**. Cargas reais ficam mais frescas.

## Reboot-batch (aplicar no próximo reboot do dono)

- `loglevel=0→3` (já staged no kernelstub). **Só isso** — todo o resto é a quente. Reboot valida boot limpo.

## Deferido / decisões

- **Undervolt real**: só via BIOS (Smokeless_UMAF), pois o SMU rejeita o Curve Optimizer por software. **ADIADO** — alto risco (mãos do dono, possível brick) para ganho marginal dado o stack. Fan max + PPT/tctl já entregam o controle térmico.
- `pcie_aspm=off`, NVMe APST, `usbcore.autosuspend=-1`: **mantidos** (escolha do dono — só mudanças seguras nesta rodada).
- Swap/zram/vm (swappiness=180, watermark=125, page-cluster=0): **não tocado** (saudável, PSI≈0, compressão 4.4x).
