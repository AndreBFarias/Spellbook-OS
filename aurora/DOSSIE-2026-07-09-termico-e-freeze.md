# Dossiê — "PC esquentando" + freeze total (REISUB)

**Data:** 2026-07-09 · **Host:** nitro-5 (Acer Nitro AN515-47, Ryzen 5 7535HS + RTX 3050, Pop!_OS 22.04, GNOME 42.9/X11, BIOS V1.17)
**Método:** instrumentação direta (sensores/journald persistente) + auditoria adversarial de 26 agentes sobre os ~10 scripts do Aurora. Nada de culpar componente pela aparência — cada afirmação abaixo tem evidência.

---

## TL;DR (dois problemas independentes)

1. **Esquenta = por design, não é fan quebrada.** Sob carga real (2x mpv + 2x claude + chrome) a CPU está a **73-74 C** — normal (Tjmax ~= 100 C, zero throttle). O calor vem do **governor `performance` + EPP `performance`** que prende os 12 cores em 2.9-4.0 GHz sempre que há atividade. As fans **funcionam** (a prova: a temperatura fica contida em 73 C sob carga; fan morta escalaria a >90 C em minutos). **Dá para manter rápido E frio** — seção 3.
2. **Freeze = hang de display/compositor, não CPU/RAM/temperatura.** "O mouse mexia mas nada respondia" é a assinatura exata de hang do display AMD (cursor de hardware vivo, tela sem redesenhar, kernel vivo — por isso o REISUB funcionou). **Não foi OOM, não foi térmico.** A saída sem reboot já existe (**Ctrl+Alt+0**) mas não foi usada — seção 4.

---

## 1. Estado térmico medido (verdade de sensor, sob carga real)

| Sensor | Leitura | Veredito |
|---|---|---|
| CPU `k10temp Tctl` | **73,1 C** | Normal (Tjmax ~100 C) |
| Chassi `acpitz` (o "79 C" do fastfetch) | 74,0 C | Sensor de placa, não do die |
| iGPU AMD `amdgpu edge` | 66 C / 22 W | Normal |
| dGPU RTX 3050 | 51 C / 15 W | Ocioso (throttle reason = idle, não térmico) |
| NVMe x2 / RAM x2 / Wi-Fi | 45-48 C | Frios |

Contexto: `load avg 2.0`, com 2x mpv (vídeo), 2x claude, chrome, gnome-shell. **Não é idle** — há trabalho real. 73 C nessas condições é seguro. Nenhum evento térmico no `dmesg`, nenhum throttle.

**As fans não expõem RPM** via `hwmon`/`acpi` no Nitro (nem `nbfc` instalado) — isso é limitação do hardware, **não defeito**. A prova de que giram é indireta e sólida: a temperatura se estabiliza em 73 C sob carga.

## 2. Causa-raiz do calor: `governor=performance`

```
amd_pstate=active · governor=performance (x12) · EPP=performance · boost=1
-> scaling_cur_freq medido: quase todos os cores em 2.9-4.0 GHz (avg 3,65 GHz) em carga leve
-> cada tarefinha vira clock máximo -> calor de idle/carga-leve elevado
```

**A ironia da 2.6:** a flexibilização de 22/06 tentou esfriar (despinou `scaling_min`, reabilitou suspend, tirou `processor.max_cstate=1`). Mas o próprio doc admite: **o despin é "inerte enquanto governor=performance"** — o governor `performance` força o P-state máximo independentemente de `scaling_min`. Verificado: C-states profundos (C2/C3) ativos e em uso, `max_cstate` fora do cmdline, reboot feito. **Resultado: a 2.6 entregou resfriamento só em suspend/idle-real; a temperatura sob carga — o sintoma que você sente — ficou 100 % intocada.**

## 3. "Dá pra manter bom mas gelado?" -> SIM

A única alavanca que esfria de verdade **sem perder responsividade útil**:

```
governor: performance -> powersave           (dinâmico: cai no idle, sobe sob carga)
EPP:      performance -> balance_performance  (mantém turbo total sob carga)
boost:    mantém 1                            (turbo continua disponível)
```

Com `amd_pstate=active`, o par **powersave + EPP** entrega turbo instantâneo quando há trabalho e deixa os cores caírem quando não há — cai a temperatura de idle/carga-leve **sem** a perda de "snappiness" que a memória de laptop teme. É a recomendação da lente de design da auditoria: **maior impacto térmico, perda de performance desprezível.**

**NÃO mexer** (impacto térmico marginal e reintroduz instabilidade já resolvida): `pcie_aspm=off`, `nvme ps_max_latency=0`, `usbcore.autosuspend=-1`, `boost`. O ganho é de watts, não de graus — e esses params são de estabilidade.

### Três armadilhas que sabotam a troca (por isso não basta `cpupower -g powersave`)
- **O watchdog reverte em <=15 min.** `aurora-watchdog-check.sh` trata `governor != performance` e `system76-power != performance` como DESVIO e re-roda `aurora-root-apply`, que re-pina performance. Qualquer troca só-em-runtime é desfeita.
- **EPP fica preso em performance.** `aurora-root-apply` re-escreve `EPP=performance` em todo core (seção 3). Sob powersave, EPP é a alavanca de frequência do amd_pstate — deixá-lo em performance abafa o resfriamento.
- **`system76-power profile performance`** (seção 1) reafirma governor/EPP performance por fora.

-> Por isso a solução é um **toggle persistente** que edita a política nos dois arquivos + um sentinela (`/etc/aurora/allow-powersave`) que faz o watchdog e o `aurora-root-apply` respeitarem a escolha. Especificado na seção 5.

---

## 4. O freeze (REISUB de horas atrás) — investigação

**Linha do tempo:** boot que travou = 08/07 15:21 -> 09/07 18:49 (~27 h ligado). Descartados por evidência:

- **NÃO foi OOM/memória:** no minuto do freeze, `mem_avail ~5,5 GB` (36 %), `PSI avg10 = 0.00`, swap estável. (O post-mortem marcou "S2 pressão de memória", mas é **falso-positivo**: agregou amostras de 05-07/jul; ver seção 5C, bug do post-mortem.)
- **NÃO foi térmico:** 73 C não congela; throttle só perto de 100 C.
- **NÃO foi hang clássico de DMCUB:** zero erros `Error queueing DMUB / DMCUB error` em qualquer boot persistente. O watchdog de display (que detecta o hang com spam de erro) não tinha o que pegar.
- **NÃO foi suspend/resume:** nenhum evento de suspend no boot que travou.
- **NÃO foi crash de gnome-shell:** só warnings inócuos de `clutter_input_focus`; o shell não morreu — travou junto com o display.
- **NÃO foi hard lockup de CPU:** você conseguiu **REISUB** -> o kernel estava **vivo** (SysRq é tratado pelo kernel). CPU travada não processa REISUB.

**O que sobra, com o seu relato "o mouse mexia mas nada respondia":** é a assinatura literal descrita no cabeçalho do `amdgpu-dmcub-watchdog` — "a tela CONGELA; o cursor do mouse até pode mexer, mas o resto fica estático". **Veredito: hang de display/compositor (o "estado morto residual") — tela para de redesenhar, cursor de HW segue, input morto, kernel vivo.**

**Por que doeu tanto (e não precisava):**
- A saída projetada pra exatamente esse caso é o **Ctrl+Alt+0** (`aurora-gpu-revive`, via xbindkeys/`XGrabKey` — funciona com o compositor travado). Verifiquei: **está ativo agora** (xbindkeys rodando, binding presente). Você só não usou. **1x recupera; se a tela não voltar, 2x reinicia a sessão** (sem reboot, trabalho salvo permanece).
- O watchdog automático **não pega** esse tipo sem-erro — é o "estado morto residual" que o próprio script diz não ter sinal automático confiável.
- `nmi_watchdog=0` (hard-lockup detector desligado): um hard-hang real passaria sem log nem auto-reboot.

**Gatilho provável (não provado):** **PSR (Panel Self Refresh)** está ativo (`amdgpu.dcdebugmask=0`). PSR é a causa nº 1 de freeze silencioso de display em laptop AMD (eDP). Não há log que prove — por isso o plano é **observabilidade + mitigação conhecida**, não chute. Opções na seção 5B.

---

## 5. Plano de correção (o que fazer)

### A. Térmico — deixar "bom mas gelado" (a alavanca real)
- **A1.** `aurora-root-apply`: amarrar EPP ao governor — `case "$ALVO_GOVERNOR" in powersave) ALVO_EPP="balance_performance";; esac`.
- **A2.** Introduzir sentinela `/etc/aurora/allow-powersave`: quando existir, watchdog e `aurora-root-apply` **não** re-pinam governor/EPP/system76-power. (fecha as 3 armadilhas)
- **A3.** Comando **`cool` / `perf`** (toggle persistente): edita `ALVO_GOVERNOR` nos dois arquivos, liga/desliga o sentinela, reinstala em `/usr/local/sbin`, aplica na hora. Um comando, sem reboot.
- **A4.** Comando **`temp`**: readout de todos os sensores (CPU/iGPU/dGPU/NVMe/fans) + alerta. Você achava que "a fan não funciona" **porque não há readout nenhum** — isso resolve na raiz.

### B. Freeze — recuperar melhor e mitigar
- **B1.** Reforçar o **Ctrl+Alt+0** na sua memória muscular (e um aviso no boot). Já funciona.
- **B2.** (decisão sua, precisa reboot) Desligar PSR: `amdgpu.dcdebugmask=0x10` no cmdline (kernelstub). Ataca o suspeito nº 1 do freeze silencioso.
- **B3.** (opcional) `nmi_watchdog=1` + `kernel.hardlockup_panic=1`: transforma um hard-hang futuro em auto-reboot logado (em vez de REISUB manual às cegas).
- **B4.** (melhoria) Detector de liveness no watchdog de display para pegar o hang sem-erro (hoje ele só pega o hang com spam de erro).

### C. Bugs confirmados pela auditoria (19 achados — todos latentes hoje, nenhum é a causa do calor/freeze)
Correção incluída no lote de fixes do repo (nenhum remove função):
- **[médio]** doc "trocar p/ powersave" quebrado (EPP fica performance) -> A1/A3 resolvem + corrigir o doc.
- **[médio]** watchdog reverte cooling manual em 15 min -> A2 resolve.
- **[médio]** watchdog re-aplica `/usr/local/sbin` (defasado do repo) -> editar repo sem `bootstrap` não tem efeito; add guarda de divergência (`cmp` + aviso).
- **[médio]** CHANGELOG ainda anuncia "anti-suspend" como ativo + órfão `99-no-suspend.conf` versionado pode regredir a 2.6 -> marcar revertido + `git rm`.
- **[baixo]** EPP write-fail silencioso (assimétrico com governor) -> espelhar o `warn`.
- **[baixo]** self-heal do `99-aurora-ultra-wifi.conf` ausente -> loop de re-apply se sumir.
- **[baixo]** watchdog sempre `exit 0` -> falha de self-heal invisível.
- **[baixo]** `postboot-validate` grepa `max_cstate` morto.
- **[baixo]** `aurora-health` cego ao `acpitz`/`amdgpu` (sensores mais quentes) -> alerta quase nunca dispara.
- **[baixo]** `pcie_aspm=off` / `nvme ps0` / `usbcore.autosuspend=-1` = calor de idle marginal, sem benefício no laptop (manter por estabilidade; só documentar).
- **[baixo]** `sysupgrade()` vaza `set -o pipefail` pro shell interativo (zsh não escopa opção em função).
- **[info]** seção 7 (unpin) é dead code que loga "resfriamento" falso.
- **[novo/meu]** `oom-postmortem` gera falso "S2" agregando amostras de dias anteriores.

---

## 6. Estado / decisões pendentes

- Nível de resfriamento (`balance_performance` vs `balance_power` vs `power`) — decisão do usuário.
- Aplicar cooling ao vivo agora vs só preparar o toggle — decisão do usuário.
- B2 (desligar PSR, requer reboot) — decisão do usuário.

*Relacionado: `AURORA-2.6-THERMAL.md` (flexibilização anterior), `amdgpu-dmcub-watchdog` (recuperação de display), `aurora-gpu-revive` (Ctrl+Alt+0).*
