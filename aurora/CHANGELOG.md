# Aurora — Changelog de features e mapa de reaplicação

Cada feature listada tem um **aplicador idempotente** que pode reaplicar a configuração após `apt full-upgrade`, reinstalação de pacote, ou drift acidental.

## Mecanismo de reaplicação automática

1. **APT DPkg::Post-Invoke** (`/etc/apt/apt.conf.d/99-aurora-postinvoke`):
   Após cada operação apt (install/upgrade/remove), roda `aurora-bootstrap.sh --post-update --quiet` como usuário `andrefarias`. Cobre TUDO listado abaixo.

2. **`aurora-reapply-all.sh`** (manual ou via `sysupgrade`):
   Wrapper standalone que invoca o bootstrap + sub-aplicadores user-space. Loga em `~/.local/state/aurora-reapply.log`.

3. **`aurora-self-heal-cached`** (boot do shell, cache 1h):
   Detecta drift em 13 checkpoints. Se houver, oferece o aplicador correspondente.

4. **`sysupgrade`** (zsh function):
   Sequência completa: `apt update -> upgrade -> topgrade -> autoremove -> autoclean -> aurora-reapply-all`.

## Matriz feature -> aplicador

Coluna "Self-heal check" indica se `aurora-self-heal` consegue detectar drift dessa feature: `OK` = detecta, `(pendente)` = a implementar.

| Data | Versão | Feature | Side-effect | Aplicador | Self-heal check |
|---|---|---|---|---|---|
| 2026-08-10 | 2.2 | Freeze por thrashing: earlyoom prefer Flatpak + drop-ins app-flatpak-* → slices + browser.slice 4G/6G/3G + alerta PSI no mem-snapshot (SPR-2026-08-07) | `/etc/default/earlyoom`, `~/.config/systemd/user/app-flatpak-*-.scope.d/`, browser.slice, `/usr/local/sbin/mem-snapshot` | bootstrap | (pendente) |
| 2026-03 | 1.0 | Persistent journald | `/etc/systemd/journald.conf.d/00-aurora-persistent.conf` | bootstrap (sysctl + journald) | (pendente) |
| 2026-03 | 1.0 | earlyoom config | `/etc/default/earlyoom` | bootstrap copia_se_diff | OK |
| 2026-03 | 1.0 | sysctl tuning | `/etc/sysctl.d/99-aurora.conf` | bootstrap copia_se_diff | OK |
| 2026-03 | 1.0 | aurora-root.service + watchdog | `/etc/systemd/system/aurora-{root,watchdog}.*` | bootstrap copia_se_diff | OK |
| 2026-03 | 1.0 | APT post-invoke (auto-reapply) | `/etc/apt/apt.conf.d/99-aurora-postinvoke` | bootstrap copia_se_diff | OK |
| 2026-04 | 1.5 | mem-snapshot + logrotate | `/var/log/mem-snapshot.log` + units | bootstrap (units) | (pendente) |
| 2026-04 | 1.5 | product-oom-watchdog | systemd unit | bootstrap (units) | (pendente) |
| 2026-04 | 2.0 | Ollama keepalive + VRAM watchdog | `slices ollama.slice + units` | bootstrap (units) | (pendente) |
| 2026-06-01 | 2.3 | amdgpu DMCUB display watchdog (recupera display AMD travado sem reboot: gpu_recover + restart do compositor; endurecido: detecta Wayland, valida debugfs/recover, rajada de reset >=3/10min, assinaturas extras de hang) | `units amdgpu-dmcub-watchdog.{service,timer}` + `aurora/amdgpu-dmcub-watchdog` | bootstrap (units) | OK |
| 2026-06-01 | 2.3 | botão de pânico de GPU (Ctrl+Alt+0 via xbindkeys: 1x recupera, 2x reinicia a sessão) | `/usr/local/sbin/aurora-gpu-revive` + `/etc/sudoers.d/aurora-gpu-revive` + `~/.xbindkeysrc` + autostart | bootstrap (revive+sudoers) + aurora-gpu-shortcut-apply.sh | OK |
| 2026-06-01 | 2.3 | editor padrão estilo Notepad (gnome-text-editor restaura sessão e guarda rascunho sem título; gedit mantido) | `xdg-mime default text/plain` + `gsettings restore-session` | aurora-editor-apply.sh | OK |
| 2026-04 | 2.0 | Chrome dpkg-divert (anti-IA) | `/usr/bin/google-chrome-stable.distrib` + symlinks | aurora-chrome-divert-apply.sh | OK |
| 2026-04 | 2.0 | Chrome policy IA/Antigravity | `/etc/opt/chrome/policies/managed/aurora-no-ai-no-antigravity.json` | aurora-chrome-divert-apply.sh | OK |
| 2026-04 | 2.0 | Chrome --load-extension | `~/.local/share/applications/google-chrome.desktop` | aurora-chrome-extensions-apply.sh | OK |
| 2026-04 | 2.0 | Ctrl+C Ilimitado userscript | `~/.local/bin/control-c-ilimitado-ext` | aurora-userscripts-apply.sh | OK (info) |
| 2026-04 | 2.1 | gradia-autosave daemon | `~/.config/systemd/user/gradia-autosave.service` | aurora-user-services-apply.sh | OK |
| 2026-05-16 | 2.3-ULTRA | ~~Anti-suspend persistente~~ REVERTIDA pela 2.6-thermal (2026-06-22): suspend reabilitado | `/etc/systemd/logind.conf.d/99-no-suspend.conf` | NENHUM (bootstrap não instala mais) | revertida |
| 2026-05-16 | 2.3-ULTRA | NVIDIA persistence-mode | systemd unit | bootstrap | (pendente) |
| 2026-05-16 | 2.3-ULTRA | Wi-Fi powersave OFF | `/etc/NetworkManager/conf.d/99-aurora-ultra-wifi.conf` + remoção do `default-wifi-powersave-on.conf` | bootstrap (com .bak guard) | OK |
| 2026-05-16 | 2.3-ULTRA | kernel cmdline params (pcie_aspm, nvme PS0) | `kernelstub --add-options` | bootstrap (--first-install) | (pendente; check via `/proc/cmdline`) |
| 2026-05-19 | 2.4 | imagens-router daemon | `~/.config/systemd/user/imagens-router.service` | aurora-user-services-apply.sh | OK |
| 2026-05-20 | 2.5 | aurora-reapply-all.sh consolidado | `~/.config/zsh/aurora/aurora-reapply-all.sh` | (próprio) | -- |
| 2026-05-20 | 2.5 | self-heal ampliado (13 checks) | -- | -- | -- |
| 2026-06-03 | 2.6 | systemd-coredump (diagnostica crash silencioso de terminal/app -- ghostty não deixava rastro) | pacote do sistema + `coredumpctl` | `sudo apt install systemd-coredump` (aguarda dono) | (pendente) |
| 2026-06-16 | 2.7 | spellbook-autosync timer (commit+push periodico a cada 10min; independe de fechar terminal -- o hook zshexit mascarou parada de ~1 mes) | `~/.config/systemd/user/spellbook-autosync.{service,timer}` | aurora-user-services-apply.sh | OK |
| 2026-06-22 | 2.6-thermal | Flexibilizacao termica laptop-friendly (scaling_min despinado; suspend REABILITADO; processor.max_cstate=1 removido do cmdline) | governor/suspend/unpin/max_cstate | aurora-root-apply (seções 2/6/7) + aurora-watchdog | OK |
| 2026-07-09 | 2.8 | Toggle termico `cool`/`perf` (sentinela `/etc/aurora/allow-powersave`; EPP amarrado ao governor) + comando `temp` + heartbeat de liveness do compositor (auto-recupera hang silencioso que o watchdog de erro não pega) | `functions/termico.zsh`, `aurora/aurora-compositor-heartbeat.sh` | aurora-root-apply + aurora-gpu-shortcut-apply.sh | OK |
| 2026-07-09 | 2.8 | Fans agressivas: `acer_wmi predator_v4=1` destrava `platform_profile` (aplica `balanced-performance`; `performance` e rejeitado pelo EC do Nitro) + RPM das fans legivel via hwmon | `/etc/modprobe.d/acer_wmi-predator.conf` + `platform_profile` | aurora-bootstrap.sh + aurora-root-apply (sec 11, idempotente/tolera I/O error) + watchdog (re-assere apos resume) | OK |
| 2026-07-11 | 2.9 | NBFC-Linux fan SEMPRE agressiva (curva própria piso 40%/100%@78C, 7692 RPM vs 5555 do EC; resolve o 97C-em-3s) | `nbfc_service.service` + `Acer Nitro AN515-47 Aurora.json` + `ec_sys write_support` | aurora-thermal-apply.sh (via bootstrap §6g) | OK |
| 2026-07-11 | 2.9 | auto-switcher de CPU (BASE idle / PERF sob carga por busy%; governor powersave fixo; EPP+PPT dinamicos; tctl-cap 90C; `/run/aurora/target` = fonte-de-verdade, sem guerra com watchdog) | `aurora-switcher` + `units/aurora-switcher.{service,timer}` | aurora-thermal-apply.sh (via bootstrap §6g) | OK |
| 2026-07-11 | 2.9 | ryzenadj (PPT/tctl-temp; CO `--set-coall` rejeitado pelo SMU) build-if-missing do source | `/usr/local/bin/ryzenadj` | aurora-thermal-apply.sh | OK |
| 2026-07-11 | 2.9 | Higiene termica: thermald mascarado (no-op AMD) + timers 30s de-alinhados + `vm.page-cluster=0` persistido | `mask thermald` + `RandomizedDelaySec` + `99-aurora.conf` | aurora-thermal-apply.sh + bootstrap + 99-aurora.conf | OK |
| 2026-07-11 | 2.9 | loglevel 0->3 (0 cegava warnings de throttle termico/HW no journal) | `kernelstub --add-options loglevel=3` | aurora-bootstrap.sh §1 (migra) | (apos reboot; check /proc/cmdline) |
| 2026-08-06 | 3.0 | **Reversão de política do dono**: modo PERF estático volta a ser o default (sentinela removida) -> governor+EPP performance, system76 High Performance, auto-switcher inerte. Motivo medido: o gatilho `BUSY_UP=70%` (busy% agregado nos 12 threads) nunca dispara em uso interativo — 150 escaladas a PERF em 107.963 amostras (0,14% do tempo), e o `CAP_TEMP=85` derrubava o PPT a 38W com só 20% de carga | sentinela `/etc/aurora/allow-powersave` ausente | `perf` (functions/termico.zsh) | OK |
| 2026-08-06 | 3.0 | `aurora-root-apply` §12: reafirma PPT/tctl stock no modo PERF (slow 70W / fast 80W / tctl-temp 90C). Fecha buraco real: o switcher era o ÚNICO que reafirmava o ryzenadj, então ao sair deixava o PPT congelado em 38-45W com governor pinado em performance (clock alto + potência de modo econômico). Valida por `PPT LIMIT SLOW`, não por `STAPM LIMIT` (adaptativo: o SMU recalcula e a leitura deriva 71->56W, geraria warn falso a cada watchdog) | `ryzenadj --stapm/fast/slow-limit --tctl-temp` | aurora-root-apply §12 (boot + watchdog <=15min + pos-resume) | OK |
| 2026-08-14 | 3.1 | **Sentinela do modo COOL virou volátil**: `/etc/aurora/allow-powersave` -> `/run/aurora/allow-powersave` (tmpfs). PERF passa a ser o estado natural da máquina: `cool` vale só até desligar, e nascer em COOL exigiria recriar a sentinela de propósito. Motivo: um `cool` rodado em 10/08 e esquecido deixou todo boot seguinte em "Equilibrado" (governor powersave + system76 Balanced), com o dono corrigindo na mão. Estado que depende de memória humana não é idempotente. `aurora-root-apply` apaga o resíduo de `/etc` a cada execução | `/run/aurora/allow-powersave` | aurora-root-apply, aurora-watchdog-check.sh, aurora-switcher, aurora-self-heal.zsh, termico.zsh | OK |
| 2026-08-14 | 3.1 | `cpufreq.default_governor=performance` no cmdline: o governor nasce em performance no kernel init, antes de qualquer daemon (o default do amd-pstate é powersave). Não conflita com `cool` — define o DEFAULT, e o root-apply escreve o governor explicitamente sob a sentinela | `kernelstub --add-options` | aurora-bootstrap.sh §1 (`KERNELSTUB_PARAMS`) | (após reboot; check `/proc/cmdline`) |
| 2026-08-14 | 3.1 | Curva NBFC ULTRA: piso 40%->**60%**, 100% aos 78C->**65C** (CPU) / 80C->**68C** (GPU); 6 degraus viraram 4. A curva antiga chegava ao máximo DEPOIS do calor; esta chega antes. Medido: sob carga total as fans já saturavam em 7692 RPM a 87C — quem segura temperatura ali é o PPT, não a fan; o ganho da curva nova é em carga média/idle | `Acer Nitro AN515-47 Aurora.json` | aurora-thermal-apply.sh §4 | OK |
| 2026-08-14 | 3.1 | Dois bugs de idempotência corrigidos: (1) `aurora-thermal-apply.sh` instalava a curva nova mas não reiniciava o `nbfc_service` — o daemon lê a curva só no start, então editar o JSON não tinha efeito até o próximo boot; (2) `aurora-bootstrap.sh` §1 caía em `/proc/cmdline` (boot CORRENTE) quando `kernelstub --print-config` exigia sudo, e re-adicionava param novo a CADA execução (apt hook incluso) até o reboot. Fallback agora é `/etc/kernelstub/configuration` (0644, config persistida) | -- | aurora-thermal-apply.sh §5, aurora-bootstrap.sh §1 | OK |

## Para validar o sistema todo

```bash
aurora-self-heal           # 21 checks (inclui stack termico 2.9), mostra drift e propoe fix
bash aurora-reapply-all.sh # reaplica tudo idempotente; loga em ~/.local/state/aurora-reapply.log
sysupgrade                 # apt + topgrade + reapply em sequencia
```

## Cenário de falha após `apt full-upgrade`

Se uma feature se perder:
1. `apt full-upgrade` roda; ao terminar, `99-aurora-postinvoke` dispara `aurora-bootstrap.sh --post-update --quiet`.
2. Bootstrap reaplica `/etc/sysctl.d/`, `/etc/systemd/system/`, `/etc/default/earlyoom`, NetworkManager, etc.
3. Próxima abertura de terminal, `aurora-self-heal-cached` faz double-check (1h de cache para não pesar boot).
4. Se ainda houver drift, mostra mensagem com o aplicador específico.
