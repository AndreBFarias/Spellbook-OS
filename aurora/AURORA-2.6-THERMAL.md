# Aurora 2.6 — Flexibilização térmica (laptop-friendly)

**Data:** 2026-06-22 · **Host:** nitro-5 (Acer Nitro AN515-47, Ryzen 5 7535HS, RTX 3050)

## Contexto

Até a 2.5, o Aurora aplicava uma postura térmica de "desktop sempre-na-tomada":
CPU pinada no teto, sem suspend, sem C-states profundos. Numa auditoria preventiva
(2026-06-22) isso se mostrou um custo de **longevidade** para um laptop (Tctl ~65°C
mesmo parado, alta potência 24/7). A 2.6 relaxa parte disso preservando performance.

## O que mudou

| Item | Antes (≤2.5) | Agora (2.6) | Vale quando |
|---|---|---|---|
| **CPU governor** | `performance` | **`performance`** (mantido — escolha do usuário) | imediato |
| **CPU scaling_min** | pinado em `scaling_max` (4.6GHz) | **`cpuinfo_min_freq`** (~416MHz) | imediato* |
| **Suspend/sleep** | targets `masked` + logind/dconf no-suspend | **reabilitado** (desmascarado, no-suspend removido) | imediato (auto-suspend lid/idle no reboot) |
| **`processor.max_cstate=1`** | no cmdline (sem C-states profundos) | **removido** do cmdline (kernelstub) | **após reboot** |
| `mitigations=off` | ativo | **mantido** | — |
| `pcie_aspm=off` | ativo | **mantido** | — |
| EPP / boost | performance / on | performance / on (mantidos) | imediato |

\* **Inerte enquanto governor=performance**: o governor `performance` força o P-state
máximo independentemente do `scaling_min`. A desafixação só tem efeito prático se o
governor for trocado para `powersave` (dinâmico). Foi mantida para esse caso futuro.

### Estado térmico resultante
Com `governor=performance`, a CPU continua no máximo quando **ativa** (performance
preservada). O ganho de resfriamento vem de:
- **Suspend** funcionando (o laptop pode dormir).
- **C-states profundos** (após reboot): cores totalmente ociosos entram em sono
  profundo, reduzindo calor/consumo no idle real.

Para resfriar também a frequência em idle, trocar o governor para `powersave`
(ver "Alternar governor" abaixo).

## Arquivos (fonte versionada em `~/.config/zsh/aurora/`)

- `aurora-root-apply` — seção 2 (governor), 6 (suspend → **unmask**), 7 (CPU → **unpin**).
  Instalado em `/usr/local/sbin/aurora-root-apply` (via `aurora-bootstrap.sh`), rodado
  por `aurora-root.service` (boot) e `aurora-watchdog`.
- `aurora-watchdog-check.sh` — `ALVO_GOVERNOR` + removidos os checks de anti-suspend e
  de CPU-pin (não re-aplicam mais). Roda direto do repo via `aurora-watchdog.timer` (15min).
- `aurora-postboot-validate.sh` — removido `processor.max_cstate=1` dos params obrigatórios
  e os Checks 10/11 (anti-suspend + CPU-pin).
- `aurora-bootstrap.sh` — `KERNELSTUB_PARAMS` sem `processor.max_cstate=1`; instalação do
  logind/dconf no-suspend desativada.

### Aplicado ao sistema (uma vez, 2026-06-22)
- `sudo install` do `aurora-root-apply` em `/usr/local/sbin/`.
- `sudo /usr/local/sbin/aurora-root-apply` (governor, unmask suspend, unpin).
- `sudo rm /etc/systemd/logind.conf.d/99-no-suspend.conf`.
- `sudo rm /etc/dconf/db/local.d/00-no-suspend{,/locks}` + `sudo dconf update`.
- `sudo kernelstub --delete-options "processor.max_cstate=1"` → **requer reboot**.

## Alternar governor (performance ↔ powersave)

**A partir da 2.8 use os comandos `cool` / `perf`** (`functions/termico.zsh`) — não edite
mais os scripts à mão. O gatilho é o sentinela `/etc/aurora/allow-powersave`, que o
`aurora-root-apply` e o `aurora-watchdog-check.sh` consultam para NÃO re-pinar performance.

```bash
cool    # governor powersave + EPP balance_performance: esfria idle/carga-leve, turbo intacto
perf    # volta ao governor performance pinado (postura historica)
temp    # readout de todos os sensores + modo atual
```

Por que não bastava o antigo `sed` (nem `cpupower -g powersave`): (1) o watchdog revertia
em <=15min; (2) `ALVO_EPP` seguia `performance` — sob `amd_pstate=active` o EPP é a alavanca
real de frequência, então o idle não esfriava; (3) `system76-power profile performance`
reafirmava tudo por fora. O sentinela + a amarração EPP←governor no `aurora-root-apply`
resolvem os três. Detalhes em `DOSSIE-2026-07-09-termico-e-freeze.md`.

## Reverter tudo (voltar à postura ≤2.5)

`git revert` dos commits 2.6 no repo Spellbook-OS, **ou** `aurora-ROLLBACK.sh`, **ou**
manualmente: re-pinar CPU + `sudo systemctl mask sleep.target suspend.target ...` +
`sudo kernelstub --add-options "processor.max_cstate=1"` + reboot.

## Pendência
**Reboot** para o `max_cstate`/C-states valerem. Os demais ajustes já estão ativos.

---
*Relacionado: `aurora-desktop-guards-apply.sh` + checkpoint no `aurora-self-heal` (self-heal
idempotente de `.desktop`: perm 644, Exec PhotoGIMP gimp-3.0→gimp, órfãos NoDisplay,
tracker-extract-3 mascarado).*
